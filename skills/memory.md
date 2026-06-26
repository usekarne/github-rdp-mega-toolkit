# Agent Memory Skill — GitHub RDP Mega Toolkit v9.0

> **PURPOSE**: Any AI agent working on this project MUST read this file first. It contains all critical project context, known bugs, user preferences, and reusable patterns.

## Project Identity
- **Name**: GitHub RDP Mega Toolkit
- **Version**: 9.0.0 (MEGA rewrite)
- **Repo**: `usekarne/github-rdp-mega-toolkit`
- **License**: MIT
- **Author**: usekarne

## User Preferences (CRITICAL)
1. **NO NGROK** — user explicitly banned ngrok. Use Serveo (SSH) → localhost.run (SSH) → Cloudflare (fallback)
2. **Cross-platform**: Kali Linux + Windows + Android (Termux) all must work
3. **Real production code** — no demos, no placeholders, no TODOs
4. **.deb package** for Kali native install
5. **Auto-config** — workflows must auto-generate config files on first run
6. **Error-free** — user is very strict about bugs. Test all code before pushing.
7. **User language**: Hindi/English mix. Respond in same language.

## GitHub Secrets (already set)
- `RDP_MASTER_PASSWORD`: YOUR_PASSWORD_HERE
- (NO ngrok token — using Serveo instead)

## Known Bugs Fixed in v9.0 (DO NOT REINTRODUCE)
1. `Export-ModuleMember` in `.ps1` files → causes "can only be called from inside a module" error. FIX: Don't use it in dot-sourced scripts.
2. `$args` reserved variable in PowerShell → breaks winget install. FIX: Use `$wingetArgs` instead.
3. `connect-info.txt` BRIDGE_CMD and CONNECT_CMD on same line → client can't parse. FIX: Use `"BRIDGE_CMD=$b\`r\`nCONNECT_CMD=$c"` (CRLF separator).
4. `multi-runner.yml` matrix `fromJSON(format(...))` → produces empty array, no jobs created. FIX: Use static matrix `[0,1,2,3,4]` with step-level `if:` guard.
5. Cloudflare Quick Tunnel URLs expire when cloudflared process dies → session appears alive but tunnel is dead. FIX: Use Serveo as primary (SSH-based, more stable).

## Architecture
```
github-rdp-mega-toolkit/
├── .github/workflows/     # 25 workflows (lite/pro/ultimate/kali/ubuntu/multi-runner/...)
├── core/
│   ├── powershell/        # 12 PS modules (utils, setup-rdp, setup-tunnel, optimize, install-software, keepalive, cleanup, rotate-password, health-check, notify, setup-venv, auto-config)
│   ├── bash/              # 11 bash modules (same set, for Linux runners)
│   └── shared/            # tunnel-regex.md, artifact-spec.md, common-headers.txt
├── platforms/
│   ├── kali/              # .deb package, scripts, configs
│   ├── windows/           # installer (PS1/BAT/WiX/Chocolatey/Scoop/Winget), scripts, configs
│   └── android/           # Termux scripts
├── venvs/
│   ├── docker/            # Dockerfile.kali, docker-compose.yml, entrypoint.sh
│   ├── vagrant/           # Vagrantfile.kali
│   └── podman/
├── tools/
│   ├── python/            # fetch-creds.py, rdp-cli.py, tunnel-health-check.py, bulk-kill.py, session-stats.py, config-validator.py, release-builder.py
│   ├── bash/              # rdp-cli.sh, tunnel-bridge.sh, install.sh, uninstall.sh
│   └── powershell/        # rdp-cli.ps1
├── configs/               # 12 JSON configs
├── skills/                # Agent skills (this file + 9 others)
├── installer/             # Universal installer scripts
├── tests/                 # Test suite
├── docs/                  # 10 deep-dive docs
├── README.md, INSTALL.md, FEATURES.md, USAGE.md, TROUBLESHOOTING.md, API.md, CONTRIBUTING.md, CHANGELOG.md, MANIFEST.md, LICENSE, version.txt, .gitignore
```

## Tunnel Provider Priority
1. **Serveo** (primary) — `ssh -R 3389:localhost:3389 -N serveo.net` → direct host:port, no client bridge
2. **localhost.run** (secondary) — `ssh -R 3389:localhost:3389 -N nokey@localhost.run` → direct host:port
3. **Cloudflare** (fallback) — `cloudflared tunnel --url tcp://localhost:3389` → needs client bridge

## Artifact Files (every RDP run uploads these)
- `rdp-password.txt` — plain password
- `RDP_USERNAME.txt` — `RDP_USERNAME=runner`
- `RDP_PASSWORD.txt` — `RDP_PASSWORD=...`
- `tunnel-info.txt` — plain URL
- `tunnel-type.txt` — `serveo` | `localhost.run` | `cloudflare`
- `tunnel-host.txt` — plain host
- `tunnel-port.txt` — plain port
- `connect-info.txt` — `BRIDGE_CMD=...\r\nCONNECT_CMD=...` (CRLF separated)

## PowerShell Critical Rules
- Dot-source utils: `. "$PSScriptRoot\utils.ps1"`
- Artifact writes: `Out-File -Encoding ASCII -NoNewline`
- Multi-line in artifact: `"LINE1`r`nLINE2"` (use backtick-r backtick-n)
- NO `Export-ModuleMember` in `.ps1` files
- NO `$args` variable (reserved) — use `$wingetArgs`

## Bash Critical Rules
- Shebang: `#!/usr/bin/env bash`
- Always: `set -euo pipefail`
- Source utils: `source "$(dirname "$0")/utils.sh"`
- Artifact writes: `printf '%s'` (no trailing newline)
- Multi-line: `printf 'K1=%s\r\nK2=%s' "$v1" "$v2"`

## Workflow Critical Rules
- `name: "Workflow Name v9.0"` (version inside quotes)
- `permissions: contents: read, actions: write`
- `TUNNEL_PROVIDERS: serveo,localhost.run,cloudflare` (NO NGROK)
- `actions/checkout@v4`
- `actions/upload-artifact@v4`
- `if: always()` on cleanup steps
- Static matrix for multi-runner: `matrix: { index: [0,1,2,3,4] }`

## Common Failure Modes
1. **Setup RDP fails** → check utils.ps1 doesn't have Export-ModuleMember
2. **Tunnel setup fails** → check ssh.exe is available on runner, check TUNNEL_PROVIDERS env
3. **Artifact missing** → check upload-artifact step path list matches actual files
4. **xfreerdp can't connect** → tunnel expired (Cloudflare) or wrong port; re-fetch artifact
5. **Password shell error** → wrap in single quotes: `/p:'YOUR_PASSWORD_HERE'`

## User's GitHub PAT
`ghp_YOUR_TOKEN_HERE` — used for API calls, pushing, triggering workflows.
