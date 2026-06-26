#!/usr/bin/env bash
# core/bash/optimize-linux.sh - Linux optimizations
set -euo pipefail
source "$(dirname "$0")/utils.sh"

log_block "OPTIMIZE LINUX"

# Disable unnecessary services
SERVICES_TO_DISABLE=(avahi-daemon cups bluetooth ModemManager speech-dispatcher)
for svc in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        systemctl stop "$svc" 2>/dev/null || true
        log_ok "Stopped $svc"
    fi
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        systemctl disable "$svc" 2>/dev/null || true
        log_ok "Disabled $svc"
    fi
done

# Set swappiness to 10 (less swap usage = better performance)
sysctl -w vm.swappiness=10 2>/dev/null || true
echo 'vm.swappiness=10' > /etc/sysctl.d/99-rdp-toolkit.conf 2>/dev/null || true
log_ok 'Swappiness set to 10'

# Enable performance CPU governor if available
if command -v cpupower &>/dev/null; then
    cpupower frequency-set -g performance 2>/dev/null && log_ok 'CPU governor: performance' || true
fi

# Disable sleep/suspend/hibernate via systemd
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
log_ok 'Sleep/suspend/hibernate disabled'

# Enable TCP BBR for better network performance
if ! sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
    echo 'net.core.default_qdisc=fq' >> /etc/sysctl.d/99-rdp-toolkit.conf 2>/dev/null || true
    echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.d/99-rdp-toolkit.conf 2>/dev/null || true
    sysctl --system 2>/dev/null || true
    log_ok 'TCP BBR enabled'
fi

log_ok 'Linux optimization complete'
