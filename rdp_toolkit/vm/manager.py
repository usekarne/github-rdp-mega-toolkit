"""Docker Compose-backed VM manager for the RDP Mega Toolkit.

The toolkit ships three RDP-capable containers (kali-rdp / ubuntu-rdp /
windows-rdp) declared in ``docker/docker-compose.yml``.  :class:`VMManager`
wraps ``docker compose`` so the CLI can ``start`` / ``stop`` / ``status``
them with one-liners, and so the rest of the package can fetch a uniform
connection dict (host/port/user/password) for any running VM.

Design notes:

* All shell-out calls go through :func:`subprocess.run` with a small
  timeout.  The manager never raises on a non-zero exit — it returns a
  dict with ``ok=False`` and an ``error`` field instead, so the CLI can
  render a friendly message.
* Health-check polling uses ``docker inspect`` (not ``docker compose ps``
  filtering) because ``inspect`` returns the canonical ``Health`` status
  string (``"starting"`` / ``"healthy"`` / ``"unhealthy"``) without
  needing ``jq``.
* ``shell(name)`` does **not** actually spawn an interactive TTY from
  Python — that doesn't work reliably across platforms.  Instead we
  print the exact command the user should run, and return it as a
  string so callers (CLI / docs) can capture / display it.
"""
from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from .compose import (
    DEFAULT_CREDENTIALS,
    DEFAULT_PORTS,
    SHORT_TO_SERVICE,
    ComposeSpec,
    find_compose_file,
    parse_compose,
)

__all__ = [
    "VMManager",
    "VMError",
    "start",
    "stop",
    "shell",
    "status",
    "list_vms",
    "short_names",
]

_LOG = logging.getLogger(__name__)

#: Maximum seconds to wait for a container to become ``healthy``.
HEALTH_TIMEOUT = 120

#: Seconds between healthcheck polls.
HEALTH_INTERVAL = 3


class VMError(RuntimeError):
    """Raised for unrecoverable VM manager errors (docker missing, etc.)."""


