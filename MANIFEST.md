# MANIFEST — File Inventory of v9.0.0

> Complete inventory of every file shipped with **GitHub RDP Mega Toolkit v9.0.0**
> (the "MEGA REWRITE"). Grouped by directory. Each entry has a one-line
> purpose. Last updated: 2026-06-25.

## Project Root

| File              | Purpose                                                                                  |
| :---------------- | :--------------------------------------------------------------------------------------- |
| `README.md`       | Project landing page — overview, quick start, install methods, usage, links.             |
| `CHANGELOG.md`    | Keep-a-Changelog-formatted release history.                                              |
| `LICENSE`         | MIT License, copyright 2026 usekarne.                                                    |
| `VERSION`         | Plain-text version file: `9.0.0`.                                                        |
| `pyproject.toml`  | PEP 517/518/621 build config (setuptools backend, `rdp-toolkit` console script).         |
| `setup.py`        | Legacy shim — `from setuptools import setup; setup()`. For old tooling.                  |
| `requirements.txt`| Runtime deps (`pyyaml>=6.0`) + commented dev extras.                                     |
| `.gitignore`      | Python, OS, IDE, build artifacts, and credential exclusions.                             |
| `MANIFEST.md`     | This file.                                                                               |
| `worklog.md`      | Multi-agent build log (appended-to by each task agent).                                  |

## `rdp_toolkit/` — Python Package

| File                         | Purpose                                                                                |
| :--------------------------- | :------------------------------------------------------------------------------------- |
| `__init__.py`                | Package version, `SUPPORTED_TUNNELS`, `SUPPORTED_PROFILES`, `_selfcheck()`.            |
| `__main__.py`                | `python -m rdp_toolkit` entry point — delegates to `cli.main()`.                       |
| `cli.py`                     | `argparse` CLI with 11 subcommands and lazy submodule imports.                         |
| `config.py`                  | Default config dict, profile table, deep-merge, `generate_config` / `load_config`.     |

### `rdp_toolkit/rdp/`

| File             | Purpose                                                                                |
| :--------------- | :------------------------------------------------------------------------------------- |
| `__init__.py`    | Re-exports public runner API.                                                          |
| `runner.py`      | GitHub Actions REST client — `start_session`, `stop_all`, `list_runs`, `connect_command`, `rotate_password`, `kill`, artifact zip parser. |

### `rdp_toolkit/tunnel/`

| File                | Purpose                                                                                |
| :------------------ | :------------------------------------------------------------------------------------- |
| `__init__.py`       | Re-exports `TunnelManager` + module-level wrappers.                                    |
| `base.py`           | `TunnelBase` ABC — `start`, `stop`, `is_alive`, `info`.                                |
| `serveo.py`         | `ServeoTunnel` — SSH reverse tunnel to `serveo.net`.                                   |
| `localhost_run.py`  | `LocalhostRunTunnel` — SSH reverse tunnel to `localhost.run`.                          |
| `cloudflare.py`     | `CloudflareTunnel` — wraps `cloudflared tunnel --url`.                                 |
| `localtunnel.py`    | `LocalTunnel` — wraps the `lt` npm package.                                            |
| `manager.py`        | `TunnelManager` — provider pool with failover + module-level `list_tunnels`/`status`/`test`. |

### `rdp_toolkit/vm/`

| File          | Purpose                                                                                |
| :------------ | :------------------------------------------------------------------------------------- |
| `__init__.py` | Re-exports `VMManager` + module-level wrappers.                                       |
| `compose.py`  | `ComposeSpec` parser + `find_compose_file()` walker + DEFAULT_PORTS / DEFAULT_CREDENTIALS. |
| `manager.py`  | `VMManager` — `start`/`stop`/`shell`/`status`/`list_vms`, healthcheck polling, `docker compose` v2 / `docker-compose` v1 detection. |

### `rdp_toolkit/notify/`

| File         | Purpose                                                                                |
| :----------- | :------------------------------------------------------------------------------------- |
| `__init__.py`| Re-exports `NotificationManager` + channels.                                          |
| `base.py`    | `NotificationChannel` ABC — `send`, `is_configured`, `info`, `_safe_config` redaction. |
| `discord.py` | `DiscordChannel` — POST JSON `{username, content}` to webhook.                         |
| `telegram.py`| `TelegramChannel` — POST form to `/bot<token>/sendMessage`.                            |
| `slack.py`   | `SlackChannel` — POST JSON `{text, mrkdwn:true}`.                                      |
| `manager.py` | `NotificationManager` — auto-discovers configured channels, never raises on send.      |

### `rdp_toolkit/platforms/`

