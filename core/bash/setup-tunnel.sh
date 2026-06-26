#!/usr/bin/env bash
# core/bash/setup-tunnel.sh - Multi-provider tunnel manager (v9.0)
# v9.0: NO NGROK. Uses Serveo (SSH, primary) -> localhost.run (SSH) -> Cloudflare (fallback)
set -euo pipefail
source "$(dirname "$0")/utils.sh"

PROVIDERS="${TUNNEL_PROVIDERS:-serveo,localhost.run,cloudflare}"
TUNNEL_URL=""
TUNNEL_TYPE=""
TUNNEL_HOST=""
TUNNEL_PORT=""

try_serveo() {
    log_info "Trying Serveo (SSH-based, no signup, no token)..."
    if ! command -v ssh &>/dev/null; then
        log_warn "ssh not found"
        return 1
    fi

    nohup ssh -o StrictHostKeyChecking=no \
              -o UserKnownHostsFile=/dev/null \
              -o ServerAliveInterval=30 \
              -o ServerAliveCountMax=3 \
              -o ExitOnForwardFailure=yes \
              -R 3389:localhost:3389 \
              -N serveo.net > serveo-out.log 2> serveo-err.log &
    local pid=$!
    log_info "ssh pid=$pid, waiting for forwarding URL..."

    for i in $(seq 1 25); do
        sleep 2
        # Look for serveo.net:PORT in either log
        local match
        match=$(grep -oE 'serveo\.net:[0-9]+' serveo-err.log serveo-out.log 2>/dev/null | head -1)
        if [ -n "$match" ]; then
            TUNNEL_HOST="serveo.net"
            TUNNEL_PORT="${match##*:}"
            TUNNEL_URL="tcp://${TUNNEL_HOST}:${TUNNEL_PORT}"
            TUNNEL_TYPE="serveo"
            log_ok "Serveo UP: $TUNNEL_URL"
            return 0
        fi
        echo "[TUNNEL] Waiting for serveo... attempt $i/25"
    done

    log_warn "Serveo did not provide a forwarding URL in 50s"
    [ -f serveo-err.log ] && head -c 500 serveo-err.log
    kill "$pid" 2>/dev/null || true
    return 1
}

try_localhost_run() {
    log_info "Trying localhost.run (SSH-based, no signup, no token)..."
    if ! command -v ssh &>/dev/null; then
        log_warn "ssh not found"
        return 1
    fi

    nohup ssh -o StrictHostKeyChecking=no \
              -o UserKnownHostsFile=/dev/null \
              -o ServerAliveInterval=30 \
              -o ServerAliveCountMax=3 \
              -o ExitOnForwardFailure=yes \
              -R 3389:localhost:3389 \
              -N nokey@localhost.run > lr-out.log 2> lr-err.log &
    local pid=$!
    log_info "ssh pid=$pid, waiting for forwarding URL..."

    for i in $(seq 1 25); do
        sleep 2
        # localhost.run prints: "your tunnel is ready at: localhost.run:PORT" or "TCP forwarding from host:PORT"
        local match
        match=$(grep -oE '(localhost\.run|[\w-]+\.localhost\.run):[0-9]+' lr-err.log lr-out.log 2>/dev/null | head -1)
        if [ -n "$match" ]; then
            TUNNEL_HOST="${match%:*}"
            TUNNEL_PORT="${match##*:}"
            TUNNEL_URL="tcp://${TUNNEL_HOST}:${TUNNEL_PORT}"
            TUNNEL_TYPE="localhost.run"
            log_ok "localhost.run UP: $TUNNEL_URL"
            return 0
        fi
        echo "[TUNNEL] Waiting for localhost.run... attempt $i/25"
    done

    log_warn "localhost.run did not provide a forwarding URL in 50s"
    [ -f lr-err.log ] && head -c 500 lr-err.log
    kill "$pid" 2>/dev/null || true
    return 1
}

try_cloudflare() {
    log_info "Trying Cloudflare Quick Tunnel..."
    local arch="amd64"
    [ "$(uname -m)" = "aarch64" ] && arch="arm64"

    curl -sL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}" -o cloudflared
    chmod +x cloudflared
    log_info "cloudflared downloaded"

    nohup ./cloudflared tunnel --no-autoupdate --url tcp://localhost:3389 > cf-out.log 2> cf-err.log &
    local pid=$!

    for i in $(seq 1 30); do
        sleep 2
        local match
        match=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' cf-err.log cf-out.log 2>/dev/null | head -1)
        if [ -n "$match" ]; then
            TUNNEL_URL="$match"
            TUNNEL_HOST="${match#https://}"
            TUNNEL_PORT="443"
            TUNNEL_TYPE="cloudflare"
            log_ok "Cloudflare UP: $TUNNEL_URL"
            return 0
        fi
        echo "[TUNNEL] Waiting for cloudflared... attempt $i/30"
    done

    log_warn "Cloudflare did not come up in 60s"
    [ -f cf-err.log ] && head -c 500 cf-err.log
    kill "$pid" 2>/dev/null || true
    rm -f cloudflared
    return 1
}