class VMManager:
    """Manage the toolkit's three RDP containers via ``docker compose``."""

    def __init__(self, compose_file: str = "docker/docker-compose.yml") -> None:
        """Construct a manager.

        ``compose_file`` is interpreted relative to the package root if it
        doesn't exist as-is.  We also locate the file automatically via
        :func:`rdp_toolkit.vm.compose.find_compose_file` as a fallback so
        the manager works regardless of the caller's CWD.
        """
        candidate = Path(compose_file)
        if candidate.is_file():
            self.compose_path: Path = candidate.resolve()
        else:
            # Try relative to the package root first, then auto-discover.
            pkg_root = Path(__file__).resolve().parent.parent.parent
            rel = pkg_root / compose_file
            if rel.is_file():
                self.compose_path = rel.resolve()
            else:
                try:
                    self.compose_path = find_compose_file(pkg_root)
                except FileNotFoundError as exc:
                    raise VMError(str(exc)) from exc
        self._spec: ComposeSpec = parse_compose(self.compose_path)
        self._compose_cmd: List[str] = self._detect_compose_cmd()

    # ------------------------------------------------------------------ #
    # Public API
    # ------------------------------------------------------------------ #
    def start(self, name: str) -> Dict[str, Any]:
        """Start the ``<name>-rdp`` service and wait for its healthcheck.

        ``name`` must be one of ``"kali"``, ``"ubuntu"``, ``"windows"``.
        Returns a connection dict on success::

            {"ok": True, "name": "kali", "service": "kali-rdp",
             "host": "localhost", "port": 13389,
             "user": "kali", "password": "kali", "container": "rdp-toolkit-kali"}
        """
        service = self._require_service(name)
        self._require_docker()
        port = self._rdp_port(name)
        creds = self._credentials(name)
        container = self._spec.container_name(service) or f"rdp-toolkit-{name}"
        _LOG.info("Starting VM %s (service=%s, port=%d)", name, service, port)
        up = self._run(["up", "-d", service])
        if not up["ok"]:
            return {"ok": False, "name": name, "error": up["error"]}
        healthy = self._wait_healthy(container)
        return {
            "ok": healthy,
            "name": name,
            "service": service,
            "host": "localhost",
            "port": port,
            "user": creds["user"],
            "password": creds["password"],
            "container": container,
            "healthy": healthy,
        }

    def stop(self, name: str) -> Dict[str, Any]:
        """Stop the ``<name>-rdp`` service (container stays defined)."""
        service = self._require_service(name)
        self._require_docker()
        _LOG.info("Stopping VM %s (service=%s)", name, service)
        out = self._run(["stop", service])
        return {"ok": out["ok"], "name": name, "service": service, "error": out["error"]}

    def shell(self, name: str) -> Dict[str, Any]:
        """Return (and print) the command to attach an interactive shell.

        We don't actually exec into the container from Python — TTY
        handling differs wildly across platforms.  Instead the caller is
        expected to run the printed command directly.
        """
        service = self._require_service(name)
        cmd = self._compose_cmd + [
            "-f", str(self.compose_path),
            "exec", service, "bash",
        ]
        printable = " ".join(self._quote(arg) for arg in cmd)
        print(f"# Run an interactive shell in {service}:\n  {printable}")
        return {"ok": True, "name": name, "service": service, "command": printable}

    def status(self, name: Optional[str] = None) -> Dict[str, Any]:
        """Return ``docker compose ps`` output.

        With ``name`` set, returns a single-service dict; otherwise
        returns a dict keyed by service name plus a ``raw`` field holding
        the full ``docker compose ps`` text.
        """
        self._require_docker()
        ps = self._run(["ps"], capture=True)
        raw = ps.get("stdout") or ""
        if name is not None:
            service = self._require_service(name)
            return {
                "ok": ps["ok"],
                "name": name,
                "service": service,
                "running": service in raw and "Exit" not in raw.split(service)[-1],
                "raw": raw,
            }
        return {"ok": ps["ok"], "raw": raw, "services": self._spec.services}

    def list_vms(self) -> List[Dict[str, Any]]:
        """Return a list of VMs with their running / stopped state."""
        self._require_docker()
        ps = self._run(["ps", "--format", "json"], capture=True)
        running: Dict[str, bool] = {}
        if ps["ok"] and ps.get("stdout"):
            try:
                # ``docker compose ps --format json`` emits one JSON object
                # per line (NDJSON) in newer Compose v2 builds.
                for line in ps["stdout"].splitlines():
                    line = line.strip()
                    if not line:
                        continue
                    obj = json.loads(line)
                    svc = obj.get("Service") or obj.get("service") or ""
                    running[svc] = (obj.get("State") or obj.get("state") or "") == "running"
            except (json.JSONDecodeError, AttributeError):
                # Fallback: scan the human-readable ``docker compose ps`` output.
                txt = self._run(["ps"], capture=True).get("stdout") or ""
                for short, service in SHORT_TO_SERVICE.items():
                    running[service] = service in txt
        out: List[Dict[str, Any]] = []
        for short, service in SHORT_TO_SERVICE.items():
            out.append({
                "name": short,
                "service": service,
                "port": self._rdp_port(short),
                "running": running.get(service, False),
                "image": self._spec.image(service),
                "container": self._spec.container_name(service) or f"rdp-toolkit-{short}",
            })
        return out

    # ------------------------------------------------------------------ #
    # Internal helpers
    # ------------------------------------------------------------------ #
    @staticmethod
    def _quote(arg: str) -> str:
        """Quote ``arg`` for shell printing if it contains whitespace."""
        if any(ch in arg for ch in (" ", "\t", '"', "'")):
            return '"%s"' % arg.replace('"', '\\"')
        return arg

    def _run(self, args: List[str], capture: bool = False) -> Dict[str, Any]:
        """Run ``docker compose -f <file> <args>`` and return a result dict."""
        cmd = self._compose_cmd + ["-f", str(self.compose_path), *args]
        _LOG.debug("compose run: %s", cmd)
        try:
            proc = subprocess.run(
                cmd,
                stdout=subprocess.PIPE if capture else None,
                stderr=subprocess.PIPE if capture else None,
                text=True,
                timeout=180,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            return {"ok": False, "error": f"docker compose timed out: {exc}", "stdout": "", "stderr": ""}
        except FileNotFoundError as exc:
            return {"ok": False, "error": f"docker binary not found: {exc}", "stdout": "", "stderr": ""}
        ok = proc.returncode == 0
        return {
            "ok": ok,
            "stdout": (proc.stdout or "") if capture else "",
            "stderr": (proc.stderr or "") if capture else "",
            "returncode": proc.returncode,
            "error": "" if ok else (proc.stderr or "").strip() or f"exit {proc.returncode}",
        }

    def _wait_healthy(self, container: str, timeout: int = HEALTH_TIMEOUT) -> bool:
        """Poll ``docker inspect`` until the container reports ``healthy``."""
        deadline = time.monotonic() + timeout
        docker_bin = shutil.which("docker")
        if not docker_bin:
            return False
        while time.monotonic() < deadline:
            try:
                proc = subprocess.run(
                    [docker_bin, "inspect", "--format", "{{json .State.Health}}", container],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=10, check=False,
                )
            except subprocess.TimeoutExpired:
                proc = None
            if proc is not None and proc.returncode == 0:
                raw = (proc.stdout or "").strip()
                if raw and raw != "null":
                    try:
                        health = json.loads(raw)
                    except json.JSONDecodeError:
                        health = {}
                    status = (health or {}).get("Status", "")
                    if status == "healthy":
                        return True
                    if status == "unhealthy":
                        _LOG.warning("Container %s is unhealthy", container)
                        return False
            time.sleep(HEALTH_INTERVAL)
        _LOG.warning("Container %s did not become healthy within %ds", container, timeout)
        return False

    def _require_service(self, name: str) -> str:
        """Validate short name and return the compose service name."""
        service = SHORT_TO_SERVICE.get(name)
        if not service:
            raise VMError(
                f"unknown VM {name!r} — expected one of: {sorted(SHORT_TO_SERVICE)}"
            )
        return service

    def _require_docker(self) -> None:
        """Ensure docker CLI exists and the daemon answers ``docker info``."""
        if not shutil.which("docker"):
            raise VMError(
                "docker is not installed or not on PATH — install Docker Desktop "
                "(https://www.docker.com/products/docker-desktop) or `apt install docker.io`"
            )
        try:
            proc = subprocess.run(
                ["docker", "info"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=10, check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise VMError("docker daemon did not respond within 10s") from exc
        if proc.returncode != 0:
            raise VMError(
                "docker daemon is not running — start Docker Desktop or `sudo systemctl start docker`"
            )

    @staticmethod
    def _detect_compose_cmd() -> List[str]:
        """Return the compose invocation (``["docker","compose"]`` preferred)."""
        # ``docker compose`` (v2 plugin) is the modern path; ``docker-compose``
        # (v1 standalone Python binary) is the legacy fallback.
        if shutil.which("docker"):
            try:
                proc = subprocess.run(
                    ["docker", "compose", "version"],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=8, check=False,
                )
                if proc.returncode == 0:
                    return ["docker", "compose"]
            except subprocess.TimeoutExpired:
                pass
        if shutil.which("docker-compose"):
            return ["docker-compose"]
        # Default to v2 — _require_docker will surface a clearer error later.
        return ["docker", "compose"]

    def _rdp_port(self, name: str) -> int:
        """Return the host port for ``name`` (from compose or DEFAULT_PORTS)."""
        service = SHORT_TO_SERVICE.get(name, "")
        port = self._spec.rdp_port(service) if service else 0
        if port:
            return port
        return DEFAULT_PORTS.get(name, 0)

    def _credentials(self, name: str) -> Dict[str, str]:
        """Return ``{"user","password"}`` for ``name`` from compose env (with defaults)."""
        service = SHORT_TO_SERVICE.get(name, "")
        env = self._spec.environment(service) if service else {}
        defaults = DEFAULT_CREDENTIALS.get(name, {"user": "rdp", "password": "rdp"})
        # The compose file uses RDP_USER / RDP_PASS with shell-expansion
        # defaults like ``"${KALI_RDP_USER:-kali}"``.  Prefer a real env
        # override if the user set one; otherwise fall through to defaults.
        env_user_key = f"{name.upper()}_RDP_USER"
        env_pass_key = f"{name.upper()}_RDP_PASS"
        user = os.environ.get(env_user_key) or defaults["user"]
        password = os.environ.get(env_pass_key) or defaults["password"]
        # Honour an explicit literal value baked into the compose env block
        # (i.e. one without ``${...}`` shell expansion) when no env override
        # is present.
        raw_user = env.get("RDP_USER", "")
        raw_pass = env.get("RDP_PASS", "")
        if raw_user and "${" not in raw_user and not os.environ.get(env_user_key):
            user = raw_user
        if raw_pass and "${" not in raw_pass and not os.environ.get(env_pass_key):
            password = raw_pass
        return {"user": user, "password": password}


# --------------------------------------------------------------------------- #
# Module-level default instance + convenience wrappers for CLI integration.
# --------------------------------------------------------------------------- #
_default = VMManager()


def short_names() -> List[str]:
    """Return the list of supported short VM names (``kali``, ``ubuntu``, ``windows``)."""
    return list(SHORT_TO_SERVICE)


def start(name: str) -> Dict[str, Any]:
    """Module-level wrapper — see :meth:`VMManager.start`."""
    return _default.start(name)


def stop(name: str) -> Dict[str, Any]:
    """Module-level wrapper — see :meth:`VMManager.stop`."""
    return _default.stop(name)


def shell(name: str) -> Dict[str, Any]:
    """Module-level wrapper — see :meth:`VMManager.shell`."""
    return _default.shell(name)


def status(name: Optional[str] = None) -> Dict[str, Any]:
    """Module-level wrapper — see :meth:`VMManager.status`."""
    return _default.status(name)


def list_vms() -> List[Dict[str, Any]]:
    """Module-level wrapper — see :meth:`VMManager.list_vms`."""
    return _default.list_vms()