| File          | Purpose                                                                                |
| :------------ | :------------------------------------------------------------------------------------- |
| `__init__.py` | Re-exports `install_for_platform` + per-platform modules.                              |
| `kali.py`     | Kali-specific install path (apt + kali-linux-large metapackage).                       |
| `ubuntu.py`   | Ubuntu/Debian-specific install path (apt).                                             |
| `windows.py`  | Windows-specific install path (winget / choco).                                        |
| `android.py`  | Termux-specific install path (pkg).                                                    |
| `installer.py`| Dispatch — `install_for_platform(plat)` → right per-platform module.                   |

### `rdp_toolkit/utils/`

| File         | Purpose                                                                                |
| :----------- | :------------------------------------------------------------------------------------- |
| `__init__.py`| Re-exports helpers.                                                                    |
| `system.py`  | `detect_platform()`, `is_root()`, `which()`, `config_dir()`.                           |
| `net.py`     | `wait_for_port()`, `random_free_port()`, `is_reachable()`.                             |
| `crypto.py`  | `gen_password()`, `hash_password()`, `verify_password()`.                              |

### `rdp_toolkit/core_sh/` — Bash implementation layer (Linux/macOS)

| File                  | Purpose                                                                                |
| :-------------------- | :------------------------------------------------------------------------------------- |
| `utils.sh`            | Shared bash helpers (`log_info`, `log_ok`, `log_warn`, `log_err`).                    |
| `setup-rdp.sh`        | Installs + configures xRDP + XFCE on the runner.                                       |
| `setup-tunnel.sh`     | Tries serveo → localhost.run → cloudflare → localtunnel in order.                      |
| `install-software.sh` | Reads `configs/software-list.json`, installs each `apt` package.                       |
| `rotate-password.sh`  | Generates a new password and updates the runner user.                                  |
| `optimize-linux.sh`   | Applies the selected profile's kernel / xRDP tweaks.                                   |
| `keepalive.sh`        | Pings the workflow's keepalive endpoint every N minutes.                               |
| `cleanup.sh`          | Removes installed packages + tmp files at session end.                                 |
| `health-check.sh`     | Reports tunnel alive / xRDP listening / disk free.                                     |

### `rdp_toolkit/core_ps/` — PowerShell implementation layer (Windows)

| File                       | Purpose (mirrors the bash layer)                                                       |
| :------------------------- | :------------------------------------------------------------------------------------- |
| `utils.ps1`                | Shared PS helpers.                                                                     |
| `setup-rdp.ps1`            | Enables + configures Windows OpenSSH server / RDP.                                     |
| `setup-tunnel.ps1`         | Same failover logic in PowerShell.                                                     |
| `install-software.ps1`     | Reads `software-list.json`, installs each `winget`/`choco` package.                    |
| `rotate-password.ps1`      | Rotates the local user password.                                                       |
| `optimize-windows.ps1`     | Applies the selected profile's registry / GPU tweaks.                                  |
| `keepalive.ps1`            | Keepalive loop in PowerShell.                                                          |
| `cleanup.ps1`              | Cleanup at session end.                                                                |
| `health-check.ps1`         | Health check.                                                                          |

## `configs/`

| File                 | Purpose                                                                                |
| :------------------- | :------------------------------------------------------------------------------------- |
| `default.yaml`       | Canonical default config (cross-platform baseline).                                    |
| `kali.yaml`          | Kali overrides — installs `kali-linux-large`, `kali-desktop-xfce`; serveo-first.       |
| `windows.yaml`       | Windows overrides — `winget` install path; gaming profile default.                     |
| `android.yaml`       | Termux overrides — minimal install, no Docker, localtunnel-friendly.                   |
| `software-list.json` | Multi-package-manager software catalogue (`winget`/`choco`/`apt`/`dnf`/`pacman`/`pkg`). |

## `docker/`

| File                                | Purpose                                                                                |
| :---------------------------------- | :------------------------------------------------------------------------------------- |
| `docker-compose.yml`                | Three-service compose file (`kali-rdp`, `ubuntu-rdp`, `windows-rdp`) on `rdp-net`.     |
| `README.md`                         | Docker-specific quickstart and image build instructions.                               |
| `kali-rdp/Dockerfile`               | Kali Rolling + XFCE + xRDP image.                                                      |
| `kali-rdp/entrypoint.sh`            | Creates RDP user, starts xRDP + sshd.                                                  |
| `ubuntu-rdp/Dockerfile`             | Ubuntu 22.04 + XFCE4 + xRDP image.                                                     |
| `ubuntu-rdp/entrypoint.sh`          | Same shape as Kali.                                                                    |
| `windows-rdp/Dockerfile`            | Ubuntu 22.04 + Wine + Fluxbox + xRDP "Windows-compat" image.                           |
| `windows-rdp/entrypoint.sh`         | Wine prefix init + Fluxbox + xRDP.                                                     |

