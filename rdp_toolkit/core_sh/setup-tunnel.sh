#!/usr/bin/env bash
# setup-tunnel.sh — establish a public TCP tunnel to local RDP (3389)
# using serveo / localhost.run / cloudflare.  NO NGROK.
#
# Reads TUNNEL_PROVIDERS (comma-separated, default:
# 'serveo,localhost.run,cloudflare') and tries each in order.
# First provider that exposes a routable hostname:port wins.
#
# Output files (in $RDP_ARTIFACT_DIR):
#   tunnel-info.txt   — human-readable summary
#   tunnel-type.txt   — 'serveo' | 'localhost.run' | 'cloudflare'
#   tunnel-host.txt   — hostname
#   tunnel-port.txt   — remote port
#   connect-info.txt  — TWO lines (BRIDGE_CMD\nCONNECT_CMD)

set -euo pipefail
# shellcheck source=utils.sh
. "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

LOCAL_PORT="${RDP_LOCAL_PORT:-3389}"
CONNECT_TIMEOUT_SEC="${TUNNEL_CONNECT_TIMEOUT:-25}"

if [[ -z "${TUNNEL_PROVIDERS:-}" ]]; then
    TUNNEL_PROVIDERS='serveo,localhost.run,cloudflare'
fi

# Split into array (bash 3.x compatible).
IFS=',' read -ra PROVIDERS <<< "$TUNNEL_PROVIDERS"

DIR="$(ensure_artifact_dir)"

write_info "Tunnel providers (priority): ${PROVIDERS[*]// /  ->  }"

# ---------------------------------------------------------------------------
# save_tunnel_info TYPE HOST PORT BRIDGE_CMD CONNECT_CMD [EXTRA]
# ---------------------------------------------------------------------------
save_tunnel_info() {
    local type="$1" host="$2" port="$3"
    local bridge="$4" connect="$5"
    local extra="${6:-}"

    {
        echo "Tunnel type: $type"
        echo "Host:        $host"
        echo "Port:        $port"
        echo "Local port:  $LOCAL_PORT"
        echo "Started at:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Public IP:   $(get_public_ip)"
        [[ -n "$extra" ]] && echo "$extra"
    } > "${DIR}/tunnel-info.txt"

    printf '%s' "$type"    > "${DIR}/tunnel-type.txt"
    printf '%s' "$host"    > "${DIR}/tunnel-host.txt"
    printf '%s' "$port"    > "${DIR}/tunnel-port.txt"
    # Two separate lines joined by LF (Python splitlines() handles both).
    printf '%s\n%s' "$bridge" "$connect" > "${DIR}/connect-info.txt"

    write_ok "Saved tunnel artifacts to ${DIR}"
    write_info "BRIDGE_CMD:   $bridge"
    write_info "CONNECT_CMD:  $connect"
}

# ---------------------------------------------------------------------------
# Provider: serveo
# ---------------------------------------------------------------------------
try_serveo() {
    if ! command -v ssh >/dev/null 2>&1; then
        write_warn 'ssh client not found — skipping serveo.'
        return 1
    fi
    write_block 'Trying provider: serveo'
    local log="${DIR}/serveo.log"
    : > "$log"

    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ServerAliveInterval=60 \
        -o ExitOnForwardFailure=yes \
        -R "3389:localhost:${LOCAL_PORT}" -N serveo.net >"$log" 2>&1 &
    local pid=$!
    echo "$pid" > "${DIR}/serveo.pid"

    local deadline=$(( $(date +%s) + CONNECT_TIMEOUT_SEC ))
    local found=''
    while (( $(date +%s) < deadline )); do
        sleep 1
        if ! kill -0 "$pid" 2>/dev/null; then
            write_warn 'serveo ssh process exited early.'
            break
        fi
        if [[ -s "$log" ]]; then
            # Serveo prints: "Forwarding TCP traffic from serveo.net:PORT"
            # Or: a line like "Hi! You've got port forwarding to 3389..."
            if grep -Eq 'serveo\.net:[0-9]+' "$log"; then
                found="$(grep -Eo 'serveo\.net:[0-9]+' "$log" | head -n1 | cut -d: -f2)"
                break
            fi
            if grep -Eqi 'Forwarding.*from.*serveo\.net.*:[0-9]+' "$log"; then
                found="$(grep -Eo 'serveo\.net:[0-9]+' "$log" | head -n1 | cut -d: -f2)"
                break
            fi
        fi
    done

    if [[ -z "$found" ]]; then
        write_warn 'serveo did not expose a remote port in time.'
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        return 1
    fi

    local host='serveo.net'
    local port="$found"
    write_ok "serveo remote: ${host}:${port}"

    local bridge="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -R 3389:localhost:3389 -N serveo.net"
    local connect="xfreerdp /v:${host}:${port} /u:${RDP_USERNAME:-runner} /cert:ignore /dynamic-resolution"
    save_tunnel_info 'serveo' "$host" "$port" "$bridge" "$connect" "ssh pid: $pid"
    return 0
}

