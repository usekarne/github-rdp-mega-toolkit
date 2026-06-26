#!/usr/bin/env bash
# core/bash/rotate-password.sh - Rotate runner password mid-session
set -euo pipefail
source "$(dirname "$0")/utils.sh"

USER_NAME="${RDP_USER:-runner}"
NEW_PWD="$(gen_password 24)"

log_block "ROTATE PASSWORD - user=$USER_NAME"

echo "${USER_NAME}:${NEW_PWD}" | chpasswd
log_ok 'Password rotated'

# Update artifact files
printf '%s' "$NEW_PWD" > rdp-password.txt
printf 'RDP_PASSWORD=%s' "$NEW_PWD" > RDP_PASSWORD.txt
echo "[ARTIFACT] RDP_PASSWORD=$NEW_PWD"

# Update connect-info.txt (preserve BRIDGE_CMD, update /p:'...' in CONNECT_CMD)
if [ -f connect-info.txt ]; then
    BRIDGE_CMD=$(grep '^BRIDGE_CMD=' connect-info.txt | head -1 | sed 's/^BRIDGE_CMD=//')
    OLD_CONNECT=$(grep '^CONNECT_CMD=' connect-info.txt | head -1 | sed 's/^CONNECT_CMD=//')
    NEW_CONNECT=$(echo "$OLD_CONNECT" | sed "s|/p:'[^']*'|/p:'${NEW_PWD}'|")
    printf 'BRIDGE_CMD=%s\r\nCONNECT_CMD=%s' "$BRIDGE_CMD" "$NEW_CONNECT" > connect-info.txt
fi

if [ -n "${GITHUB_ENV:-}" ]; then
    echo "RDP_PASS=$NEW_PWD" >> "$GITHUB_ENV"
fi

send_notify "RDP Password Rotated" "User: $USER_NAME
New password: $NEW_PWD"

log_block "NEW PASSWORD"
echo "|  $NEW_PWD"
echo "+============================================================+"
