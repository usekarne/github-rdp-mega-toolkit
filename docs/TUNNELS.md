# Tunnel Providers

> The RDP Mega Toolkit ships with first-class support for **four** public
> tunnel providers. **Ngrok is intentionally not supported.** This document
> explains each provider, the comparison table, and how to choose.

## Why not ngrok?

Ngrok was the toolkit's primary tunnel in v4-v8. It was removed in v9 for
three concrete reasons:

1. **ToS violation.** Ngrok's free-tier Terms of Service explicitly prohibit
   "running a remote desktop" without a paid plan. The toolkit was getting
   free-tier accounts banned.
2. **Mandatory binary download.** Ngrok requires downloading the proprietary
   `ngrok` binary, which can't be vendored into a repo (license restrictions
   on redistribution).
3. **Free-tier rate limits.** Ngrok's free tier limits concurrent tunnels
   and bandwidth, making it unsuitable for the toolkit's 6-hour sessions
   with desktop-grade traffic.

The four replacements (serveo, localhost.run, cloudflare, localtunnel)
cover the same use cases with more permissive ToS and no account
requirements.

## Provider Comparison

| Aspect                | serveo              | localhost.run           | cloudflare              | localtunnel            |
| :-------------------- | :------------------ | :---------------------- | :---------------------- | :--------------------- |
| **Priority (default)** | 1                   | 2                       | 3                       | 4                      |
| **Binary required**   | `ssh`               | `ssh`                   | `cloudflared`           | `lt` (npm)             |
| **Auth needed**       | No                  | No                      | No (quick tunnels)      | No                     |
| **Account needed**    | No                  | No                      | No                      | No                     |
| **Endpoint style**    | `serveo.net:<port>` | `<hash>.ltr.run:443`    | `<hash>.trycloudflare.com` | `<sub>.loca.lt`     |
| **Transport**         | Raw TCP (SSH -R)    | HTTPS (SSH -R)          | QUIC / HTTP2            | HTTP                   |
| **RDP works directly?** | Yes              | No (HTTPS bridge)       | Yes (cloudflared client) | No (HTTP bridge)     |
| **Bridge required?**  | No                  | Yes                     | No (QUIC mode)          | Yes                    |
| **Latency (US-East)** | ~30ms               | ~50ms                   | ~40ms                   | ~80ms                  |
| **Bandwidth**         | Unlimited           | Unlimited               | Unlimited               | ~1 MB/s                |
| **Stability**         | Occasional outages  | Very stable             | Very stable             | Stable                 |
| **Works on Termux?**  | Yes                 | Yes                     | Via ARM64 binary        | Yes                    |
| **Works on Windows?** | Yes (OpenSSH)       | Yes (OpenSSH)           | Yes (cloudflared.exe)   | Yes (npm)              |
| **Persistent URL?**   | No (random port)    | No (random hash)        | No (random hash)        | Yes (subdomain option) |
| **ToS summary**       | Free, no limits     | Free, no limits         | Free for quick tunnels  | Free, no limits        |

## Provider Deep-Dives

### 1. serveo (`serveo.net`)

Serveo is a free SSH-based relay. You run:

```bash
ssh -R 3389:localhost:3389 -N serveo.net
```

Serveo allocates a random public port on `serveo.net` and forwards TCP
traffic back to `localhost:3389` on your machine. The public endpoint
becomes `serveo.net:<port>` — a raw TCP socket that `xfreerdp` can connect
to directly with no client-side bridge.

**Strengths:**
- No client binary other than `ssh` (already installed everywhere).
- Raw TCP — works for RDP without any HTTP bridging.
- Lowest latency of the four (one SSH hop).
- Free, no account, no ToS restrictions on RDP.

**Weaknesses:**
- Occasional outages (single-operator service).
- Random port allocation means you can't get a stable URL.
- No encryption beyond SSH's transport layer.

**Output parsing:** The toolkit greps for two patterns in serveo's SSH
output:

```
Hi! You've successfully authenticated, but we do not provide shell access.
Forwarding TCP traffic from port 43210
```

The `43210` becomes the remote port. The public endpoint is
`serveo.net:43210`.

**Config:**

```yaml
tunnel:
  providers:
    serveo:
      server: serveo.net
      port: 22
      remote_port: 0          # 0 = let serveo pick
      ssh_opts:
        - "-o StrictHostKeyChecking=no"
        - "-o ServerAliveInterval=30"
        - "-o ExitOnForwardFailure=yes"
```

