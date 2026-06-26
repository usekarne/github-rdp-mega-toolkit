# Kali Linux — Install & Usage Guide

> Complete guide to installing and using the RDP Mega Toolkit on Kali Linux
> (and Debian / Ubuntu, which use the same install path).

## Why Kali?

Kali is the recommended platform for the toolkit because:

- It ships with `xfreerdp2-x11`, `openssh-client`, and `socat` by default.
- The `kali-linux-large` metapackage gives you a full pentest toolset inside
  the RDP session, pre-installed.
- Kali's `kali-desktop-xfce` is the lightest weight desktop that doesn't
  fight with xRDP's X11 expectations.
- Kali's apt repositories are fast and reliable from GitHub Actions runners
  (US-East).

## Prerequisites

| Requirement            | Minimum version | Check command                |
| :---------------------- | :-------------- | :--------------------------- |
| Kali Linux             | 2024.1+         | `cat /etc/os-release`        |
| Python                 | 3.10+           | `python3 --version`          |
| apt                    | 2.0+            | `apt --version`              |
| sudo privileges        | Required        | `sudo -v`                    |
| GitHub PAT             | `repo`+`workflow` scopes | <https://github.com/settings/tokens> |
| Disk space             | ~500 MB         | `df -h /`                    |

## Installation

### Method 1 — Debian `.deb` (recommended)

```bash
# Download or build the .deb:
#   - Pre-built: installers/debian/rdp-toolkit_9.0.0_all.deb
#   - From source: bash installers/debian/build.sh

sudo apt update
sudo apt install -y ./installers/debian/rdp-toolkit_9.0.0_all.deb
```

The `.deb` declares dependencies on `python3`, `python3-yaml`,
`openssh-client`, and `freerdp2-x11` — they're pulled in automatically
if missing. Post-install, `postinst` installs bash completion system-wide
and runs `rdp-toolkit config --platform kali` to bootstrap a default
config at `/etc/rdp-toolkit/config.yaml` (with user-specific overrides at
`~/.config/rdp-toolkit/config.yaml`).

Verify the install:

```bash
rdp-toolkit --version
rdp-toolkit doctor
```

### Method 2 — `pip install` from source

```bash
# Install build deps
sudo apt install -y python3-pip python3-build python3-venv

# Build + install
cd /path/to/rdp-mega-toolkit-v9
python3 -m build
python3 -m pip install --user --break-system-packages dist/rdp_toolkit-9.0.0-py3-none-any.whl

# Add ~/.local/bin to PATH if not already
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

rdp-toolkit --version
```

> **Kali 2024+ note**: Kali enforces PEP 668 (externally-managed
> environments). Use `--break-system-packages` for a user-wide install, or
> use a venv:
>
> ```bash
> python3 -m venv ~/.venvs/rdp-toolkit
> source ~/.venvs/rdp-toolkit/bin/activate
> pip install .
> ```

### Method 3 — Universal shell installer

```bash
bash installers/universal/install.sh
```

Detects Kali, runs `apt install python3-pip`, runs `pip install --user .`,
and symlinks `scripts/rdp-toolkit` into `~/.local/bin/`. Uninstall with
`bash installers/universal/uninstall.sh`.

### Method 4 — Manual (for development)

```bash
git clone https://github.com/usekarne/github-rdp-mega-toolkit.git
cd github-rdp-mega-toolkit

# Install runtime dep
sudo apt install -y python3-yaml

# Use the launcher directly
./scripts/rdp-toolkit doctor

# Or symlink it
sudo ln -sf "$PWD/scripts/rdp-toolkit" /usr/local/bin/rdp-toolkit
```

## Configuration

After install, generate the Kali-specific config:

```bash
rdp-toolkit config --platform kali
```

This writes `~/.config/rdp-toolkit/config.yaml` (mode `0600`). Open it in
your editor and tweak as needed — the defaults should "just work" on a
fresh Kali install, but you'll likely want to:

1. Fill in your Telegram / Discord notify block (optional).
2. Confirm `github.repo` points at your fork if you've forked the repo.
3. Confirm `tunnel.priority` matches your network realities.

Set your GitHub PAT:

```bash
echo 'export GH_PAT=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx' >> ~/.bashrc
source ~/.bashrc
```

## Usage Examples

### Start a 6-hour Kali RDP session

```bash
$ rdp-toolkit start --profile productivity --hours 6
[INFO] Starting RDP session: profile=productivity, hours=6
[OK]   Session started: run-id=12345678901
[INFO] Tunnel URL: serveo.net:43210
[INFO] Password: YOUR_PASSWORD_HERE
```

### Connect to the running session

```bash
$ rdp-toolkit connect 12345678901
[OK]   Ready-to-paste xfreerdp command:
xfreerdp /v:serveo.net:43210 /u:kali /p:YOUR_PASSWORD_HERE /cert:ignore +fonts +aero +window-drag +menu-anims /compression-level:2 /gfx:AVC444
```

Copy-paste that into a terminal and your RDP session opens.

### List active runs

```bash
$ rdp-toolkit status
[INFO] Active runs:
  - 12345678901  | in_prog  | tunnel=serveo.net:43210
  - 12345670000  | queued   | tunnel=n/a
[OK]   2 active run(s).
```

