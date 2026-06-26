# Windows — Install & Usage Guide

> Complete guide to installing and using the RDP Mega Toolkit on Windows 10/11
> (and Windows Server 2019+).

## Why Windows?

Windows is a first-class platform for the toolkit because:

- `xfreerdp` (via `freerdp` winget package) and `cloudflared` install cleanly
  via `winget` or `choco`.
- The NSIS installer gives a real Add/Remove Programs entry with a one-click
  uninstaller — no Python experience required.
- Windows is the most common RDP *client* OS, so running the toolkit on the
  same machine you connect from is convenient.
- Docker Desktop on Windows (WSL2 backend) runs the toolkit's three VMs
  natively.

## Prerequisites

| Requirement            | Minimum version          | Check command                |
| :---------------------- | :----------------------- | :--------------------------- |
| Windows                 | 10 build 19041+ / 11     | `winver`                     |
| PowerShell              | 5.1 (5.x preinstalled)   | `$PSVersionTable.PSVersion`  |
| Python                  | 3.10+                    | `py -3 --version`            |
| winget                  | v1.4+ (App Installer)    | `winget --version`           |
| Git                     | 2.30+ (optional)         | `git --version`              |
| GitHub PAT              | `repo` + `workflow` scope | <https://github.com/settings/tokens> |
| Disk space              | ~300 MB (without Docker) | `Get-PSDrive C`              |

## Installation

### Method 1 — NSIS `.exe` installer (recommended)

If a pre-built `rdp-toolkit-setup.exe` is available in
`installers/windows/`, double-click it and follow the wizard.

To build the installer from source:

```powershell
# Requires NSIS 3.x installed (https://nsis.sourceforge.io/)
cd installers\windows
.\build.bat
# Output: installers\windows\rdp-toolkit-setup.exe
```

The installer:

1. Checks for Python 3.10+ on `PATH`. If missing, it opens the Microsoft
   Store Python page.
2. Copies the Python package to `%LOCALAPPDATA%\Programs\rdp-toolkit\`.
3. Installs the `rdp-toolkit` console script (via `pip install --user`).
4. Adds `%LOCALAPPDATA%\Programs\rdp-toolkit\` to the user `PATH`.
5. Drops PowerShell completion into the PowerShell profile directory.
6. Registers an uninstaller in Add/Remove Programs.

Verify:

```powershell
rdp-toolkit --version
rdp-toolkit doctor
```

### Method 2 — `pip install` from source

```powershell
# Open PowerShell (not cmd.exe — cmd doesn't support $env:GH_PAT nicely)
cd C:\path\to\rdp-mega-toolkit-v9

# Build + install
py -3 -m pip install --user .
# Or, from a pre-built wheel:
py -3 -m pip install --user .\dist\rdp_toolkit-9.0.0-py3-none-any.whl

# Reload PATH (or open a new PowerShell window)
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

rdp-toolkit --version
```

### Method 3 — Universal installer (Git Bash / WSL)

If you have Git Bash or WSL installed:

```bash
bash installers/universal/install.sh
```

This is the same installer used on Linux/macOS — it detects Windows (via
`$OSTYPE`) and adapts its install path accordingly.

### Method 4 — Manual (for development)

```powershell
git clone https://github.com/usekarne/github-rdp-mega-toolkit.git
cd github-rdp-mega-toolkit

# Use the launcher directly (in PowerShell):
.\scripts\rdp-toolkit doctor

# Or, run via Python directly:
py -3 -m rdp_toolkit doctor
```

## Configuration

After install, generate the Windows-specific config:

```powershell
rdp-toolkit config --platform windows
```

This writes `%APPDATA%\rdp-toolkit\config.yaml` (per-user). Open it in
Notepad / VS Code and tweak as needed. The defaults use the `gaming`
profile (because Windows users are typically gaming or running multimedia)
and prefer `cloudflare` for tunnels (better throughput from non-USA
GitHub clients).

Set your GitHub PAT:

```powershell
# For the current session:
$env:GH_PAT = "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# For the current user (persistent):
[Environment]::SetEnvironmentVariable("GH_PAT", "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx", "User")

# For the machine (requires admin):
# [Environment]::SetEnvironmentVariable("GH_PAT", "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx", "Machine")
```

Open a new PowerShell window for the persistent set to take effect.

## Usage Examples

### Start a 4-hour gaming RDP session

```powershell
PS> rdp-toolkit start --profile gaming --hours 4
[INFO] Starting RDP session: profile=gaming, hours=4
[OK]   Session started: run-id=12345678901
[INFO] Tunnel URL: abc123.trycloudflare.com
[INFO] Password: YOUR_PASSWORD_HERE
```

### Connect to the running session

```powershell
PS> rdp-toolkit connect 12345678901
[OK]   Ready-to-paste xfreerdp command:
xfreerdp /v:abc123.trycloudflare.com:443 /u:runner /p:YOUR_PASSWORD_HERE /cert:ignore /gfx:AVC444 /gfx-hw:1 /network:auto +glyph-cache -theming
```

Paste that into a terminal and your RDP session opens. (You can also use
the native Windows `mstsc.exe` RDP client — see "Using mstsc.exe" below.)

### Using the native Windows `mstsc.exe` client

If you'd rather use the built-in Remote Desktop Connection client instead
of `xfreerdp`:

1. Press `Win+R`, type `mstsc`, press Enter.
2. In the "Computer" field, enter the host:port from the tunnel URL.
3. Click "Connect", enter the username + password when prompted.

Note: `mstsc.exe` doesn't accept all the `xfreerdp` flags (e.g. `/gfx:AVC444`
is FreeRDP-specific). The defaults work fine for most use cases.

### Run the Windows-compat Docker VM

The `windows-rdp` Docker image is **Ubuntu 22.04 + Wine + Fluxbox**, not a
real Windows image (licensing). It behaves the same from the RDP protocol's
point of view:

```powershell
PS> rdp-toolkit vm start windows
[INFO] Starting VM: windows
[OK]   VM 'windows' started.

