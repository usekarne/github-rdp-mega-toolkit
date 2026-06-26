#!/usr/bin/env bash
# core/bash/health-check.sh - Probe system health, write JSON to health-status.json
set -euo pipefail
source "$(dirname "$0")/utils.sh"

log_block "HEALTH CHECK"

RDP_PORT_OK="false"
test_port localhost 3389 && RDP_PORT_OK="true"

XRDP_STATUS="unknown"
if command -v systemctl &>/dev/null; then
    XRDP_STATUS=$(systemctl is-active xrdp 2>/dev/null || echo 'unknown')
fi

PUBLIC_IP=$(get_public_ip)
TUNNEL_TYPE="${TUNNEL_TYPE:-unknown}"
TUNNEL_URL="${TUNNEL_URL:-unknown}"

DISK_FREE_GB=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
MEM_FREE_KB=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
MEM_FREE_GB=$(awk "BEGIN {printf \"%.2f\", ${MEM_FREE_KB:-0}/1048576}")

UPTIME_SEC=$(awk '{print $1}' /proc/uptime 2>/dev/null || echo 0)
UPTIME_HRS=$(awk "BEGIN {printf \"%.2f\", ${UPTIME_SEC}/3600}")

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

python3 -c "
import json
status = {
    'timestamp': '$TIMESTAMP',
    'rdp_port_3389': $RDP_PORT_OK,
    'xrdp_service': '$XRDP_STATUS',
    'tunnel_type': '$TUNNEL_TYPE',
    'tunnel_url': '$TUNNEL_URL',
    'public_ip': '$PUBLIC_IP',
    'disk_free_gb': ${DISK_FREE_GB:-0},
    'mem_free_gb': $MEM_FREE_GB,
    'uptime_hrs': $UPTIME_HRS
}
print(json.dumps(status, indent=2))
with open('health-status.json', 'w') as f:
    json.dump(status, f, indent=2)
"

log_ok 'Health check complete (health-status.json written)'
