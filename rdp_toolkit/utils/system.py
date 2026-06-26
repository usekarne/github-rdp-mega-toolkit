"""System-level helpers: platform detection, command execution, paths.

Everything here is pure stdlib and safe to import on any OS — the functions
return sensible fallbacks (``None`` / ``False`` / ``"unknown"``) instead of
raising when the host environment does not match expectations.
"""
from __future__ import annotations

import os
import platform as _platform
import shutil
import subprocess
from pathlib import Path
from typing import List, Optional, Union

__all__ = [
    "detect_platform",
    "is_root",
    "which",
    "run",
    "ensure_dir",
    "config_dir",
]


def detect_platform() -> str:
    """Return a normalised platform identifier.

    Possible return values:

    * ``"kali"``     — Kali Linux (detected via ``/etc/os-release``)
    * ``"ubuntu"``   — Ubuntu (or close Debian derivative)
    * ``"windows"``  — any Windows NT kernel
    * ``"android"``  — Termux / Android (via ``ANDROID_ROOT`` / ``PREFIX``)
    * ``"mac"``      — macOS / Darwin
    * ``"unknown"``  — anything we cannot classify
    """
    system = _platform.system().lower()
    if system == "windows":
        return "windows"
    if system == "darwin":
        return "mac"

    # Android / Termux detection — these env vars are set by Termux.
    if (
        "ANDROID_ROOT" in os.environ
        or "TERMUX_VERSION" in os.environ
        or "com.termux" in os.environ.get("PREFIX", "")
    ):
        return "android"

    # Linux distro detection via /etc/os-release (systemd standard).
    try:
        release = Path("/etc/os-release")
        if release.exists():
            text = release.read_text(errors="ignore").lower()
            if "kali" in text:
                return "kali"
            if "ubuntu" in text or "debian" in text or "pop!_os" in text:
                return "ubuntu"
            if "arch" in text or "manjaro" in text:
                return "ubuntu"  # treat arch like ubuntu for tool routing
            if "fedora" in text or "rhel" in text or "centos" in text:
                return "ubuntu"
    except OSError:
        pass

    if system == "linux":
        return "unknown"
    return "unknown"


def is_root() -> bool:
    """Return ``True`` when the current process has admin / root rights."""
    # POSIX path — geteuid exists on Linux/macOS/Termux.
    geteuid = getattr(os, "geteuid", None)
    if geteuid is not None:
        try:
            return geteuid() == 0
        except OSError:
            return False
    # Windows fallback — shell32.IsUserAnAdmin.
    try:  # pragma: no cover - Windows-only
        import ctypes  # type: ignore

        return bool(ctypes.windll.shell32.IsUserAnAdmin())  # type: ignore[attr-defined]
    except Exception:
        return False


def which(binary: str) -> Optional[str]:
    """Return the absolute path to ``binary`` on ``$PATH`` or ``None``."""
    if not binary:
        return None
    return shutil.which(binary)


def run(
    cmd: Union[str, List[str]],
    capture: bool = True,
    check: bool = False,
    timeout: Optional[int] = None,
    env: Optional[dict] = None,
) -> subprocess.CompletedProcess:
    """Run a command, returning a :class:`subprocess.CompletedProcess`.

    Parameters
    ----------
    cmd:
        Either a string (executed via the shell) or a list of arguments
        (executed without a shell — preferred for safety).
    capture:
        Capture stdout / stderr as text.
    check:
        Raise :class:`subprocess.CalledProcessError` on non-zero exit.
    timeout:
        Optional kill timeout in seconds.
    env:
        Optional environment-variable mapping (defaults to inherited).
    """
    shell = isinstance(cmd, str)
    return subprocess.run(
        cmd,
        shell=shell,
        capture_output=capture,
        text=True,
        check=check,
        timeout=timeout,
        env=env,
    )


def ensure_dir(path: Union[str, Path]) -> Path:
    """Create ``path`` (and parents) if missing; return it as a :class:`Path`."""
    p = Path(path)
    p.mkdir(parents=True, exist_ok=True)
    return p


def config_dir() -> Path:
    """Return the user config directory (``~/.config/rdp-toolkit``).

    On Windows this falls back to ``%APPDATA%\\rdp-toolkit``; on macOS /
    Termux it uses ``~/.config/rdp-toolkit`` for consistency.
    """
    if os.name == "nt":  # pragma: no cover - Windows-only
        base = os.environ.get("APPDATA") or str(Path.home())
        return Path(base) / "rdp-toolkit"
    return Path.home() / ".config" / "rdp-toolkit"
