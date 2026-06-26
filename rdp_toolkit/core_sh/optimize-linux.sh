#!/usr/bin/env bash
# optimize-linux.sh — apply a system-optimisation profile
# (productivity / gaming / minimal) on a Linux RDP runner.
#
# What it does:
#   - disables unnecessary services (avahi, cups, bluetooth, etc.)
#   - sets swappiness + clears caches
#   - disables unattended-upgrades for the session
#   - sets CPU governor to 'performance' when available

set -euo pipefail
# shellcheck source=utils.sh
. "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

PROFILE="${OPTIMIZE_PROFILE:-productivity}"
case "$PROFILE" in
    productivity|gaming|minimal) ;;
    *)
        write_err "Unknown profile: '$PROFILE' (expected productivity|gaming|minimal)"
        exit 1
        ;;
esac

require_root

write_block "Applying Linux profile: $PROFILE"

# ---------------------------------------------------------------------------
# Services to disable per profile
# ---------------------------------------------------------------------------
declare -a SERVICES=()
case "$PROFILE" in
    productivity)
        SERVICES+=(avahi-daemon cups bluetooth modemmanager)
        ;;
    gaming)
        SERVICES+=(avahi-daemon cups bluetooth modemmanager apport whoopsies)
        ;;
    minimal)
        SERVICES+=(
            avahi-daemon cups bluetooth modemmanager apport whoopsies
            networkd-dispatcher multipathd fwupd unattended-upgrades
            packagekit polkit udisks2 rsyslog
        )
        ;;
esac

disable_service() {
    local svc="$1"
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            systemctl stop "$svc" 2>/dev/null || true
            write_ok "Stopped service: $svc"
        fi
        if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            systemctl disable "$svc" 2>/dev/null || true
            write_ok "Disabled service: $svc"
        fi
    fi
}

for s in "${SERVICES[@]}"; do
    disable_service "$s"
done

# ---------------------------------------------------------------------------
# Swappiness + cache cleanup
# ---------------------------------------------------------------------------
write_info 'Tuning VM settings'
if [[ -w /proc/sys/vm/swappiness ]]; then
    if [[ "$PROFILE" == "gaming" ]]; then
        echo 10 > /proc/sys/vm/swappiness
    else
        echo 20 > /proc/sys/vm/swappiness
    fi
    write_ok "vm.swappiness = $(cat /proc/sys/vm/swappiness)"
fi
if [[ -w /proc/sys/vm/vfs_cache_pressure ]]; then
    echo 50 > /proc/sys/vm/vfs_cache_pressure
    write_ok "vm.vfs_cache_pressure = $(cat /proc/sys/vm/vfs_cache_pressure)"
fi
# Drop clean caches (3 = pagecache + dentries + inodes).
if [[ -w /proc/sys/vm/drop_caches ]]; then
    sync || true
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    write_ok 'Dropped pagecache + dentries + inodes'
fi

# ---------------------------------------------------------------------------
# CPU governor — performance for gaming, ondemand otherwise.
# ---------------------------------------------------------------------------
write_info 'Tuning CPU governor'
gov='ondemand'
if [[ "$PROFILE" == "gaming" ]]; then
    gov='performance'
fi
if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
    for cpu_file in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [[ -w "$cpu_file" ]] && echo "$gov" > "$cpu_file" 2>/dev/null || true
    done
    write_ok "CPU governor -> $gov"
else
    write_info 'No CPU governor available (VM or unsupported).'
fi

# ---------------------------------------------------------------------------
# Disable unattended-upgrades (avoid surprise apt locks during RDP).
# ---------------------------------------------------------------------------
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
        systemctl stop unattended-upgrades 2>/dev/null || true
        write_ok 'Stopped unattended-upgrades for session'
    fi
fi
if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
    sed -i 's|APT::Periodic::Update-Package-Lists "1";|APT::Periodic::Update-Package-Lists "0";|' \
        /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || true
    sed -i 's|APT::Periodic::Unattended-Upgrade "1";|APT::Periodic::Unattended-Upgrade "0";|' \
        /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || true
    write_ok 'Disabled apt auto-updates for session'
fi

# ---------------------------------------------------------------------------
# Disable iptables / ufw if they'd block 3389 (CI runners usually have none).
# We do NOT modify firewalls that look user-configured.
# ---------------------------------------------------------------------------
if command -v ufw >/dev/null 2>&1; then
    if ufw status 2>/dev/null | grep -q 'Status: active'; then
        ufw allow 3389/tcp 2>/dev/null || true
        ufw allow 3389/udp 2>/dev/null || true
        write_ok 'Allowed 3389/tcp + 3389/udp in ufw'
    fi
fi

# ---------------------------------------------------------------------------
# Journal: limit systemd-journald to 50M to save disk on tiny VMs.
# ---------------------------------------------------------------------------
if [[ -d /etc/systemd ]]; then
    if ! grep -q 'SystemMaxUse=50M' /etc/systemd/journald.conf 2>/dev/null; then
        if [[ -w /etc/systemd/journald.conf ]]; then
            sed -i 's|^#SystemMaxUse=.*|SystemMaxUse=50M|' /etc/systemd/journald.conf 2>/dev/null || true
            if ! grep -q '^SystemMaxUse=' /etc/systemd/journald.conf 2>/dev/null; then
                echo 'SystemMaxUse=50M' >> /etc/systemd/journald.conf
            fi
            systemctl restart systemd-journald 2>/dev/null || true
            write_ok 'Capped journald at 50M'
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Notify + done
# ---------------------------------------------------------------------------
send_notify "Linux optimisation applied ($PROFILE) on $(hostname)" 'Optimise' || true

write_block "optimize-linux.sh ($PROFILE) complete"
