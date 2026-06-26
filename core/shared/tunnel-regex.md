# Tunnel URL Regex Patterns (v9.0)

This document defines the regex patterns used by `core/powershell/setup-tunnel.ps1` and `core/bash/setup-tunnel.sh` to detect tunnel URLs in process logs.

## Serveo

- **Command**: `ssh -R 3389:localhost:3389 -N serveo.net`
- **Log location**: stderr (ssh writes status messages to stderr)
- **Regex**: `serveo\.net:(\d+)`
- **Example match**: `Forwarding TCP connections from serveo.net:12345 to localhost:3389`
- **Capture group 1**: port number (e.g., `12345`)
- **TunnelHost**: `serveo.net`
- **TunnelPort**: captured port
- **Needs client bridge**: No (direct host:port, paste into xfreerdp)

## localhost.run

- **Command**: `ssh -R 3389:localhost:3389 -N nokey@localhost.run`
- **Log location**: stderr
- **Regex**: `(?:localhost\.run|[\w-]+\.localhost\.run):(\d+)`
- **Example match**: `your tunnel is ready at: localhost.run:54321` OR `TCP forwarding from abc.localhost.run:54321`
- **Capture group 1**: port number
- **TunnelHost**: `localhost.run` (or subdomain if present)
- **TunnelPort**: captured port
- **Needs client bridge**: No

## Cloudflare Quick Tunnel

- **Command**: `cloudflared tunnel --no-autoupdate --url tcp://localhost:3389`
- **Log location**: stderr (cloudflared writes status to stderr)
- **Regex**: `(https://[a-z0-9-]+\.trycloudflare\.com)`
- **Example match**: `Your quick Tunnel has been created! Visit it at: https://abc-def-ghi.trycloudflare.com`
- **Capture group 1**: full HTTPS URL
- **TunnelHost**: URL minus `https://` prefix
- **TunnelPort**: `443` (HTTPS)
- **Needs client bridge**: Yes (`cloudflared access tcp --hostname HOST --url localhost:33890`)

## Polling Strategy

All providers poll their respective log files every 2 seconds:
- Serveo: 25 attempts = 50 seconds max
- localhost.run: 25 attempts = 50 seconds max
- Cloudflare: 30 attempts = 60 seconds max

If no URL is found within the polling window, the provider function returns `$false` (PowerShell) or `1` (bash), and the next provider in the priority list is tried.

## Fallback

If all providers fail, `Get-PublicIp` is called and the resulting IP is written to the artifact with `TUNNEL_TYPE=direct-ip-wont-work`. This won't actually work for RDP (GitHub runners don't allow inbound 3389), but at least the artifact has something for debugging.
