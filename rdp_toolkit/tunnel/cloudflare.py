"""Cloudflare TryCloudflare tunnel provider.

``cloudflared`` is Cloudflare's official client.  The ``tunnel --url``
subcommand spins up an ephemeral "quick" tunnel and prints a public
``https://<random>.trycloudflare.com`` URL that proxies traffic to the
local port.

Because TryCloudflare is HTTP/HTTPS-fronted, raw TCP traffic (such as
RDP) cannot be consumed directly from the printed URL — a client-side
``cloudflared access tcp`` bridge is needed.  We therefore set
``bridge_required=True`` in :attr:`info`.

Binary provisioning
-------------------
If ``cloudflared`` is not on ``$PATH`` we download the appropriate
prebuilt binary from the official GitHub release into
``~/.config/rdp-toolkit/bin/cloudflared`` (or ``.exe`` on Windows) and
``chmod +x`` it.  The download happens *before* the 60-second startup
timeout starts ticking.
"""
from __future__ import annotations

import os
import platform as _platform
import shutil
import stat
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path
from typing import Dict, Optional, Union

from ..utils.system import config_dir, detect_platform
from .base import TunnelBase

__all__ = ["CloudflareTunnel"]

# ``https://abc-def-ghi.trycloudflare.com`` printed on a banner line.
_URL_RE = r"(https://[a-z0-9-]+\.trycloudflare\.com)"

_BASE_URL = "https://github.com/cloudflare/cloudflared/releases/latest/download"
_USER_AGENT = "rdp-toolkit/9.0 (+https://github.com/usekarne/github-rdp-mega-toolkit)"


class CloudflareTunnel(TunnelBase):
    """Expose ``local_port`` through Cloudflare's ephemeral quick tunnel.

    The public URL is HTTPS-fronted and therefore unsuitable for raw
    TCP consumption — callers must run ``cloudflared access tcp`` on the
    client side.  :attr:`bridge_required` is set to ``True`` to signal
    this.
    """

    name = "cloudflare"
    startup_timeout = 60

    def start(self, local_port: int = 3389) -> Dict[str, Union[str, int, bool]]:
        """Start the cloudflared quick tunnel.

        Raises
        ------
        RuntimeError
            If the binary cannot be located or downloaded, or no URL
            appears in cloudflared's output before the startup timeout.
        """
        self.local_port = local_port
        binary = self._ensure_binary()
        cmd = [binary, "tunnel", "--url", f"tcp://localhost:{local_port}"]
        self._run_command(cmd, capture=True)
        captured = self._wait_for_url(
            self.startup_timeout,
            checker=lambda: self.parse_log_for_url(_URL_RE),
        )
        if not captured:
            self.stop()
            raise RuntimeError(
                f"cloudflare: no URL captured after {self.startup_timeout}s "
                "(cloudflared may be rate-limited — try again later)"
            )
        # ``captured`` is the full ``https://...`` URL.
        self.url = captured
        host = captured.split("://", 1)[1].split("/", 1)[0]
        # Strip any trailing path; cloudflare quick tunnels print bare host.
        host = host.split(":", 1)[0]
        self.host, self.port = host, 443
        self.tunnel_type = "http"
        self.bridge_required = True
        return {
            "url": self.url,
            "host": self.host,
            "port": self.port,
            "type": self.tunnel_type,
            "bridge_required": self.bridge_required,
        }

    def stop(self) -> None:
        """Terminate the cloudflared process and release resources."""
        self._terminate_process()
        self.cleanup()

    def is_alive(self) -> bool:
        """Return ``True`` while the cloudflared process is running."""
        return self.process is not None and self.process.poll() is None

    # ------------------------------------------------------------------ #
    # Binary provisioning
    # ------------------------------------------------------------------ #
    def _ensure_binary(self) -> str:
        """Return path to a usable ``cloudflared`` binary.

        Order of preference:
        1. ``cloudflared`` already on ``$PATH`` (``shutil.which``).
        2. Previously downloaded copy in ``~/.config/rdp-toolkit/bin/``.
        3. Freshly downloaded from the official GitHub release.
        """
        existing = self._which("cloudflared")
        if existing:
            return existing
        bin_dir = config_dir() / "bin"
        bin_dir.mkdir(parents=True, exist_ok=True)
        suffix = ".exe" if os.name == "nt" else ""
        bin_path = bin_dir / f"cloudflared{suffix}"
        if bin_path.exists() and os.access(str(bin_path), os.X_OK):
            return str(bin_path)
        url, needs_extract = self._download_url()
        self._download(url, bin_path, needs_extract)
        return str(bin_path)

    def _download_url(self) -> tuple[str, bool]:
        """Return the (URL, needs_tar_extract) tuple for this platform."""
        plat = detect_platform()
        arch = (_platform.machine() or "").lower()
        is_arm = "aarch64" in arch or "arm64" in arch
        if plat == "windows" or os.name == "nt":
            return f"{_BASE_URL}/cloudflared-windows-amd64.exe", False
        if plat == "mac":
            suffix = "arm64" if is_arm else "amd64"
            return f"{_BASE_URL}/cloudflared-darwin-{suffix}.tgz", True
        # Default: Linux (also used for Termux/Android & unknown Unix).
        suffix = "arm64" if is_arm else "amd64"
        return f"{_BASE_URL}/cloudflared-linux-{suffix}", False

    @staticmethod
    def _download(url: str, dest: Path, needs_extract: bool) -> None:
        """Download ``url`` to ``dest``; if a .tgz, extract the binary."""
        dest.parent.mkdir(parents=True, exist_ok=True)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = resp.read()
        except Exception as exc:  # pragma: no cover - network-dependent
            raise RuntimeError(f"cloudflared: download failed from {url}: {exc}") from exc
        if not needs_extract:
            dest.write_bytes(data)
        else:
            with tempfile.TemporaryDirectory() as tmp:
                tgz = Path(tmp) / "cloudflared.tgz"
                tgz.write_bytes(data)
                with tarfile.open(tgz, "r:gz") as tar:
                    tar.extractall(tmp)  # noqa: S202 — trusted source
                # Find the extracted binary (named cloudflared or cloudflared.exe).
                extracted = None
                for candidate in Path(tmp).iterdir():
                    if candidate.name.startswith("cloudflared"):
                        extracted = candidate
                        break
                if extracted is None:
                    raise RuntimeError("cloudflared: archive contained no binary")
                shutil.move(str(extracted), str(dest))
        # chmod +x on POSIX.
        if os.name == "posix":
            try:
                dest.chmod(dest.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
            except OSError:
                pass
