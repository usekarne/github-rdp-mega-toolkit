#!/usr/bin/env bash
# keepalive.sh — keep the runner alive until SESSION_HOURS expires.
# Writes a heartbeat every 5 minutes to keepalive.log.

set -euo pipefail
# shellcheck source=utils.sh
. "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

HEARTBEAT_SEC="${HEARTBEAT_SEC:-300}"

if [[ -z "${SESSION_HOURS:-}" ]]; then
    write_err 'SESSION_HOURS env var is missing.'
    exit 1
fi
if ! [[ "$SESSION_HOURS" =~ ^[0-9]+$ ]]; then
    write_err "SESSION_HOURS must be an integer (got '$SESSION_HOURS')."
    exit 1
fi
if (( SESSION_HOURS <= 0 )); then
    write_err "SESSION_HOURS must be > 0 (got $SESSION_HOURS)."
    exit 1
fi

START_EPOCH="$(date +%s)"
END_EPOCH=$(( START_EPOCH + SESSION_HOURS * 3600 ))
END_HUMAN="$(date -u -d "@${END_EPOCH}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -r "$END_EPOCH" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "$END_EPOCH")"

write_block "Keepalive starting — will run until $END_HUMAN ($SESSION_HOURS h)"
write_info "Heartbeat interval: ${HEARTBEAT_SEC} s"

DIR="$(ensure_artifact_dir)"
LOG="${DIR}/keepalive.log"
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] keepalive start, hours=${SESSION_HOURS}" >> "$LOG"

cleanup() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] keepalive exit, heartbeats=${BEAT:-0}" >> "$LOG"
}
trap cleanup EXIT

BEAT=0
while true; do
    NOW="$(date +%s)"
    if (( NOW >= END_EPOCH )); then
        write_ok "Reached SESSION_HOURS deadline ($END_HUMAN). Exiting."
        break
    fi
    REMAIN_MIN=$(( (END_EPOCH - NOW) / 60 ))
    BEAT=$((BEAT+1))

    # Health snapshot.
    CPU=''
    if [[ -r /proc/loadavg ]]; then
        # 1-minute load average * 100 / num_cpus = rough CPU%.
        local_load="$(awk '{print $1}' /proc/loadavg)"
        num_cpus="$(nproc 2>/dev/null || echo 1)"
        CPU="$(awk -v l="$local_load" -v n="$num_cpus" 'BEGIN { printf "%.0f", (l / n) * 100 }')"
    fi
    MEM_FREE_PCT=''
    if [[ -r /proc/meminfo ]]; then
        MEM_FREE_PCT="$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END { if (t>0) printf "%.1f", (a/t)*100 }' /proc/meminfo)"
    fi
    SVC_STATE='unknown'
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet xrdp 2>/dev/null; then
            SVC_STATE='active'
        else
            SVC_STATE='inactive'
        fi
    fi

    TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    LINE="[${TS}] heartbeat #${BEAT}  remaining=${REMAIN_MIN}min  cpu=${CPU}%  mem_free=${MEM_FREE_PCT}%  xrdp=${SVC_STATE}"
    write_info "$LINE"
    echo "$LINE" >> "$LOG"

    # Every 30 minutes (6 beats at 5min), push a notify ping.
    if (( BEAT % 6 == 0 )); then
        send_notify "RDP session alive — ${REMAIN_MIN} min remaining" 'Heartbeat' || true
    fi

    sleep "$HEARTBEAT_SEC"
done

exit 0
