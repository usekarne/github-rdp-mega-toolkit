# Artifact File Specification (v9.0)

Every RDP session workflow uploads an artifact named `rdp-credentials` containing these files:

## File List

| File | Format | Content | Example |
|---|---|---|---|
| `rdp-password.txt` | plain | The RDP password (no KEY= prefix) | `YOUR_PASSWORD_HERE` |
| `RDP_USERNAME.txt` | KEY=VALUE | The username | `RDP_USERNAME=runner` |
| `RDP_PASSWORD.txt` | KEY=VALUE | Same password as rdp-password.txt | `RDP_PASSWORD=YOUR_PASSWORD_HERE` |
| `tunnel-info.txt` | plain | Full tunnel URL | `tcp://serveo.net:12345` OR `https://abc.trycloudflare.com` |
| `tunnel-type.txt` | plain | Which provider came up | `serveo` \| `localhost.run` \| `cloudflare` \| `direct-ip-wont-work` |
| `tunnel-host.txt` | plain | Hostname part | `serveo.net` |
| `tunnel-port.txt` | plain | Port part | `12345` |
| `connect-info.txt` | KEY=VALUE (multi-line) | BRIDGE_CMD + CONNECT_CMD | see below |
| `health-status.json` | JSON | System health (only from health-check step) | see health-check.ps1 |

## connect-info.txt Format

Two lines, separated by `\r\n` (CRLF):

```
BRIDGE_CMD=cloudflared access tcp --hostname abc.trycloudflare.com --url localhost:33890
CONNECT_CMD=xfreerdp /v:localhost:33890 /u:runner /p:'YOUR_PASSWORD_HERE' /cert:ignore +clipboard +auto-reconnect /size:1280x720
```

For serveo/localhost.run (no bridge needed), BRIDGE_CMD is empty:

```
BRIDGE_CMD=
CONNECT_CMD=xfreerdp /v:serveo.net:12345 /u:runner /p:'YOUR_PASSWORD_HERE' /cert:ignore +clipboard +auto-reconnect /size:1280x720
```

## Writing Convention

- **PowerShell**: `Out-File -Encoding ASCII -NoNewline` (avoids BOM and trailing newline)
- **Bash**: `printf '%s'` (no trailing newline)
- **Multi-line in PowerShell**: Use `\`r\`n` explicitly in the string: `"BRIDGE_CMD=$bridge\`r\`nCONNECT_CMD=$connect"`
- **Multi-line in Bash**: Use `printf 'BRIDGE_CMD=%s\r\nCONNECT_CMD=%s' "$bridge" "$connect"`

## Why No Trailing Newline?

The client-side `fetch-creds.py` parser strips whitespace anyway, but keeping files newline-free avoids issues with tools that don't expect a trailing `\n`. The CRLF between BRIDGE_CMD and CONNECT_CMD is the only intentional line break.

## Client Parser

`tools/python/fetch-creds.py` uses a robust 2-pass `parse_kv()` function:
1. **Pass 1**: Line-by-line parsing (handles properly-formatted multi-line files)
2. **Pass 2**: Regex backfill with key-boundary lookahead (handles legacy single-line concat bug `K1=V1K2=V2`)

For plain-value files (like `tunnel-type.txt` which is just `cloudflare`), the parser uses a `plain()` helper that returns the raw content stripped of whitespace.
