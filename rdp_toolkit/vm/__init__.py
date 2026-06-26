"""VM subpackage — Docker Compose-backed RDP VM management.

Re-exports the manager module plus the convenience functions and the
short-name -> service mapping so callers can write::

    from rdp_toolkit.vm import start, stop, status, list_vms, shell, VMManager

Three RDP-capable containers ship with the toolkit: ``kali-rdp``,
``ubuntu-rdp`` and ``windows-rdp`` (Kali/Ubuntu/XFCE4 + Wine respectively).
The manager wraps ``docker compose`` so the CLI can start/stop/status them
and fetch a uniform connection dict (host/port/user/password) for any
running VM.
"""
from __future__ import annotations

from . import compose, manager
from .compose import (
    DEFAULT_PORTS,
    SHORT_TO_SERVICE,
    ComposeSpec,
    find_compose_file,
    parse_compose,
)
from .manager import (
    VMError,
    VMManager,
    list_vms,
    shell,
    short_names,
    start,
    status,
    stop,
)

__all__ = [
    "VMManager",
    "VMError",
    "ComposeSpec",
    "compose",
    "manager",
    "find_compose_file",
    "parse_compose",
    "SHORT_TO_SERVICE",
    "DEFAULT_PORTS",
    "start",
    "stop",
    "shell",
    "status",
    "list_vms",
    "short_names",
]