PS> rdp-toolkit connect
# xfreerdp /v:localhost:33389 /u:win /p:win ...
```

### Self-diagnose

```powershell
PS> rdp-toolkit doctor
[INFO] RDP Mega Toolkit v9.0.0 — diagnostics
  Platform:    windows
  Root/Admin:  True
  Python:      3.12.4
  Config dir:  ~\.config\rdp-toolkit\
  [OK]   xfreerdp     C:\Program Files\FreeRDP\bin\xfreerdp.exe
  [OK]   ssh          C:\Windows\System32\OpenSSH\ssh.exe
  [MISS] socat        not found
  [OK]   curl         C:\Windows\System32\curl.exe
  [OK]   cloudflared  C:\Program Files (x86)\cloudflared\cloudflared.exe
  [OK]   docker       C:\Program Files\Docker\Docker\resources\bin\docker.exe
  [MISS] lt           not found
[INFO] Binaries found: 5/7
  [OK]   module rdp.runner
  [OK]   module tunnel.manager
  [OK]   module vm.manager
  [OK]   module platforms.installer
  [OK]   module notify
[OK]   Config OK: platform=windows, profile=gaming, hours=4
```

## Troubleshooting

### `rdp-toolkit : The term 'rdp-toolkit' is not recognized`

The install directory isn't on your `PATH`. Fix:

```powershell
$installDir = "$env:LOCALAPPDATA\Programs\rdp-toolkit"
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";$installDir", "User")
$env:Path += ";$installDir"   # for the current session
```

### `'py' is not recognized as an internal or external command`

Install the Python launcher from the Microsoft Store, or use the full
Python path:

```powershell
C:\Python312\python.exe -m rdp_toolkit doctor
```

### `RunnerError: GH_PAT environment variable is not set`

Set it (see "Configuration" above). Remember that PowerShell
`$env:GH_PAT = "..."` only sets it for the current session — use
`[Environment]::SetEnvironmentVariable(...)` for persistence.

### `winget install` fails with `0x80073d1f`

The Microsoft Store cache is corrupted. Reset it:

```powershell
wsreset.exe
```

Then retry the install.

### Docker Desktop won't start

Check that virtualization is enabled in your BIOS / UEFI. On Windows 11,
also ensure WSL2 is installed:

```powershell
wsl --install
wsl --set-default-version 2
```

Reboot after the WSL2 install.

### `xfreerdp` complains about missing `libwinpr` DLLs

The `freerdp` winget package sometimes installs without the runtime DLLs
on PATH. Add them:

```powershell
$dllPath = "C:\Program Files\FreeRDP\bin"
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";$dllPath", "User")
```

### Execution policy blocks the PowerShell scripts

If you're invoking `core_ps/*.ps1` directly:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### Antivirus flags the installer as suspicious

This is a false positive — the NSIS installer drops a Python package into
`%LOCALAPPDATA%`, which some heuristics flag. Add an exclusion for the
install directory:

```powershell
Add-MpPreference -ExclusionPath "$env:LOCALAPPDATA\Programs\rdp-toolkit"
```

### `xfreerdp` connects but the screen is black

You're hitting an RDP security negotiation mismatch. Add `/sec:nla` to
the connect command (forces Network Level Authentication):

```powershell
rdp-toolkit connect <run_id>   # prints the base command
# Append /sec:nla manually:
xfreerdp /v:... /u:... /p:... /sec:nla
```

### Cloudflare tunnel returns `trycloudflare.com` but RDP fails to connect

Cloudflare's free tier exposes an HTTPS endpoint on port 443, not raw TCP.
You need the cloudflared client on *your* side too:

```powershell
winget install Cloudflare.cloudflared
cloudflared access tcp --hostname abc123.trycloudflare.com --url localhost:13389
# Then in another terminal:
xfreerdp /v:localhost:13389 /u:runner /p:...
```

### `localtunnel` (`lt`) is missing

It's an npm package:

```powershell
# Requires Node.js (https://nodejs.org/)
npm install -g localtunnel
```

## Uninstall

### If installed via the NSIS installer

Open **Settings → Apps → Installed apps**, find "RDP Mega Toolkit", click
**Uninstall**. Or run:

```powershell
& "$env:LOCALAPPDATA\Programs\rdp-toolkit\uninstall.exe"
```

### If installed via `pip`

```powershell
py -3 -m pip uninstall rdp-toolkit
Remove-Item -Recurse -Force "$env:APPDATA\rdp-toolkit"
```

### If installed via the universal installer

```bash
bash installers/universal/uninstall.sh
```

## See Also

- [TUNNELS.md](TUNNELS.md) — Cloudflare bridge setup details.
- [ANDROID.md](ANDROID.md) — Sister guide for Termux.
- [API.md](API.md) — GitHub Actions REST API reference.
- [SECURITY.md](SECURITY.md) — Credentials handling on Windows (DPAPI note).
