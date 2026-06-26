# GitHub RDP Mega Toolkit v9

> Cross-platform (Kali / Windows / Android) RDP automation with built-in Docker
> VMs, multi-tunnel failover, real installers, and YAML-driven auto-config.

[![Version](https://img.shields.io/badge/version-9.0.0-blue.svg)](./VERSION)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Python](https://img.shields.io/badge/python-%E2%89%A53.10-blue.svg)](./pyproject.toml)
[![Platforms](https://img.shields.io/badge/platforms-Kali%20%7C%20Windows%20%7C%20Android%20%7C%20Ubuntu-lightgrey.svg)](#quick-start)
[![Tunnels](https://img.shields.io/badge/tunnels-serveo%20%7C%20localhost.run%20%7C%20cloudflare%20%7C%20localtunnel-success.svg)](docs/TUNNELS.md)
[![Code Style](https://img.shields.io/badge/code%20style-PEP%208-black.svg)](docs/CONTRIBUTING.md)
[![Build](https://img.shields.io/badge/build-8%20workflows-orange.svg)](.github/workflows/)
[![Docs](https://img.shields.io/badge/docs-latest-brightgreen.svg)](docs/)

---

## What is this?

**GitHub RDP Mega Toolkit** is a single command-line tool (`rdp-toolkit`) that
boots a remote desktop — either as a GitHub Actions run that auto-tunnels back
to your machine, or as a local Docker VM — and then prints a ready-to-paste
`xfreerdp` / FreeRDP command so you can connect in seconds. It replaces the
dozens of half-finished shell scripts and disposable "RDP-in-a-Runner" repos
that exist across GitHub with one well-tested, installable, documented Python
package that behaves the same on Kali, Ubuntu, Windows, and Android (Termux).

The toolkit ships with **multi-tunnel failover** (serveo → localhost.run →
cloudflared → localtunnel, in that order — **no ngrok**), **three Docker VMs**
(Kali Rolling + XFCE, Ubuntu 22.04 + XFCE4, Wine + Fluxbox "Windows-compat")
exposed on host ports `13389 / 23389 / 33389`, **real platform installers**
(`.deb` for Kali/Debian, NSIS `.exe` for Windows, Termux `.sh` for Android,
plus a universal installer and a `pip`-installable wheel), and a YAML
auto-config system that materialises sensible per-platform defaults into
`~/.config/rdp-toolkit/config.yaml` and deep-merges any user overrides on top.
Eight GitHub Actions workflows drive the actual RDP runner, with credentials
delivered as a downloadable `rdp-credentials` artifact.

## Features

- **Multi-platform** — First-class support for **Kali Linux**, **Windows 10/11**,
  **Android (Termux)**, and **Ubuntu / Debian**. The CLI auto-detects the host
  platform via `rdp_toolkit.utils.system.detect_platform()` and loads the right
  defaults from `configs/<platform>.yaml`.
- **Tunnel failover (no ngrok)** — At session start the
  [`TunnelManager`](rdp_toolkit/tunnel/manager.py) tries providers in priority
  order: **serveo → localhost.run → cloudflare → localtunnel**. The first
  provider to return a working URL wins; the rest are left untouched. Each
  provider is implemented in its own module under
  `rdp_toolkit/tunnel/` and inherits from `TunnelBase`.
- **Docker VMs** — Three ready-to-run containers defined in
  [`docker/docker-compose.yml`](docker/docker-compose.yml): `kali-rdp`,
  `ubuntu-rdp`, `windows-rdp`. The toolkit wraps `docker compose` so the CLI
  can `start` / `stop` / `shell` / `status` them with one-liners and surfaces
  uniform host/port/user/password info to the caller.
- **Real installers** — Debian `.deb` (built from
  [`installers/debian/`](installers/debian/)), NSIS `.exe` for Windows
  ([`installers/windows/installer.nsi`](installers/windows/installer.nsi)),
  Termux bootstrap
  ([`installers/android/setup-termux.sh`](installers/android/setup-termux.sh)),
  plus a universal `install.sh`/`uninstall.sh` pair and a PEP 517-compliant
  `pip` wheel via [`pyproject.toml`](pyproject.toml).
- **Auto-config** — `rdp-toolkit config` introspects the host and writes a
  ready-to-edit YAML config to `~/.config/rdp-toolkit/config.yaml` (mode
  `0600`). Three optimisation profiles ship built-in:
  `productivity`, `gaming`, `minimal` — see
  [`rdp_toolkit/config.py`](rdp_toolkit/config.py).
- **Eight GitHub Actions workflows** — Drive the actual RDP runner inside a
  GitHub-hosted Ubuntu VM. Each workflow uploads an `rdp-credentials` artifact
  containing the tunnel host, port, username, and a ready-to-paste `xfreerdp`
  command.
- **Notifications** — Optional alerts to Discord / Telegram / Slack on session
  start, stop, and rotate. Channels are auto-discovered from the config block
  — see [`rdp_toolkit/notify/`](rdp_toolkit/notify).
- **Self-diagnosing** — `rdp-toolkit doctor` probes for every binary the
  toolkit uses (`xfreerdp`, `ssh`, `socat`, `curl`, `cloudflared`, `docker`,
  `lt`), checks whether each Python submodule imports cleanly, and validates
  the current config.
- **Shell completions** — Bash, Zsh, and Fish completions for all subcommands
  ship in [`scripts/completions/`](scripts/completions/).

## Quick Start

### Kali Linux

```bash
# 1. Install the .deb (preferred)
sudo apt install ./installers/debian/rdp-toolkit_9.0.0_all.deb

# 2. (or) pip install from source
python3 -m pip install --user .

# 3. Set up your GitHub PAT
export GH_PAT=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx

# 4. Diagnose, then start
rdp-toolkit doctor
rdp-toolkit config --platform kali
rdp-toolkit start --profile productivity --hours 6
```

### Windows 10/11

```powershell
# 1. Install via the NSIS installer (preferred)
.\installers\windows\rdp-toolkit-setup.exe

# 2. (or) pip install from source
py -3 -m pip install --user .

# 3. Set your PAT
$env:GH_PAT = "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# 4. Diagnose, then start
rdp-toolkit doctor
rdp-toolkit config --platform windows
rdp-toolkit start --profile gaming --hours 4
```

### Android (Termux)

```bash
# 1. Bootstrap Termux
pkg update && pkg install -y python openssh socat curl

# 2. Install the toolkit
bash installers/android/setup-termux.sh

# 3. Set your PAT
export GH_PAT=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx

# 4. Diagnose, then start (Termux uses the minimal profile by default)
rdp-toolkit doctor
rdp-toolkit config --platform android
rdp-toolkit start --profile minimal --hours 2
```

> **No GH PAT yet?** Create one at <https://github.com/settings/tokens> with
> the `repo` and `workflow` scopes, then export it as `GH_PAT` before running
> `rdp-toolkit start`. The toolkit uses `urllib.request` directly — no
> `requests` dependency required.

## Installation

The toolkit can be installed five different ways depending on your platform
and taste. All five end up with the same `rdp-toolkit` command on your
`$PATH`.

### 1. Debian `.deb` (Kali / Ubuntu / Debian)

```bash
sudo apt install ./installers/debian/rdp-toolkit_9.0.0_all.deb
```

The `.deb` declares dependencies on `python3`, `python3-yaml`,
`openssh-client`, and `freerdp2-x11` so they're pulled in automatically. To
rebuild from source: `bash installers/debian/build.sh`. The maintainer scripts
(`postinst`, `postrm`, `prerm`) install bash completion system-wide.

### 2. NSIS `.exe` (Windows)

```bat
:: Build it (requires NSIS installed):
installers\windows\build.bat

:: Install:
installers\windows\rdp-toolkit-setup.exe
```

The installer drops the Python package into `%LOCALAPPDATA%\Programs\rdp-toolkit`,
adds it to the user `PATH`, and registers an uninstaller in Add/Remove
Programs. Requires Python 3.10+ on `PATH`.

### 3. Termux (Android)

```bash
bash installers/android/setup-termux.sh
```

Installs the Python deps Termux can satisfy, symlinks the launcher into
`$PREFIX/bin/rdp-toolkit`, and writes a default config. No root required.

### 4. Universal shell installer (any POSIX system)

```bash
bash installers/universal/install.sh
# To remove:
bash installers/universal/uninstall.sh
```

Detects the OS, installs `python3-pip` if missing, runs `pip install --user .`
and links `rdp-toolkit` into `~/.local/bin`. Works on macOS, too.

### 5. `pip` (wheel)

```bash
python3 -m pip install --user .
# Or, after building a wheel:
python3 -m build && python3 -m pip install --user dist/rdp_toolkit-9.0.0-py3-none-any.whl
```

The `[project.scripts]` table in `pyproject.toml` exposes the
`rdp-toolkit` entry point.

## Usage

The CLI is `argparse`-based with subcommands. Every subcommand prints
prefixed lines (`[INFO]`, `[OK]`, `[WARN]`, `[ERR]`) so output is greppable
and machine-parseable.

```text
$ rdp-toolkit --help
usage: rdp_toolkit [-h] [-V] <command> ...

commands:
  install     install platform dependencies
  start       start an RDP session
  stop        stop active RDP session(s)
  status      show active runs
  connect     print ready-to-paste xfreerdp command
  config      auto-generate YAML config
  tunnel      manage tunnels
  vm          manage Docker VMs
  rotate      rotate password for a run
  kill        cancel runs
  doctor      diagnose installation
```

### `start` — boot an RDP session

```bash
# 6-hour productivity session
rdp-toolkit start --profile productivity --hours 6

# 4-hour low-latency gaming session
rdp-toolkit start --profile gaming --hours 4

# 2-hour lightweight session for slow links / Termux
rdp-toolkit start --profile minimal --hours 2
```

Triggers a `workflow_dispatch` against the configured repository
(`usekarne/github-rdp-mega-toolkit` by default) and polls the Actions API
until the new run appears. The run-id and tunnel URL are printed to stdout.

### `stop` — cancel active runs

```bash
rdp-toolkit stop
```

Cancels every `in_progress` / `queued` run for the configured repository.

### `status` — list active runs

```bash
rdp-toolkit status
```

Prints a compact table of recent workflow runs with their status and tunnel
URL.

### `connect` — print ready-to-paste `xfreerdp`

```bash
# Latest completed run
rdp-toolkit connect

# Specific run
rdp-toolkit connect 12345678901
```

Downloads the `rdp-credentials` artifact from the run, parses the connect
info, and prints a one-liner you can paste directly into a terminal. The
profile-selected `xfreerdp` flags (`+aero`, `/gfx:AVC444`, etc.) are applied
automatically.

### `config` — materialise the YAML config

```bash
rdp-toolkit config                       # auto-detect platform
rdp-toolkit config --platform kali       # force
rdp-toolkit config --platform android    # force
```

Writes `~/.config/rdp-toolkit/config.yaml` with mode `0600`. Edit by hand
afterwards — partial configs are deep-merged on top of the platform defaults.

### `tunnel` — inspect / test tunnel providers

```bash
rdp-toolkit tunnel list
rdp-toolkit tunnel status
rdp-toolkit tunnel test serveo
rdp-toolkit tunnel test all
```

### `vm` — manage Docker VMs

```bash
rdp-toolkit vm start kali        # boots kali-rdp on localhost:13389
rdp-toolkit vm start ubuntu      # boots ubuntu-rdp on localhost:23389
rdp-toolkit vm start windows     # boots windows-rdp on localhost:33389
rdp-toolkit vm stop kali
rdp-toolkit vm shell kali        # prints `docker compose exec kali-rdp bash`
```

Requires Docker 20.10+ and the `docker compose` v2 plugin (or the legacy
`docker-compose` v1 binary — both are auto-detected).

### `rotate` — rotate RDP password

```bash
rdp-toolkit rotate                 # latest run
rdp-toolkit rotate 12345678901     # specific run
```

Triggers the `credential-rotate.yml` workflow, which generates a new random
password, applies it inside the running session, and re-uploads the
`rdp-credentials` artifact.

### `kill` — cancel runs (specific or all)

```bash
rdp-toolkit kill                   # cancel everything
rdp-toolkit kill 12345678901       # cancel one run
rdp-toolkit kill all               # same as default
```

### `doctor` — diagnose the installation

```bash
rdp-toolkit doctor
```

Prints the detected platform, root/admin status, Python version, config
directory, then probes each binary on `$PATH` (`xfreerdp`, `ssh`, `socat`,
`curl`, `cloudflared`, `docker`, `lt`) and each Python submodule
(`rdp.runner`, `tunnel.manager`, `vm.manager`, `platforms.installer`,
`notify`). Exits non-zero if the config fails to load.

## Tunnel Providers

The toolkit ships with first-class support for four public tunnel providers,
tried in priority order at session start. **Ngrok is intentionally not
supported** — see [`docs/TUNNELS.md`](docs/TUNNELS.md) for the rationale.

| Priority | Provider        | Binary Required | Auth Needed | Endpoint Style         | Bridge Required |
| :------: | :-------------- | :-------------- | :---------- | :--------------------- | :-------------- |
|    1     | **serveo**      | `ssh`           | No          | `serveo.net:<port>`    | No              |
|    2     | **localhost.run** | `ssh`         | No          | `<hash>.ltr.run:443`   | Yes (HTTPS)     |
|    3     | **cloudflare**  | `cloudflared`   | No (quick)  | `<hash>.trycloudflare.com` | No (QUIC)   |
|    4     | **localtunnel** | `lt` (npm)      | No          | `<sub>.loca.lt`        | Yes (HTTP)      |

Override the priority in your config:

```yaml
tunnel:
  priority: [cloudflare, serveo, localhost.run, localtunnel]
```

See [`docs/TUNNELS.md`](docs/TUNNELS.md) for per-provider setup,
troubleshooting, and selection guidance.

## Docker VMs

The toolkit ships three RDP-capable containers in
[`docker/`](docker/docker-compose.yml). All three expose both RDP (3389 → host
`13389`/`23389`/`33389`) and SSH (22 → host `10022`/`20022`/`30022`).

| Service       | Image                        | Host RDP Port | Host SSH Port | Default User | Default Password |
| :------------ | :--------------------------- | :-----------: | :-----------: | :----------- | :--------------- |
| `kali-rdp`    | `rdp-toolkit-kali:9.0`       | `13389`       | `10022`       | `kali`       | `kali`           |
| `ubuntu-rdp`  | `rdp-toolkit-ubuntu:9.0`     | `23389`       | `20022`       | `ubuntu`     | `ubuntu`         |
| `windows-rdp` | `rdp-toolkit-windows:9.0`    | `33389`       | `30022`       | `win`        | `win`            |

> The `windows-rdp` image is **Ubuntu 22.04 + Wine + Fluxbox** — not a real
> Windows image, because licensing. It behaves the same from the RDP
> protocol's point of view. See
> [`docker/windows-rdp/Dockerfile`](docker/windows-rdp/Dockerfile) for the
> rationale.

Quick start:

```bash
cd docker
docker compose build kali-rdp
docker compose up -d kali-rdp

# Connect (kali/kali):
xfreerdp /v:localhost:13389 /u:kali /p:kali /cert:ignore +fonts +aero

# Or via the toolkit:
rdp-toolkit vm start kali
rdp-toolkit connect
```

Override the default credentials via environment variables
(`KALI_RDP_USER`, `KALI_RDP_PASS`, etc.) before `docker compose up`.

## Configuration

The toolkit auto-generates `~/.config/rdp-toolkit/config.yaml` on first use.
You can also bootstrap it explicitly:

```bash
rdp-toolkit config --platform kali
```

A typical config looks like this (see
[`configs/default.yaml`](configs/default.yaml) for the canonical version):

```yaml
version: "9.0.0"
platform: kali
profile: productivity

session:
  hours: 6
  username: rdpuser
  password: ""
  domain: ""

tunnel:
  priority: [serveo, localhost.run, cloudflare, localtunnel]
  providers:
    serveo:        { server: serveo.net, port: 22, remote_port: 0 }
    localhost.run: { server: nokey@localhost.run, port: 22 }
    cloudflare:    { bin: cloudflared, protocol: quic }
    localtunnel:   { bin: lt }

software:
  - xfreerdp2-x11
  - openssh-client
  - socat
  - apache2-utils
  - curl
  - jq

rdp:
  description: "Balanced for daily productivity RDP work"
  xfreerdp_args:
    - "/cert:ignore"
    - "+fonts"
    - "+aero"
    - "+window-drag"
    - "+menu-anims"
    - "/compression-level:2"
    - "/gfx:AVC444"
  resolution: "1920x1080"
  color_depth: 32
  audio: "sys:alsa"

notify:
  telegram: { enabled: false, bot_token: "", chat_id: "" }
  discord:  { enabled: false, webhook_url: "" }
  email:    { enabled: false, smtp_host: "", smtp_port: 587, to: "" }

vm:
  enabled: true
  default: kali
  docker_image_prefix: "rdp-toolkit/"
```

**Environment variables** override config values at runtime:

| Variable     | Purpose                                              | Default                              |
| :----------- | :--------------------------------------------------- | :----------------------------------- |
| `GH_PAT`     | GitHub PAT (`repo` + `workflow` scope). **Required.**| —                                    |
| `GH_REPO`    | Repository in `owner/name` form                      | `usekarne/github-rdp-mega-toolkit`   |
| `GH_API_URL` | API root (for GHES)                                  | `https://api.github.com`             |
| `KALI_RDP_USER` / `KALI_RDP_PASS` | Override Docker VM creds              | `kali` / `kali`                      |
| `UBUNTU_RDP_USER` / `UBUNTU_RDP_PASS` | Override Docker VM creds          | `ubuntu` / `ubuntu`                  |
| `WINDOWS_RDP_USER` / `WINDOWS_RDP_PASS` | Override Docker VM creds        | `win` / `win`                        |

## Documentation

| Document                                                | What it covers                                                              |
| :------------------------------------------------------ | :-------------------------------------------------------------------------- |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)         | Internal architecture, layer diagram, data flow, tunnel failover logic, VM management, CLI structure |
| [`docs/KALI.md`](docs/KALI.md)                          | Kali Linux install (`.deb` + manual) and usage guide with troubleshooting   |
| [`docs/WINDOWS.md`](docs/WINDOWS.md)                    | Windows install (NSIS `.exe` + manual) and usage guide with troubleshooting |
| [`docs/ANDROID.md`](docs/ANDROID.md)                    | Android / Termux install and usage guide                                    |
| [`docs/TUNNELS.md`](docs/TUNNELS.md)                    | All four tunnel providers explained, with comparison table & selection guide |
| [`docs/API.md`](docs/API.md)                            | GitHub Actions REST API reference used by the toolkit                       |
| [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md)          | Dev workflow, code standards, commit conventions, PR process                |
| [`docs/SECURITY.md`](docs/SECURITY.md)                  | Security model, credentials handling, mitigations, incident response        |
| [`CHANGELOG.md`](CHANGELOG.md)                          | Release history (Keep a Changelog format)                                   |
| [`MANIFEST.md`](MANIFEST.md)                            | File inventory of v9 (every file with its purpose)                          |

## Contributing

Contributions are welcome — please read
[`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) before opening a PR. In short:

1. Fork the repo, create a feature branch (`feat/<short-desc>` or
   `fix/<short-desc>`).
2. Run `python3 -m py_compile` on every `.py` you touch (the project has no
   test framework dependency — we rely on import-cleanliness + manual smoke
   tests).
3. Match the existing code style: PEP 8, `from __future__ import annotations`,
   explicit `__all__`, stdlib-only where possible, lazy imports inside CLI
   handlers.
4. Use [Conventional Commits](https://www.conventionalcommits.org/) —
   `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`.
5. Open a PR with a clear description and link any related issue.

See [`docs/SECURITY.md`](docs/SECURITY.md) for the security policy before
contributing anything that touches credentials, tokens, or networking.

## License

Released under the **MIT License** — see [`LICENSE`](LICENSE).

Copyright © 2026 [usekarne](https://github.com/usekarne).

---

<p align="center">
  <sub>Built with standard-library Python, bash, PowerShell, Docker, and a
  deep mistrust of ngrok.</sub>
</p>