### Rotate the password

```bash
$ rdp-toolkit rotate 12345678901
[INFO] Rotating password for run: 12345678901
[OK]   Password rotated.
[INFO] New password: 7Hn$Qw2xLp9mKzB4
```

### Spin up a local Kali Docker VM instead

If you'd rather run RDP locally instead of in GitHub Actions:

```bash
$ rdp-toolkit vm start kali
[INFO] Starting VM: kali
[OK]   VM 'kali' started.
# Connect:
$ rdp-toolkit connect   # auto-detects the local VM
xfreerdp /v:localhost:13389 /u:kali /p:kali /cert:ignore +fonts +aero +window-drag +menu-anims /compression-level:2 /gfx:AVC444
```

### Stop everything

```bash
$ rdp-toolkit stop
[INFO] Stopping active RDP session(s)...
[OK]   Stopped 2 session(s).

$ rdp-toolkit vm stop kali
[INFO] Stopping VM: kali
[OK]   VM 'kali' stopped.
```

### Self-diagnose

```bash
$ rdp-toolkit doctor
[INFO] RDP Mega Toolkit v9.0.0 — diagnostics
  Platform:    kali
  Root/Admin:  True
  Python:      3.12.4
  Config dir:  ~/.config/rdp-toolkit/
  [OK]   xfreerdp     /usr/bin/xfreerdp
  [OK]   ssh          /usr/bin/ssh
  [OK]   socat        /usr/bin/socat
  [OK]   curl         /usr/bin/curl
  [OK]   cloudflared  /usr/bin/cloudflared
  [MISS] docker       not found
  [MISS] lt           not found
[INFO] Binaries found: 5/7
  [OK]   module rdp.runner
  [OK]   module tunnel.manager
  [OK]   module vm.manager
  [OK]   module platforms.installer
  [OK]   module notify
[OK]   Config OK: platform=kali, profile=productivity, hours=6
```

## Troubleshooting

### `rdp-toolkit: command not found` after pip install

The `~/.local/bin` directory isn't on your `PATH`. Fix:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### `RunnerError: GH_PAT environment variable is not set`

Set it:

```bash
export GH_PAT=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

To make it permanent, add the same line to `~/.bashrc` (or use a
`~/.config/rdp-toolkit/.env` file loaded by your shell).

### `RunnerError: workflow_dispatch failed (HTTP 403)`

Your PAT doesn't have `workflow` scope. Regenerate it at
<https://github.com/settings/tokens> with both `repo` and `workflow`
scopes checked.

### `xfreerdp: command not found` when connecting

Install it:

```bash
sudo apt install -y xfreerdp2-x11
```

### Tunnels all fail — `[ERR] Failed to start session: all tunnels failed`

The four tunnel providers occasionally have outages. Check
<https://serveo.net/> and <https://localhost.run/> status pages. If both
are down, install cloudflared:

```bash
# Add Cloudflare's GPG key + repo
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update
sudo apt install -y cloudflared
```

Then re-run `rdp-toolkit start` — the manager will fall through to
cloudflare automatically.

### `VMError: docker is not installed or not on PATH`

Install Docker:

```bash
sudo apt install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
# Log out and back in for the group change to take effect.
```

### `VMError: docker daemon is not running`

```bash
sudo systemctl start docker
```

### `permission denied while trying to connect to the Docker daemon socket`

Your user isn't in the `docker` group:

```bash
sudo usermod -aG docker $USER
newgrp docker   # or log out and back in
```

### `apt install ./rdp-toolkit_9.0.0_all.deb` fails with dependency errors

```bash
sudo apt update
sudo apt install -f     # fix broken deps
sudo apt install -y ./installers/debian/rdp-toolkit_9.0.0_all.deb
```

### Bash completion doesn't work

The `.deb` installs the completion to
`/etc/bash_completion.d/rdp-toolkit`. Make sure bash completion is enabled
in your shell:

```bash
# On Kali / Debian:
sudo apt install -y bash-completion
echo '. /etc/bash_completion' >> ~/.bashrc
source ~/.bashrc
```

### Running on Wayland

`xfreerdp` runs fine under XWayland — no special setup needed. If you're
on a pure Wayland session and `xfreerdp` complains about `DISPLAY`, force
XWayland:

```bash
xhost +local:   # one-time
xfreerdp /v:... # works
```

## Uninstall

### If installed via `.deb`

```bash
sudo apt remove --purge rdp-toolkit
```

The `--purge` flag also removes `/etc/rdp-toolkit/`. Your user config at
`~/.config/rdp-toolkit/` is preserved — delete it manually if you want a
full clean.

### If installed via `pip`

```bash
python3 -m pip uninstall rdp-toolkit
rm -rf ~/.config/rdp-toolkit
```

### If installed via the universal installer

```bash
bash installers/universal/uninstall.sh
```

## See Also

- [TUNNELS.md](TUNNELS.md) — Deep-dive on each tunnel provider.
- [API.md](API.md) — GitHub Actions REST API reference.
- [ARCHITECTURE.md](ARCHITECTURE.md) — Internal architecture & data flow.
- [SECURITY.md](SECURITY.md) — Credentials handling & security model.
