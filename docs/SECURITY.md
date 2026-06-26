# Security Policy

> The RDP Mega Toolkit handles GitHub personal access tokens, RDP
> credentials, and SSH tunnels. This document explains the security model,
> how credentials are handled, what mitigations are in place, and how to
> report a vulnerability.

## Supported Versions

| Version | Supported          |
| :------ | :----------------- |
| 9.0.x   | :white_check_mark: |
| 5.0.x   | :x: (EOL — upgrade)|
| 4.x     | :x: (EOL — upgrade)|

Only the latest 9.0.x release receives security updates.

## Threat Model

The toolkit operates in three trust zones:

```
┌──────────────────────────────────────────────────────────────────────┐
│  ZONE 1: User's machine (high trust)                                 │
│  - ~/.config/rdp-toolkit/config.yaml (may contain notify tokens)     │
│  - GH_PAT environment variable                                       │
│  - xfreerdp process (has plaintext RDP password in argv)             │
└────────────────────────────┬─────────────────────────────────────────┘
                             │ SSH (tunnel) + HTTPS (GitHub API)
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│  ZONE 2: GitHub Actions runner (medium trust — shared infra)         │
│  - Workflow runs here with the toolkit's shell scripts               │
│  - rdp-credentials artifact (host/port/user/password) lives here     │
│  - Artifacts are deleted after 90 days by default                    │
└────────────────────────────┬─────────────────────────────────────────┘
                             │ Public tunnel (serveo / cloudflare / ...)
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│  ZONE 3: Public internet (zero trust)                                │
│  - Tunnel endpoint is publicly reachable                             │
│  - Anyone who knows host+port can attempt RDP login                  │
│  - Mitigation: 16-char random password rotated per session           │
└──────────────────────────────────────────────────────────────────────┘
```

### Primary threats

1. **PAT exfiltration** — An attacker who obtains `GH_PAT` can dispatch
   arbitrary workflows, cancel runs, and read artifacts (including RDP
   credentials) for the target repo.
2. **Tunnel eavesdropping** — An attacker who can sniff traffic to the
   public tunnel endpoint could capture RDP credentials if NLA is disabled.
3. **Artifact leak** — The `rdp-credentials` artifact contains plaintext
   host/port/user/password. Anyone with read access to the repo can
   download it.
4. **Local credential theft** — An attacker with read access to
   `~/.config/rdp-toolkit/config.yaml` could lift notify bot tokens.

## Credentials Handling

### GitHub PAT (`GH_PAT`)

- **Never written to disk** by the toolkit. Read from the environment
  variable at runtime.
- **Never logged.** The `runner._headers()` function does not log the
  token; the `User-Agent` is `rdp-mega-toolkit-v9/runner`, not the token.
- **Never passed via command-line arguments** to subprocesses — always
  via environment variables.
- **Stored in your shell's rc file** at the user's discretion (`echo
  'export GH_PAT=...' >> ~/.bashrc`). The toolkit doesn't do this for you.

### RDP password

- **Generated fresh per session** by `runner.start_session()` (16 random
  alphanumeric characters, excluding visually-similar pairs like `0/O` and
  `1/l`).
- **Rotatable on demand** via `rdp-toolkit rotate` (triggers the
  `credential-rotate.yml` workflow).
- **Stored in the `rdp-credentials` artifact** as plaintext. This is a
  deliberate trade-off — the alternative (encrypted artifact) would
  require the user to manage a keypair.
- **Printed to stdout** by `rdp-toolkit start` and `rdp-toolkit connect`
  for convenience. If you don't want this, redirect stdout:
  `rdp-toolkit start > /tmp/session.log`.

### Tunnel provider tokens

- **None required** for the four supported providers (serveo,
  localhost.run, cloudflare quick-tunnels, localtunnel). All four work
  without an account.
- If you configure a paid cloudflare account (for stable named tunnels),
  the `cloudflared` daemon reads its own credentials from
  `~/.cloudflared/cert.json` — the toolkit doesn't touch this file.

