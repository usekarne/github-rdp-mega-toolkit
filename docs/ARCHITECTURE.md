# Architecture

> Internal architecture of the GitHub RDP Mega Toolkit v9.
>
> This document is for contributors and maintainers. If you're a user looking
> for "how do I use this", see [`KALI.md`](KALI.md), [`WINDOWS.md`](WINDOWS.md),
> or [`ANDROID.md`](ANDROID.md) instead.

## High-Level Layers

The toolkit is structured as a layered Python package. Each layer talks only
to the layer directly below it, and the top-most layer (the CLI) is the only
one allowed to print to the terminal.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       CLI Layer (rdp_toolkit.cli)                       │
│  argparse subcommands: install / start / stop / status / connect /      │
│  config / tunnel / vm / rotate / kill / doctor                          │
└─────────────┬──────────────────┬──────────────────┬────────────────────┘
              │                  │                  │
              ▼                  ▼                  ▼
   ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
   │ rdp.runner       │ │ tunnel.manager   │ │ vm.manager       │
   │ GitHub Actions   │ │ Provider pool +  │ │ Docker Compose   │
   │ REST client      │ │ failover         │ │ wrapper          │
   └────────┬─────────┘ └────────┬─────────┘ └────────┬─────────┘
            │                    │                    │
            ▼                    ▼                    ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │                       Implementation Layer                       │
   │  core_sh/*.sh     core_ps/*.ps1     tunnel/*.py     vm/compose.py │
   └──────────────────────────────────────────────────────────────────┘
            │                    │                    │
            ▼                    ▼                    ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │                       Foundation Layer                           │
   │  config.py  utils/system.py  utils/net.py  utils/crypto.py       │
   │  notify/*.py     platforms/*.py                                  │
   └──────────────────────────────────────────────────────────────────┘
```

### Layer responsibilities

| Layer            | Modules                                                        | Responsibility                                                  |
| :--------------- | :------------------------------------------------------------- | :-------------------------------------------------------------- |
| **CLI**          | `rdp_toolkit.cli`, `rdp_toolkit.__main__`                      | Parse argv, dispatch to the right submodule, print prefixed lines |
| **Orchestration**| `rdp_toolkit.rdp.runner`, `tunnel.manager`, `vm.manager`       | Coordinate multiple primitives into a high-level operation       |
| **Implementation**| `core_sh/`, `core_ps/`, `tunnel/<provider>.py`, `vm/compose.py`| The actual shell commands, HTTP requests, SSH invocations        |
| **Foundation**   | `config.py`, `utils/`, `notify/`, `platforms/`                 | Cross-cutting concerns: config, system detection, notifications  |

## Data Flow — `rdp-toolkit start --profile productivity --hours 6`

This is the canonical end-to-end flow when a user runs `start`. Every arrow
is a function call inside the same process; no IPC.

```
User
  │  $ rdp-toolkit start --profile productivity --hours 6
  ▼
cli.cmd_start(args)
  │  info("Starting RDP session: profile=productivity, hours=6")
  │  runner = lazy_import("rdp_toolkit.rdp.runner")
  ▼
rdp.runner.start_session(profile="productivity", hours=6)
  │  cfg = config.load_config()                       # Foundation
  │  workflow = cfg["github"]["workflow"]             # "lite-rdp.yml"
  │  token = os.environ["GH_PAT"]
  │  POST /repos/<repo>/actions/workflows/<wf>/dispatches
  │     body = {"ref": "main", "inputs": {"profile": "productivity", "hours": "6"}}
  │  if 204:
  │      run_id = _wait_for_new_run()                 # poll /actions/runs
  ▼
GitHub Actions
  │  Runner boots (ubuntu-latest), checks out the repo, runs:
  │    bash rdp_toolkit/core_sh/setup-rdp.sh          # install xRDP + XFCE
  │    bash rdp_toolkit/core_sh/install-software.sh   # read software-list.json
  │    bash rdp_toolkit/core_sh/optimize-linux.sh     # apply profile tweaks
  │    bash rdp_toolkit/core_sh/setup-tunnel.sh       # ← tunnel failover (below)
  │    bash rdp_toolkit/core_sh/keepalive.sh &        # 6-hour keepalive loop
  │    # at end:
  │    # upload rdp-credentials artifact (host/port/user/password/CONNECT_CMD)
  ▼
core_sh/setup-tunnel.sh  (inside the runner)
  │  for provider in serveo localhost.run cloudflare localtunnel:
  │      try _start_provider $provider
  │      if success: write host/port to /tmp/tunnel-info.txt, exit 0
  │      else: try next
  │  exit 1 (total failure)
  ▼
rdp.runner._wait_for_new_run (back in the CLI process)
  │  GET /repos/<repo>/actions/runs?event=workflow_dispatch
  │  diff against baseline, return the new run_id
  ▼
cli.cmd_start (continued)
  │  ok("Session started: run-id=<run_id>")
  │  info("Tunnel URL: serveo.net:43210")
  │  info("Password: <16-char random>")
  ▼
User pastes: $ rdp-toolkit connect <run_id>
  ▼
cli.cmd_connect(args)
  ▼
rdp.runner.connect_command(run_id)
  │  GET /repos/<repo>/actions/runs/<run_id>/artifacts
  │  for a in artifacts: if a.name == "rdp-credentials": artifact = a
  │  GET artifact.archive_download_url                  # zip download
  │  _parse_artifact_zip(blob)                          # parse KEY:VALUE / JSON / raw
  │  host = info["host"]; port = info["port"]; user = info["username"]
  │  args = _profile_args("productivity")
  │  return f"xfreerdp /v:{host}:{port} /u:{user} {args}"
  ▼
User runs the printed xfreerdp command → RDP session opens.
```

## Tunnel Failover Logic

The tunnel subpackage is the most subtle part of the toolkit. Failover
ordering is critical: **serveo → localhost.run → cloudflare → localtunnel**.
The first provider to return a working URL wins. The rest are *not* started
— we don't want three open tunnels, just one.

```
┌────────────────────────────────────────────────────────────────────────┐
│ TunnelManager.start_with_failover(local_port=3389)                     │
└────────────────────────────────────────────────────────────────────────┘
                  │
                  ▼
        ┌──────────────────┐
        │ Try serveo.net?  │  ssh -R 3389:localhost:3389 -N serveo.net
        └────────┬─────────┘  parse "Forwarding TCP traffic from port N"
            │
   ┌────────┴────────┐
   │ success?        │
   │                 │
  YES               NO
   │                 │
   │                 ▼
   │       ┌──────────────────┐
   │       │ Try localhost.run?│  ssh -R 80:localhost:3389 nokey@localhost.run
   │       └────────┬─────────┘  parse "<hash>.ltr.run"
   │            │
   │     ┌──────┴──────┐
   │    YES           NO
   │     │             │
   │     │             ▼
   │     │     ┌──────────────────┐
   │     │     │ Try cloudflare?  │  cloudflared tunnel --url tcp://localhost:3389
   │     │     └────────┬─────────┘  parse "<hash>.trycloudflare.com"
   │     │          │
   │     │     ┌────┴────┐
   │     │    YES       NO
   │     │     │         │
   │     │     │         ▼
   │     │     │ ┌──────────────────┐
   │     │     │ │ Try localtunnel? │  lt --port 3389
   │     │     │ └────────┬─────────┘  parse "<sub>.loca.lt"
   │     │     │      │
   │     │     │ ┌────┴────┐
   │     │     │YES       NO
   │     │     │ │         │
   │     │     │ │         ▼
   │     │     │ │  return {"ok": False, "errors": [...]}
   │     │     │ │
   ▼     ▼     ▼ ▼
   return {"ok": True, "provider": <name>, "url": <url>, ...}
```

### Why this order?

1. **Serveo first** — Pure SSH, no client binary other than `ssh` (already
   installed everywhere). Lowest latency from GitHub's US-East runners.
   Public, free, no auth. Works for raw TCP RDP traffic (port 3389 directly).
2. **localhost.run second** — Same SSH transport, returns an HTTPS URL on
   port 443. Useful when the client is behind an HTTPS-only proxy. Requires
   a small bridge because RDP-over-HTTPS isn't native.
3. **Cloudflare third** — Requires the `cloudflared` binary. Better
   throughput for non-USA clients, but the binary is 50 MB and not always
   preinstalled.
4. **localtunnel last** — Requires Node.js + `npm install -g localtunnel`.
   HTTP-based, survives cellular NAT handovers (good for Termux). Slowest
   of the four.

### Why no ngrok?

- The free tier requires registration and imposes aggressive rate limits.
- The ToS prohibits "running a remote desktop" without a paid plan.
- The binary download is mandatory (no static binary mirror).
- Cloudflare tunnels cover the same use-case with no auth and a more
  permissive ToS.

## VM Management

The `VMManager` (`rdp_toolkit/vm/manager.py`) wraps `docker compose` so the
CLI can `start` / `stop` / `shell` / `status` the three RDP containers
declared in `docker/docker-compose.yml`.

```
┌──────────────────────────────────────────────────────────────────────┐
│ VMManager                                                            │
│  ├── compose_path: Path     # docker/docker-compose.yml (auto-found)│
│  ├── _spec: ComposeSpec      # parsed services + ports + env        │
│  └── _compose_cmd: [str]     # ["docker", "compose"] or ["docker-  │
│                              #   compose"]                          │
└──────────────────────────────────────────────────────────────────────┘
              │
              │  start(name="kali")
              ▼
   _require_service("kali")     # SHORT_TO_SERVICE["kali"] = "kali-rdp"
   _require_docker()            # `which docker` + `docker info`
   port = _rdp_port("kali")     # 13389 (host port)
   creds = _credentials("kali") # {"user": "kali", "password": "kali"}
              │
              ▼
   _run(["up", "-d", "kali-rdp"])   # docker compose up -d kali-rdp
              │
              ▼
   _wait_healthy("rdp-toolkit-kali") # poll `docker inspect` for "healthy"
              │
              ▼
   return {"ok": True, "name": "kali", "port": 13389,
           "user": "kali", "password": "kali", ...}
```

### Compose v2 vs v1 detection

`VMManager._detect_compose_cmd()` prefers the modern `docker compose` v2
plugin (shipped with Docker Desktop and `docker-ce` since 2022), falling
back to the standalone `docker-compose` v1 Python binary on older systems.
Both work identically from the manager's point of view — the only
difference is the argv prefix.

### Health-check polling

Instead of grepping `docker compose ps` output (which differs wildly
between Compose versions), we poll `docker inspect --format
'{{json .State.Health}}' <container>` directly. This returns the canonical
`Status` field: `"starting"`, `"healthy"`, or `"unhealthy"`. We treat
`"unhealthy"` as a hard failure (returns immediately) and `"starting"` as
"keep polling until the deadline (default 120s)".

### Compose file auto-discovery

`VMManager.__init__` tries three locations for the compose file, in order:

1. The path passed to the constructor (relative to CWD).
2. `<package_root>/docker/docker-compose.yml` (so `pip install`-ed copies
   ship the compose file inside the package data).
3. A recursive upward search via `find_compose_file()` (for git checkouts).

## CLI Structure

The CLI is a single `argparse` parser with eleven subcommands. Every
subcommand handler is a top-level function `cmd_<name>(args) -> int`
returning a POSIX exit code. Handlers are wired up via
`sub.add_parser(...).set_defaults(func=cmd_<name>)`.

### Lazy imports

To keep `rdp-toolkit --help` fast and resilient (even when sibling
subpackages are still being built), every handler does its heavy import
*inside* the function body:

```python
def cmd_start(args):
    from .rdp import runner   # ← only imported when `start` is actually run
    runner.start_session(...)
```

This means a user can run `rdp-toolkit doctor` even if, say,
`rdp_toolkit.vm.manager` has a syntax error. The `doctor` command's
submodule probe will report `[PEND] module vm.manager` and move on.

### Output conventions

Every line the CLI prints is prefixed with one of four tags:

| Prefix   | Stream | Meaning                                            |
| :------- | :----- | :------------------------------------------------- |
| `[INFO]` | stdout | Neutral informational message                      |
| `[OK]`   | stdout | Successful operation                               |
| `[WARN]` | stdout | Recoverable warning (e.g. "not running as root")   |
| `[ERR]`  | stderr | Error — operation failed                           |

This makes the CLI grep-able (`grep '^\[ERR\]'`) and machine-parseable
(`grep -c '^\[OK\]'`).

## Module Dependency Graph

```
__main__  ────────────────► cli
                            │
        ┌───────────┬───────┼────────┬──────────┬─────────┐
        ▼           ▼       ▼        ▼          ▼         ▼
      config    rdp.runner tunnel.   vm.      platforms.  notify.
                (GitHub   manager   manager   installer   manager
                 API)                                      │
                 │                                         ▼
                 │                                  notify/discord.py
                 │                                  notify/telegram.py
                 │                                  notify/slack.py
                 │
                 └────► utils/system.py (detect_platform, config_dir, ...)
                        utils/net.py     (wait_for_port, ...)
                        utils/crypto.py  (gen_password, ...)
```

No cycles. `rdp.runner` is intentionally import-clean (no inter-module
dependencies) so it can be vendored standalone.

## Configuration Deep-Merge

`config.load_config()` works in three steps:

1. Read `~/.config/rdp-toolkit/config.yaml` (if it exists) into `user_cfg`.
2. Build `defaults = default_config(platform, profile, hours)` from the
   built-in defaults table.
3. Deep-merge `user_cfg` on top of `defaults` (user wins). Lists are
   *replaced wholesale* (not concatenated) — this matches user expectations
   when overriding e.g. `tunnel.priority`.

The merge is implemented in `config.merge_defaults()` as a recursive
helper that walks both dicts in lockstep.

## Failure Modes & Mitigations

| Failure                                | Where it surfaces         | Mitigation                                                  |
| :------------------------------------- | :------------------------ | :---------------------------------------------------------- |
| `GH_PAT` not set                       | `runner._config()`        | `RunnerError` with a helpful "create one at ..." message    |
| All four tunnels fail                  | `setup-tunnel.sh`         | Workflow exits non-zero; artifact upload is skipped; CLI prints `[ERR]` |
| Docker not installed                   | `VMManager._require_docker` | `VMError` with install URL                                 |
| Compose file missing                   | `find_compose_file()`     | `VMError` listing the searched paths                       |
| `pyyaml` not installed                 | `config._require_yaml()`  | `RuntimeError` with `pip install pyyaml` hint               |
| GitHub API rate-limited                | `runner._request()`       | `RunnerError` with HTTP 403 + body snippet                  |
| Artifact never uploaded (workflow failed) | `_download_and_parse_artifact` | Polls for 120s, then `RunnerError` with conclusion info |
| Artifact zip has the single-line concat bug | `runner.parse_kv()`  | Regex handles `KEY: VALUE KEY2: VALUE2` on one line        |

## Extending the Toolkit

### Adding a new tunnel provider

1. Create `rdp_toolkit/tunnel/<name>.py` with a class inheriting `TunnelBase`.
2. Implement `start(local_port) -> {"url", "host", "port", "type"}` and
   `stop()`.
3. Register the class in `tunnel/manager.py:_PROVIDER_MAP`.
4. Add the provider name to `TUNNEL_PRIORITY` in `config.py` (and to each
   per-platform `configs/*.yaml`).
5. Document in `docs/TUNNELS.md`.

### Adding a new notification channel

1. Create `rdp_toolkit/notify/<name>.py` with a class inheriting
   `NotificationChannel`.
2. Implement `send(message)`, `is_configured()`, and `info()`.
3. Register the class in `notify/manager.py:_CHANNEL_MAP`.
4. Add a stub block to `NOTIFY_DEFAULTS` in `config.py` and to
   `configs/default.yaml`.

### Adding a new CLI subcommand

1. Write `def cmd_<name>(args) -> int` in `cli.py`.
2. In `build_parser()`, add a `sub.add_parser("<name>")` block with all
   flags, then `p.set_defaults(func=cmd_<name>)`.
3. Add the subcommand to all three completion files
   (`scripts/completions/rdp-toolkit.{bash,zsh,fish}`).
4. Document in `README.md` and `MANIFEST.md`.
