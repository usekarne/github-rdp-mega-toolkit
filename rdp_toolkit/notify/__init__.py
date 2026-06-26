"""Notify subpackage — multi-channel notifications for the RDP toolkit.

Re-exports the abstract base, the three concrete channel implementations
(Discord / Telegram / Slack) and the manager module so callers can write::

    from rdp_toolkit.notify import (
        NotificationManager, NotificationChannel,
        DiscordChannel, TelegramChannel, SlackChannel,
        send, list_channels,
    )

All channels are pure-stdlib (``urllib.request`` + ``json``) — no
third-party HTTP libraries are required.  Network errors are swallowed
inside each channel's ``send()`` so the manager can keep going on the
remaining channels.
"""
from __future__ import annotations

from . import base, manager
from .base import NotificationChannel
from .discord import DiscordChannel
from .manager import CHANNEL_CLASSES, NotificationManager, list_channels, send
from .slack import SlackChannel
from .telegram import TelegramChannel

__all__ = [
    "NotificationChannel",
    "NotificationManager",
    "DiscordChannel",
    "TelegramChannel",
    "SlackChannel",
    "CHANNEL_CLASSES",
    "base",
    "manager",
    "send",
    "list_channels",
]
