# rdp-mega-toolkit v9 — Docker VMs

Three RDP-capable containers that ship with the toolkit. Each exposes a full
graphical desktop over the standard RDP protocol (TCP/3389), so any FreeRDP /
Remmina / xrdp / mstsc client can connect.

| Service         | Base image                  | Desktop          | Host port | Image tag               |
| --------------- | --------------------------- | ---------------- | --------- | ----------------------- |
| `kali-rdp`      | `kalilinux/kali-rolling`    | XFCE (Kali)      | `13389`   | `rdp-toolkit-kali:9.0`  |
| `ubuntu-rdp`    | `ubuntu:22.04`              | XFCE4            | `23389`   | `rdp-toolkit-ubuntu:9.0`|
| `windows-rdp`   | `ubuntu:22.04` + Wine64     | Fluxbox + Wine   | `33389`   | `rdp-toolkit-windows:9.0`|

> **Licensing note (Windows)**: a real Microsoft Windows desktop image
> cannot be legally redistributed as a generic Docker container.
> `windows-rdp` therefore ships a **Wine** compatibility layer on top of
> Ubuntu + Fluxbox so users get a desktop that runs many Windows `.exe`
> tools without shipping Microsoft binaries. See
> [`windows-rdp/Dockerfile`](windows-rdp/Dockerfile) for the full note. The
> RDP contract (port 3389) stays identical, so the toolkit doesn't care
> which image is underneath.

## Requirements

- Docker 20.10+ (BuildKit enabled by default in modern Docker)
- Docker Compose v2 (`docker compose ...`)
- ~6 GB free disk for the Kali image (it pulls `kali-desktop-xfce`)
- A Linux host with an X.509 RDP client: `xfreerdp`, `remmina`, `gnome-connections`, …

## Build

```bash
cd docker/

# Build all three
docker compose build

# Build a single one
docker compose build kali-rdp
```

## Run

```bash
# Start everything
docker compose up -d

# Start one (deps resolved automatically)
docker compose up -d kali-rdp

# Stream logs
docker compose logs -f kali-rdp
```

## Connect

Default credentials per image:

| Service         | User      | Password    | Connect command                                                       |
| --------------- | --------- | ----------- | --------------------------------------------------------------------- |
| `kali-rdp`      | `kali`    | `kali`      | `xfreerdp /v:localhost:13389 /u:kali /p:kali /dynamic-resolution`     |
| `ubuntu-rdp`    | `ubuntu`  | `ubuntu`    | `xfreerdp /v:localhost:23389 /u:ubuntu /p:ubuntu /dynamic-resolution` |
| `windows-rdp`   | `win`     | `win`       | `xfreerdp /v:localhost:33389 /u:win /p:win /dynamic-resolution`       |

SSH is also exposed (one host port per service: 10022 / 20022 / 30022):

```bash
ssh -p 10022 kali@localhost      # kali-rdp
ssh -p 20022 ubuntu@localhost    # ubuntu-rdp
ssh -p 30022 win@localhost       # windows-rdp
```

## Stop

```bash
docker compose down            # stop + remove containers, keep volumes
docker compose down -v         # also wipe the home-dir volumes
```

## Customization

All runtime knobs are environment variables — set them either inline with
`-e` for `docker run`, or in a `.env` file next to `docker-compose.yml`
(the compose file already reads them).

| Variable             | Default   | Applies to            | Purpose                                       |
| -------------------- | --------- | --------------------- | --------------------------------------------- |
| `RDP_USER`           | per image | all                   | Username for RDP / SSH / sudo                 |
| `RDP_PASS`           | per image | all                   | Password (re-applied on every container start)|
| `RDP_UID` / `RDP_GID`| `1000`    | all                   | Numeric uid/gid for the RDP user              |
| `ENABLE_SSH`         | `true`    | all                   | Start sshd                                    |
| `ENABLE_XRDP`        | `true`    | all                   | Start xrdp / xrdp-sesman                      |
| `ENABLE_WINE`        | `true`    | `windows-rdp`         | Bootstrap Wine prefix + winetricks on boot    |
| `WINETRICKS_APPS`    | `notepad` | `windows-rdp`         | Comma-separated winetricks verbs              |
| `TZ`                 | `UTC`     | all                   | Timezone                                      |

Compose-level overrides (in `.env` or shell env):

```bash
KALI_RDP_USER=kali
KALI_RDP_PASS=changeme
UBUNTU_RDP_USER=ubuntu
UBUNTU_RDP_PASS=changeme
WINDOWS_RDP_USER=win
WINDOWS_RDP_PASS=changeme
WINETRICKS_APPS=notepad,ie6,fonts
```

## Persistent volumes

Each service mounts a named volume on the user's home directory so config,
bash history, and (for `windows-rdp`) the Wine prefix survive restarts:

- `rdp-toolkit-kali-home`    → `/home/kali`
- `rdp-toolkit-ubuntu-home`  → `/home/ubuntu`
- `rdp-toolkit-windows-home` → `/home/win`

To reset a desktop back to defaults: `docker compose down -v && docker compose up -d`.

## Healthchecks

Every container ships a healthcheck that polls `ss -ltn` for a listener on
TCP/3389. Inspect with:

```bash
docker compose ps                              # shows (healthy)/(unhealthy)
docker inspect --format '{{.State.Health.Status}}' rdp-toolkit-kali
```

`start_period` is 60–90 s because the Kali / Wine images take a while to
boot on first run (large metapackages / prefix init).

## Networking

A single user-defined bridge network `rdp-net` is created. All three
containers live on it, so they can reach each other by service name:

```bash
# from inside kali-rdp
ssh ubuntu@ubuntu-rdp
xfreerdp /v:windows-rdp:3389 /u:win /p:win
```

## Troubleshooting

- **`xrdp-sesman: not found`** — image built from a stripped base; install
  `xrdp` explicitly in the Dockerfile.
- **Black screen after login** — `~/.xsession` is missing or unreadable.
  The entrypoint creates it from `/etc/skel/.xsession`; if you mount a
  read-only home dir, pre-create the file.
- **Wine first boot is slow** — the prefix init runs `wineboot --init` plus
  winetricks, both of which can take a couple of minutes on a cold cache.
  Watch with `docker compose logs -f windows-rdp`.
- **Port already in use on host** — change the left-hand side of the
  `ports:` mapping, e.g. `213389:3389`.

## Building / running images individually (without compose)

```bash
cd kali-rdp/
docker build -t rdp-toolkit-kali .
docker run -d --name rdp-toolkit-kali \
    -p 13389:3389 -p 10022:22 \
    -e RDP_USER=kali -e RDP_PASS=kali \
    -v rdp-toolkit-kali-home:/home/kali \
    rdp-toolkit-kali
```

Repeat the same pattern for `ubuntu-rdp/` and `windows-rdp/`.
