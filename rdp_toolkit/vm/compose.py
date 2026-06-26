"""Helpers to parse ``docker/docker-compose.yml`` without external tools.

The toolkit ships three RDP-capable services (``kali-rdp``, ``ubuntu-rdp``,
``windows-rdp``) defined in a Compose file.  We need to read it back to
discover:

* the service names,
* the public port mappings (e.g. ``13389:3389``),
* the per-service environment defaults (RDP_USER / RDP_PASS),
* the assigned container_name and image.

PyYAML is already a project dependency (see :mod:`rdp_toolkit.config`) so we
use it when available.  A small stdlib regex fallback is also provided for
environments where PyYAML is missing — that fallback only extracts the
service names and port mappings (which is all the CLI needs to display
status), but the YAML path is preferred because it also exposes the
``environment`` block used to populate default credentials.
"""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    import yaml  # type: ignore
except ImportError:  # pragma: no cover - pyyaml is a declared dep
    yaml = None  # type: ignore

__all__ = [
    "ComposeSpec",
    "parse_compose",
    "find_compose_file",
    "service_names",
    "port_mappings",
]

#: Canonical short-name -> compose service name mapping used across the
#: toolkit.  Short names are what the CLI accepts (e.g. ``kali``); the
#: compose service names are what we pass to ``docker compose``.
SHORT_TO_SERVICE: Dict[str, str] = {
    "kali": "kali-rdp",
    "ubuntu": "ubuntu-rdp",
    "windows": "windows-rdp",
}

#: Default host port for each short VM name (matches docker-compose.yml).
DEFAULT_PORTS: Dict[str, int] = {
    "kali": 13389,
    "ubuntu": 23389,
    "windows": 33389,
}

#: Default RDP credentials baked into the compose env section.  Real values
#: come from the file at runtime, but these are the fallbacks used when the
#: ``KALI_RDP_USER`` / ``UBUNTU_RDP_USER`` / ``WINDOWS_RDP_USER`` env vars
#: are unset (see ``docker-compose.yml``).
DEFAULT_CREDENTIALS: Dict[str, Dict[str, str]] = {
    "kali": {"user": "kali", "password": "kali"},
    "ubuntu": {"user": "ubuntu", "password": "ubuntu"},
    "windows": {"user": "win", "password": "win"},
}

# Regex used by the stdlib fallback parser to find ``"<host>:<container>"``
# port pairs under a ``ports:`` key.
_PORT_PAIR_RE = re.compile(r'"(\d+):(\d+)"|(\d+):(\d+)')


class ComposeSpec:
    """Lightweight view over a parsed ``docker-compose.yml`` document.

    The class is intentionally a thin data bag — all the heavy lifting
    (subprocess calls, health-check polling, etc.) lives in
    :mod:`rdp_toolkit.vm.manager`.  We expose only what the manager needs:
    the service list, port mappings, and per-service env defaults.
    """

    def __init__(self, data: Dict[str, Any]) -> None:
        """Construct from the raw dict returned by :func:`parse_compose`."""
        self._data: Dict[str, Any] = data
        services: Dict[str, Any] = data.get("services") or {}
        self._services: Dict[str, Any] = services if isinstance(services, dict) else {}

    @property
    def services(self) -> List[str]:
        """Return the list of service names declared in the compose file."""
        return list(self._services.keys())

    def service_def(self, name: str) -> Dict[str, Any]:
        """Return the raw YAML block for service ``name`` (empty dict if absent)."""
        block = self._services.get(name)
        return dict(block) if isinstance(block, dict) else {}

    def ports(self, name: str) -> List[Tuple[int, int]]:
        """Return list of ``(host_port, container_port)`` tuples for ``name``."""
        block = self.service_def(name)
        raw_ports = block.get("ports") or []
        out: List[Tuple[int, int]] = []
        if not isinstance(raw_ports, list):
            return out
        for entry in raw_ports:
            if isinstance(entry, str):
                m = _PORT_PAIR_RE.search(entry)
                if m:
                    host = m.group(1) or m.group(3)
                    cont = m.group(2) or m.group(4)
                    if host and cont:
                        out.append((int(host), int(cont)))
            elif isinstance(entry, (int, float)):
                out.append((int(entry), int(entry)))
        return out

    def rdp_port(self, name: str) -> int:
        """Return the *host* port mapped to container port 3389 (or 0)."""
        for host, cont in self.ports(name):
            if cont == 3389:
                return host
        return 0

    def environment(self, name: str) -> Dict[str, str]:
        """Return the service ``environment`` block as a flat ``str`` dict."""
        block = self.service_def(name)
        env = block.get("environment") or {}
        flat: Dict[str, str] = {}
        if isinstance(env, dict):
            for key, val in env.items():
                flat[str(key)] = str(val) if val is not None else ""
        elif isinstance(env, list):
            for item in env:
                if isinstance(item, str) and "=" in item:
                    key, _, value = item.partition("=")
                    flat[key.strip()] = value.strip()
        return flat

    def image(self, name: str) -> str:
        """Return the ``image:`` tag for ``name`` (empty string if absent)."""
        return str(self.service_def(name).get("image") or "")

    def container_name(self, name: str) -> str:
        """Return the ``container_name:`` for ``name`` (empty string if absent)."""
        return str(self.service_def(name).get("container_name") or "")


