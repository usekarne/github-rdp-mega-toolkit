"""Multi-channel notification manager.

Reads the ``notify`` section of :mod:`rdp_toolkit.config` (a dict with
``discord`` / ``telegram`` / ``slack`` sub-dicts, each carrying an
``enabled`` flag and the channel-specific credentials) and instantiates
only the channels that are both enabled AND properly configured.

Public surface:

* :class:`NotificationManager` — OO API.
* :func:`send` / :func:`list_channels` — module-level wrappers backed by a
  shared default instance (constructed from the empty default config; the
  CLI normally rebuilds a manager from the loaded config before sending).

All HTTP/transport errors are caught inside each channel's ``send()`` —
the manager never raises, it returns ``[(channel_name, success_bool), ...]``
so the CLI can render a per-channel status table.
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Tuple

from .base import NotificationChannel
from .discord import DiscordChannel
from .slack import SlackChannel
from .telegram import TelegramChannel

__all__ = [
    "NotificationManager",
    "CHANNEL_CLASSES",
    "send",
    "list_channels",
]

_LOG = logging.getLogger(__name__)

#: Mapping of canonical channel name -> implementation class.  Used by the
#: manager to auto-discover configured channels and by the CLI to render
#: help text.
CHANNEL_CLASSES: Dict[str, type] = {
    "discord": DiscordChannel,
    "telegram": TelegramChannel,
    "slack": SlackChannel,
}


class NotificationManager:
    """Fan-out a message to every configured notification channel."""

    def __init__(self, config: Optional[Dict[str, Any]] = None) -> None:
        """Build a manager from the ``notify`` section of the toolkit config.

        ``config`` shape (mirrors :data:`rdp_toolkit.config.NOTIFY_DEFAULTS`)::

            {
              "telegram": {"enabled": True, "bot_token": "...", "chat_id": "123"},
              "discord":  {"enabled": True, "webhook_url": "https://..."},
              "slack":    {"enabled": False, "webhook_url": ""},
              "email":    {"enabled": False, ...},  # not implemented yet
            }

        Passing ``None`` (or an empty dict) yields a manager with no
        channels — useful for tests and for ``list_channels()`` reporting.
        """
        self.config: Dict[str, Any] = dict(config or {})
        self._channels: List[NotificationChannel] = []
        self._build_channels()

    def _build_channels(self) -> None:
        """Instantiate every channel that's both ``enabled`` and configured."""
        self._channels.clear()
        for name, cls in CHANNEL_CLASSES.items():
            block = self.config.get(name) or {}
            if not isinstance(block, dict):
                continue
            if not block.get("enabled"):
                continue
            try:
                channel = self._instantiate(name, cls, block)
            except Exception as exc:  # noqa: BLE001 — never fail manager construction
                _LOG.warning("notify: failed to build %s channel: %s", name, exc)
                continue
            if channel is None:
                continue
            self._channels.append(channel)
            _LOG.info(
                "notify: registered %s channel (configured=%s)",
                name, channel.is_configured(),
            )

    @staticmethod
    def _instantiate(
        name: str, cls: type, block: Dict[str, Any]
    ) -> Optional[NotificationChannel]:
        """Construct a single channel instance from its config block."""
        if name == "discord":
            return DiscordChannel(
                webhook_url=str(block.get("webhook_url") or ""),
                username=str(block.get("username") or "RDP Toolkit Bot"),
            )
        if name == "telegram":
            return TelegramChannel(
                bot_token=str(block.get("bot_token") or ""),
                chat_id=str(block.get("chat_id") or ""),
            )
        if name == "slack":
            return SlackChannel(
                webhook_url=str(block.get("webhook_url") or ""),
            )
        # Unknown channel — silently skip so future channel types don't crash.
        _LOG.debug("notify: skipping unknown channel %r", name)
        return None

    # ------------------------------------------------------------------ #
    # Public API
    # ------------------------------------------------------------------ #
    def send_all(self, title: str, body: str) -> List[Tuple[str, bool]]:
        """Send ``title``+``body`` to every configured channel.

        Returns a list of ``(channel_name, success_bool)`` tuples — one
        per registered channel, in registration order.  Channels that
        were enabled but not properly configured are still attempted (they
        will return ``False`` from their own ``send``).
        """
        results: List[Tuple[str, bool]] = []
        if not self._channels:
            _LOG.info("notify: no channels configured — skipping send_all")
            return results
        for channel in self._channels:
            try:
                ok = bool(channel.send(title, body))
            except Exception as exc:  # noqa: BLE001 — defensive, channel.send already swallows
                _LOG.warning("notify: %s.send raised: %s", channel.name, exc)
                ok = False
            results.append((channel.name, ok))
            if ok:
                _LOG.info("notify: %s delivery OK", channel.name)
            else:
                _LOG.warning("notify: %s delivery FAILED", channel.name)
        return results

    def list_channels(self) -> List[Dict[str, Any]]:
        """Return a per-channel metadata list (name + configured status).

        Includes every channel type the manager *knows about* (see
        :data:`CHANNEL_CLASSES`), not just the registered ones, so the CLI
        can show users which channels are available vs. configured.
        """
        out: List[Dict[str, Any]] = []
        registered = {c.name: c for c in self._channels}
        for name in CHANNEL_CLASSES:
            if name in registered:
                out.append(registered[name].info)
            else:
                block = self.config.get(name) or {}
                enabled = bool(isinstance(block, dict) and block.get("enabled"))
                out.append({
                    "name": name,
                    "configured": False,
                    "enabled": enabled,
                    "registered": False,
                })
        return out

    def get_channel(self, name: str) -> Optional[NotificationChannel]:
        """Return the registered channel named ``name`` (or ``None``)."""
        for channel in self._channels:
            if channel.name == name:
                return channel
        return None

    def reload(self, config: Dict[str, Any]) -> None:
        """Replace the config and rebuild the channel pool in-place."""
        self.config = dict(config or {})
        self._build_channels()


# --------------------------------------------------------------------------- #
# Module-level default instance + convenience wrappers.
#
# The default instance is built from an empty config so the manager never
# raises during package import — the CLI is expected to call
# ``NotificationManager(load_config()['notify'])`` explicitly before sending
# real notifications.
# --------------------------------------------------------------------------- #
_default = NotificationManager({})


def send(title: str, body: str) -> List[Tuple[str, bool]]:
    """Module-level wrapper — see :meth:`NotificationManager.send_all`."""
    return _default.send_all(title, body)


def list_channels() -> List[Dict[str, Any]]:
    """Module-level wrapper — see :meth:`NotificationManager.list_channels`."""
    return _default.list_channels()
