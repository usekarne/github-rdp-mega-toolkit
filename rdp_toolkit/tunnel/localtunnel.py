"""localtunnel provider — Node.js based HTTPS tunnel via ``loca.lt``.

`localtunnel <https://theboroer.github.io/localtunnel-www/>`_ is a
small npm package that exposes a local port behind a public
``https://<subdomain>.loca.lt`` URL.  It requires Node.js (and ``npx``)
to be installed on the host — we warn loudly if either is missing.

Typical session::

    $ npx --yes localtunnel 3389
    your url is: https://random-words-1234.loca.lt

Because loca.lt is HTTPS-fronted, raw TCP traffic (such as RDP) cannot
be consumed directly from the printed URL — a TCP-over-HTTP bridge is
needed on the client side.  We leave ``bridge_required`` at ``False``
by default but expose the ``type`` field as ``"http"`` so callers can
decide.
"""
from __future__ import annotations

import sys
import warnings
from typing import Dict, Optional, Union

from .base import TunnelBase

__all__ = ["LocalTunnel"]

# ``your url is: https://abc-def-1234.loca.lt``
_URL_RE = r"(https://[a-z0-9-]+\.loca\.lt)"


class LocalTunnel(TunnelBase):
    """Expose ``local_port`` via the ``localtunnel`` npm package.

    Requires Node.js (``node``) and ``npx`` on ``$PATH``.  If they are
    missing, :meth:`start` raises :class:`RuntimeError` after emitting a
    :class:`UserWarning`.
    """

    name = "localtunnel"
    startup_timeout = 50

    def start(self, local_port: int = 3389) -> Dict[str, Union[str, int, bool]]:
        """Start localtunnel via ``npx --yes localtunnel <port>``.

        Raises
        ------
        RuntimeError
            If Node.js / npx are missing, or no URL appears before the
            startup timeout elapses.
        """
        self.local_port = local_port
        node_bin = self._which("node")
        npx_bin = self._which("npx")
        if not node_bin or not npx_bin:
            warnings.warn(
                "localtunnel requires Node.js (node + npx) — install from "
                "https://nodejs.org/ or via your package manager",
                UserWarning,
                stacklevel=2,
            )
            raise RuntimeError(
                "localtunnel: Node.js runtime not found on PATH "
                "(need both 'node' and 'npx')"
            )
        cmd = [npx_bin, "--yes", "localtunnel", str(local_port)]
        self._run_command(cmd, capture=True)
        captured = self._wait_for_url(
            self.startup_timeout,
            checker=lambda: self.parse_log_for_url(_URL_RE),
        )
        if not captured:
            self.stop()
            raise RuntimeError(
                f"localtunnel: no URL captured after {self.startup_timeout}s "
                "(npx may still be downloading the package — re-run)"
            )
        self.url = captured
        host = captured.split("://", 1)[1].split("/", 1)[0]
        host = host.split(":", 1)[0]  # strip explicit port if any
        self.host, self.port = host, 443
        self.tunnel_type = "http"
        self.bridge_required = False
        return {
            "url": self.url,
            "host": self.host,
            "port": self.port,
            "type": self.tunnel_type,
            "bridge_required": self.bridge_required,
        }

    def stop(self) -> None:
        """Terminate the localtunnel process and release resources."""
        self._terminate_process()
        self.cleanup()

    def is_alive(self) -> bool:
        """Return ``True`` while the localtunnel process is running."""
        return self.process is not None and self.process.poll() is None
