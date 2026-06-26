"""Networking helpers: port probing, public-IP discovery, HTTP probes.

All functions are non-blocking beyond their explicit ``timeout`` argument
and never raise on network failure — they return ``None`` or a dict with
``ok=False`` so callers can use them in failover chains without wrapping
every call in try/except.
"""
from __future__ import annotations

import socket
import urllib.error
import urllib.request
from typing import Any, Dict, Optional
from urllib.parse import urlparse

__all__ = ["test_port", "get_public_ip", "probe_http", "parse_tunnel_url"]

_USER_AGENT = "rdp-toolkit/9.0 (+https://github.com/usekarne/github-rdp-mega-toolkit)"


def test_port(host: str, port: int, timeout: float = 2.0) -> bool:
    """Return ``True`` if a TCP connection to ``host:port`` succeeds."""
    if not host or not (0 < port < 65536):
        return False
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except (socket.timeout, ConnectionRefusedError, OSError, ValueError):
        return False


def get_public_ip(timeout: float = 5.0) -> Optional[str]:
    """Return the host's public IPv4/IPv6 address, or ``None`` if offline.

    Queries a small list of well-known echo services in order and returns
    the first successful response.
    """
    services = [
        "https://api.ipify.org",
        "https://ifconfig.me/ip",
        "https://icanhazip.com",
    ]
    for url in services:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                if 200 <= resp.status < 400:
                    return resp.read().decode("utf-8", errors="ignore").strip()
        except (urllib.error.URLError, OSError, ValueError):
            continue
    return None


def probe_http(url: str, timeout: float = 5.0) -> Dict[str, Any]:
    """Probe ``url`` with a HEAD-ish GET, returning a structured result.

    The returned dict always contains the keys ``url``, ``ok``,
    ``status``, ``final_url`` and ``error``.  ``ok`` is ``True`` when the
    HTTP status code is in the 2xx–3xx range.
    """
    result: Dict[str, Any] = {
        "url": url,
        "ok": False,
        "status": None,
        "final_url": url,
        "error": None,
    }
    if not url:
        result["error"] = "empty url"
        return result
    try:
        req = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            result["status"] = resp.status
            result["final_url"] = resp.url or url
            result["ok"] = 200 <= resp.status < 400
    except urllib.error.HTTPError as exc:
        # HTTPError is also a valid response — capture the status code.
        result["status"] = exc.code
        result["final_url"] = getattr(exc, "url", None) or url
        result["ok"] = 200 <= exc.code < 400
        result["error"] = f"HTTP {exc.code}"
    except (urllib.error.URLError, OSError, ValueError) as exc:
        result["error"] = str(exc)
    return result


def parse_tunnel_url(url: str) -> Dict[str, Any]:
    """Parse a tunnel URL into its component parts.

    Accepts forms such as::

        https://abc123.serveo.net
        tcp://localhost:3389
        abc123.localhost.run            (scheme-less → assumed https)
        rdp.example.com:3389            (scheme-less with port)

    Returns a dict with ``raw``, ``scheme``, ``host``, ``port`` and
    ``type`` (``"http"`` for http/https/ws/wss, ``"tcp"`` for tcp/rdp).
    """
    raw = (url or "").strip()
    if not raw:
        return {"raw": "", "scheme": "", "host": "", "port": 0, "type": "http"}

    normalised = raw if "://" in raw else "https://" + raw
    parsed = urlparse(normalised)
    scheme = (parsed.scheme or "https").lower()
    host = parsed.hostname or ""
    port = parsed.port
    if port is None:
        port = 443 if scheme in ("https", "wss") else 80

    tunnel_type = "tcp" if scheme in ("tcp", "rdp") else "http"
    return {
        "raw": raw,
        "scheme": scheme,
        "host": host,
        "port": port,
        "type": tunnel_type,
    }
