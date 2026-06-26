"""Termux (Android) setup helpers.

Termux is unique: it runs as a regular Android app and uses ``pkg`` (a thin
wrapper around ``apt``) instead of a system package manager.  RDP support
is provided through ``proot-distro`` (run a real Linux distro inside
Termux) or directly via Termux:X11 + xrdp.

This module exposes the small set of helpers the dispatcher needs.
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import List, Optional

from ..utils.system import run, which

__all__ = [
    "is_termux",
    "pkg_update",
    "pkg_install",
    "install_termux_deps",
    "install_proot_distro",
    "proot_login",
    "termux_storage_ok",
    "install_freerdp",
    "ensure_x11_repo",
]

# Packages we need on Termux itself (NOT inside proot).
TERMUX_DEPS = (
    "openssh",
    "curl",
    "ca-certificates",
    "jq",
    "termux-api",
    "proot",
    "proot-distro",
)


def is_termux() -> bool:
    """Return ``True`` when running inside Termux on Android."""
    return (
        "TERMUX_VERSION" in os.environ
        or "com.termux" in os.environ.get("PREFIX", "")
        or "ANDROID_ROOT" in os.environ
    )


def _pkg_bin() -> str:
    return which("pkg") or "pkg"


def pkg_update() -> subprocess.CompletedProcess:
    return run([_pkg_bin(), "update", "-y"], capture=True, check=False)


def pkg_install(packages: List[str]) -> subprocess.CompletedProcess:
    return run([_pkg_bin(), "install", "-y", *packages], capture=True, check=False)


def ensure_x11_repo() -> bool:
    """Enable Termux's x11 repo (needed for xrdp / termux-x11)."""
    # The x11 repo is added via a one-liner recommended by Termux.
    if not is_termux():
        return False
    # Idempotent: install x11-repo if missing.
    proc = run([_pkg_bin(), "install", "-y", "x11-repo"], capture=True, check=False)
    return proc.returncode == 0


def install_termux_deps(deps: Optional[List[str]] = None) -> dict:
    """Install the Termux-side dependencies (ssh, curl, proot-distro, ...)."""
    if not is_termux():
        raise RuntimeError("install_termux_deps called outside Termux")
    pkg_update()
    packages = list(deps or TERMUX_DEPS)
    proc = pkg_install(packages)
    ok = proc.returncode == 0
    return {p: ok for p in packages}


def install_proot_distro() -> bool:
    """Install proot-distro (used to install Ubuntu/Kali inside Termux)."""
    if not is_termux():
        return False
    proc = pkg_install(["proot-distro"])
    return proc.returncode == 0


def proot_login(distro: str = "kali", command: Optional[List[str]] = None) -> subprocess.CompletedProcess:
    """Log into an installed proot distro and (optionally) run ``command``."""
    cmd = ["proot-distro", "login", distro]
    if command:
        cmd.append("--")
        cmd.extend(command)
    return run(cmd, capture=True, check=False)


def termux_storage_ok() -> bool:
    """Return ``True`` when ``termux-setup-storage`` has been run.

    A symlink ``~/storage`` should exist if storage has been set up.
    """
    return Path.home().joinpath("storage").exists()


def install_freerdp() -> bool:
    """Install freerdp on Termux itself (for client-side RDP)."""
    if not is_termux():
        return False
    ensure_x11_repo()
    proc = pkg_install(["freerdp"])
    return proc.returncode == 0


def install_distro(distro: str = "kali") -> bool:
    """``proot-distro install <distro>``."""
    proc = run(["proot-distro", "install", distro], capture=True, check=False)
    return proc.returncode == 0


def setup_distro_rdp(distro: str = "kali") -> bool:
    """Inside the proot distro, install xfce4 + xrdp.

    This runs the toolkit's bash setup script inside the proot environment.
    """
    if not which("proot-distro"):
        return False
    # Run setup-rdp.sh inside the distro.  We assume the toolkit has been
    # bind-mounted into the distro at /data/data/com.termux/files/home/rdp-toolkit.
    script = Path(__file__).resolve().parent.parent / "core_sh" / "setup-rdp.sh"
    if not script.exists():
        return False
    proc = proot_login(distro, ["bash", str(script)])
    return proc.returncode == 0
