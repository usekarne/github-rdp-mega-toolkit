"""GitHub Actions runner for the RDP Mega Toolkit v9.

A thin, stdlib-only client around the GitHub Actions REST API that:

* triggers workflow_dispatch runs (`start_session`)
* cancels in-progress runs (`stop_all` / `kill`)
* lists recent runs with their status (`list_runs`)
* downloads and parses the ``rdp-credentials`` artifact from a run
  (`connect_command`) and returns a ready-to-run ``xfreerdp`` command
* triggers the credential-rotate workflow (`rotate_password`)

Environment variables
---------------------
``GH_PAT``
    GitHub personal-access token (``repo`` scope). Required.
``GH_REPO``
    Repository in ``owner/name`` form. Defaults to
    ``usekarne/github-rdp-mega-toolkit``.
``GH_API_URL``
    Override the GitHub API root (for GHES). Defaults to
    ``https://api.github.com``.

The module uses only :mod:`urllib.request`, :mod:`json`, :mod:`zipfile`,
:mod:`io` and :mod:`time` so it can be vendored without dependencies.
"""
from __future__ import annotations

import base64
import io
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

__all__ = [
    "DEFAULT_REPO",
    "DEFAULT_WORKFLOW",
    "CREDENTIALS_ARTIFACT",
    "RunnerError",
    "RunInfo",
    "start_session",
    "stop_all",
    "list_runs",
    "connect_command",
    "rotate_password",
    "kill",
    "parse_kv",
]

DEFAULT_REPO = "usekarne/github-rdp-mega-toolkit"
DEFAULT_WORKFLOW = "lite-rdp.yml"
CREDENTIALS_ARTIFACT = "rdp-credentials"
DEFAULT_BRANCH = "main"

# How long to wait (in seconds) for a freshly-dispatched run to appear in the
# API list before giving up.  GitHub usually propagates within ~5s but allow
# generous headroom.
_RUN_VISIBILITY_TIMEOUT_SEC = 60
_POLL_INTERVAL_SEC = 3

# How long to wait for an artifact to be uploaded after a run finishes.
_ARTIFACT_TIMEOUT_SEC = 120


# ---------------------------------------------------------------------------
# Errors and dataclasses
# ---------------------------------------------------------------------------
class RunnerError(RuntimeError):
    """Raised when the GitHub Actions API returns an unrecoverable error."""


@dataclass
class RunInfo:
    """Minimal representation of a GitHub Actions run."""

    run_id: int
    name: str
    status: str  # queued | in_progress | completed
    conclusion: Optional[str]  # success | failure | cancelled | None
    html_url: str
    created_at: str
    head_branch: str
    workflow_id: int

    @classmethod
    def from_api(cls, payload: Dict) -> "RunInfo":
        return cls(
            run_id=int(payload["id"]),
            name=str(payload.get("name") or payload.get("display_title") or ""),
            status=str(payload.get("status") or "unknown"),
            conclusion=payload.get("conclusion"),
            html_url=str(payload.get("html_url") or ""),
            created_at=str(payload.get("created_at") or ""),
            head_branch=str(payload.get("head_branch") or ""),
            workflow_id=int(payload.get("workflow_id") or 0),
        )

    def to_dict(self) -> Dict:
        return {
            "run_id": self.run_id,
            "name": self.name,
            "status": self.status,
            "conclusion": self.conclusion,
            "html_url": self.html_url,
            "created_at": self.created_at,
            "head_branch": self.head_branch,
            "workflow_id": self.workflow_id,
        }


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------
def _config() -> Tuple[str, str, str]:
    """Return ``(token, repo, api_root)`` from environment variables."""
    token = os.environ.get("GH_PAT") or ""
    if not token:
        raise RunnerError(
            "GH_PAT environment variable is not set. Create a PAT with "
            "'repo' scope at https://github.com/settings/tokens."
        )
    repo = os.environ.get("GH_REPO") or DEFAULT_REPO
    api_root = os.environ.get("GH_API_URL") or "https://api.github.com"
    return token, repo, api_root.rstrip("/")


def _headers(token: str) -> Dict[str, str]:
    return {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "rdp-mega-toolkit-v9/runner",
    }