### 2. localhost.run (`localhost.run`)

localhost.run is also SSH-based, but it returns an HTTPS URL on port 443
instead of a raw TCP port:

```bash
ssh -R 80:localhost:3389 nokey@localhost.run
# Output: "Connect your tunneled URLs:
#          https://abc123def.ltr.run"
```

**Strengths:**
- Same SSH transport as serveo — no extra binary.
- HTTPS endpoint works through corporate proxies that block raw TCP.
- Very stable (single operator but well-funded).
- Free, no account.

**Weaknesses:**
- HTTPS endpoint means RDP traffic has to be tunneled through HTTP — you
  need a small bridge on the client side (e.g. `socat` or `cloudflared
  access tcp`).
- Higher latency than serveo (HTTP framing overhead).

**Output parsing:** The toolkit greps for `https://<hash>.ltr.run`.

**Config:**

```yaml
tunnel:
  providers:
    localhost.run:
      server: nokey@localhost.run
      port: 22
      ssh_opts:
        - "-o StrictHostKeyChecking=no"
```

**Client bridge:** To connect from `xfreerdp`:

```bash
# On the client side:
socat TCP-LISTEN:13389,fork TCP:abc123def.ltr.run:443
# Then:
xfreerdp /v:localhost:13389 /u:runner /p:...
```

### 3. cloudflare (`trycloudflare.com`)

Cloudflare's `cloudflared` binary supports "quick tunnels" — no account,
no config, no DNS setup:

```bash
cloudflared tunnel --url tcp://localhost:3389
# Output: "Your quick Tunnel has been created!
#          Visit it at: https://abc-def-ghi.trycloudflare.com"
```

**Strengths:**
- Cloudflare's global anycast network — best throughput for non-USA
  clients.
- QUIC transport option (lower latency than TCP).
- Very stable (Cloudflare operates it).
- Free, no account.

**Weaknesses:**
- Requires the `cloudflared` binary (~50 MB download).
- ARM64 binary not in standard repos (manual install on Termux).
- The `<hash>.trycloudflare.com` URL is HTTP/HTTPS — for raw TCP RDP,
  you need `cloudflared access tcp` on the client side too.

**Output parsing:** The toolkit greps for `https://<hash>.trycloudflare.com`.

**Config:**

```yaml
tunnel:
  providers:
    cloudflare:
      bin: cloudflared
      protocol: quic          # quic | http2
      edge_ip: ""             # Optional: pin to a specific edge IP
```

**Install cloudflared:**

| Platform | Command                                                            |
| :------- | :----------------------------------------------------------------- |
| Kali/Deb | `sudo apt install -y cloudflared` (see [KALI.md](KALI.md))         |
| Windows  | `winget install Cloudflare.cloudflared`                            |
| macOS    | `brew install cloudflared`                                         |
| Termux   | Manual binary download (see [ANDROID.md](ANDROID.md))              |

**Client bridge (for RDP-over-HTTPS):**

```bash
cloudflared access tcp --hostname abc-def-ghi.trycloudflare.com --url localhost:13389
xfreerdp /v:localhost:13389 /u:runner /p:...
```

### 4. localtunnel (`loca.lt`)

localtunnel is an npm package that exposes a local port via an HTTP tunnel:

```bash
lt --port 3389
# Output: "your url is: https://angry-elephant.loca.lt"
```

**Strengths:**
- HTTP-based — survives cellular NAT handovers (great for Termux).
- Optional subdomain reservation (`--subdomain my-rdp`).
- Very stable.
- Free, no account.

**Weaknesses:**
- Requires Node.js + `npm install -g localtunnel`.
- HTTP-based — needs a client-side bridge for RDP.
- Slowest of the four (~1 MB/s bandwidth cap).

**Output parsing:** The toolkit greps for `https://<sub>.loca.lt`.

**Config:**

```yaml
tunnel:
  providers:
    localtunnel:
      bin: lt
      subdomain: ""           # Optional: request a specific subdomain
```

**Install localtunnel:**

```bash
# Requires Node.js (https://nodejs.org/)
npm install -g localtunnel
```

**Client bridge (for RDP-over-HTTP):**

```bash
socat TCP-LISTEN:13389,fork TCP:angry-elephant.loca.lt:443
xfreerdp /v:localhost:13389 /u:runner /p:...
```

## When to Use Which

### Default priority (recommended for most users)

```yaml
tunnel:
  priority: [serveo, localhost.run, cloudflare, localtunnel]
```

