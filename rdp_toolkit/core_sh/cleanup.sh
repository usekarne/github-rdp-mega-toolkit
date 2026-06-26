#!/usr/bin/env bash
# cleanup.sh — reverse everything setup-rdp.sh + setup-tunnel.sh did.
# Always-runs (GitHub Actions `if: always()`).

set -uo pipefail
# Deliberately NOT `set -e` — cleanup must be best-effort.
# shellcheck source=utils.sh
. "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

USERNAME="${RDP_USERNAME:-runner}"
DIR="${RDP_ARTIFACT_DIR:-$(pwd)/rdp-artifacts}"
mkdir -p "$DIR"

safe_step() {
    local name="$1"; shift
    if "$@"; then
        write_ok "Step '$name' ok"
    else
        local rc=$?
        write_warn "Step '$name' failed (exit $rc)"
    fi
}

# ---------------------------------------------------------------------------
# Step implementations
# ---------------------------------------------------------------------------

_stop_tunnels() {
    local pid_files=("serveo.pid" "localhostrun.pid" "cloudflared.pid")
    for pf in "${pid_files[@]}"; do
        local f="${DIR}/${pf}"
        if [[ -f "$f" ]]; then
            local pid
            pid="$(cat "$f" 2>/dev/null || true)"
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                write_info "Killing tunnel pid $pid ($pf)"
                kill "$pid" 2>/dev/null || true
                sleep 1
                kill -9 "$pid" 2>/dev/null || true
            fi
            rm -f "$f"
        fi
    done
    pkill -f 'serveo.net'                  2>/dev/null || true
    pkill -f 'nokey@localhost.run'         2>/dev/null || true
    pkill -f 'cloudflared.*tunnel --url'   2>/dev/null || true
    return 0
}

_stop_xrdp() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop xrdp 2>/dev/null || true
        systemctl disable xrdp 2>/dev/null || true
    fi
    pkill -x xrdp 2>/dev/null || true
    pkill -x xrdp-sesman 2>/dev/null || true
    return 0
}

_remove_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null | grep -q 'Status: active'; then
            ufw delete allow 3389/tcp 2>/dev/null || true
            ufw delete allow 3389/udp 2>/dev/null || true
        fi
    fi
    return 0
}

_remove_user() {
    if ! id "$USERNAME" >/dev/null 2>&1; then
        write_warn "User '$USERNAME' not present."
        return 0
    fi
    pkill -KILL -u "$USERNAME" 2>/dev/null || true
    sleep 1
    userdel -r "$USERNAME" 2>/dev/null || userdel "$USERNAME" 2>/dev/null || true
    rm -f "/etc/sudoers.d/${USERNAME}"
    return 0
}

_clean_artifacts() {
    if [[ "${KEEP_ARTIFACTS:-0}" == "1" ]]; then
        write_info 'KEEP_ARTIFACTS=1 — leaving artifact files in place.'
        return 0
    fi
    local files=(
        rdp-password.txt RDP_USERNAME.txt RDP_PASSWORD.txt rdp-summary.json
        tunnel-info.txt tunnel-type.txt tunnel-host.txt tunnel-port.txt
        connect-info.txt serveo.log localhostrun.log cloudflared.log
        keepalive.log health-status.json password-rotations.log
        serveo.pid localhostrun.pid cloudflared.pid
    )
    local f
    for f in "${files[@]}"; do
        rm -f "${DIR}/${f}"
    done
    return 0
}

# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
write_block 'cleanup.sh — best-effort teardown'

safe_step 'Stop tunnel processes'     _stop_tunnels
safe_step 'Stop xrdp'                 _stop_xrdp
safe_step 'Remove firewall rules'     _remove_firewall
safe_step "Remove user '$USERNAME'"   _remove_user
safe_step 'Clean artifact files'      _clean_artifacts

send_notify "RDP session on $(hostname) torn down by cleanup.sh" 'Cleanup complete' 2>/dev/null || true

write_block 'cleanup.sh complete'
exit 0
