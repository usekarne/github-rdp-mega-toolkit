"""Auto-config generation and YAML loading for RDP Mega Toolkit v9.

The toolkit ships with sensible per-platform defaults (tunnel priority,
software list, optimization profile, notify channels).  ``generate_config``
materialises those defaults into ``~/.config/rdp-toolkit/config.yaml``
and ``load_config`` reads it back, deep-merging any user overrides on top
of the defaults so partial configs always work.
"""
from __future__ import annotations

import os
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, Optional

try:
    import yaml
except ImportError as _exc:  # pragma: no cover - pyyaml is a declared dep
    yaml = None
    _YAML_IMPORT_ERROR = _exc
else:
    _YAML_IMPORT_ERROR = None

from .utils.system import config_dir, detect_platform

__all__ = [
    "CONFIG_DIR",
    "CONFIG_FILE",
    "TUNNEL_PRIORITY",
    "PROFILES",
    "SOFTWARE_BY_PLATFORM",
    "default_config",
    "merge_defaults",
    "generate_config",
    "load_config",
]

CONFIG_DIR = config_dir()
CONFIG_FILE = CONFIG_DIR / "config.yaml"

# Tunnel priority — NO NGROK.  Tried left-to-right at session start.
TUNNEL_PRIORITY = ["serveo", "localhost.run", "cloudflare", "localtunnel"]

# Optimization profiles selectable from the CLI.
PROFILES: Dict[str, Dict[str, Any]] = {
    "productivity": {
        "description": "Balanced for daily productivity RDP work",
        "xfreerdp_args": [
            "/cert:ignore",
            "+fonts",
            "+aero",
            "+window-drag",
            "+menu-anims",
            "/compression-level:2",
            "/gfx:AVC444",
        ],
        "resolution": "1920x1080",
        "color_depth": 32,
        "audio": "sys:alsa",
    },
    "gaming": {
        "description": "Low-latency profile for gaming / multimedia",
        "xfreerdp_args": [
            "/cert:ignore",
            "/gfx:AVC444",
            "/gfx-hw:1",
            "/network:auto",
            "+glyph-cache",
            "-theming",
        ],
        "resolution": "1920x1080",
        "color_depth": 32,
        "audio": "sys:alsa",
    },
    "minimal": {
        "description": "Lightweight profile for slow links / Termux",
        "xfreerdp_args": [
            "/cert:ignore",
            "-aero",
            "-themes",
            "-wallpaper",
            "-window-drag",
            "-menu-anims",
            "/compression-level:2",
        ],
        "resolution": "1280x720",
        "color_depth": 16,
        "audio": "off",
    },
}

SOFTWARE_BY_PLATFORM: Dict[str, list] = {
    "kali": ["xfreerdp2-x11", "openssh-client", "socat", "apache2-utils", "curl", "jq"],
    "ubuntu": ["freerdp2-x11", "openssh-client", "socat", "curl", "jq"],
    "windows": ["freerdp", "openssh", "socat"],
    "android": ["termux-api", "openssh", "socat", "curl"],
}

NOTIFY_DEFAULTS: Dict[str, Dict[str, Any]] = {
    "telegram": {"enabled": False, "bot_token": "", "chat_id": ""},
    "discord": {"enabled": False, "webhook_url": ""},
    "email": {"enabled": False, "smtp_host": "", "smtp_port": 587, "to": ""},
}


def default_config(
    platform: Optional[str] = None,
    profile: str = "productivity",
    hours: int = 6,
) -> Dict[str, Any]:
    """Build a default config dict for ``platform`` / ``profile`` / ``hours``."""
    plat = platform or detect_platform()
    return {
        "version": "9.0.0",
        "platform": plat,
        "profile": profile,
        "session": {
            "hours": int(hours),
            "username": "rdpuser",
            "password": "",
            "domain": "",
        },
        "tunnel": {
            "priority": list(TUNNEL_PRIORITY),
            "providers": {
                "serveo": {"server": "serveo.net", "port": 22, "remote_port": 0},
                "localhost.run": {"server": "nokey@localhost.run", "port": 22},
                "cloudflare": {"bin": "cloudflared", "protocol": "quic"},
                "localtunnel": {"bin": "lt"},
            },
        },
        "software": list(SOFTWARE_BY_PLATFORM.get(plat, SOFTWARE_BY_PLATFORM["ubuntu"])),
        "rdp": deepcopy(PROFILES.get(profile, PROFILES["productivity"])),
        "notify": deepcopy(NOTIFY_DEFAULTS),
        "vm": {
            "enabled": plat in ("kali", "ubuntu"),
            "default": "kali",
            "docker_image_prefix": "rdp-toolkit/",
        },
    }


def merge_defaults(user_config: Dict[str, Any], defaults: Dict[str, Any]) -> Dict[str, Any]:
    """Deep-merge ``user_config`` on top of ``defaults`` (user wins).

    Lists are replaced wholesale (not concatenated) — this matches user
    expectations when overriding e.g. ``tunnel.priority``.
    """
    result = deepcopy(defaults)

    def _merge(base: Dict[str, Any], overlay: Dict[str, Any]) -> Dict[str, Any]:
        for key, value in overlay.items():
            if key in base and isinstance(base[key], dict) and isinstance(value, dict):
                _merge(base[key], value)
            else:
                base[key] = deepcopy(value)
        return base

    return _merge(result, user_config)


def _require_yaml() -> None:
    if yaml is None:  # pragma: no cover - pyyaml is a declared dep
        raise RuntimeError(
            "PyYAML is required for config handling. Install it with: pip install pyyaml"
        ) from _YAML_IMPORT_ERROR


def generate_config(
    platform: Optional[str] = None,
    profile: str = "productivity",
    hours: int = 6,
    path: Optional[Path] = None,
) -> Path:
    """Write a fresh YAML config to ``path`` (default: ``CONFIG_FILE``).

    The file is created with mode ``0600`` because it may eventually hold
    secrets (notify tokens, etc.).  Returns the path written.
    """
    _require_yaml()
    plat = platform or detect_platform()
    if profile not in PROFILES:
        raise ValueError(f"unknown profile: {profile!r} (expected one of {list(PROFILES)})")
    cfg = default_config(plat, profile, hours)
    target = Path(path) if path else CONFIG_FILE
    target.parent.mkdir(parents=True, exist_ok=True)
    with open(target, "w", encoding="utf-8") as fh:
        yaml.safe_dump(cfg, fh, sort_keys=False, default_flow_style=False)
    try:
        os.chmod(target, 0o600)
    except OSError:
        # chmod can fail on some filesystems (e.g. Windows) — not fatal.
        pass
    return target


def load_config(path: Optional[Path] = None) -> Dict[str, Any]:
    """Load the YAML config (generating one first if absent).

    User values are deep-merged on top of platform defaults so a partial
    config always yields a fully-populated dict.
    """
    _require_yaml()
    target = Path(path) if path else CONFIG_FILE
    user_cfg: Dict[str, Any] = {}
    if target.exists():
        try:
            with open(target, "r", encoding="utf-8") as fh:
                loaded = yaml.safe_load(fh)
            if isinstance(loaded, dict):
                user_cfg = loaded
        except (yaml.YAMLError, OSError):
            user_cfg = {}
    else:
        generate_config(path=target)

    plat = user_cfg.get("platform") or detect_platform()
    profile = user_cfg.get("profile") or "productivity"
    session = user_cfg.get("session") or {}
    hours = session.get("hours", 6) if isinstance(session, dict) else 6
    defaults = default_config(plat, profile, hours)
    return merge_defaults(user_cfg, defaults)
