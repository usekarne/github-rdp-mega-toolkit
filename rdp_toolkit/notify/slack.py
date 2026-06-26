"""Slack incoming webhook notification channel.

Posts a single message per call to a Slack workspace webhook URL.

The webhook URL has the form: hooks.slack.com/services/<TEAM>/<BOT>/<SECRET>
(documented at api.slack.com/messaging/webhooks). We never embed a live URL
here — the user supplies their own via config.

Slack's incoming webhooks accept a JSON body with ``text`` (plain string)
or richer ``blocks`` / ``attachments`` payloads.  We use the simplest
``text`` form, with Slack's own markdown flavour: ``*bold*`` for the
title and newlines preserved as-is in the body.
"""
from __future__ import annotations

import json
import logging
from typing import Any, Dict
from urllib import error, request

from .base import NotificationChannel

__all__ = ["SlackChannel"]

_LOG = logging.getLogger(__name__)

_MAX_TEXT = 2900  # Slack allows ~3000 chars per text block


class SlackChannel(NotificationChannel):
    """Deliver messages via a Slack incoming webhook."""

    name = "slack"

    def __init__(self, webhook_url: str) -> None:
        """Construct the channel.

        ``webhook_url`` is the full Slack webhook URL (starts with the
        Slack hooks hostname followed by ``/services/``).
        """
        super().__init__(webhook_url=webhook_url)
        self.webhook_url: str = (webhook_url or "").strip()

    def is_configured(self) -> bool:
        """Return ``True`` when the webhook URL looks like a Slack one."""
        # Match by hostname + path prefix without hardcoding the full URL
        # (Push Protection will block commits containing literal webhook URLs)
        try:
            from urllib.parse import urlparse
            p = urlparse(self.webhook_url)
            return (p.scheme == "https" and p.netloc == "hooks.slack.com"
                    and p.path.startswith("/services/"))
        except Exception:
            return False

    def send(self, title: str, body: str) -> bool:
        """POST the message to the webhook; return ``True`` on HTTP 2xx."""
        if not self.is_configured():
            _LOG.warning("slack: not configured — skipping send")
            return False
        text = f"*{title}*\n{body}"
        if len(text) > _MAX_TEXT:
            text = text[: _MAX_TEXT - 1] + "\u2026"
        payload: Dict[str, Any] = {"text": text, "mrkdwn": True}
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
                    _LOG.warning("slack: webhook returned HTTP %s", resp.status)
                    return False
                # Slack returns the literal string "ok" on success and
                # a human-readable error message (e.g. "no_text") on failure.
                try:
                    response_text = resp.read().decode("utf-8", "ignore").strip()
                except OSError:
                    response_text = ""
                if response_text and response_text != "ok":
                    _LOG.warning("slack: webhook rejected payload: %s", response_text)
                    return False
                return True
        except (error.URLError, error.HTTPError, OSError, TimeoutError) as exc:
            _LOG.warning("slack: send failed: %s", exc)
            return False
        except Exception as exc:  # noqa: BLE001 — never raise from send()
            _LOG.warning("slack: unexpected error: %s", exc)
            return False
