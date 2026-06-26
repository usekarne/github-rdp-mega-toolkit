#!/usr/bin/env bash
# utils.sh — shared helpers for the RDP Mega Toolkit v9 Bash core.
#
# Provides: logging (block/info/ok/warn/err), networking (test_port,
# get_public_ip), password generation (new_random_password) and webhook
# notifications (send_notify -> Discord/Telegram/Slack).
#
# Pure bash + POSIX userland.  Source this from every other script:
#
#   # shellcheck source=utils.sh
#   . "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
RDP_ARTIFACT_DIR="${RDP_ARTIFACT_DIR:-$(pwd)/rdp-artifacts}"
RDP_DEFAULT_USER="${RDP_DEFAULT_USER:-runner}"
TOOLKIT_VERSION="${TOOLKIT_VERSION:-9.0.0}"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
# Always log to stderr so stdout stays clean for callers that capture output.
_log() {
    local prefix="$1"; shift
    local color="$1"; shift
    printf '%b[%s]%b %s\n' "$color" "$prefix" '\033[0m' "$*" >&2
}

write_block() {
    local bar
    bar="$(printf '=%.0s' {1..78})"
    printf '\n\033[36m%s\033[0m\n' "$bar" >&2
    printf '\033[36m%s\033[0m\n' "$*" >&2
    printf '\033[36m%s\033[0m\n' "$bar" >&2
}

write_info() { _log INFO   '\033[37m' "$@"; }
write_ok()   { _log OK     '\033[32m' "$@"; }
write_warn() { _log WARN   '\033[33m' "$@"; }
write_err()  { _log ERR    '\033[31m' "$@"; }

write_banner() {
    cat >&2 <<'BANNER'
  ____  ____  ____  _   _  _____    ____  _____ __  __ _____ _
 |  _ \|  _ \|  _ \| \ | || ____|  / ___|| ____|  \/  | ____| |
 | |_) | |_) | |_) |  \| ||  _|    \___ \|  _| | |\/| |  _| | |
 |  _ <|  __/|  _ <| |\  || |___    ___) | |___| |  | | |___| |___
 |_| \_\_|   |_| \_\_| \_||_____|  |____/|_____|_|  |_|_____|_____|
                         v9 — cross-platform RDP toolkit
BANNER
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

# test_port HOST PORT [TIMEOUT_SEC]
test_port() {
    local host="$1"
    local port="$2"
    local timeout_sec="${3:-3}"
    # Prefer nc(1); fall back to bash /dev/tcp.
    if command -v nc >/dev/null 2>&1; then
        if nc -z -w "$timeout_sec" "$host" "$port" >/dev/null 2>&1; then
            return 0
        fi
        return 1
    elif command -v timeout >/dev/null 2>&1; then
        if timeout "$timeout_sec" bash -c "exec 3<>/dev/tcp/$host/$port" >/dev/null 2>&1; then
            return 0
        fi
        return 1
    fi
    # Last-ditch bash /dev/tcp (no timeout, but works on most systems).
    if (exec 3<>/dev/tcp/"$host"/"$port") >/dev/null 2>&1; then
        exec 3>&- 3<&- || true
        return 0
    fi
    return 1
}

# get_public_ip — echo the host's public IP (best effort).
get_public_ip() {
    local ip
    local url
    for url in \
        'https://api.ipify.org?format=text' \
        'https://ifconfig.me/ip' \
        'https://icanhazip.com'; do
        if command -v curl >/dev/null 2>&1; then
            ip="$(curl -fsS --max-time 5 "$url" 2>/dev/null || true)"
        elif command -v wget >/dev/null 2>&1; then
            ip="$(wget -qO- --timeout=5 "$url" 2>/dev/null || true)"
        else
            echo 'unknown'
            return 0
        fi
        ip="$(printf '%s' "$ip" | tr -d '[:space:]')"
        if [[ -n "$ip" ]]; then
            printf '%s' "$ip"
            return 0
        fi
    done
    echo 'unknown'
}

