"""Serveo.net tunnel provider — exposes a local TCP port via SSH reverse tunnel.

serveo.net is a free SSH-based relay that allocates a remote port on
``serveo.net`` and forwards traffic back to ``localhost:LOCAL_PORT``.
No client binary other than ``ssh`` is required.

Typical session::

    $ ssh -R 3389:localhost:3389 -N serveo.net
    Hi! You've successfully authenticated, but we do not provide shell access.
    Forwarding TCP traffic from port 43210

The ``43210`` part is what we extract as the remote port — the public
endpoint becomes ``serveo.net:43210`` (a raw TCP socket, no bridge).
"""
from __future__ import annotations

from typing import Dict, Optional, Union

from .base import TunnelBase

__all__ = ["ServeoTunnel"]

# ``serveo.net:43210`` style — explicit host:port on one line.
_HOSTPORT_RE = r"((?:[a-z0-9-]+\.)?serveo\.net):(\d{2,5})"
# ``Forwarding TCP traffic from port 43210`` — port only, host defaults
# to ``serveo.net``.
_FORWARD_RE = r"Forwarding (?:TCP|HTTP) traffic from port (\d{2,5})"


class ServeoTunnel(TunnelBase):
    """Expose ``local_port`` through serveo.net via SSH reverse forwarding.

    The endpoint returned by :meth:`start` is a direct ``host:port``
    TCP socket — no client-side bridge is required.
    """

    name = "serveo"
    startup_timeout = 50

    def start(self, local_port: int = 3389) -> Dict[str, Union[str, int, bool]]:
        """Start the serveo SSH tunnel and return ``{url, host, port, type}``.

        Raises
        ------
        RuntimeError
            If ``ssh`` is missing from ``$PATH`` or no URL appears in the
            serveo output before :attr:`startup_timeout` expires.
        """
        self.local_port = local_port
        ssh_bin = self._which("ssh")
        if not ssh_bin:
            raise RuntimeError(
                "ssh binary not found on PATH — install openssh-client "
                "(apt install openssh-client on Debian/Ubuntu)"
            )
        cmd = [
            ssh_bin,
            "-R", f"{local_port}:localhost:{local_port}",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-N",
            "serveo.net",
        ]
        self._run_command(cmd, capture=True)
        captured = self._wait_for_url(
            self.startup_timeout,
            checker=self._checker,
        )
        if not captured:
            self.stop()
            raise RuntimeError(
                f"serveo: no URL captured after {self.startup_timeout}s "
                "(check network reachability to serveo.net)"
            )
        # ``captured`` is either ``host:port`` or a bare port number.
        host: str
        port_s: str
        if ":" in captured:
            host, _, port_s = captured.partition(":")
        else:
            host, port_s = "serveo.net", captured
        try:
            port = int(port_s)
        except ValueError:
            port = 0
        if port == 0:
            self.stop()
            raise RuntimeError(f"serveo: could not parse port from {captured!r}")
        self.host, self.port = host, port
        self.url = f"{host}:{port}"
        self.tunnel_type = "tcp"
        self.bridge_required = False
        return {
            "url": self.url,
            "host": self.host,
            "port": self.port,
            "type": self.tunnel_type,
            "bridge_required": self.bridge_required,
        }

    def _checker(self) -> Optional[str]:
        """Try both regexes against the current log buffer."""
        hp = self.parse_log_for_url(_HOSTPORT_RE)
        if hp:
            return hp
        port = self.parse_log_for_url(_FORWARD_RE)
        if port:
            return f"serveo.net:{port}"
        return None

    def stop(self) -> None:
        """Terminate the serveo SSH process and release resources."""
        self._terminate_process()
        self.cleanup()

    def is_alive(self) -> bool:
        """Return ``True`` while the SSH process is still running."""
        return self.process is not None and self.process.poll() is None
