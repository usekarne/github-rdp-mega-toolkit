"""Abstract base class for every notification channel.

A *channel* is anything that can deliver a ``(title, body)`` message to a
human: a Discord webhook, a Telegram bot, a Slack webhook, an SMTP email,
etc.  Concrete subclasses live next to this module (``discord.py``,
``telegram.py``, ``slack.py``) and implement :meth:`NotificationChannel.send`
on top of :mod:`urllib.request`.

The contract is intentionally minimal — two methods, both returning
booleans — so adding a new channel is a 30-line exercise.  The manager
(:mod:`rdp_toolkit.notify.manager`) auto-discovers configured channels and
fans a single message out to all of them in parallel.
"""
from __future__ import annotations

import abc
from typing import Any, Dict

__all__ = ["NotificationChannel"]


class NotificationChannel(abc.ABC):
    """Abstract notification channel.

    Subclasses MUST implement :meth:`send` and :meth:`is_configured`.
    The :attr:`name` attribute is used by :class:`NotificationManager` for
    logging and for the ``list_channels()`` report.
    """

    #: Human-readable channel name (e.g. ``"discord"``).
    name: str = "abstract"

    def __init__(self, **kwargs: Any) -> None:
        """Store arbitrary kwargs as attributes for subclass use."""
        self.config: Dict[str, Any] = dict(kwargs)

    @abc.abstractmethod
    def send(self, title: str, body: str) -> bool:
        """Deliver ``title`` + ``body`` to the channel.

        Returns ``True`` on success, ``False`` on any failure (network
        error, non-2xx HTTP response, malformed credentials, ...).  Concrete
        subclasses must NOT raise — they should catch all expected
        exceptions and return ``False`` so the manager can keep going on
        the remaining channels.
        """

    @abc.abstractmethod
    def is_configured(self) -> bool:
        """Return ``True`` when the channel has all required credentials.

        For example, a Discord channel is configured when its
        ``webhook_url`` is non-empty and starts with ``https://``.
        """

    @property
    def info(self) -> Dict[str, Any]:
        """Return a metadata dict used by the manager's ``list_channels()``."""
        return {
            "name": self.name,
            "configured": self.is_configured(),
            "config": self._safe_config(),
        }

    def _safe_config(self) -> Dict[str, Any]:
        """Return ``self.config`` with sensitive fields redacted."""
        redacted: Dict[str, Any] = {}
        sensitive = ("token", "webhook_url", "bot_token", "password", "api_key", "secret")
        for key, value in self.config.items():
            if any(s in key.lower() for s in sensitive):
                redacted[key] = "<redacted>" if value else ""
            else:
                redacted[key] = value
        return redacted

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"<{type(self).__name__} name={self.name!r} configured={self.is_configured()}>"
