#!/usr/bin/env bash
# core/bash/auto-config.sh - Auto-generate configs/*.json if missing
set -euo pipefail
source "$(dirname "$0")/utils.sh"

log_block "AUTO-CONFIG - check missing config files"

CONFIG_DIR="$(dirname "$0")/../../configs"
mkdir -p "$CONFIG_DIR"

# Defaults file
DEFAULTS_FILE="$CONFIG_DIR/auto-generated-defaults.json"
if [ ! -f "$DEFAULTS_FILE" ]; then
    cat > "$DEFAULTS_FILE" <<'EOF'
{
  "version": "9.0.0",
  "description": "Default values used by auto-config.sh when other config files are missing",
  "software_list_default": [
    {"id": "curl", "enabled": true, "provider": "apt"},
    {"id": "wget", "enabled": true, "provider": "apt"},
    {"id": "xfce4", "enabled": true, "provider": "apt"}
  ],
  "tunnel_providers_default": ["serveo", "localhost.run", "cloudflare"],
  "optimization_profile_default": "productivity",
  "session_hours_default": 6,
  "heartbeat_sec_default": 300
}
EOF
    log_ok "Created $DEFAULTS_FILE"
fi

# Check required configs
REQUIRED_CONFIGS=(
    software-list.json
    tunnel-providers.json
    notification-channels.json
    optimization-profiles.json
    session-profiles.json
    virtual-environments.json
    security-policies.json
    client-tools-config.json
    kali-tools.json
    android-termux-packages.json
    windows-features.json
)

for cfg in "${REQUIRED_CONFIGS[@]}"; do
    cfg_path="$CONFIG_DIR/$cfg"
    if [ ! -f "$cfg_path" ]; then
        log_warn "$cfg missing - would auto-generate from defaults"
    else
        log_ok "$cfg present"
    fi
done

log_ok 'Auto-config check complete'
