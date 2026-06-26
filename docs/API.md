# GitHub Actions REST API Reference

> The `rdp_toolkit.rdp.runner` module is a thin stdlib-only client around
> the GitHub Actions REST API. This document enumerates every endpoint it
> calls, the request/response shape, and how the toolkit uses each one.
>
> Canonical docs: <https://docs.github.com/en/rest/actions>

## Authentication

Every request carries:

```http
Authorization: Bearer <GH_PAT>
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
User-Agent: rdp-mega-toolkit-v9/runner
```

The PAT must have **`repo`** and **`workflow`** scopes. Create one at
<https://github.com/settings/tokens>.

The toolkit reads the token from the `GH_PAT` environment variable (overridable
via `github.pat_env_var` in the config). The repo defaults to
`usekarne/github-rdp-mega-toolkit` (overridable via `GH_REPO`).

## Endpoints Used

### 1. Trigger a workflow dispatch — `POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches`

Used by: `runner.start_session()`, `runner.rotate_password()`.

| Path param   | Value                              | Example                       |
| :----------- | :--------------------------------- | :---------------------------- |
| `owner/repo` | from `GH_REPO` env var             | `usekarne/github-rdp-mega-toolkit` |
| `workflow_id`| workflow filename or numeric ID    | `lite-rdp.yml`                |

**Request body** (`application/json`):

```json
{
  "ref": "main",
  "inputs": {
    "profile": "productivity",
    "hours": "6"
  }
}
```

> Workflow inputs are always strings — GitHub coerces them inside the
> workflow's `${{ inputs.X }}` substitution.

**Response:**

| Status | Meaning                              | Toolkit action                              |
| :----- | :----------------------------------- | :------------------------------------------ |
| `204`  | Dispatch accepted                    | Proceed to poll for the new run-id          |
| `404`  | Workflow not found                   | Raise `RunnerError` with the response body  |
| `422`  | Bad inputs (unknown `ref`, etc.)     | Raise `RunnerError` with the response body  |
| `403`  | PAT lacks `workflow` scope           | Raise `RunnerError` with "regenerate token" hint |

**Code:**

```python
# rdp_toolkit/rdp/runner.py
def start_session(profile="productivity", hours=6, workflow="lite-rdp.yml", *,
                  branch="main", extra_inputs=None):
    path = f"/repos/{repo}/actions/workflows/{workflow}/dispatches"
    inputs = {"profile": profile, "hours": str(int(hours))}
    if extra_inputs:
        inputs.update({k: str(v) for k, v in extra_inputs.items()})
    body = {"ref": branch, "inputs": inputs}
    status, _, raw = _request("POST", path, body=body, ...)
    if status != 204:
        raise RunnerError(f"workflow_dispatch failed (HTTP {status}): {raw[:500]}")
    return _wait_for_new_run(...)
```

### 2. Get a workflow — `GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}`

Used by: `runner._wait_for_new_run()` (to resolve the numeric `workflow_id`
so we can filter the runs list).

**Response (200):**

```json
{
  "id": 12345678,
  "name": "Lite RDP",
  "path": ".github/workflows/lite-rdp.yml",
  "state": "active",
  ...
}
```

The toolkit uses `id` to filter the runs list in the next call.

### 3. List workflow runs — `GET /repos/{owner}/{repo}/actions/runs`

Used by: `runner._wait_for_new_run()`, `runner.list_runs()`.

**Query params:**

| Param        | Purpose                                  | Example value              |
| :----------- | :--------------------------------------- | :------------------------- |
| `per_page`   | Page size (max 100)                      | `30`                       |
| `event`      | Filter by event type                     | `workflow_dispatch`        |
| `branch`     | Filter by branch                         | `main`                     |
| `status`     | Filter by status                         | `in_progress`, `completed` |

**Response (200):**

```json
{
  "total_count": 42,
  "workflow_runs": [
    {
      "id": 12345678901,
      "name": "Lite RDP",
      "head_branch": "main",
      "status": "in_progress",
      "conclusion": null,
      "workflow_id": 12345678,
      "html_url": "https://github.com/usekarne/github-rdp-mega-toolkit/actions/runs/12345678901",
      "created_at": "2026-06-25T10:00:00Z",
      ...
    },
    ...
  ]
}
```

