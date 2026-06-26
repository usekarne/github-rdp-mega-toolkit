#!/usr/bin/env python3
"""
tunnel-health-check.py — Probe a tunnel URL externally.

Tries, in order:
  1. TCP connect to host:port (raw socket, 5s timeout)
  2. HTTP HEAD or GET to the URL (5s timeout) — for tunnel URLs that return
     a redirect or 200/4xx
  3. TLS handshake check (for https URLs)

Exits 0 on success, 1 on failure, 2 on usage error.
Use --json for machine-readable output.
"""
from __future__ import annotations

import argparse
import json
import socket
import ssl
import sys
from typing import Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

DEFAULT_TIMEOUT = 5


def tcp_probe(host: str, port: int, timeout: int = DEFAULT_TIMEOUT) -> dict:
    """Open a raw TCP socket. Returns dict with ok, error, ms."""
    import time as _t
    t0 = _t.monotonic()
    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            elapsed_ms = int((_t.monotonic() - t0) * 1000)
        return {"ok": True, "ms": elapsed_ms}
    except OSError as e:
        return {"ok": False, "error": f"tcp: {e}"}


def http_probe(url: str, timeout: int = DEFAULT_TIMEOUT, method: str = "HEAD") -> dict:
    """HTTP probe. Returns dict with ok, status, error, ms."""
    import time as _t
    req = Request(url, method=method, headers={"User-Agent": "tunnel-health-check/1.0"})
    t0 = _t.monotonic()
    try:
        with urlopen(req, timeout=timeout) as resp:
            elapsed_ms = int((_t.monotonic() - t0) * 1000)
            return {"ok": True, "status": resp.status, "ms": elapsed_ms}
    except HTTPError as e:
        # 4xx/5xx still means the tunnel is reachable; treat as "ok" with status
        elapsed_ms = int((_t.monotonic() - t0) * 1000)
        return {"ok": True, "status": e.code, "ms": elapsed_ms,
                "note": f"http error (tunnel reachable): {e.reason}"}
    except URLError as e:
        return {"ok": False, "error": f"http: {e.reason}"}
    except Exception as e:
        return {"ok": False, "error": f"http: {e}"}


def tls_probe(host: str, port: int = 443, timeout: int = DEFAULT_TIMEOUT) -> dict:
    """Try a TLS handshake."""
    import time as _t
    ctx = ssl.create_default_context()
    t0 = _t.monotonic()
    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            with ctx.wrap_socket(sock, server_hostname=host) as ssock:
                cert = ssock.getpeercert()
                elapsed_ms = int((_t.monotonic() - t0) * 1000)
                return {"ok": True, "ms": elapsed_ms,
                        "subject": dict(x[0] for x in cert.get("subject", [])) if cert else None}
    except Exception as e:
        return {"ok": False, "error": f"tls: {e}"}


def probe(url_or_host: str, port: Optional[int] = None, timeout: int = DEFAULT_TIMEOUT) -> dict:
    """
    Auto-detect what kind of probe to run:
      * If input starts with http(s)://, do HTTP + TLS (if https) + TCP
      * Else if a port is given, do TCP only
      * Else if input looks like host:port, parse it
    Returns combined result.
    """
    result: dict = {"target": url_or_host, "steps": []}

    if url_or_host.startswith(("http://", "https://")):
        parsed = urlparse(url_or_host)
        host = parsed.hostname or ""
        port = parsed.port or (443 if parsed.scheme == "https" else 80)

        # HTTP first (most useful signal)
        http_res = http_probe(url_or_host, timeout=timeout)
        result["steps"].append({"name": "http", **http_res})

        # TLS if https
        if parsed.scheme == "https":
            tls_res = tls_probe(host, port, timeout=timeout)
            result["steps"].append({"name": "tls", **tls_res})

        # TCP always
        tcp_res = tcp_probe(host, port, timeout=timeout)
        result["steps"].append({"name": "tcp", **tcp_res})

        # Overall OK if HTTP or TLS succeeded
        result["ok"] = any(s.get("ok") for s in result["steps"])
    else:
        # host or host:port
        if ":" in url_or_host and port is None:
            host, port_str = url_or_host.rsplit(":", 1)
            try:
                port = int(port_str)
            except ValueError:
                host = url_or_host
                port = None
        else:
            host = url_or_host
        if port is None:
            port = 443
        tcp_res = tcp_probe(host, port, timeout=timeout)
        result["steps"].append({"name": "tcp", **tcp_res})
        result["ok"] = tcp_res["ok"]

    return result


def main(argv=None) -> int:
    p = argparse.ArgumentParser(
        prog="tunnel-health-check.py",
        description="Probe a tunnel URL externally (TCP / HTTP / TLS).",
    )
    p.add_argument("target", help="URL (https://host.trycloudflare.com) or host:port")
    p.add_argument("--port", type=int, default=None, help="Override port")
    p.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT, help="Per-probe timeout (s)")
    p.add_argument("--json", action="store_true", help="Machine-readable JSON output")
    args = p.parse_args(argv)

    result = probe(args.target, port=args.port, timeout=args.timeout)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        ok_str = "OK" if result["ok"] else "FAIL"
        print(f"Tunnel {ok_str}: {result['target']}")
        for step in result["steps"]:
            status = "ok" if step.get("ok") else "fail"
            extra = ""
            if "status" in step:
                extra = f" HTTP {step['status']}"
            if "ms" in step:
                extra += f" {step['ms']}ms"
            if "error" in step:
                extra += f" — {step['error']}"
            print(f"  [{step['name']:<4}] {status:<4}{extra}")

    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
