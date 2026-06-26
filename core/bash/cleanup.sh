#!/usr/bin/env bash
# core/bash/cleanup.sh - Tear down Linux xrdp session
set -euo pipefail
source "$(dirname "$0")/utils.sh"

log_block "CLEANUP UBUNTU"

USER_NAME="${RDP_USER:-runner}"

systemctl stop xrdp 2>/dev/null || true
systemctl disable xrdp 2>/dev/null || true
log_ok 'xrdp stopped'

userdel -r -f "$USER_NAME" 2>/dev/null || true
rm -f "/etc/sudoers.d/${USER_NAME}"
log_ok "User '$USER_NAME' removed"

pkill -f 'ngrok|cloudflared|ssh.*serveo|ssh.*localhost\.run' 2>/dev/null || true
rm -f cloudflared 2>/dev/null || true
log_ok 'Tunnel processes killed'

send_notify "RDP Session Ended" "Cleanup complete on Linux runner."

log_ok 'Cleanup done.'