The toolkit's `RunInfo.from_api()` parses this into a dataclass:

```python
@dataclass
class RunInfo:
    run_id: int
    name: str
    status: str          # queued | in_progress | completed
    conclusion: Optional[str]   # success | failure | cancelled | None
    html_url: str
    created_at: str
    head_branch: str
    workflow_id: int
```

### 4. Get a workflow run — `GET /repos/{owner}/{repo}/actions/runs/{run_id}`

Used by: `runner._download_and_parse_artifact()` (to detect when a run has
ended without producing the artifact).

**Response (200):** single run object (same shape as a `workflow_runs[]`
entry above).

The toolkit checks:

```python
if run_status == "completed" and conclusion != "success":
    raise RunnerError(
        f"run {run_id} ended with conclusion={conclusion!r} — "
        f"no {artifact_name} artifact will be produced."
    )
```

### 5. Cancel a workflow run — `POST /repos/{owner}/{repo}/actions/runs/{run_id}/cancel`

Used by: `runner._cancel_run()` (called by `runner.stop_all()` and
`runner.kill()`).

**Response:**

| Status | Meaning                              | Toolkit action                              |
| :----- | :----------------------------------- | :------------------------------------------ |
| `202`  | Cancel accepted                      | Return `True` (counted as cancelled)        |
| `409`  | Conflict (run already completed)     | Return `False` (not counted)                |
| `404`  | Run not found                        | Raise `RunnerError`                         |

```python
def stop_all(*, workflow=None):
    cancelled = 0
    for run in list_runs(limit=30, workflow=workflow):
        if run.status in ("in_progress", "queued"):
            if _cancel_run(token, repo, api_root, run.run_id):
                cancelled += 1
    return cancelled
```

### 6. List workflow run artifacts — `GET /repos/{owner}/{repo}/actions/runs/{run_id}/artifacts`

Used by: `runner._download_and_parse_artifact()`.

**Query params:**

| Param      | Purpose                |
| :--------- | :--------------------- |
| `per_page` | Page size (max 100)    |

**Response (200):**

```json
{
  "total_count": 2,
  "artifacts": [
    {
      "id": 987654321,
      "name": "rdp-credentials",
      "size_in_bytes": 1024,
      "url": "https://api.github.com/repos/.../actions/artifacts/987654321",
      "archive_download_url": "https://api.github.com/repos/.../actions/artifacts/987654321/zip",
      "expired": false,
      "created_at": "2026-06-25T10:05:00Z",
      ...
    },
    {
      "id": 987654322,
      "name": "rdp-logs",
      ...
    }
  ]
}
```

The toolkit finds the artifact with `name == "rdp-credentials"` (configurable
via `github.credentials_artifact`) and follows its `archive_download_url`.

### 7. Download an artifact — `GET {archive_download_url}`

Used by: `runner._download_and_parse_artifact()`.

> **Note:** This URL is on `api.github.com` and requires the same `Bearer`
> token as every other call. It returns a 302 redirect to a time-limited
> S3 URL — `urllib.request.urlopen()` follows the redirect automatically.

**Response (200):** binary ZIP archive.

The toolkit parses the ZIP into a flat `KEY: VALUE` dict via
`_parse_artifact_zip()`, handling:

- Multi-line `KEY: VALUE` files (one per line).
- The single-line concat bug (`KEY1: VALUE1 KEY2: VALUE2 ...`).
- Plain `KEY=VALUE` env-style files.
- Raw credential files (`RDP_USERNAME.txt`, `RDP_PASSWORD.txt`).
- Embedded JSON (e.g. `rdp-summary.json`).

## End-to-End `start_session` Flow

```
1. POST   /repos/{repo}/actions/workflows/lite-rdp.yml/dispatches
   body: {"ref":"main","inputs":{"profile":"productivity","hours":"6"}}
   → 204 No Content

2. GET    /repos/{repo}/actions/workflows/lite-rdp.yml
   → 200 + {"id": 12345678, ...}
   (we cache this workflow_id)

3. baseline = { run-ids we already know about }

4. Poll loop (every 3s, timeout 60s):
   GET  /repos/{repo}/actions/runs?event=workflow_dispatch&per_page=30
   → 200 + {"workflow_runs": [...]}
   for each run in workflow_runs:
     if run.workflow_id == 12345678 and run.id not in baseline:
       return run.id   ← SUCCESS

5. (out of band, GitHub Actions is now running the workflow)
   The workflow:
     - boots ubuntu-latest
     - checks out the repo
     - runs rdp_toolkit/core_sh/setup-rdp.sh
     - runs rdp_toolkit/core_sh/setup-tunnel.sh    (tunnel failover)
     - runs rdp_toolkit/core_sh/keepalive.sh &     (6-hour keepalive)
     - at end: uploads rdp-credentials artifact
```

