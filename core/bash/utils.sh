#!/usr/bin/env bash
# core/bash/utils.sh - Shared helpers for GitHub RDP Mega Toolkit v9.0 (Linux/Ubuntu/Kali)
# Source with: source "$(dirname "$0")/utils.sh"

log_info()  { echo "[INFO] $*"; }
log_ok()    { echo "[OK]   $*"; }
log_warn()  { echo "[WARN] $*"; }
log_err()   { echo "[ERR]  $*" >&2; }

log_block() {
    local title="$1"
    echo ""
    echo "+============================================================+"
    echo "|  $title"
    echo "+============================================================+"
}

test_port() {
    local host="${1:-localhost}"
    local port="${2:-3389}"
    local timeout="${3:-2}"
    if command -v ss &>/dev/null; then
        ss -tln | grep -q ":${port} " && return 0 || return 1
    elif command -v nc &>/dev/null; then
        nc -z -w "$timeout" "$host" "$port" 2>/dev/null && return 0 || return 1
    else
        # Fallback using bash /dev/tcp
        timeout "$timeout" bash -c "echo > /dev/tcp/${host}/${port}" 2>/dev/null && return 0 || return 1
    fi
}

get_public_ip() {
    curl -s --max-time 10 https://api.ipify.org 2>/dev/null || \
    curl -s --max-time 10 https://ifconfig.me 2>/dev/null || \
    echo "unknown"
}

ensure_complexity() {
    local pwd="$1"
    [[ "$pwd" =~ [A-Z] ]] || pwd="A${pwd}"
    [[ "$pwd" =~ [a-z] ]] || pwd="${pwd}a"
    [[ "$pwd" =~ [0-9] ]] || pwd="1${pwd}"
    [[ "$pwd" =~ [^A-Za-z0-9] ]] || pwd="${pwd}!"
    echo "$pwd"
}

gen_password() {
    local length="${1:-24}"
    # Use openssl if available, else /dev/urandom
    local pwd
    if command -v openssl &>/dev/null; then
        pwd=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' | head -c "$length")
    else
        pwd=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c "$length")
    fi
    ensure_complexity "$pwd"
}

write_artifact() {
    local name="$1"
    local value="$2"
    printf '%s=%s' "$name" "$value" > "${name}.txt"
    echo "[ARTIFACT] $name=$value"
}

send_notify() {
    local title="$1"
    local body="$2"
    local cfg_file="$(dirname "$0")/../../configs/notification-channels.json"
    [ -f "$cfg_file" ] || return 0

    # Discord
    local discord_enabled discord_url
    discord_enabled=$(python3 -c "import json;d=json.load(open('$cfg_file'));print(d.get('discord',{}).get('enabled',False))" 2>/dev/null)
    discord_url=$(python3 -c "import json;d=json.load(open('$cfg_file'));print(d.get('discord',{}).get('webhook_url',''))" 2>/dev/null)
    if [ "$discord_enabled" = "True" ] && [ -n "$discord_url" ]; then
        curl -s -X POST -H "Content-Type: application/json" \
            -d "{\"content\":\"**${title}**\n${body}\"}" \
            "$discord_url" >/dev/null 2>&1 || true
    fi

    # Telegram
    local tg_enabled tg_token tg_chat
    tg_enabled=$(python3 -c "import json;d=json.load(open('$cfg_file'));print(d.get('telegram',{}).get('enabled',False))" 2>/dev/null)
    tg_token=$(python3 -c "import json;d=json.load(open('$cfg_file'));print(d.get('telegram',{}).get('bot_token',''))" 2>/dev/null)
    tg_chat=$(python3 -c "import json;d=json.load(open('$cfg_file'));print(d.get('telegram',{}).get('chat_id',''))" 2>/dev/null)
    if [ "$tg_enabled" = "True" ] && [ -n "$tg_token" ] && [ -n "$tg_chat" ]; then
        curl -s -X POST "https://api.telegram.org/bot${tg_token}/sendMessage" \
            -d "chat_id=${tg_chat}" -d "text=*${title}*
${body}" -d "parse_mode=Markdown" >/dev/null 2>&1 || true
    fi

    # Slack
    local slack_enabled slack_url
    slack_enabled=$(python3 -c "import json;d=json.load(open('$cfg_file'));print(d.get('slack',{}).get('enabled',False))" 2>/dev/null)
    slack_url=$(python3 -c "import json;d=json.load(open('$cfg_file'));print(d.get('slack',{}).get('webhook_url',''))" 2>/dev/null)
    if [ "$slack_enabled" = "True" ] && [ -n "$slack_url" ]; then
        curl -s -X POST -H "Content-Type: application/json" \
            -d "{\"text\":\"*${title}*\n${body}\"}" \
            "$slack_url" >/dev/null 2>&1 || true
    fi
}

get_system_info() {
    echo "OS: $(uname -a)"
    echo "Memory: $(free -h 2>/dev/null | grep Mem | awk '{print $2" total, "$4" free"}' || echo 'unknown')"
    echo "Disk: $(df -h / 2>/dev/null | tail -1 | awk '{print $4" free"}' || echo 'unknown')"
    echo "Uptime: $(uptime 2>/dev/null || echo 'unknown')"
    echo "Public IP: $(get_public_ip)"
}
