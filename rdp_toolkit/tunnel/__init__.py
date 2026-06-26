"""Tunnel subpackage — public API.

Re-exports the abstract base, the four concrete providers and the
manager module so callers can simply::

    from rdp_toolkit.tunnel import (
        ServeoTunnel, LocalhostRunTunnel, CloudflareTunnel,
        LocalTunnel, manager,
    )

NO NGROK — we don't ship support for it.  Default failover order is
``serveo -> localhost.run -> cloudflare -> localtunnel``.
"""
from __future__ import annotations

from . import manager
from .base import TunnelBase
from .cloudflare import CloudflareTunnel
from .localhost_run import LocalhostRunTunnel
from .localtunnel import LocalTunnel
from .serveo import ServeoTunnel

__all__ = [
    "TunnelBase",
    "ServeoTunnel",
    "LocalhostRunTunnel",
    "CloudflareTunnel",
    "LocalTunnel",
    "manager",
    "DEFAULT_PROVIDERS",
]

# Re-export the default priority list for CLI / docs consumers.
from .manager import DEFAULT_PROVIDERS  # noqa: E402