log_block "SETUP TUNNEL v9.0 - providers: $PROVIDERS"

IFS=',' read -ra PROVIDER_ARRAY <<< "$PROVIDERS"
for provider in "${PROVIDER_ARRAY[@]}"; do
    provider="$(echo "$provider" | tr -d ' ' | tr '[:upper:]' '[:lower:]')"
    if [ -z "$TUNNEL_URL" ]; then
        case "$provider" in
            serveo)        try_serveo && break ;;
            localhost.run) try_localhost_run && break ;;
            cloudflare)    try_cloudflare && break ;;
        esac
    fi
done

if [ -z "$TUNNEL_URL" ]; then
    ip="$(get_public_ip)"
    TUNNEL_URL="$ip"
    TUNNEL_HOST="$ip"
    TUNNEL_PORT="3389"
    TUNNEL_TYPE="direct-ip-wont-work"
    log_warn "ALL TUNNELS FAILED. Direct IP $ip will NOT work for RDP."
fi

log_info "FINAL: type=$TUNNEL_TYPE host=$TUNNEL_HOST port=$TUNNEL_PORT url=$TUNNEL_URL"

# Read password
PWD_VAL="$(cat rdp-password.txt 2>/dev/null || echo "${RDP_PASS:-}")"

BRIDGE_CMD=""
CONNECT_CMD=""
if [ "$TUNNEL_TYPE" = "serveo" ] || [ "$TUNNEL_TYPE" = "localhost.run" ]; then
    CONNECT_CMD="xfreerdp /v:${TUNNEL_HOST}:${TUNNEL_PORT} /u:runner /p:'${PWD_VAL}' /cert:ignore +clipboard +auto-reconnect /size:1280x720"
elif [ "$TUNNEL_TYPE" = "cloudflare" ]; then
    BRIDGE_CMD="cloudflared access tcp --hostname ${TUNNEL_HOST} --url localhost:33890"
    CONNECT_CMD="xfreerdp /v:localhost:33890 /u:runner /p:'${PWD_VAL}' /cert:ignore +clipboard +auto-reconnect /size:1280x720"
else
    CONNECT_CMD="xfreerdp /v:${TUNNEL_HOST}:${TUNNEL_PORT} /u:runner /p:'${PWD_VAL}' /cert:ignore +clipboard +auto-reconnect /size:1280x720"
fi

# Save artifacts (printf to avoid trailing newline; BRIDGE_CMD and CONNECT_CMD on SEPARATE lines)
printf '%s' "$TUNNEL_URL"  > tunnel-info.txt
printf '%s' "$TUNNEL_TYPE" > tunnel-type.txt
printf '%s' "$TUNNEL_HOST" > tunnel-host.txt
printf '%s' "$TUNNEL_PORT" > tunnel-port.txt
printf 'BRIDGE_CMD=%s\r\nCONNECT_CMD=%s' "$BRIDGE_CMD" "$CONNECT_CMD" > connect-info.txt

# Expose to GITHUB_ENV
if [ -n "${GITHUB_ENV:-}" ]; then
    echo "TUNNEL_URL=$TUNNEL_URL"   >> "$GITHUB_ENV"
    echo "TUNNEL_TYPE=$TUNNEL_TYPE" >> "$GITHUB_ENV"
    echo "TUNNEL_HOST=$TUNNEL_HOST" >> "$GITHUB_ENV"
    echo "TUNNEL_PORT=$TUNNEL_PORT" >> "$GITHUB_ENV"
fi

send_notify "RDP Tunnel UP" "Type: $TUNNEL_TYPE
Host: $TUNNEL_HOST
Port: $TUNNEL_PORT
URL: $TUNNEL_URL"

log_block "TUNNEL READY - $TUNNEL_TYPE"
echo "|  Host:     $TUNNEL_HOST"
echo "|  Port:     $TUNNEL_PORT"
echo "|  URL:      $TUNNEL_URL"
[ -n "$BRIDGE_CMD" ] && echo "|  Bridge:   $BRIDGE_CMD"
echo "|  Connect:  $CONNECT_CMD"
echo "+============================================================+"