# ---------------------------------------------------------------------------
# Provider: localhost.run
# ---------------------------------------------------------------------------
try_localhost_run() {
    if ! command -v ssh >/dev/null 2>&1; then
        write_warn 'ssh client not found — skipping localhost.run.'
        return 1
    fi
    write_block 'Trying provider: localhost.run'
    local log="${DIR}/localhostrun.log"
    : > "$log"

    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ServerAliveInterval=60 \
        -o ExitOnForwardFailure=yes \
        -R "3389:localhost:${LOCAL_PORT}" nokey@localhost.run >"$log" 2>&1 &
    local pid=$!
    echo "$pid" > "${DIR}/localhostrun.pid"

    local deadline=$(( $(date +%s) + CONNECT_TIMEOUT_SEC ))
    local found=''
    while (( $(date +%s) < deadline )); do
        sleep 1
        if ! kill -0 "$pid" 2>/dev/null; then
            write_warn 'localhost.run ssh process exited early.'
            break
        fi
        if [[ -s "$log" ]]; then
            # localhost.run prints: "Connect to tcp://<sub>.lhr.life:443"
            # Or: "Tunnel created on host: <sub>.lhr.life"
            if grep -Eqo '[a-z0-9-]+\.lhr\.life' "$log"; then
                found="$(grep -Eo '[a-z0-9-]+\.lhr\.life' "$log" | head -n1)"
                break
            fi
            if grep -Eqo '[a-z0-9-]+\.localhost\.run' "$log"; then
                found="$(grep -Eo '[a-z0-9-]+\.localhost\.run' "$log" | head -n1)"
                break
            fi
        fi
    done

    if [[ -z "$found" ]]; then
        write_warn 'localhost.run did not expose a host in time.'
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        return 1
    fi

    # localhost.run TCP forwards land on port 443.
    local port=443
    write_ok "localhost.run remote: ${found}:${port}"

    local bridge="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -R 3389:localhost:3389 nokey@localhost.run"
    local connect="xfreerdp /v:${found}:${port} /u:${RDP_USERNAME:-runner} /cert:ignore /dynamic-resolution"
    save_tunnel_info 'localhost.run' "$found" "$port" "$bridge" "$connect" "ssh pid: $pid"
    return 0
}

# ---------------------------------------------------------------------------
# Provider: cloudflare (cloudflared binary)
# ---------------------------------------------------------------------------
try_cloudflare() {
    write_block 'Trying provider: cloudflare'
    local cf_cmd=''
    if command -v cloudflared >/dev/null 2>&1; then
        cf_cmd="$(command -v cloudflared)"
    else
        local exe="${DIR}/cloudflared"
        local arch
        arch="$(uname -m)"
        case "$arch" in
            x86_64)  arch='amd64' ;;
            aarch64) arch='arm64' ;;
            armv7l)  arch='arm' ;;
            *)       arch='amd64' ;;
        esac
        local os_name
        os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
        # Normalise: macOS reports 'darwin', Linux reports 'linux'.
        case "$os_name" in
            darwin) os_name='darwin' ;;
            *)      os_name='linux' ;;
        esac

        local url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-${os_name}-${arch}"
        write_info "Downloading cloudflared from $url"
        if command -v curl >/dev/null 2>&1; then
            if ! curl -fsSL --max-time 60 -o "$exe" "$url"; then
                write_warn 'cloudflared download failed.'
                return 1
            fi
        elif command -v wget >/dev/null 2>&1; then
            if ! wget -qO "$exe" --timeout=60 "$url"; then
                write_warn 'cloudflared download failed.'
                return 1
            fi
        else
            write_warn 'Neither curl nor wget available — cannot download cloudflared.'
            return 1
        fi
        chmod +x "$exe" 2>/dev/null || true
        cf_cmd="$exe"
    fi

    local log="${DIR}/cloudflared.log"
    : > "$log"

    "$cf_cmd" tunnel --url "tcp://localhost:${LOCAL_PORT}" >"$log" 2>&1 &
    local pid=$!
    echo "$pid" > "${DIR}/cloudflared.pid"

    local deadline=$(( $(date +%s) + CONNECT_TIMEOUT_SEC + 15 ))
    local found=''
    while (( $(date +%s) < deadline )); do
        sleep 1
        if ! kill -0 "$pid" 2>/dev/null; then
            write_warn 'cloudflared exited early.'
            break
        fi
        if [[ -s "$log" ]]; then
            # trycloudflare hostname shows up as: "https://<sub>.trycloudflare.com"
            if grep -Eqo '[a-z0-9-]+\.trycloudflare\.com' "$log"; then
                found="$(grep -Eo '[a-z0-9-]+\.trycloudflare\.com' "$log" | head -n1)"
                break
            fi
        fi
    done

    if [[ -z "$found" ]]; then
        write_warn 'cloudflared did not expose a trycloudflare host in time.'
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        return 1
    fi

    local port=443
    write_ok "cloudflare remote: ${found}:${port}"

    local bridge="${cf_cmd} tunnel --url tcp://localhost:3389"
    local connect="xfreerdp /v:${found}:${port} /u:${RDP_USERNAME:-runner} /cert:ignore /dynamic-resolution"
    save_tunnel_info 'cloudflare' "$found" "$port" "$bridge" "$connect" "cloudflared pid: $pid"
    return 0
}

# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
main() {
    local success=0
    for p in "${PROVIDERS[@]}"; do
        p="$(printf '%s' "$p" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
        case "$p" in
            serveo)         if try_serveo; then success=1; break; fi ;;
            localhost.run)  if try_localhost_run; then success=1; break; fi ;;
            cloudflare)     if try_cloudflare; then success=1; break; fi ;;
            *)              write_warn "Unknown provider: '$p' — skipping." ;;
        esac
    done

    if (( success == 0 )); then
        write_err 'All tunnel providers failed.'
        printf 'failed' > "${DIR}/tunnel-type.txt"
        echo 'All tunnel providers failed.' > "${DIR}/tunnel-info.txt"
        send_notify 'All RDP tunnel providers failed — manual intervention required.' 'Tunnel failure' || true
        exit 1
    fi

    write_block 'setup-tunnel.sh complete'
}

main "$@"
