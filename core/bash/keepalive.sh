#!/usr/bin/env bash
# core/bash/keepalive.sh - Hold the RDP session open with heartbeat logging
set -euo pipefail
source "$(dirname "$0")/utils.sh"

HOURS="${SESSION_HOURS:-6}"
HEARTBEAT_SEC="${HEARTBEAT_SEC:-300}"

END=$(( $(date +%s) + HOURS * 3600 ))
log_block "KEEP ALIVE - ${HOURS}hr session, heartbeat every ${HEARTBEAT_SEC}s"
log_info "Session will end at $(date -u -d "@$END" 2>/dev/null || date -u -r "$END")"

iter=0
while [ "$(date +%s)" -lt "$END" ]; do
    iter=$((iter + 1))
    rem=$(( END - $(date +%s) ))
    h=$(( rem / 3600 ))
    m=$(( (rem % 3600) / 60 ))
    s=$(( rem % 60 ))

    if test_port localhost 3389; then
        rdp_status="OK"
    else
        rdp_status="DOWN"
    fi
    tunnel="${TUNNEL_URL:-n/a}"

    echo "[Heartbeat #$iter] Remaining: ${h}h ${m}m ${s}s | RDP: $rdp_status | Tunnel: $tunnel"

    if [ $((iter % 6)) -eq 0 ]; then
        send_notify "RDP Heartbeat #$iter" "Remaining: ${h}h ${m}m
RDP port: $rdp_status
Tunnel: $tunnel"
    fi

    sleep "$HEARTBEAT_SEC"
done

log_warn 'Session time expired.'