def _request(
    method: str,
    path: str,
    *,
    body: Optional[Dict] = None,
    raw_body: Optional[bytes] = None,
    token: Optional[str] = None,
    api_root: Optional[str] = None,
    timeout: int = 30,
    accept: str = "application/vnd.github+json",
) -> Tuple[int, Dict[str, str], bytes]:
    """Perform an HTTP request against the GitHub API.

    Returns ``(status_code, headers, body_bytes)``.
    """
    if token is None or api_root is None:
        t, _, root = _config()
        token = token or t
        api_root = api_root or root

    if path.startswith("http://") or path.startswith("https://"):
        url = path
    else:
        url = f"{api_root}{path}"

    data: Optional[bytes] = None
    headers = _headers(token)
    headers["Accept"] = accept
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    elif raw_body is not None:
        data = raw_body

    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, dict(resp.headers), resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, dict(exc.headers), exc.read()
    except urllib.error.URLError as exc:
        raise RunnerError(f"network error calling {url}: {exc}") from exc


def _json_or_raise(status: int, body: bytes, expected: Tuple[int, ...]) -> Dict:
    """Decode JSON body, raising RunnerError for unexpected status codes."""
    if status not in expected:
        text = body.decode("utf-8", errors="replace")[:500]
        raise RunnerError(f"unexpected HTTP {status} (expected {expected}): {text}")
    if not body:
        return {}
    try:
        return json.loads(body.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise RunnerError(f"invalid JSON response: {exc}") from exc


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
def start_session(
    profile: str = "productivity",
    hours: int = 6,
    workflow: str = DEFAULT_WORKFLOW,
    *,
    branch: str = DEFAULT_BRANCH,
    extra_inputs: Optional[Dict[str, str]] = None,
) -> int:
    """Trigger a ``workflow_dispatch`` and return the new run_id.

    Parameters
    ----------
    profile:
        Optimisation profile (``productivity`` / ``gaming`` / ``minimal``).
    hours:
        Session length in hours (drives the keepalive loop).
    workflow:
        Workflow filename (e.g. ``lite-rdp.yml``).
    branch:
        Git ref to dispatch against (default ``main``).
    extra_inputs:
        Any additional ``inputs`` to send in the dispatch payload.
    """
    token, repo, api_root = _config()
    path = f"/repos/{repo}/actions/workflows/{urllib.parse.quote(workflow)}/dispatches"
    inputs: Dict[str, str] = {
        "profile": profile,
        "hours": str(int(hours)),
    }
    if extra_inputs:
        inputs.update({k: str(v) for k, v in extra_inputs.items()})
    body = {"ref": branch, "inputs": inputs}
    status, _, raw = _request(
        "POST", path, body=body, token=token, api_root=api_root
    )
    if status != 204:
        text = raw.decode("utf-8", errors="replace")[:500]
        raise RunnerError(f"workflow_dispatch failed (HTTP {status}): {text}")

    # workflow_dispatch returns 204 No Content — we have to poll the runs list
    # to find the run that was just created.
    return _wait_for_new_run(token, repo, api_root, workflow, branch)


def _wait_for_new_run(
    token: str,
    repo: str,
    api_root: str,
    workflow: str,
    branch: str,
    since: Optional[float] = None,
) -> int:
    """Poll ``/repos/.../actions/runs`` until a new run for ``workflow`` appears."""
    workflow_path = f"/repos/{repo}/actions/workflows/{urllib.parse.quote(workflow)}"
    # Resolve workflow_id so we can filter the runs list.
    status, _, raw = _request("GET", workflow_path, token=token, api_root=api_root)
    if status != 200:
        raise RunnerError(
            f"could not resolve workflow {workflow!r} (HTTP {status})"
        )
    wf_data = _json_or_raise(status, raw, (200,))
    workflow_id = int(wf_data.get("id") or 0)

    baseline: set[int] = set()
    deadline = time.time() + _RUN_VISIBILITY_TIMEOUT_SEC
    while time.time() < deadline:
        params = urllib.parse.urlencode(
            {"event": "workflow_dispatch", "per_page": 30}
        )
        path = f"/repos/{repo}/actions/runs?{params}"
        status, _, raw = _request("GET", path, token=token, api_root=api_root)
        if status != 200:
            time.sleep(_POLL_INTERVAL_SEC)
            continue
        data = _json_or_raise(status, raw, (200,))
        runs = data.get("workflow_runs") or []
        # Capture baseline on first iteration so we don't pick up an older run.
        if not baseline:
            baseline = {
                int(r["id"])
                for r in runs
                if int(r.get("workflow_id") or 0) == workflow_id
            }
            if not baseline:
                # No prior runs — fall through to looking for any matching run.
                baseline = {int(r["id"]) for r in runs}
        for r in runs:
            if int(r.get("workflow_id") or 0) != workflow_id:
                continue
            rid = int(r["id"])
            if rid in baseline:
                continue
            # New run found.
            return rid
        time.sleep(_POLL_INTERVAL_SEC)
    raise RunnerError(
        f"timed out waiting for new {workflow} run to appear in the API list"
    )


def stop_all(*, workflow: Optional[str] = None) -> int:
    """Cancel every in_progress / queued run, returning the cancelled count."""
    token, repo, api_root = _config()
    cancelled = 0
    for run in list_runs(limit=30, workflow=workflow):
        if run.status in ("in_progress", "queued"):
            ok = _cancel_run(token, repo, api_root, run.run_id)
            if ok:
                cancelled += 1
    return cancelled


def kill(target: str = "all", *, workflow: Optional[str] = None) -> int:
    """Cancel a specific run_id (``target`` is an int-as-str) or all runs."""
    if target in ("all", "*", ""):
        return stop_all(workflow=workflow)
    try:
        run_id = int(target)
    except (TypeError, ValueError) as exc:
        raise RunnerError(f"kill target must be 'all' or an int run_id, got {target!r}") from exc
    token, repo, api_root = _config()
    ok = _cancel_run(token, repo, api_root, run_id)
    return 1 if ok else 0


def _cancel_run(token: str, repo: str, api_root: str, run_id: int) -> bool:
    path = f"/repos/{repo}/actions/runs/{run_id}/cancel"
    status, _, raw = _request("POST", path, token=token, api_root=api_root)
    if status == 202:
        return True
    # 409 conflict = already completed/cancelled.
    if status == 409:
        return False
    text = raw.decode("utf-8", errors="replace")[:300]
    raise RunnerError(f"cancel run {run_id} failed (HTTP {status}): {text}")


def list_runs(
    limit: int = 10,
    *,
    workflow: Optional[str] = None,
    branch: Optional[str] = None,
    status_filter: Optional[str] = None,
) -> List[RunInfo]:
    """Return the most recent runs (newest first)."""
    token, repo, api_root = _config()
    if workflow:
        path = (
            f"/repos/{repo}/actions/workflows/{urllib.parse.quote(workflow)}/runs"
        )
    else:
        path = f"/repos/{repo}/actions/runs"

    params: Dict[str, str] = {"per_page": str(max(1, min(100, limit)))}
    if branch:
        params["branch"] = branch
    if status_filter:
        params["status"] = status_filter
    path = f"{path}?{urllib.parse.urlencode(params)}"

    status, _, raw = _request("GET", path, token=token, api_root=api_root)
    data = _json_or_raise(status, raw, (200,))
    out: List[RunInfo] = []
    for r in data.get("workflow_runs") or []:
        out.append(RunInfo.from_api(r))
        if len(out) >= limit:
            break
    return out


# ---------------------------------------------------------------------------
# Artifact download + parse
# ---------------------------------------------------------------------------
def connect_command(
    run_id: Optional[int] = None,
    *,
    artifact_name: str = CREDENTIALS_ARTIFACT,
    profile: str = "productivity",
    extra_xfreerdp_args: Optional[List[str]] = None,
) -> str:
    """Return a ready-to-run ``xfreerdp`` command for the given run.

    Parameters
    ----------
    run_id:
        Specific run to target.  If ``None``, the most recent completed run
        is used.
    artifact_name:
        Artifact containing the connect-info.txt + credentials.
    profile:
        Profile to pull xfreerdp args from (see config.PROFILES).
    extra_xfreerdp_args:
        Append additional CLI flags to the generated command.
    """
    token, repo, api_root = _config()

    if run_id is None:
        run_id = _find_latest_completed_run(token, repo, api_root)

    info = _download_and_parse_artifact(
        token, repo, api_root, run_id, artifact_name
    )
    host = info.get("host") or info.get("tunnel_host")
    port = info.get("port") or info.get("tunnel_port")
    user = info.get("username") or info.get("RDP_USERNAME") or "runner"
    # Prefer a pre-built CONNECT_CMD if present in the artifact.
    connect_cmd = info.get("CONNECT_CMD") or info.get("connect_cmd")
    if connect_cmd:
        return connect_cmd
    if not host or not port:
        raise RunnerError(
            "connect-info artifact missing host/port — tunnel may have failed."
        )
    args = _profile_args(profile)
    if extra_xfreerdp_args:
        args.extend(extra_xfreerdp_args)
    arg_str = " ".join(args)
    return f"xfreerdp /v:{host}:{port} /u:{user} {arg_str}".strip()


def _find_latest_completed_run(
    token: str, repo: str, api_root: str
) -> int:
    runs = list_runs(limit=20)
    for r in runs:
        if r.status == "completed" and r.conclusion == "success":
            return r.run_id
    if runs:
        return runs[0].run_id
    raise RunnerError("no runs found in repository")


def _download_and_parse_artifact(
    token: str,
    repo: str,
    api_root: str,
    run_id: int,
    artifact_name: str,
) -> Dict[str, str]:
    """Download an artifact zip and return its key/value contents as a dict."""
    # Poll for the artifact to appear (with timeout).
    deadline = time.time() + _ARTIFACT_TIMEOUT_SEC
    artifact: Optional[Dict] = None
    while time.time() < deadline:
        path = f"/repos/{repo}/actions/runs/{run_id}/artifacts?per_page=100"
        status, _, raw = _request("GET", path, token=token, api_root=api_root)
        data = _json_or_raise(status, raw, (200,))
        for a in data.get("artifacts") or []:
            if a.get("name") == artifact_name:
                artifact = a
                break
        if artifact:
            break
        # If the run already completed without producing the artifact, bail.
        run_status, _, run_raw = _request(
            "GET",
            f"/repos/{repo}/actions/runs/{run_id}",
            token=token,
            api_root=api_root,
        )
        if run_status == 200:
            rj = _json_or_raise(run_status, run_raw, (200,))
            if (
                rj.get("status") == "completed"
                and rj.get("conclusion") != "success"
            ):
                raise RunnerError(
                    f"run {run_id} ended with conclusion={rj.get('conclusion')!r} "
                    f"— no {artifact_name} artifact will be produced."
                )
        time.sleep(_POLL_INTERVAL_SEC)

    if not artifact:
        raise RunnerError(
            f"artifact {artifact_name!r} not found for run {run_id}"
        )

    download_url = artifact.get("archive_download_url")
    if not download_url:
        raise RunnerError("artifact has no archive_download_url")

    status, _, raw = _request(
        "GET",
        download_url,
        token=token,
        api_root=api_root,
        accept="application/vnd.github+json",
        timeout=120,
    )
    if status != 200:
        raise RunnerError(
            f"artifact download failed (HTTP {status})"
        )
    if not raw:
        raise RunnerError("artifact download returned empty body")

    return _parse_artifact_zip(raw)


def _parse_artifact_zip(blob: bytes) -> Dict[str, str]:
    """Parse the artifact zip into a flat key/value dict.

    Handles:
      * multi-line ``KEY: VALUE`` files (one per line)
      * single-line concat bug (``KEY1: VALUE1 KEY2: VALUE2 ...``)
      * plain ``KEY=VALUE`` env-style files
      * raw credential files like ``RDP_USERNAME.txt`` / ``RDP_PASSWORD.txt``
        (filename becomes the key)
    """
    out: Dict[str, str] = {}
    with zipfile.ZipFile(io.BytesIO(blob)) as zf:
        for name in zf.namelist():
            if name.endswith("/"):
                continue
            try:
                content = zf.read(name).decode("utf-8", errors="replace")
            except KeyError:
                continue
            base = os.path.basename(name)
            stem, ext = os.path.splitext(base)

            if ext.lower() == ".json":
                # Embedded JSON (e.g. rdp-summary.json) — merge top-level keys.
                try:
                    parsed = json.loads(content)
                    if isinstance(parsed, dict):
                        for k, v in parsed.items():
                            out[str(k)] = str(v) if not isinstance(v, str) else v
                except json.JSONDecodeError:
                    out[stem] = content.strip()
                continue

            if ext.lower() == ".txt":
                # Either KEY: VALUE list, KEY=VALUE list, or raw value.
                kv = parse_kv(content)
                if kv:
                    out.update(kv)
                else:
                    # Raw text — use filename stem as key.
                    out[stem] = content.strip()
                continue

            # Anything else: store as raw text keyed by stem.
            out[stem] = content.strip()
    return out


def parse_kv(text: str) -> Dict[str, str]:
    """Parse KEY: VALUE / KEY=VALUE text, robust against the single-line
    concat bug where multiple KV pairs were accidentally joined on one line.

    Examples
    --------
    >>> parse_kv("host: serveo.net\\nport: 12345")
    {'host': 'serveo.net', 'port': '12345'}

    >>> parse_kv("host: serveo.net port: 12345")
    {'host': 'serveo.net', 'port': '12345'}
    """
    out: Dict[str, str] = {}
    if not text:
        return out
    # Normalise line endings then split on any whitespace boundary that is
    # immediately followed by a KEY: or KEY= token.
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    # Pattern: capture KEY (alphanumeric + _ . -), followed by ':' or '=', then
    # value continues until the next KEY: or KEY= boundary or end of string.
    token_re = re.compile(
        r"([A-Za-z_][A-Za-z0-9_.\-]*)\s*[:=]\s*(.*?)(?=\s+[A-Za-z_][A-Za-z0-9_.\-]*\s*[:=]|$)",
        re.DOTALL,
    )
    matched_any = False
    for m in token_re.finditer(text):
        key = m.group(1).strip()
        val = m.group(2).strip()
        if not key:
            continue
        # If value spans multiple lines, collapse whitespace.
        val = re.sub(r"\s+", " ", val).strip()
        if key not in out:
            out[key] = val
        matched_any = True
    if matched_any:
        return out
    # Fallback: maybe it's a single key with no separator (rare).
    return {}


def rotate_password(
    run_id: Optional[int] = None,
    *,
    workflow: str = "credential-rotate.yml",
    branch: str = DEFAULT_BRANCH,
) -> int:
    """Trigger the credential-rotate workflow for a run (or the latest)."""
    token, repo, api_root = _config()
    inputs: Dict[str, str] = {}
    if run_id is not None:
        inputs["run_id"] = str(int(run_id))
    body = {"ref": branch, "inputs": inputs}
    path = f"/repos/{repo}/actions/workflows/{urllib.parse.quote(workflow)}/dispatches"
    status, _, raw = _request(
        "POST", path, body=body, token=token, api_root=api_root
    )
    if status != 204:
        text = raw.decode("utf-8", errors="replace")[:500]
        raise RunnerError(
            f"credential-rotate dispatch failed (HTTP {status}): {text}"
        )
    return _wait_for_new_run(token, repo, api_root, workflow, branch)


# ---------------------------------------------------------------------------
# Profile args (mirror of rdp_toolkit.config.PROFILES, but kept local so the
# runner has no inter-module dependencies — it must be importable standalone).
# ---------------------------------------------------------------------------
def _profile_args(profile: str) -> List[str]:
    table = {
        "productivity": [
            "/cert:ignore",
            "+fonts",
            "+aero",
            "+window-drag",
            "+menu-anims",
            "/compression-level:2",
            "/gfx:AVC444",
        ],
        "gaming": [
            "/cert:ignore",
            "/gfx:AVC444",
            "/gfx-hw:1",
            "/network:auto",
            "+glyph-cache",
            "-theming",
        ],
        "minimal": [
            "/cert:ignore",
            "-aero",
            "-themes",
            "-wallpaper",
            "-window-drag",
            "-menu-anims",
            "/compression-level:2",
        ],
    }
    return list(table.get(profile, table["productivity"]))


# ---------------------------------------------------------------------------
# Convenience CLI entry point
# ---------------------------------------------------------------------------
def _main() -> int:  # pragma: no cover - manual smoke test
    import argparse

    p = argparse.ArgumentParser(description="rdp-mega-toolkit v9 runner")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("start", help="trigger a workflow_dispatch")
    sub.add_parser("stop", help="cancel all in-progress runs")
    sub.add_parser("list", help="list recent runs")
    sub.add_parser("connect", help="print xfreerdp connect command")
    sub.add_parser("rotate", help="trigger credential-rotate workflow")
    args = p.parse_args()

    if args.cmd == "start":
        rid = start_session()
        print(f"Started run_id={rid}")
    elif args.cmd == "stop":
        n = stop_all()
        print(f"Cancelled {n} run(s)")
    elif args.cmd == "list":
        for r in list_runs(limit=10):
            print(f"{r.run_id:>10}  {r.status:<11}  {r.conclusion or '-':<10}  {r.name}")
    elif args.cmd == "connect":
        print(connect_command())
    elif args.cmd == "rotate":
        rid = rotate_password()
        print(f"Triggered credential-rotate run_id={rid}")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(_main())
