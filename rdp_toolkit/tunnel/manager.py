"""Tunnel manager with multi-provider failover.

This module is the public entry point for the tunnel subpackage.  It
exposes a :class:`TunnelManager` class plus three module-level
functions (``list_tunnels``, ``status``, ``test``) that satisfy the
core-package contract consumed by :mod:`rdp_toolkit.cli`.

Failover order: ``serveo -> localhost.run -> cloudflare -> localtunnel``.
The first provider to return a valid URL wins; the rest are left
untouched.  No NGROK — we don't use it.
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Type

from .base import TunnelBase
from .cloudflare import CloudflareTunnel
from .localhost_run import LocalhostRunTunnel
from .localtunnel import LocalTunnel
from .serveo import ServeoTunnel

__all__ = [
    "TunnelManager",
    "list_tunnels",
    "status",
    "test",
    "stop_all",
    "start_with_failover",
]

_LOG = logging.getLogger(__name__)

#: Mapping of canonical provider names to their implementation classes.
#: Aliases (e.g. ``localhost_run`` for ``localhost.run``) are accepted too.
_PROVIDER_MAP: Dict[str, Type[TunnelBase]] = {
    "serveo": ServeoTunnel,
    "localhost.run": LocalhostRunTunnel,
    "localhost_run": LocalhostRunTunnel,
    "cloudflare": CloudflareTunnel,
    "localtunnel": LocalTunnel,
    "lt": LocalTunnel,
}

#: Default priority order — NO NGROK.  Defined once so both the
#: constructor default and the CLI help can reference it.
DEFAULT_PROVIDERS: List[str] = ["serveo", "localhost.run", "cloudflare", "localtunnel"]


class TunnelManager:
    """Manage a pool of tunnel providers with failover support."""

    def __init__(self, providers: Optional[List[str]] = None) -> None:
        """Construct a manager.

        ``providers`` is the ordered list of provider names to try during
        failover; defaults to :data:`DEFAULT_PROVIDERS`.
        """
        self.providers: List[str] = list(providers) if providers else list(DEFAULT_PROVIDERS)
        self._active: Dict[str, TunnelBase] = {}

    def list_tunnels(self) -> List[Dict[str, Any]]:
        """Return a list of all configured providers with their status."""
        out: List[Dict[str, Any]] = []
        for name in self.providers:
            entry: Dict[str, Any] = {
                "provider": name,
                "available": name in _PROVIDER_MAP,
                "alive": False,
                "url": "",
                "type": "",
                "bridge_required": False,
            }
            tunnel = self._active.get(name)
            if tunnel is not None:
                info = tunnel.info
                entry["alive"] = bool(info.get("alive"))
                entry["url"] = info.get("url", "")
                entry["type"] = info.get("type", "")
                entry["bridge_required"] = bool(info.get("bridge_required"))
                entry["host"] = info.get("host", "")
                entry["port"] = info.get("port", 0)
            out.append(entry)
        return out

    def status(self) -> Dict[str, Dict[str, Any]]:
        """Return a dict mapping provider name -> state dict."""
        return {entry["provider"]: entry for entry in self.list_tunnels()}

    def start_with_failover(self, local_port: int = 3389) -> Dict[str, Any]:
        """Try each provider in order; return the first success.

        On success: ``{"provider": <name>, "ok": True, ...tunnel_info}``.
        On total failure: ``{"provider": None, "ok": False, "errors": [...]}``.
        """
        errors: List[Dict[str, str]] = []
        for name in self.providers:
            cls = _PROVIDER_MAP.get(name)
            if cls is None:
                errors.append({"provider": name, "error": "unknown provider"})
                continue
            _LOG.info("Trying tunnel provider: %s", name)
            tunnel = cls(name=name, local_port=local_port)
            try:
                result = tunnel.start(local_port=local_port)
            except Exception as exc:  # noqa: BLE001 — provider may raise anything
                _LOG.warning("Provider %s failed: %s", name, exc)
                errors.append({"provider": name, "error": str(exc)})
                try:
                    tunnel.stop()
                except Exception:  # noqa: BLE001
                    pass
                continue
            self._active[name] = tunnel
            _LOG.info("Provider %s succeeded: %s", name, result.get("url"))
            return {"provider": name, "ok": True, **result}
        return {"provider": None, "ok": False, "errors": errors}

    def test(self, provider_name: str) -> Dict[str, Any]:
        """Start a single provider, capture its info, then stop it.

        If ``provider_name`` is ``"all"`` (or falsy), every configured
        provider is tested and the result is a dict keyed by provider
        name.
        """
        if not provider_name or provider_name == "all":
            return {name: self.test(name) for name in self.providers}
        cls = _PROVIDER_MAP.get(provider_name)
        if cls is None:
            return {"provider": provider_name, "ok": False, "error": "unknown provider"}
        tunnel = cls(name=provider_name, local_port=3389)
        try:
            result = tunnel.start(local_port=3389)
            return {"provider": provider_name, "ok": True, **result}
        except Exception as exc:  # noqa: BLE001 — surface any provider failure
            return {"provider": provider_name, "ok": False, "error": str(exc)}
        finally:
            try:
                tunnel.stop()
            except Exception:  # noqa: BLE001
                pass

    def stop_all(self) -> int:
        """Stop every active tunnel. Returns the count of tunnels stopped."""
        stopped = 0
        for name, tunnel in list(self._active.items()):
            try:
                tunnel.stop()
                stopped += 1
            except Exception:  # noqa: BLE001
                _LOG.warning("Failed to stop tunnel %s", name, exc_info=True)
        self._active.clear()
        return stopped

    def get_active(self) -> Optional[TunnelBase]:
        """Return the first active (alive) tunnel, or ``None``."""
        for tunnel in self._active.values():
            if tunnel.is_alive():
                return tunnel
        return None


# --------------------------------------------------------------------------- #
# Module-level default instance + convenience functions.  The core-package
# contract (consumed by rdp_toolkit.cli.cmd_tunnel) requires this module to
# expose `list_tunnels`, `status`, and `test` at module scope.  We delegate to
# a shared default TunnelManager so both functional and OO styles work.
# --------------------------------------------------------------------------- #
_default = TunnelManager()


def list_tunnels() -> List[Dict[str, Any]]:
    """Module-level wrapper — see :meth:`TunnelManager.list_tunnels`."""
    return _default.list_tunnels()


def status() -> Dict[str, Any]:
    """Module-level wrapper — see :meth:`TunnelManager.status`."""
    return _default.status()


def test(provider: str) -> Dict[str, Any]:
    """Module-level wrapper — see :meth:`TunnelManager.test`."""
    return _default.test(provider)


def stop_all() -> int:
    """Module-level wrapper — see :meth:`TunnelManager.stop_all`."""
    return _default.stop_all()


def start_with_failover(local_port: int = 3389) -> Dict[str, Any]:
    """Module-level wrapper — see :meth:`TunnelManager.start_with_failover`."""
    return _default.start_with_failover(local_port)
