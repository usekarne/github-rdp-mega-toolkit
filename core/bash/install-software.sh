#!/usr/bin/env bash
# core/bash/install-software.sh - Install packages via apt (parsed from JSON via python3)
set -euo pipefail
source "$(dirname "$0")/utils.sh"

LIST_FILE="$(dirname "$0")/../../configs/software-list.json"
[ -f "$LIST_FILE" ] || { log_warn "software-list.json not found"; exit 0; }

# Get list of enabled apt package IDs
PACKAGES=$(python3 -c "
import json
with open('$LIST_FILE') as f:
    d = json.load(f)
for pkg in d.get('software', []):
    if pkg.get('enabled') and pkg.get('provider') == 'apt':
        print(pkg['id'])
" 2>/dev/null || echo "")

if [ -z "$PACKAGES" ]; then
    log_info 'No apt packages marked enabled - skipping'
    exit 0
fi

log_block "INSTALL SOFTWARE (apt)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq 2>&1 | tail -2

echo "$PACKAGES" | while read -r pkg; do
    [ -z "$pkg" ] && continue
    log_info "Installing $pkg..."
    if apt-get install -y -qq "$pkg" 2>&1 | tail -2; then
        log_ok "$pkg installed"
    else
        log_warn "$pkg failed"
    fi
done

log_ok 'Software install pass complete'
