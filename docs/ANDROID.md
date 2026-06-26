# Android / Termux — Install & Usage Guide

> Complete guide to installing and using the RDP Mega Toolkit on Android via
> [Termux](https://termux.dev/).

## Why Termux?

Termux gives you a real Linux userland running as a regular Android app —
no root required. The toolkit supports it as a first-class platform because:

- **No root needed.** Termux runs as a regular Android app with normal
  app permissions.
- **Always-on.** Your phone is always with you — start a session from your
  pocket, connect from any device.
- **Cheap.** GitHub Actions runners are free for public repos, and Termux
  itself is free. Your only cost is mobile data.
- **RDP client built-in.** Termux's `freerdp` package gives you a working
  `xfreerdp` you can use to connect directly from the phone (with a
  Bluetooth keyboard/mouse).

## Limitations on Android

| Limitation                | Why                                                            | Workaround                              |
| :------------------------ | :------------------------------------------------------------- | :-------------------------------------- |
| No Docker                 | Android kernel lacks the modules Docker needs; no root        | Use GitHub Actions runs instead         |
| No `kali-linux-large`     | Metapackage too big for Termux storage limits                  | Install individual tools with `pkg`     |
| Mobile bandwidth          | Cellular data caps + NAT handovers                             | Use `minimal` profile + `localtunnel`   |
| Background limits         | Android kills background apps to save battery                  | Use `termux-wake-lock` during sessions  |
| No systemd                | Termux is a single-process userland                            | Use `nohup` or `termux-services`        |
| Filesystem perms          | Android's scoped storage restricts `/sdcard` writes            | Work inside `$HOME`                     |

## Prerequisites

| Requirement            | Minimum version         | How to check                          |
| :---------------------- | :---------------------- | :------------------------------------ |
| Android                 | 9.0+ (API 28+)         | Settings → About phone                |
| Termux                  | 0.118+ from F-Droid    | `termux --version`                    |
| Termux:API (addon)      | 0.118+                  | Install from F-Droid                  |
| Storage                 | ~200 MB free           | `df -h $PREFIX`                       |
| GitHub PAT              | `repo` + `workflow`    | <https://github.com/settings/tokens>  |
| Internet                | Wi-Fi or 4G+           | `curl -sI https://api.github.com`     |

> **Important:** Install Termux from **F-Droid**, not Google Play. The Play
> Store version is unmaintained and has broken signature verification.

## Installation

### Step 1 — Bootstrap Termux

```bash
# Update + upgrade
pkg update && pkg upgrade -y

# Install core deps
pkg install -y python openssh socat curl jq git termux-api nano

# Grant storage access (one-time)
termux-setup-storage
```

### Step 2 — Install the toolkit

#### Option A — Termux bootstrap script (recommended)

```bash
# Clone (or download the ZIP from GitHub and extract)
git clone https://github.com/usekarne/github-rdp-mega-toolkit.git
cd github-rdp-mega-toolkit

# Run the Termux installer
bash installers/android/setup-termux.sh
```

The installer:

1. Installs Python deps via `pkg` (pyyaml, etc.).
2. Runs `pip install --user .` against the local source.
3. Symlinks `scripts/rdp-toolkit` into `$PREFIX/bin/rdp-toolkit`.
4. Installs bash completion into `$PREFIX/share/bash-completion/completions/`.
5. Writes a default config to `~/.config/rdp-toolkit/config.yaml`.
6. Prints a summary of what was installed.

#### Option B — `pip install` directly

```bash
pkg install -y python python-pip
pip install --user git+https://github.com/usekarne/github-rdp-mega-toolkit.git
```

#### Option C — Universal installer

```bash
git clone https://github.com/usekarne/github-rdp-mega-toolkit.git
cd github-rdp-mega-toolkit
bash installers/universal/install.sh
```

### Step 3 — Verify

```bash
rdp-toolkit --version
rdp-toolkit doctor
```

You should see `platform: android` in the doctor output. Some binaries
(specifically `cloudflared` and `docker`) will show `[MISS]` — that's
expected on Termux.

## Configuration

Generate the Android-specific config:

```bash
rdp-toolkit config --platform android
```

This writes `~/.config/rdp-toolkit/config.yaml` (mode `0600`). The Android
defaults:

- `profile: minimal` — strips aero/themes/wallpaper, 16-bit colour, 720p.
- `tunnel.priority: [localtunnel, cloudflare, serveo, localhost.run]` —
  HTTP-based localtunnel survives cellular NAT handovers best.
- `software` — minimal list (termux-api, openssh, socat, curl, jq, htop,
  git, nano, freerdp).
- `vm.enabled: false` — no Docker on Android.
- `session.hours: 2` — shorter default to respect mobile battery / data.

### Set your GitHub PAT

```bash
echo 'export GH_PAT=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx' >> ~/.bashrc
source ~/.bashrc
```

### Acquire wakelock (important!)

Android will kill background processes aggressively. Before starting a
session, acquire a wakelock:

```bash
termux-wake-lock
# To release later:
# termux-wake-unlock
```

## Usage Examples

### Start a 2-hour minimal session

```bash
$ rdp-toolkit start --profile minimal --hours 2
[INFO] Starting RDP session: profile=minimal, hours=2
[OK]   Session started: run-id=12345678901
[INFO] Tunnel URL: angry-elephant.loca.lt
[INFO] Password: YOUR_PASSWORD_HERE
```

### Connect to the running session (from the phone)

If you have a Bluetooth keyboard / mouse, you can connect directly from
Termux:

```bash
$ rdp-toolkit connect 12345678901
[OK]   Ready-to-paste xfreerdp command:
xfreerdp /v:angry-elephant.loca.lt:443 /u:termux /p:YOUR_PASSWORD_HERE /cert:ignore -aero -themes -wallpaper -window-drag -menu-anims /compression-level:2
```

Run that command and the RDP session opens in your terminal (with mouse
support if you have a Bluetooth mouse).

### Connect from a different device

Most of the time, you'll want to connect from a laptop or another phone
using the tunnel URL and credentials the toolkit printed.

- **From another phone/laptop with `xfreerdp`:** paste the printed command.
- **From a Windows machine with `mstsc.exe`:** enter the host (without
  `:443`) in the Computer field, click Connect, enter the username +
  password.
- **From a Mac:** use [Microsoft Remote Desktop](https://apps.apple.com/us/app/microsoft-remote-desktop/id1295203466).

### Check session status

```bash
$ rdp-toolkit status
[INFO] Active runs:
  - 12345678901  | in_prog  | tunnel=angry-elephant.loca.lt
[OK]   1 active run(s).
```

### Rotate the password

```bash
$ rdp-toolkit rotate
[INFO] Rotating password for run: latest
[OK]   Password rotated.
[INFO] New password: 7Hn$Qw2xLp9mKzB4
```

### Stop everything and release wakelock

```bash
$ rdp-toolkit stop
[INFO] Stopping active RDP session(s)...
[OK]   Stopped 1 session(s).

$ termux-wake-unlock
```

## Background Session Tips

### Use `nohup` to survive Termux being backgrounded

```bash
nohup rdp-toolkit start --profile minimal --hours 6 > /tmp/rdp-session.log 2>&1 &
echo $! > /tmp/rdp-session.pid

# Check progress:
tail -f /tmp/rdp-session.log

# Stop:
kill $(cat /tmp/rdp-session.pid)
```

### Use `termux-services` for longer sessions

Install [termux-services](https://github.com/termux/termux-services):

```bash
pkg install -y termux-services
source $PREFIX/etc/profile.d/start-services.sh

# Create a service:
mkdir -p ~/.sv/rdp-toolkit
cat > ~/.sv/rdp-toolkit/run <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
exec rdp-toolkit start --profile minimal --hours 6 2>&1
EOF
chmod +x ~/.sv/rdp-toolkit/run

sv-enable rdp-toolkit
sv up rdp-toolkit
sv status rdp-toolkit
```

### Use Termux:Boot to start on device boot

Install [Termux:Boot](https://wiki.termux.com/wiki/Termux:Boot) (from
F-Droid), then drop a script into `~/.termux/boot/`:

```bash
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/start-rdp-toolkit <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
rdp-toolkit start --profile minimal --hours 6
EOF
chmod +x ~/.termux/boot/start-rdp-toolkit
```

## Troubleshooting

### `pip install` fails with `error: externally-managed-environment`

Termux 0.118+ enforces PEP 668. Use `--break-system-packages`:

```bash
pip install --user --break-system-packages .
```

### `bash installers/android/setup-termux.sh` fails with `package not found`

Update your package lists:

```bash
pkg update
pkg upgrade -y
```

Then re-run the installer. If a specific package is still missing, it may
have been renamed — check `pkg search <name>`.

### `xfreerdp: command not found` when connecting

```bash
pkg install -y freerdp
```

If `freerdp` isn't in the Termux repo, install from source:

```bash
pkg install -y build-essential cmake git
git clone https://github.com/FreeRDP/FreeRDP.git
cd FreeRDP
mkdir build && cd build
cmake -DCMAKE_INSTALL_PREFIX=$PREFIX ..
make -j4
make install
```

### `localtunnel` (`lt`) is missing

Install Node.js and localtunnel:

```bash
pkg install -y nodejs
npm install -g localtunnel
```

### `serveo.net: port 22: Connection refused` — serveo is down

The failover should kick in and try `localhost.run` next. If all four
providers fail, check your internet connection:

```bash
curl -sI https://api.github.com   # should return 200
curl -sI https://serveo.net       # may return 000 if down
```

### `cloudflared` is missing and you really need it

Cloudflare doesn't ship an Android-native `cloudflared` binary, but you
can run the Linux ARM64 binary in Termux:

```bash
# Download the ARM64 binary
curl -L -o $PREFIX/bin/cloudflared \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64
chmod +x $PREFIX/bin/cloudflared
cloudflared --version
```

### Android kills the session after ~5 minutes

You didn't acquire a wakelock:

```bash
termux-wake-lock
```

Also, disable battery optimization for Termux in Android Settings → Apps →
Termux → Battery → Unrestricted.

### `xfreerdp` connects but the screen is frozen / laggy

Switch to the `minimal` profile:

```bash
rdp-toolkit start --profile minimal --hours 2
```

If it's still laggy, your mobile data connection is the bottleneck. Try
Wi-Fi or a different carrier. You can also drop the resolution by editing
`~/.config/rdp-toolkit/config.yaml`:

```yaml
rdp:
  resolution: "1024x768"
  color_depth: 8
```

### `cannot create directory '/sdcard/...'` — filesystem perms

Work inside `$HOME` instead of `/sdcard`. Termux can read but not write
`/sdcard` without explicit user consent (and even then, scoped storage
restricts which subdirectories are writable).

## Uninstall

```bash
# Remove the toolkit
pip uninstall -y rdp-toolkit

# Remove the launcher symlink
rm -f $PREFIX/bin/rdp-toolkit

# Remove the config
rm -rf ~/.config/rdp-toolkit

# Remove the bash completion
rm -f $PREFIX/share/bash-completion/completions/rdp-toolkit
```

## See Also

- [TUNNELS.md](TUNNELS.md) — Why localtunnel is the default on Android.
- [KALI.md](KALI.md) — Sister guide for Kali Linux.
- [API.md](API.md) — GitHub Actions REST API reference.
- [SECURITY.md](SECURITY.md) — Mobile-specific security considerations.