## End-to-End `connect_command` Flow

```
1. (find the latest completed run if run_id not given)
   GET  /repos/{repo}/actions/runs?per_page=20
   → 200 + workflow_runs[]
   pick first with status=completed and conclusion=success

2. (poll for the artifact to appear)
   Poll loop (every 3s, timeout 120s):
     GET  /repos/{repo}/actions/runs/{run_id}/artifacts?per_page=100
     → 200 + {"artifacts": [...]}
     for each artifact in artifacts:
       if artifact.name == "rdp-credentials":
         target = artifact; break

     if not target:
       GET  /repos/{repo}/actions/runs/{run_id}
       → 200 + run object
       if run.status == "completed" and run.conclusion != "success":
         raise RunnerError("run failed — no artifact will be uploaded")

3. (download the artifact zip)
   GET  {target.archive_download_url}     # follows 302 to S3
   → 200 + binary zip

4. (parse the zip into a key/value dict)
   _parse_artifact_zip(blob) → {
     "host": "serveo.net",
     "port": "43210",
     "username": "runner",
     "CONNECT_CMD": "xfreerdp /v:serveo.net:43210 /u:runner ..."
   }

5. Build the xfreerdp command:
   if "CONNECT_CMD" in info: return info["CONNECT_CMD"]
   else: return f"xfreerdp /v:{host}:{port} /u:{user} {profile_args}"
```

## Rate Limits

GitHub's REST API has a default limit of **5,000 requests/hour** for
authenticated requests. The toolkit's typical session burns about 30-50
requests (`start` = 1 dispatch + ~15 polls for run-id + ~10 polls for
artifact; `connect` = ~10 polls; `stop` = 1 list + 1 cancel per run).

If you hit the limit:

```http
HTTP/1.1 403 Forbidden
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1719338400
```

The toolkit surfaces this as a `RunnerError` with the body snippet. Wait
until the reset time (epoch seconds in the `X-RateLimit-Reset` header) and
retry.

## GitHub Enterprise Server (GHES)

Override the API root via the `GH_API_URL` environment variable:

```bash
export GH_API_URL=https://github.mycompany.com/api/v3
```

All paths in the toolkit are relative to this root, so GHES works
transparently. The PAT must be a classic PAT (not an OAuth token) and
must have the `repo` scope on the GHES instance.

## Error Handling

Every API call goes through `runner._request()`, which:

1. Builds a `urllib.request.Request` with the right method/headers/body.
2. Calls `urllib.request.urlopen(req, timeout=30)`.
3. On `HTTPError`, returns `(status_code, headers, body)` — never raises.
4. On `URLError` (network failure), raises `RunnerError` with the URL.
5. The caller uses `_json_or_raise(status, body, expected=(200, 204, ...))`
   to either parse JSON or raise a `RunnerError` with the body snippet.

This means *every* API failure surfaces as a `RunnerError` with a helpful
message — never a raw `urllib` exception.

## Environment Variables

| Variable       | Required | Default                                | Purpose                                          |
| :------------- | :------- | :------------------------------------- | :----------------------------------------------- |
| `GH_PAT`       | Yes      | —                                      | GitHub PAT (`repo` + `workflow` scope)           |
| `GH_REPO`      | No       | `usekarne/github-rdp-mega-toolkit`     | Target repo in `owner/name` form                 |
| `GH_API_URL`   | No       | `https://api.github.com`               | API root (override for GHES)                     |

## See Also

- GitHub Actions REST API: <https://docs.github.com/en/rest/actions>
- Authenticating to the REST API: <https://docs.github.com/en/rest/overview/authenticating-to-the-rest-api>
- Workflow dispatch event: <https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#workflow_dispatch>
- `runner.py` source: [`rdp_toolkit/rdp/runner.py`](../rdp_toolkit/rdp/runner.py)