This is the toolkit's default. Serveo wins on latency + simplicity,
localhost.run is the fallback when serveo is down, cloudflare is the
fallback when SSH-based tunnels are blocked, localtunnel is the last
resort.

### For Android / Termux

```yaml
tunnel:
  priority: [localtunnel, cloudflare, serveo, localhost.run]
```

localtunnel's HTTP transport survives cellular NAT handovers (when your
phone switches from Wi-Fi to 4G, the tunnel stays up). Cloudflare is a
strong second if you've installed the ARM64 binary.

### For non-USA clients

```yaml
tunnel:
  priority: [cloudflare, serveo, localhost.run, localtunnel]
```

Cloudflare's anycast network routes you to the nearest edge, which is
usually faster than serveo's single-region relays if you're outside
North America.

### For corporate networks (HTTPS-only proxies)

```yaml
tunnel:
  priority: [localhost.run, cloudflare, localtunnel, serveo]
```

serveo's raw TCP doesn't work through HTTPS-only proxies. Lead with
localhost.run (HTTPS endpoint) or cloudflare (QUIC over UDP, but
`cloudflared access tcp` works over HTTPS).

### For persistent URLs (testing)

localtunnel supports subdomain reservation:

```yaml
tunnel:
  providers:
    localtunnel:
      bin: lt
      subdomain: "my-rdp-test"
  priority: [localtunnel]
```

This gives you `https://my-rdp-test.loca.lt` every time — useful for
automated testing where you need a stable URL.

## Inspecting Tunnel State

```bash
# List all configured providers and their state:
$ rdp-toolkit tunnel list
  - serveo         | (not started)
  - localhost.run  | (not started)
  - cloudflare     | (not started)
  - localtunnel    | (not started)
[OK]   4 tunnel(s).

# Status of any active tunnels:
$ rdp-toolkit tunnel status
  [OK]   serveo         | serveo.net:43210
  [--]   localhost.run  | n/a
  [--]   cloudflare     | n/a
  [--]   localtunnel    | n/a

# Test a single provider (starts it, captures info, stops it):
$ rdp-toolkit tunnel test serveo
[INFO] Testing tunnel provider(s): serveo
[OK]   Tunnel test result: {'provider': 'serveo', 'ok': True, 'url': 'serveo.net:54321'}

# Test all four:
$ rdp-toolkit tunnel test all
```

## Troubleshooting

### All four providers fail

1. Check your internet: `curl -sI https://api.github.com` (should return 200).
2. Check that `ssh` works at all: `ssh -V`.
3. Try each provider manually:
   ```bash
   ssh -R 3389:localhost:3389 -N serveo.net      # should hang with "Forwarding..."
   ssh -R 80:localhost:3389 nokey@localhost.run  # should print an HTTPS URL
   cloudflared tunnel --url tcp://localhost:3389 # should print a trycloudflare.com URL
   lt --port 3389                                # should print a loca.lt URL
   ```
4. If only `cloudflared` works, your network is blocking port 22 outbound.
   Set `tunnel.priority: [cloudflare]` in your config.

### Serveo returns "no remote port allocated"

Serveo is overloaded. Wait a few minutes and retry, or temporarily bump
`localhost.run` to the top of the priority list.

### Cloudflare tunnel URL works in a browser but `xfreerdp` can't connect

`trycloudflare.com` URLs are HTTPS, not raw TCP. You need the
`cloudflared access tcp` bridge on the client side — see "Client bridge"
under the cloudflare section above.

### `localtunnel` returns a 502 error page when connecting

The `loca.lt` endpoint requires a `bypass` query parameter on the first
request to acknowledge the warning page. For RDP traffic this is moot
(you're not loading the warning page in a browser), but if you're seeing
502s, your tunnel may have expired — `lt` tunnels die after ~1 hour of
inactivity. Restart with `rdp-toolkit start`.

## Adding a Custom Provider

See [ARCHITECTURE.md → "Adding a new tunnel provider"](ARCHITECTURE.md#adding-a-new-tunnel-provider)
for the implementation checklist. In short: subclass `TunnelBase`,
implement `start` / `stop`, register in `_PROVIDER_MAP`, add to the
priority list.

## See Also

- [ARCHITECTURE.md](ARCHITECTURE.md) — Tunnel failover logic + data flow.
- [KALI.md](KALI.md) — Cloudflared install on Kali.
- [ANDROID.md](ANDROID.md) — Localtunnel as the default on Termux.
- [WINDOWS.md](WINDOWS.md) — Cloudflared bridge from Windows.
