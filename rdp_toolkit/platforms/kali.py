"""Kali Linux setup helpers.

These wrap common Kali-specific actions (kali-desktop-xfce install, Kali
repository tweaks, Kali tool selection).  They are imported by
:mod:`rdp_toolkit.platforms.installer` when running on Kali.
"""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import List, Optional

from ..utils.system import detect_platform, is_root, run, which

__all__ = [
    "is_kali",
    "ensure_kali_repos",
    "install_desktop",
    "install_kali_tools",
    "harden_kali",
]

# A curated, modest tool set — full Kali install is left to the user.
DEFAULT_KALI_TOOLS = (
    "kali-desktop-xfce",
    "xrdp",
    "xorgxrdp",
    "nmap",
    "wireshark",
    "metasploit-framework",
    "hydra",
    "john",
    "hashcat",
    "aircrack-ng",
    "burpsuite",
    "sqlmap",
    "nikto",
    "gobuster",
    "feroxbuster",
)


def is_kali() -> bool:
    """Return ``True`` when running on Kali Linux."""
    if detect_platform() != "kali":
        return False
    return True


def _apt(verb: str, packages: List[str], yes: bool = True) -> subprocess.CompletedProcess:
    cmd = ["apt-get", verb]
    if yes:
        cmd.append("-y")
    if verb == "install":
        cmd.append("--no-install-recommends")
    cmd.extend(packages)
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    return run(cmd, env=env, check=False)


def ensure_kali_repos() -> bool:
    """Make sure ``kali-rolling`` is the active source and apt is up-to-date."""
    if not is_kali():
        return False
    sources = Path("/etc/apt/sources.list")
    if sources.exists():
        text = sources.read_text(errors="ignore")
        if "kali-rolling" not in text:
            with open(sources, "a", encoding="utf-8") as fh:
                fh.write("\ndeb http://http.kali.org/kali kali-rolling main contrib non-free\n")
    run(["apt-get", "update", "-y"], check=False)
    return True


def install_desktop() -> bool:
    """Install ``kali-desktop-xfce`` + xrdp."""
    if not is_root():
        return False
    ensure_kali_repos()
    _apt("install", ["kali-desktop-xfce", "xrdp", "xorgxrdp", "dbus-x11"])
    return True


def install_kali_tools(tools: Optional[List[str]] = None) -> dict:
    """Install a curated Kali tool set.  Returns ``{pkg: ok}``."""
    if not is_root():
        raise PermissionError("install_kali_tools requires root (try sudo).")
    ensure_kali_repos()
    tools = list(tools or DEFAULT_KALI_TOOLS)
    results: dict = {}
    # Batch install for efficiency.
    proc = _apt("install", tools)
    ok = proc.returncode == 0
    for t in tools:
        results[t] = ok
    return results


def harden_kali() -> None:
    """Apply a couple of Kali-specific hardening defaults (no-op on others).

    * Disable bluetooth + avahi services for the session.
    * Set swappiness to 10.
    """
    if not is_kali() or not is_root():
        return
    for svc in ("bluetooth", "avahi-daemon", "cups"):
        run(["systemctl", "stop", svc], check=False)
        run(["systemctl", "disable", svc], check=False)
    try:
        with open("/proc/sys/vm/swappiness", "w", encoding="utf-8") as fh:
            fh.write("10\n")
    except OSError:
        pass


def locate_kali_config() -> Optional[Path]:
    """Find the ``configs/kali.yaml`` shipped with the package (or ``None``)."""
    root = Path(__file__).resolve().parent.parent.parent
    candidates = [
        root / "configs" / "kali.yaml",
        root / "configs" / "kali-rdp.yaml",
    ]
    for c in candidates:
        if c.exists():
            return c
    return None
