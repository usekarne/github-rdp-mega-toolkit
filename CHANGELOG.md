# Changelog

All notable changes to the **GitHub RDP Mega Toolkit** are documented in this
file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [9.0.0] - 2026-06-25 — MEGA REWRITE

A ground-up rewrite of the toolkit. The v8 monolithic shell-script collection
has been replaced by a proper Python package with real installers, multi-
platform support, multi-tunnel failover, Docker VMs, and YAML-driven
auto-config. This release is not backwards-compatible with v8 configs or
CLI flags.

### Added — Cross-platform core

- **Python package** `rdp_toolkit/` with subpackages `cli`, `config`,
  `rdp.runner`, `tunnel`, `vm`, `notify`, `platforms`, `utils`. Stdlib +
  PyYAML only — no `requests`, no `click`, no `rich`.
- **Auto platform detection** via `rdp_toolkit.utils.system.detect_platform()`
  — recognises Kali, Ubuntu, Debian, Windows, Termux/Android.
- **PEP 517/518 build** via `pyproject.toml` — `setuptools>=61` backend,
  `rdp-toolkit` console-script entry point.
- **`doctor` subcommand** — probes for every binary (`xfreerdp`, `ssh`,
  `socat`, `curl`, `cloudflared`, `docker`, `lt`), every Python submodule,
  and the current config. Single-command health check.

### Added — Tunnels (no ngrok)

- **`ServeoTunnel`** (`rdp_toolkit/tunnel/serveo.py`) — SSH reverse tunnel
  via `serveo.net`. No client binary other than `ssh`. Parses both
  `serveo.net:<port>` and `Forwarding TCP traffic from port <N>` output
  formats.
- **`LocalhostRunTunnel`** (`rdp_toolkit/tunnel/localhost_run.py`) — SSH
  reverse tunnel via `localhost.run`. Returns an HTTPS URL (port 443).
- **`CloudflareTunnel`** (`rdp_toolkit/tunnel/cloudflare.py`) — wraps
  `cloudflared tunnel --url tcp://localhost:3389`. Returns a
  `<hash>.trycloudflare.com` endpoint.
- **`LocalTunnel`** (`rdp_toolkit/tunnel/localtunnel.py`) — wraps the `lt`
  npm package. Returns an HTTP URL.
- **`TunnelManager`** (`rdp_toolkit/tunnel/manager.py`) — tries providers
  in priority order (`serveo → localhost.run → cloudflare → localtunnel`),
  stops on first success. Module-level `list_tunnels()`, `status()`,
  `test()`, `start_with_failover()`, `stop_all()` convenience wrappers.
- **Ngrok support removed.** The `NGROK_AUTH_TOKEN` secret is no longer
  referenced by any workflow or code path. See `docs/TUNNELS.md` for the
  rationale (ToS issues, free-tier rate limits, mandatory binary download).

### Added — Installers

- **Debian `.deb`** (`installers/debian/`) — full maintainer scripts
  (`preinst`/`postinst`/`prerm`/`postrm`), declares deps on `python3`,
  `python3-yaml`, `openssh-client`, `freerdp2-x11`, installs bash
  completion system-wide. Built artifact: `rdp-toolkit_9.0.0_all.deb`.
- **NSIS `.exe`** (`installers/windows/installer.nsi`) — Windows installer
  with `PATH` registration and Add/Remove Programs entry. Build script:
  `installers/windows/build.bat`.
- **Termux bootstrap** (`installers/android/setup-termux.sh`) — installs
  Python deps, links the launcher into `$PREFIX/bin`, writes a default
  config. Companion launcher: `installers/android/rdp-toolkit.sh`.
- **Universal installer** (`installers/universal/install.sh` +
  `uninstall.sh`) — auto-detects OS, handles macOS / Linux / WSL.
- **PyPI-ready wheel** — `python3 -m build` produces
  `dist/rdp_toolkit-9.0.0-py3-none-any.whl`.

### Added — Docker VMs

- **`docker/docker-compose.yml`** declaring three RDP-capable services on a
  shared `rdp-net` bridge network:
  - `kali-rdp` → host port `13389` (Kali Rolling + XFCE + xRDP)
  - `ubuntu-rdp` → host port `23389` (Ubuntu 22.04 + XFCE4 + xRDP)
  - `windows-rdp` → host port `33389` (Ubuntu 22.04 + Wine + Fluxbox +
    xRDP — *not* a real Windows image, see `docker/windows-rdp/Dockerfile`
    for the licensing rationale)
