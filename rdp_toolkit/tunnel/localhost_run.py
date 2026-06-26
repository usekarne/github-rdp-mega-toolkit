"""localhost.run tunnel provider — SSH reverse tunnel, similar to serveo.

``localhost.run`` allocates a public subdomain (``*.localhost.run``) and
forwards traffic back to a local port via an SSH reverse tunnel.  Unlike
serveo it tends to allocate a *named* endpoint (``<rand>.localhost.run``)
rather than a numeric remote port.

Typical session::

    $ ssh -R 3389:localhost:3389 nokey@localhost.run
    Warning: Permanently added 'localhost.run' (ED25519) to the list of known hosts.
    ...
    Connect to https://random-subdomain.localhost.run

We accept both the ``host:port`` form and the bare ``host`` form (in
which case the port defaults to 443 — localhost.run is HTTPS-fronted).
"""
from __future__ import annotations

from typing import Dict, Optional, Union

from .base import TunnelBase

__all__ = ["LocalhostRunTunnel"]

# ``random.localhost.run:12345`` or ``random.localhost.run`` (no port).
_HOSTPORT_RE = r"([a-z0-9-]+\.localhost\.run)(?::(\d{2,5}))?"
# ``Forwarding TCP traffic from port 43210`` — port only.
_FORWARD_RE = r"Forwarding (?:TCP|HTTP) traffic from port (\d{2,5})"


class LocalhostRunTunnel(TunnelBase):
    """Expose ``local_port`` through localhost.run via SSH reverse tunneling.

    Uses the ``nokey@localhost.run`` anonymous account — no SSH key
    registration is required.
    """

    name = "localhost.run"
    startup_timeout = 50

    def start(self, local_port: int = 3389) -> Dict[str, Union[str, int, bool]]:
        """Start the localhost.run SSH tunnel.

        Raises
        ------
        RuntimeError
            If ``ssh`` is missing or no URL is captured before the
            startup timeout elapses.
        """
        self.local_port = local_port
        ssh_bin = self._which("ssh")
        if not ssh_bin:
            raise RuntimeError(
                "ssh binary not found on PATH — install openssh-client"
            )
        cmd = [
            ssh_bin,
            "-R", f"{local_port}:localhost:{local_port}",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-N",
            "nokey@localhost.run",
        ]
        self._run_command(cmd, capture=True)
        captured = self._wait_for_url(
            self.startup_timeout,
            checker=self._checker,
        )
        if not captured:
            self.stop()
            raise RuntimeError(
                f"localhost.run: no URL captured after {self.startup_timeout}s "
                "(check network reachability to localhost.run)"
            )
        # ``captured`` is either ``host:port``, ``host`` or ``port``.
        host: str
        port: int
        if ":" in captured:
            host, _, port_s = captured.partition(":")
            try:
                port = int(port_s)
            except ValueError:
                port = 443
        elif captured.isdigit():
            # Bare port — host defaults to localhost.run.
            host, port = "localhost.run", int(captured)
        else:
            host, port = captured, 443
        if not host:
            self.stop()
            raise RuntimeError(f"localhost.run: could not parse host from {captured!r}")
        self.host, self.port = host, port
        self.url = f"{host}:{port}" if port and port != 443 else f"https://{host}"
        self.tunnel_type = "tcp" if port and port not in (80, 443) else "http"
        self.bridge_required = False
        return {
            "url": self.url,
            "host": self.host,
            "port": self.port,
            "type": self.tunnel_type,
            "bridge_required": self.bridge_required,
        }

    def _checker(self) -> Optional[str]:
        """Try the host:port regex, the bare-host regex, then the port regex."""
        hp = self.parse_log_for_url(_HOSTPORT_RE)
        if hp:
            return hp
        port = self.parse_log_for_url(_FORWARD_RE)
        if port:
            return f"localhost.run:{port}"
        return None

    def stop(self) -> None:
        """Terminate the localhost.run SSH process and release resources."""
        self._terminate_process()
        self.cleanup()

    def is_alive(self) -> bool:
        """Return ``True`` while the SSH process is still running."""
        return self.process is not None and self.process.poll() is None
