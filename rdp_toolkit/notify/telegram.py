"""Telegram Bot API notification channel.

Sends a Markdown-formatted message to a chat via the Bot ``sendMessage``
endpoint::

    POST https://api.telegram.org/bot<token>/sendMessage
         form: chat_id=<id> text=<msg> parse_mode=Markdown

Markdown mode means ``*bold*`` works for the title and ``_italic_`` for
emphasis.  Telegram limits message bodies to 4096 characters — we
truncate to 3500 to leave headroom for the title.
"""
from __future__ import annotations

import logging
import urllib.parse
from typing import Any, Dict
from urllib import error, request

from .base import NotificationChannel

__all__ = ["TelegramChannel"]

_LOG = logging.getLogger(__name__)

_MAX_TEXT = 3500
_API_BASE = "https://api.telegram.org/bot"


class TelegramChannel(NotificationChannel):
    """Deliver messages via the Telegram Bot API."""

    name = "telegram"

    def __init__(self, bot_token: str, chat_id: str) -> None:
        """Construct the channel.

        ``bot_token`` is the ``<digits>:<hex>`` token from BotFather.
        ``chat_id`` is the numeric chat ID (channel, group or user) the
        bot will post to.  Both must be set for :meth:`is_configured` to
        return ``True``.
        """
        super().__init__(bot_token=bot_token, chat_id=chat_id)
        self.bot_token: str = (bot_token or "").strip()
        self.chat_id: str = str(chat_id or "").strip()

    def is_configured(self) -> bool:
        """Return ``True`` when ``bot_token`` and ``chat_id`` look valid."""
        token_ok = bool(self.bot_token) and ":" in self.bot_token
        chat_ok = bool(self.chat_id) and any(c.isdigit() for c in self.chat_id)
        return token_ok and chat_ok

    def send(self, title: str, body: str) -> bool:
        """POST ``sendMessage`` to the Bot API; return ``True`` on HTTP 2xx."""
        if not self.is_configured():
            _LOG.warning("telegram: not configured — skipping send")
            return False
        text = f"*{title}*\n{body}"
        if len(text) > _MAX_TEXT:
            text = text[: _MAX_TEXT - 1] + "\u2026"
        url = f"{_API_BASE}{self.bot_token}/sendMessage"
        form: Dict[str, Any] = {
            "chat_id": self.chat_id,
            "text": text,
            "parse_mode": "Markdown",
            "disable_web_page_preview": "true",
        }
        data = urllib.parse.urlencode(form).encode("utf-8")
        req = request.Request(
            url,
            data=data,
            headers={
                "Content-Type": "application/x-www-form-urlencoded",
                "User-Agent": "rdp-toolkit/9.0",
            },
            method="POST",
        )
        try:
            with request.urlopen(req, timeout=15) as resp:
                ok = 200 <= resp.status < 300
                if not ok:
                    _LOG.warning("telegram: API returned HTTP %s", resp.status)
                    return False
                # Telegram always returns 200 even on logical errors, so we
                # need to inspect the JSON envelope for ``ok: true``.
                import json
                try:
                    payload = json.loads(resp.read().decode("utf-8", "ignore"))
                except (ValueError, OSError):
                    payload = {}
                if not payload.get("ok"):
                    _LOG.warning(
                        "telegram: sendMessage failed: %s",
                        payload.get("description") or "unknown",
                    )
                    return False
                return True
        except (error.URLError, error.HTTPError, OSError, TimeoutError) as exc:
            _LOG.warning("telegram: send failed: %s", exc)
            return False
        except Exception as exc:  # noqa: BLE001 — never raise from send()
            _LOG.warning("telegram: unexpected error: %s", exc)
            return False