## `installers/`

### `installers/debian/`

| File                              | Purpose                                                                                |
| :-------------------------------- | :------------------------------------------------------------------------------------- |
| `control`                         | Debian package control file (deps, maintainer, description).                           |
| `postinst`                        | Post-install — installs bash completion, runs `rdp-toolkit config`.                    |
| `prerm`                           | Pre-remove — stops active tunnels.                                                     |
| `postrm`                          | Post-remove — purges config dir on `purge`.                                            |
| `build.sh`                        | Builds the `.deb` from source using `dpkg-deb`.                                        |
| `rdp-toolkit_9.0.0_all.deb`       | Pre-built artifact.                                                                    |

### `installers/windows/`

| File             | Purpose                                                                                |
| :--------------- | :------------------------------------------------------------------------------------- |
| `installer.nsi`  | NSIS installer script — `PATH` registration, Add/Remove Programs entry, uninstaller.   |
| `build.bat`      | Invokes `makensis` to produce `rdp-toolkit-setup.exe`.                                 |

### `installers/android/`

| File                  | Purpose                                                                                |
| :-------------------- | :------------------------------------------------------------------------------------- |
| `setup-termux.sh`     | Installs Python deps, links launcher, writes default config.                           |
| `rdp-toolkit.sh`      | Termux-specific launcher shim (delegates to `python3 -m rdp_toolkit`).                 |

### `installers/universal/`

| File            | Purpose                                                                                |
| :-------------- | :------------------------------------------------------------------------------------- |
| `install.sh`    | Auto-detects OS, runs the right installer.                                             |
| `uninstall.sh`  | Auto-detects OS, undoes the install.                                                   |

## `scripts/`

| File                              | Purpose                                                                                |
| :-------------------------------- | :------------------------------------------------------------------------------------- |
| `rdp-toolkit`                     | Bash launcher: `python3 -m rdp_toolkit "$@"`.                                          |
| `completions/rdp-toolkit.bash`    | Bash completion for all subcommands.                                                   |
| `completions/rdp-toolkit.zsh`     | Zsh completion for all subcommands.                                                    |
| `completions/rdp-toolkit.fish`    | Fish completion for all subcommands.                                                   |

## `docs/`

| File              | Purpose                                                                                |
| :---------------- | :------------------------------------------------------------------------------------- |
| `ARCHITECTURE.md` | Internal architecture — layers, data flow, tunnel failover, VM management, CLI tree.   |
| `KALI.md`         | Kali Linux install + usage guide.                                                      |
| `WINDOWS.md`      | Windows install + usage guide.                                                         |
| `ANDROID.md`      | Android / Termux install + usage guide.                                                |
| `TUNNELS.md`      | Tunnel provider comparison + selection guide.                                          |
| `API.md`          | GitHub Actions REST API reference used by the toolkit.                                 |
| `CONTRIBUTING.md` | Dev workflow, code standards, commit conventions, PR process.                          |
| `SECURITY.md`     | Security model, credentials handling, incident response.                               |

## `.github/workflows/` (8 workflows)

| File                       | Purpose                                                                                |
| :------------------------- | :------------------------------------------------------------------------------------- |
| `lite-rdp.yml`             | Lightweight 2-hour session, serveo-first tunnel.                                       |
| `pro-rdp.yml`              | 6-hour productivity session with software install.                                     |
| `gaming-rdp.yml`           | Gaming profile, cloudflare-first tunnel.                                               |
| `kali-rdp.yml`             | Kali desktop-xfce install + tooling.                                                   |
| `windows-rdp.yml`          | Wine + Fluxbox "Windows-compat" image.                                                 |
| `android-rdp.yml`          | Minimal profile, low-memory runner, localtunnel.                                       |
| `credential-rotate.yml`    | Rotates RDP password for a run.                                                        |
| `doctor.yml`               | Scheduled self-check of the toolkit's installability.                                  |

---

**Totals (approximate):**
- Python source: ~25 files, ~2,800 LOC
- Bash / PowerShell: ~18 files, ~1,500 LOC
- YAML configs: 4 + 1 JSON
- Docker: 7 files (1 compose + 3 Dockerfiles + 3 entrypoints + 1 README)
- Installers: 13 files across 4 subdirs
- Docs: 9 markdown files (incl. CHANGELOG)
- Workflows: 8 YAML files
