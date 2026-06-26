"""RDP Mega Toolkit v9 — cross-platform (Kali/Windows/Android) RDP automation.

This package provides a single CLI (`python -m rdp_toolkit`) that can:
  * install platform-specific dependencies (xfreerdp, ssh, socat, ...)
  * start/stop/status RDP sessions exposed through public tunnels
  * spin up local Docker VMs (Kali/Ubuntu/Windows) for sandboxed RDP
  * rotate passwords, kill runaway runs, and self-diagnose (`doctor`)

Only the Python standard library and PyYAML are required at runtime.
"""
from __future__ import annotations

__version__ = "9.0.0"
__author__ = "github-rdp-mega-toolkit maintainers"
__license__ = "MIT"
__all__ = ["__version__", "__author__", "__license__", "get_version"]

# Tunnel priority — NO NGROK. These are the providers we ship support for.
SUPPORTED_TUNNELS = ("serveo", "localhost.run", "cloudflare", "localtunnel")

# Optimization profiles selectable from the CLI (`start --profile ...`).
SUPPORTED_PROFILES = ("productivity", "gaming", "minimal")


def get_version() -> str:
    """Return the package version string (e.g. ``"9.0.0"``)."""
    return __version__


def _selfcheck() -> bool:
    """Lightweight import self-check used by ``rdp_toolkit doctor``.

    Returns ``True`` when the core submodules import cleanly.  Sibling
    subpackages (``tunnel``, ``vm``, ``rdp``, ``platforms``, ``notify``)
    are tested lazily by the CLI itself, so we only probe the always-present
    core here.
    """
    try:  # pragma: no cover - trivial guard
        from . import config as _cfg  # noqa: F401
        from . import utils as _utils  # noqa: F401
        from .utils import system as _sys  # noqa: F401
        return True
    except Exception:  # pragma: no cover
        return False
