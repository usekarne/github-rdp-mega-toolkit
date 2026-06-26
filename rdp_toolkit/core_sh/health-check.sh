#!/usr/bin/env bash
# health-check.sh — probe RDP port, service status, disk, mem, write
# health-status.json (mirror of health-check.ps1).

set -euo pipefail
# shellcheck source=utils.sh
. "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

DIR="$(ensure_artifact_dir)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

write_block 'health-check.sh — gathering diagnostics'

# --- RDP port (3389) probe -------------------------------------------------
RDP_PORT_OPEN='false'
if test_port 127.0.0.1 3389 1; then
    RDP_PORT_OPEN='true'
fi
write_info "RDP port 3389 on localhost: $(if [[ "$RDP_PORT_OPEN" == 'true' ]]; then echo OPEN; else echo CLOSED; fi)"

# --- xrdp service status ---------------------------------------------------
XRDP_STATE='unknown'
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet xrdp 2>/dev/null; then
        XRDP_STATE='active'
    else
        XRDP_STATE='inactive'
    fi
elif pgrep -x xrdp >/dev/null 2>&1; then
    XRDP_STATE='running'
fi
write_info "xrdp: $XRDP_STATE"

# --- Disk (root filesystem) ------------------------------------------------
DISK_FREE_GB=0
DISK_TOTAL_GB=0
DISK_FREE_PCT=0
if command -v df >/dev/null 2>&1; then
    # awk handles both Linux and macOS df output (1K blocks).
    read -r DISK_TOTAL_GB DISK_FREE_GB DISK_FREE_PCT <<EOF
$(df -k / 2>/dev/null | awk 'NR==2 { total=$2; free=$4; if (total>0) pct=(free/total)*100; printf "%.2f %.2f %.1f", total/1024/1024, free/1024/1024, pct }')
EOF
fi
write_info "Disk: ${DISK_FREE_GB} GB free of ${DISK_TOTAL_GB} GB (${DISK_FREE_PCT}%)"

# --- Memory ---------------------------------------------------------------
MEM_FREE_GB=0
MEM_TOTAL_GB=0
MEM_FREE_PCT=0
if [[ -r /proc/meminfo ]]; then
    read -r MEM_TOTAL_GB MEM_FREE_GB MEM_FREE_PCT <<EOF
$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END { if (t>0) printf "%.2f %.2f %.1f", t/1024/1024, a/1024/1024, (a/t)*100 }' /proc/meminfo)
EOF
elif command -v vm_stat >/dev/null 2>&1 && command -v sysctl >/dev/null 2>&1; then
    # macOS fallback.
    MEM_TOTAL_GB="$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.2f", $1/1024/1024/1024}')"
    MEM_FREE_GB="$MEM_TOTAL_GB"  # approx
    MEM_FREE_PCT=50.0
fi
write_info "Memory: ${MEM_FREE_GB} GB free of ${MEM_TOTAL_GB} GB (${MEM_FREE_PCT}%)"

# --- Public IP ------------------------------------------------------------
PUB_IP="$(get_public_ip)"

# --- Tunnel state (from artifacts) ----------------------------------------
TUNNEL_TYPE=''
TUNNEL_HOST=''
if [[ -f "${DIR}/tunnel-type.txt" ]]; then
    TUNNEL_TYPE="$(tr -d '[:space:]' < "${DIR}/tunnel-type.txt")"
fi
if [[ -f "${DIR}/tunnel-host.txt" ]]; then
    TUNNEL_HOST="$(tr -d '[:space:]' < "${DIR}/tunnel-host.txt")"
fi

# --- Overall health decision ----------------------------------------------
OK='true'
if [[ "$RDP_PORT_OPEN" != 'true' ]];            then OK='false'; fi
if [[ "$XRDP_STATE" != 'active' && "$XRDP_STATE" != 'running' ]]; then OK='false'; fi
awk -v p="$DISK_FREE_PCT" 'BEGIN { if (p+0 <= 5) exit 1 }' || OK='false'
awk -v p="$MEM_FREE_PCT" 'BEGIN { if (p+0 <= 5) exit 1 }' || OK='false'

# --- Write JSON -----------------------------------------------------------
# Build via printf so we don't depend on jq.
cat > "${DIR}/health-status.json" <<EOF
{
  "timestamp": "${TS}",
  "host": "$(hostname)",
  "public_ip": "${PUB_IP}",
  "rdp_port_open": ${RDP_PORT_OPEN},
  "xrdp_service": "${XRDP_STATE}",
  "disk": {
    "free_gb": ${DISK_FREE_GB:-0},
    "total_gb": ${DISK_TOTAL_GB:-0},
    "free_pct": ${DISK_FREE_PCT:-0}
  },
  "memory": {
    "free_gb": ${MEM_FREE_GB:-0},
    "total_gb": ${MEM_TOTAL_GB:-0},
    "free_pct": ${MEM_FREE_PCT:-0}
  },
  "tunnel": {
    "type": "${TUNNEL_TYPE}",
    "host": "${TUNNEL_HOST}"
  },
  "ok": ${OK}
}
EOF
write_ok "Wrote ${DIR}/health-status.json"

if [[ "$OK" != 'true' ]]; then
    write_warn 'Health check FAILED — see JSON for details.'
    exit 2
fi
write_ok 'Health check passed.'
exit 0
