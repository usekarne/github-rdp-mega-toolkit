"""Utility subpackage — re-exports the most useful helpers.

Importing ``from rdp_toolkit.utils import generate_password`` is the
supported public API; the underlying modules (``crypto``, ``net``,
``system``) remain importable for advanced callers.
"""
from __future__ import annotations

from .crypto import (
    DIGITS,
    LOWER,
    SYMBOLS,
    UPPER,
    enforce_complexity,
    generate_password,
    hash_password,
)
from .net import get_public_ip, parse_tunnel_url, probe_http, test_port
from .system import (
    config_dir,
    detect_platform,
    ensure_dir,
    is_root,
    run,
    which,
)

__all__ = [
    # crypto
    "UPPER",
    "LOWER",
    "DIGITS",
    "SYMBOLS",
    "generate_password",
    "enforce_complexity",
    "hash_password",
    # net
    "test_port",
    "get_public_ip",
    "probe_http",
    "parse_tunnel_url",
    # system
    "detect_platform",
    "is_root",
    "which",
    "run",
    "ensure_dir",
    "config_dir",
]

__version__ = "9.0.0"