### Notification tokens (Telegram bot token, Discord webhook, etc.)

- **Stored in `~/.config/rdp-toolkit/config.yaml`** (mode `0600`).
- **Logged in redacted form** by `notify.base._safe_config()` — the
  webhook URL / bot token is replaced with `<redacted>` in any log output.
- **Sent only to the configured provider's API** (e.g.
  `https://api.telegram.org`). Never sent to any other host.

### Config file permissions

`config.generate_config()` writes `~/.config/rdp-toolkit/config.yaml`
with mode `0600` (owner read/write only). On Windows, the equivalent
ACL is "user-only" via Python's default file creation behaviour.

If you accidentally `chmod 644` it, the toolkit will warn on next
`doctor` run:

```
[WARN] config.yaml is world-readable (mode 0644) — recommend 0600.
```

## Mitigations

### Per-session random passwords

Every `start_session` call generates a fresh 16-character password using
`secrets.choice()` (cryptographically strong). The password is:

- Used inside the runner to set the local user's password via `chpasswd`.
- Uploaded as part of the `rdp-credentials` artifact.
- Discarded at session end (the runner VM is destroyed by GitHub Actions
  automatically).

### Tunnel failover reduces exposure

If serveo is down, the toolkit doesn't fall back to a less-secure
provider automatically — it falls back to the next provider in the
priority list, which is also a public, no-auth provider. There's no
"fallback to plaintext HTTP" mode.

### No remote code execution paths

The toolkit never:

- Downloads and executes scripts from the internet (other than the
  GitHub Actions workflow YAML, which is reviewed at PR time).