def find_compose_file(start: Optional[Path] = None) -> Path:
    """Walk upwards from ``start`` (default: this file) to locate compose.

    Search order:
      1. ``<start>/docker/docker-compose.yml``
      2. ``<start>/docker-compose.yml``
      3. parent of ``start`` recursively (max 5 levels).

    Returns the first existing path; raises :class:`FileNotFoundError` if
    none is found within the search budget.
    """
    here = (Path(start) if start else Path(__file__).resolve()).resolve()
    candidates: List[Path] = []
    cur = here if here.is_dir() else here.parent
    for _ in range(6):
        candidates.append(cur / "docker" / "docker-compose.yml")
        candidates.append(cur / "docker-compose.yml")
        if cur.parent == cur:
            break
        cur = cur.parent
    for cand in candidates:
        if cand.is_file():
            return cand
    raise FileNotFoundError(
        "docker-compose.yml not found near %s — checked: %s"
        % (here, ", ".join(str(c) for c in candidates))
    )


def parse_compose(path: Optional[Path] = None) -> ComposeSpec:
    """Parse ``path`` (default: auto-discovered) into a :class:`ComposeSpec`.

    Prefers PyYAML; falls back to a regex-based port/service extractor if
    PyYAML is missing.  The fallback path only populates ``services`` and
    ``ports`` — environment and image fields stay empty.
    """
    target = Path(path) if path else find_compose_file()
    text = target.read_text(encoding="utf-8")
    if yaml is not None:
        loaded = yaml.safe_load(text) or {}
        if not isinstance(loaded, dict):
            loaded = {}
        return ComposeSpec(loaded)
    return _stdlib_fallback_parse(text)


def _stdlib_fallback_parse(text: str) -> ComposeSpec:
    """Regex-only fallback used when PyYAML is unavailable.

    Extracts top-level service names and their port mappings; everything
    else stays empty.  Good enough for ``status`` / ``list_vms`` calls.
    """
    services: Dict[str, Any] = {}
    lines = text.splitlines()
    current: Optional[str] = None
    in_ports = False
    for raw in lines:
        stripped = raw.rstrip()
        if not stripped or stripped.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        # A 2-space indent under ``services:`` marks a service name.
        m = re.match(r"^  ([A-Za-z0-9_.-]+):\s*$", stripped)
        if m and indent == 2:
            current = m.group(1)
            services[current] = {"ports": []}
            in_ports = False
            continue
        if current is None:
            continue
        if re.match(r"^    ports:\s*$", stripped):
            in_ports = True
            continue
        if in_ports and indent <= 4:
            in_ports = False
        if in_ports:
            m = _PORT_PAIR_RE.search(stripped)
            if m:
                host = m.group(1) or m.group(3)
                cont = m.group(2) or m.group(4)
                if host and cont:
                    services[current].setdefault("ports", []).append(
                        f"{int(host)}:{int(cont)}"
                    )
    return ComposeSpec({"services": services})


def service_names(spec: Optional[ComposeSpec] = None) -> List[str]:
    """Convenience wrapper — return service names from ``spec``."""
    return (spec or parse_compose()).services


def port_mappings(name: str, spec: Optional[ComposeSpec] = None) -> List[Tuple[int, int]]:
    """Convenience wrapper — return port pairs for ``name``."""
    return (spec or parse_compose()).ports(name)