- **Per-service Dockerfile** + `entrypoint.sh` under `docker/<service>/`.
- **`VMManager`** (`rdp_toolkit/vm/manager.py`) — wraps `docker compose` v2
  (with v1 `docker-compose` fallback). Public API: `start` / `stop` /
  `shell` / `status` / `list_vms`. Health-check polling via
  `docker inspect` (no `jq` dependency).

### Added — Auto-config

- **`rdp_toolkit/config.py`** — `default_config(platform, profile, hours)`
  materialises a complete config dict, `generate_config()` writes it to
  `~/.config/rdp-toolkit/config.yaml` (mode `0600`), `load_config()` reads
  it back with deep-merge on top of platform defaults so partial configs
  always work.
- **Three optimisation profiles** — `productivity` (balanced),
  `gaming` (low-latency, AVC444), `minimal` (Termux / slow links).
- **Per-platform YAML configs** in `configs/` — `default.yaml`,
  `kali.yaml`, `windows.yaml`, `android.yaml`.
- **`configs/software-list.json`** — multi-package-manager catalogue
  (`winget` / `choco` / `apt` / `dnf` / `pacman` / `pkg`) consumed by the
  install-software shell + PowerShell scripts.

### Added — CLI

- **Ten subcommands** — `install`, `start`, `stop`, `status`, `connect`,
  `config`, `tunnel`, `vm`, `rotate`, `kill`, `doctor`. See `--help`.
- **Lazy submodule imports** inside each handler so `--help` and `doctor`
  keep working even when a sibling subpackage is missing.
- **Prefixed log lines** (`[INFO]`, `[OK]`, `[WARN]`, `[ERR]`) for
  grep-ability.
- **Bash / Zsh / Fish completions** in `scripts/completions/`.

### Added — Notifications

- **`rdp_toolkit/notify/`** — three channel implementations (Discord,
  Telegram, Slack) inheriting from `NotificationChannel` ABC.
- **`NotificationManager`** auto-discovers configured channels from the
  `notify:` config block, never raises on send failures, returns
  `[(channel, success_bool)]` lists for inspection.

### Added — GitHub Actions workflows (8 total)

Eight workflows drive the actual RDP runner inside a GitHub-hosted Ubuntu
VM. Each uploads an `rdp-credentials` artifact containing the tunnel host,
port, username, and a ready-to-paste `xfreerdp` command:

1. `lite-rdp.yml` — lightweight 2-hour session, serveo-first tunnel.
2. `pro-rdp.yml` — 6-hour productivity session with software install.
3. `gaming-rdp.yml` — gaming profile, cloudflare-first tunnel.
4. `kali-rdp.yml` — Kali desktop-xfce install + tooling.
5. `windows-rdp.yml` — Wine + Fluxbox "Windows-compat" image.
6. `android-rdp.yml` — minimal profile, low-memory runner, localtunnel.
7. `credential-rotate.yml` — rotates RDP password for a run.
8. `doctor.yml` — scheduled self-check of the toolkit's installability.

### Added — Documentation

- **`docs/ARCHITECTURE.md`** — internal architecture, layer diagram, data
  flow, tunnel failover logic, VM management, CLI structure.
- **`docs/KALI.md`**, **`docs/WINDOWS.md`**, **`docs/ANDROID.md`** — per-
  platform install + usage guides with troubleshooting.
- **`docs/TUNNELS.md`** — comparison table and selection guide for all
  four supported providers.
- **`docs/API.md`** — GitHub Actions REST API reference used by the
  toolkit's `rdp.runner` module.
- **`docs/CONTRIBUTING.md`** — dev workflow, code standards, commit
  conventions, PR process.
- **`docs/SECURITY.md`** — security model, credentials handling,
  mitigations, incident response.
- **`MANIFEST.md`** — file inventory of v9 (every file with its purpose).

### Changed

- **Config schema** is now versioned (`version: "9.0.0"` field). The v8
  flat-key config is no longer supported.
- **Default branch** is `main` (was `master` in v5).
- **Default repository** is `usekarne/github-rdp-mega-toolkit`.
- **Default profile** is `productivity` (was implicit "balanced" in v8).
- **Tunnel priority order** is now `serveo → localhost.run → cloudflare →
  localtunnel`. Previously v8 hard-coded ngrok-only.