- Writes to `$PATH` locations outside the user's control (`~/.local/bin`,
  `$PREFIX/bin` for Termux, `%LOCALAPPDATA%\Programs\` for Windows).
- Modifies system files (`/etc/...`, registry, etc.) without explicit
  `sudo` / admin consent.

### `xfreerdp` flag safety

The default profiles include `/cert:ignore`, which disables certificate
verification for the RDP TLS handshake. This is necessary because the
tunnel endpoints don't have valid certificates for `localhost`. The
trade-off:

- **Without `/cert:ignore`:** RDP connection fails for any tunnel that
  doesn't terminate TLS with a valid cert (all four supported providers
  fall into this category).
- **With `/cert:ignore`:** MITM is possible if an attacker controls the
  tunnel endpoint. Mitigated by NLA (Network Level Authentication), which
  the runner enables by default — without the password, the attacker
  can't establish an RDP session even if they MITM the tunnel.

### GitHub Actions artifact retention

The `rdp-credentials` artifact contains plaintext credentials. GitHub's
default retention is 90 days. To reduce exposure:

1. Set `retention-days: 1` in the workflow's `upload-artifact` step.
2. Or use `rdp-toolkit kill <run_id>` immediately after connecting —
   this cancels the run, which (combined with `retention-days: 1`)
   causes GitHub to delete the artifact within 24 hours.

### PAT scope minimization

The toolkit needs `repo` and `workflow` scopes. **Do not** grant
additional scopes (e.g. `delete_repo`, `admin:org`) — the toolkit doesn't
use them and they increase blast radius if the PAT leaks.

For maximum safety, use a fine-grained PAT scoped to a single repository
(the toolkit repo) with only `Actions: write` and `Contents: read`
permissions. Fine-grained PATs are available at
<https://github.com/settings/personal-access-tokens>.

## What the Toolkit Does NOT Do

- **Does not persist the RDP password to disk.** Generated per session,
  lives in env vars + the artifact, gone when the session ends.
- **Does not log the PAT.** Ever. The `runner._headers()` function
  returns the headers dict but the toolkit never calls `print()` on it.
- **Does not phone home.** No telemetry, no analytics, no usage tracking.
  The only outbound requests are to `api.github.com` and the tunnel
  provider endpoints.
- **Does not auto-update.** Updates are explicit (`pip install --upgrade
  rdp-toolkit` or re-run the installer).
- **Does not bundle third-party trackers.** No Google Analytics, no
  Sentry, no Bugsnag.

## Reporting a Vulnerability

If you believe you've found a security vulnerability in the toolkit:

1. **Do not open a public GitHub issue.**
2. Email the maintainer at `usekarne@users.noreply.github.com` with:
   - A description of the vulnerability.
   - Steps to reproduce (or a PoC).
   - Affected versions.
   - Suggested fix (optional but appreciated).
3. You'll receive an acknowledgement within 48 hours.
4. We'll work with you to validate and patch the issue.
5. Once a fix is released, we'll publish a GitHub Security Advisory and
   credit you (unless you'd prefer to remain anonymous).

### Scope

**In scope:**
- Anything in `rdp_toolkit/`, `installers/`, `docker/`,
  `.github/workflows/`.
- Credential handling, tunnel setup, artifact parsing.

**Out of scope:**
- Vulnerabilities in third-party dependencies (PyYAML, cloudflared, ssh,
  docker, freerdp) — report those upstream.
- GitHub Actions platform vulnerabilities — report to GitHub via
  <https://hackerone.com/github>.
- Vulnerabilities in the user's RDP client (`xfreerdp`, `mstsc.exe`).

### Bounty

There is no monetary bounty program. We will, however, credit reporters
in the GitHub Security Advisory and in `CHANGELOG.md`.

## Incident Response

If a vulnerability is confirmed:

1. **T+0:** Maintainer acknowledges the report privately.
2. **T+24h:** Maintainer validates the vulnerability and assesses
   severity (CVSS).
3. **T+72h:** Patch developed in a private branch. CVE requested (if
   severity warrants).
4. **T+7d:** Patched release cut. GitHub Security Advisory published.
   `CHANGELOG.md` updated with credit.
5. **T+30d:** Post-mortem published (if the vulnerability was
   significant).

### If your PAT has been compromised

1. **Immediately** revoke it at
   <https://github.com/settings/tokens>.
2. Audit your repo's Actions runs for any unauthorized dispatches:
   `rdp-toolkit status` (or check the Actions tab on GitHub).
3. Audit your repo's artifacts — if any unexpected `rdp-credentials`
   artifacts were downloaded, assume the RDP session was compromised.
4. Rotate the password on any active runs:
   `rdp-toolkit rotate <run_id>`.
5. Cancel all active runs: `rdp-toolkit stop`.
6. Generate a new PAT with minimal scope.
7. Update your environment: `export GH_PAT=<new>`.

## Hardening Recommendations

For high-security deployments:

1. **Use a dedicated GitHub account** for the toolkit's PAT. Don't use
   your personal account.
2. **Use a fine-grained PAT** scoped to a single repository.
3. **Set `retention-days: 1`** on the `rdp-credentials` artifact in your
   workflows.
4. **Rotate the PAT monthly** even if it hasn't been compromised.
5. **Restrict `~/.config/rdp-toolkit/`** to your user only (`chmod 700`).
6. **Disable notify channels** if you don't need them — each enabled
   channel is another outbound HTTP call with potentially-sensitive info.
7. **Use `mstsc.exe` with NLA** on Windows clients — NLA prevents
   pre-authentication attacks even if the tunnel is compromised.
8. **Run the local Docker VMs** instead of GitHub Actions runs when
   possible — they don't expose credentials via the GitHub API at all.

## See Also

- [CONTRIBUTING.md](CONTRIBUTING.md) — Read this before contributing
  anything that touches credentials or networking.
- [API.md](API.md) — GitHub Actions REST API reference (esp. the
  Authentication section).
- [TUNNELS.md](TUNNELS.md) — Per-provider security characteristics.
- [ARCHITECTURE.md](ARCHITECTURE.md) — Failure modes & mitigations table.