# ---------------------------------------------------------------------------
# Password generator — 24 chars, complexity enforced.
# Uses /dev/urandom (Linux/Mac) or termux-urandom fallback.
# ---------------------------------------------------------------------------
new_random_password() {
    local length="${1:-24}"
    if (( length < 12 )); then
        write_err "Password length must be >= 12 (got $length)"
        return 1
    fi
    local upper='ABCDEFGHJKLMNPQRSTUVWXYZ'
    local lower='abcdefghijkmnopqrstuvwxyz'
    local digit='23456789'
    local symbol='!@#$%^&*()-_=+[]{}'
    local pool="${upper}${lower}${digit}${symbol}"

    local dev
    if [[ -r /dev/urandom ]]; then
        dev=/dev/urandom
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then
        dev=/proc/sys/kernel/random/uuid   # only used as entropy source
    else
        dev=/dev/random
    fi

    # Read N random bytes and mod down to indices.
    _rand_index() {
        local modulus="$1"
        # Read 4 bytes, interpret as big-endian uint32.
        local b
        b="$(head -c 4 "$dev" | od -An -tu4 | tr -d '[:space:]')"
        # shellcheck disable=SC2004
        echo $(( b % modulus ))
    }

    local pw=''
    # Guarantee at least one of each class first.
    pw+="${upper:$(_rand_index ${#upper}):1}"
    pw+="${lower:$(_rand_index ${#lower}):1}"
    pw+="${digit:$(_rand_index ${#digit}):1}"
    pw+="${symbol:$(_rand_index ${#symbol}):1}"

    while (( ${#pw} < length )); do
        pw+="${pool:$(_rand_index ${#pool}):1}"
    done

    # Fisher–Yates shuffle.
    local arr
    arr=()
    local i
    for ((i=0; i<${#pw}; i++)); do
        arr+=("${pw:i:1}")
    done
    for ((i=${#pw}-1; i>0; i--)); do
        local j=$(_rand_index $((i+1)))
        local tmp="${arr[i]}"
        arr[i]="${arr[j]}"
        arr[j]="$tmp"
    done
    printf '%s' "${arr[*]}" | tr -d ' '
}

# ---------------------------------------------------------------------------
# Webhook notifications
# ---------------------------------------------------------------------------

# send_notify MESSAGE [TITLE]
send_notify() {
    local message="$1"
    local title="${2:-RDP Mega Toolkit v9}"
    local results=()

    # Discord
    if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
        local payload
        payload="$(printf '{"username":"rdp-mega-toolkit","embeds":[{"title":"%s","description":"%s","color":3447003}]}' \
            "$(jq_escape "$title")" "$(jq_escape "$message")" 2>/dev/null || true)"
        if command -v curl >/dev/null 2>&1; then
            if curl -fsS --max-time 10 \
                 -H 'Content-Type: application/json' \
                 -d "$payload" \
                 "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1; then
                results+=('Discord:ok')
            else
                results+=('Discord:fail')
                write_warn 'Discord notify failed'
            fi
        fi
    fi

    # Telegram
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
        local tg_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
        local payload
        payload="$(printf '{"chat_id":"%s","text":"*%s*\\n%s","parse_mode":"Markdown"}' \
            "$(jq_escape "$TELEGRAM_CHAT_ID")" "$(jq_escape "$title")" "$(jq_escape "$message")" 2>/dev/null || true)"
        if command -v curl >/dev/null 2>&1; then
            if curl -fsS --max-time 10 \
                 -H 'Content-Type: application/json' \
                 -d "$payload" \
                 "$tg_url" >/dev/null 2>&1; then
                results+=('Telegram:ok')
            else
                results+=('Telegram:fail')
                write_warn 'Telegram notify failed'
            fi
        fi
    fi

    # Slack
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        local payload
        payload="$(printf '{"text":"*%s*\\n%s"}' \
            "$(jq_escape "$title")" "$(jq_escape "$message")" 2>/dev/null || true)"
        if command -v curl >/dev/null 2>&1; then
            if curl -fsS --max-time 10 \
                 -H 'Content-Type: application/json' \
                 -d "$payload" \
                 "$SLACK_WEBHOOK_URL" >/dev/null 2>&1; then
                results+=('Slack:ok')
            else
                results+=('Slack:fail')
                write_warn 'Slack notify failed'
            fi
        fi
    fi

    if (( ${#results[@]} == 0 )); then
        write_info 'No notify channels configured (DISCORD_WEBHOOK_URL / TELEGRAM_BOT_TOKEN / SLACK_WEBHOOK_URL).'
        return 0
    fi

    printf '%s\n' "${results[@]}"
}

# jq_escape STRING — produce a JSON-safe string even when jq is missing.
jq_escape() {
    local s="$1"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$s" | jq -Rs '.'
        return
    fi
    # Manual escape: backslash-quotes + control chars.
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '"%s"' "$s"
}

# ---------------------------------------------------------------------------
# Misc helpers
# ---------------------------------------------------------------------------

ensure_artifact_dir() {
    mkdir -p "$RDP_ARTIFACT_DIR"
    echo "$RDP_ARTIFACT_DIR"
}

# require_root — exits non-zero if not root (sudo).
require_root() {
    if [[ $EUID -ne 0 ]]; then
        write_err 'This script must be run as root (try sudo).'
        exit 1
    fi
}

# require_cmd CMD1 CMD2 ... — exits non-zero if any command is missing.
require_cmd() {
    local missing=()
    local c
    for c in "$@"; do
        if ! command -v "$c" >/dev/null 2>&1; then
            missing+=("$c")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        write_err "Missing required commands: ${missing[*]}"
        exit 1
    fi
}

# is_kali — true when running on Kali Linux.
is_kali() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release 2>/dev/null || true
        if [[ "${ID:-}" == "kali" || "${NAME:-}" == *Kali* ]]; then
            return 0
        fi
    fi
    return 1
}

# is_android_termux — true when running inside Termux.
is_android_termux() {
    if [[ -n "${TERMUX_VERSION:-}" || "${PREFIX:-}" == *com.termux* ]]; then
        return 0
    fi
    return 1
}

# safe_trap_cleanup — installs a trap that runs the given command on EXIT.
safe_trap_cleanup() {
    local cmd="$1"
    trap '$cmd' EXIT
}

# When sourced interactively, show banner.
if [[ "${BASH_SOURCE[0]:-$0}" != "$0" ]]; then
    # Sourced — don't auto-banner (would spam CI logs).
    :
fi
