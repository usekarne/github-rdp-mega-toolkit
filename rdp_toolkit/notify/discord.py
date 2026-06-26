"""Discord webhook notification channel.

Sends a single message per call to a Discord channel webhook.  The
webhook URL looks like::

    https://discord.com/api/webhooks/<id>/<token>

We deliberately use the ``content`` field (not ``embeds``) so the message
shows up plainly in mobile and desktop clients without extra rendering.
Markdown ``**bold**`` for the title is honoured by Discord natively.
"""
from __future__ import annotations

import json
import logging
from typing import Any, Dict
from urllib import error, request

from .base import NotificationChannel

__all__ = ["DiscordChannel"]

_LOG = logging.getLogger(__name__)

#: Discord rejects payloads larger than 2000 characters in ``content``.
_MAX_CONTENT = 1900


class DiscordChannel(NotificationChannel):
    """Deliver messages via a Discord incoming webhook."""

    name = "discord"

    def __init__(self, webhook_url: str, username: str = "RDP Toolkit Bot") -> None:
        """Construct the channel.

        ``webhook_url`` is the full Discord webhook URL.  ``username``
        overrides the bot's display name (defaults to ``"RDP Toolkit Bot"``).
        """
        super().__init__(webhook_url=webhook_url, username=username)
        self.webhook_url: str = webhook_url or ""
        self.username: str = username or "RDP Toolkit Bot"

    def is_configured(self) -> bool:
        """Return ``True`` when the webhook URL is set and looks valid."""
        url = self.webhook_url.strip()
        return url.startswith("https://discord.com/api/webhooks/") or url.startswith(
            "https://discordapp.com/api/webhooks/"
        )

    def send(self, title: str, body: str) -> bool:
        """POST the message to the webhook; return ``True`` on HTTP 2xx."""
        if not self.is_configured():
            _LOG.warning("discord: not configured — skipping send")
            return False
        content = f"**{title}**\n{body}"
        if len(content) > _MAX_CONTENT:
            content = content[: _MAX_CONTENT - 1] + "\u2026"
        payload: Dict[str, Any] = {
            "username": self.username,
            "content": content,
        }
        data = json.dumps(payload).encode("utf-8")
        req = request.Request(
            self.webhook_url,
            data=data,
            headers={"Content-Type": "application/json", "User-Agent": "rdp-toolkit/9.0"},
            method="POST",
        )
        try:
            with request.urlopen(req, timeout=10) as resp:
                ok = 200 <= resp.status < 300
                if not ok:
                    _LOG.warning("discord: webhook returned HTTP %s", resp.status)
                return ok
        except (error.URLError, error.HTTPError, OSError, TimeoutError) as exc:
            _LOG.warning("discord: send failed: %s", exc)
            return False
        except Exception as exc:  # noqa: BLE001 — never raise from send()
            _LOG.warning("discord: unexpected error: %s", exc)
            return False