### Removed

- **Ngrok support** — gone. No `ngrok` binary probe, no `NGROK_AUTH_TOKEN`
  reference, no `--ngrok` flag.
- **Legacy `setup.py`-only build** — replaced by `pyproject.toml`
  (a tiny `setup.py` shim remains for backwards compatibility with
  callers that invoke it directly).
- **Bash-only CLI** — replaced by the Python `rdp-toolkit` CLI. The bash
  scripts remain under `rdp_toolkit/core_sh/` as the implementation layer
  invoked by `platforms.installer`, not as the user-facing entry point.
- **v4-era `--no-tunnel` flag** — superseded by the `tunnel` subcommand's
  `status` / `list` actions.

### Fixed

- Race condition where the runner's `_wait_for_new_run` could pick up a
  pre-existing run when the workflow had never been dispatched before.
  The baseline-set now captures any prior matching run-id set.
- Artifact zip parser now handles the single-line concat bug where the
  workflow's `echo "host: $H port: $P"` collapsed onto one line.
- `connect_command` now prefers a pre-built `CONNECT_CMD` if the artifact
  ships one (workflows can opt into shipping the full command).
- `VMManager._wait_healthy` now treats `unhealthy` as a hard failure
  instead of polling until the deadline.

---

## [5.0.2] - 2025-11-10

### Fixed
- `xfreerdp` connect command used `/u:runner` even when the artifact
  shipped a different `RDP_USERNAME` value.
- Bash launcher failed on Termux because `command -v python3.11` returns
  non-zero on default Termux installs.
- `doctor` falsely reported `cloudflared` as missing when it was installed
  via Homebrew on Apple Silicon (`/opt/homebrew/bin` wasn't probed).

### Changed
- Bumped default `--hours` from 4 to 6 to match the GitHub Actions 6-hour
  runner cap.

## [5.0.1] - 2025-08-22

### Fixed
- Race condition where the artifact upload raced ahead of the `actions`
  API listing — the runner now polls for up to 120s instead of failing
  immediately.
- `kill` subcommand exited non-zero when there were zero runs to cancel;
  it now returns `0` with an "no active runs" message.

### Added
- `configs/software-list.json` gained a `pkg` (Termux) field per package.
- Bash completion now completes `--profile` choices.

## [5.0.0] - 2025-06-01

### Added — v5 baseline
- First release with `argparse`-based CLI (`start`, `stop`, `status`,
  `connect`, `rotate`, `kill`, `doctor`).
- GitHub Actions REST API client (stdlib `urllib.request` only).
- Artifact download + zip parse logic.
- `xfreerdp` connect-command builder.
- Default profile args table.
- `GH_PAT`, `GH_REPO`, `GH_API_URL` env-var configuration.

### Changed
- Replaced the v4 `curl`-and-`jq` ad-hoc shell glue with a proper Python
  runner module.

---

## [4.3.1] - 2025-02-14
### Fixed
- `xfreerdp` flags included `+fonts` twice on the gaming profile.

## [4.3.0] - 2025-01-20
### Added
- `rotate` subcommand.
- `credential-rotate.yml` workflow.

## [4.2.0] - 2024-11-05
### Added
- `kill` subcommand (cancels individual run-ids, not just all).
### Changed
- `stop` now reports the cancelled count.

## [4.1.0] - 2024-08-10
### Added
- `doctor` subcommand (bash-only at this point).
- `status` subcommand (was previously only available via raw API).

## [4.0.0] - 2024-05-01
### Added
- First public release on GitHub under the MIT license.
- Single bash script (`rdp-mega.sh`) wrapping the GitHub Actions API.
- Hard-coded ngrok as the only tunnel.
- `start` / `stop` / `connect` subcommands.

---

[9.0.0]: https://github.com/usekarne/github-rdp-mega-toolkit/releases/tag/v9.0.0
[5.0.2]: https://github.com/usekarne/github-rdp-mega-toolkit/releases/tag/v5.0.2
[5.0.1]: https://github.com/usekarne/github-rdp-mega-toolkit/releases/tag/v5.0.1
[5.0.0]: https://github.com/usekarne/github-rdp-mega-toolkit/releases/tag/v5.0.0
