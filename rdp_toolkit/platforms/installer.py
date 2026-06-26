"""Cross-platform installer dispatcher.

``install_for_platform`` detects (or accepts) a platform identifier and
runs the matching setup pipeline:

* ``kali``    — uses :mod:`rdp_toolkit.platforms.kali` helpers
* ``ubuntu``  — treated like Kali but with the Ubuntu package set
* ``windows`` — uses :mod:`rdp_toolkit.platforms.windows` helpers
* ``android`` — uses :mod:`rdp_toolkit.platforms.android` (Termux) helpers
* ``mac``     — best-effort (Homebrew + xfreerdp via brew)

The dispatcher relies on the bash / PowerShell ``core_*`` scripts that ship
with this toolkit.  It finds them relative to the package install path.
"""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import List, Optional

from ..utils.system import detect_platform, is_root, run, which

__all__ = [
    "install_for_platform",
    "find_core_script",
    "PLATFORM_SCRIPTS",
    "KNOWN_PLATFORMS",
]

KNOWN_PLATFORMS = ("kali", "ubuntu", "windows", "android", "mac", "unknown")

# Map: platform -> { 'setup_rdp': filename, 'setup_tunnel': filename,
#                    'optimize': filename, 'install_software': filename,
#                    'shell': 'bash' | 'pwsh' }
PLATFORM_SCRIPTS = {
    "kali":    {"shell": "bash",  "ext": ".sh",  "subdir": "core_sh"},
    "ubuntu":  {"shell": "bash",  "ext": ".sh",  "subdir": "core_sh"},
    "android": {"shell": "bash",  "ext": ".sh",  "subdir": "core_sh"},
    "mac":     {"shell": "bash",  "ext": ".sh",  "subdir": "core_sh"},
    "windows": {"shell": "pwsh",  "ext": ".ps1", "subdir": "core_ps"},
}


def _package_root() -> Path:
    """Return the absolute path of the installed ``rdp_toolkit`` package."""
    return Path(__file__).resolve().parent.parent


def find_core_script(name: str, platform: Optional[str] = None) -> Path:
    """Locate a ``core_ps`` / ``core_sh`` script by base name.

    Raises :class:`FileNotFoundError` if the script cannot be located.
    """
    plat = platform or detect_platform()
    spec = PLATFORM_SCRIPTS.get(plat) or PLATFORM_SCRIPTS["ubuntu"]
    root = _package_root() / spec["subdir"]
    candidate = root / f"{name}{spec['ext']}"
    if candidate.exists():
        return candidate
    # Fall back to the bash core if pwsh variant is missing.
    if spec["ext"] == ".ps1":
        fallback = _package_root() / "core_sh" / f"{name}.sh"
        if fallback.exists():
            return fallback
    raise FileNotFoundError(
        f"could not find core script '{name}' for platform '{plat}' "
        f"(looked in {candidate})"
    )


def _resolve_shell(platform: str) -> str:
    spec = PLATFORM_SCRIPTS.get(platform) or PLATFORM_SCRIPTS["ubuntu"]
    shell_name = spec["shell"]
    if shell_name == "pwsh":
        # pwsh on Windows, powershell on older systems.
        return which("pwsh") or which("powershell") or "powershell"
    return which("bash") or "/bin/bash"


def _run_script(
    script: Path, shell: str, args: Optional[List[str]] = None,
    sudo: bool = False, env: Optional[dict] = None,
) -> subprocess.CompletedProcess:
    """Run ``script`` via ``shell`` with optional ``sudo`` and ``args``."""
    cmd: List[str] = []
    if sudo and os.name != "nt" and not is_root():
        cmd.append("sudo")
    if shell.endswith("pwsh") or shell.endswith("powershell"):
        cmd.extend([shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                    str(script)])
    else:
        cmd.extend([shell, str(script)])
    if args:
        cmd.extend(args)
    return run(cmd, capture=True, check=False, env=env)


def install_for_platform(
    platform: Optional[str] = None,
    *,
    steps: Optional[List[str]] = None,
    profile: str = "productivity",
    hours: int = 6,
    software_config: Optional[Path] = None,
    env: Optional[dict] = None,
) -> dict:
    """Run the full RDP setup pipeline for the host (or given) platform.

    Parameters
    ----------
    platform:
        Override the auto-detected platform.
    steps:
        Ordered list of step names to run.  Defaults to the full pipeline:
        ``['setup_rdp', 'optimize', 'install_software', 'setup_tunnel']``.
    profile:
        Optimisation profile passed to the ``optimize`` script.
    hours:
        Session length (forwarded as ``SESSION_HOURS`` env var so the
        keepalive script picks it up).
    software_config:
        Optional override for ``configs/software-list.json`` path.
    env:
        Additional environment variables to pass to the scripts.

    Returns
    -------
    dict
        ``{ step: (exit_code, stdout, stderr) }`` for every step run.
    """
    plat = platform or detect_platform()
    if plat not in PLATFORM_SCRIPTS:
        raise ValueError(
            f"platform {plat!r} is not supported (known: {list(PLATFORM_SCRIPTS)})"
        )

    steps = steps or ["setup_rdp", "optimize", "install_software", "setup_tunnel"]

    full_env = os.environ.copy()
    if env:
        full_env.update(env)
    full_env.setdefault("SESSION_HOURS", str(int(hours)))
    full_env.setdefault("RDP_PROFILE", profile)
    full_env.setdefault("OPTIMIZE_PROFILE", profile)
    if software_config:
        full_env["SOFTWARE_LIST_PATH"] = str(software_config)

    needs_sudo = plat in ("kali", "ubuntu", "android", "mac")
    shell = _resolve_shell(plat)

    results: dict = {}
    for step in steps:
        if step == "setup_rdp":
            script = find_core_script("setup-rdp", plat)
        elif step == "optimize":
            script = find_core_script(
                "optimize-windows" if plat == "windows" else "optimize-linux",
                plat,
            )
            # On non-Windows platforms the script takes no args; on Windows
            # we forward the profile.
        elif step == "install_software":
            script = find_core_script("install-software", plat)
        elif step == "setup_tunnel":
            script = find_core_script("setup-tunnel", plat)
        elif step == "keepalive":
            script = find_core_script("keepalive", plat)
        elif step == "health_check":
            script = find_core_script("health-check", plat)
        elif step == "cleanup":
            script = find_core_script("cleanup", plat)
        else:
            raise ValueError(f"unknown step: {step!r}")

        args: List[str] = []
        if step == "optimize" and plat == "windows":
            args.extend(["-Profile", profile])

        proc = _run_script(
            script, shell, args=args,
            sudo=needs_sudo and step != "setup_tunnel",
            env=full_env,
        )
        results[step] = {
            "exit_code": proc.returncode,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "script": str(script),
        }
        # Hard-fail on setup_rdp — without it nothing else makes sense.
        if step == "setup_rdp" and proc.returncode != 0:
            break

    return results


def _smoke() -> bool:
    """Self-check used by ``rdp_toolkit doctor``."""
    try:
        find_core_script("setup-rdp")
        return True
    except FileNotFoundError:
        return False
