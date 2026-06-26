#!/usr/bin/env bash
# platforms/kali/scripts/optimize-kali.sh - Kali-specific optimizations
set -euo pipefail

echo "[INFO] Optimizing Kali Linux..."

# Disable unnecessary services
for svc in avahi-daemon cups bluetooth ModemManager speech-dispatcher; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
done

# Set swappiness
sysctl -w vm.swappiness=10 2>/dev/null || true
echo 'vm.swappiness=10' > /etc/sysctl.d/99-kali-rdp.conf

# Disable sleep
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true

# Enable TCP BBR
echo 'net.core.default_qdisc=fq' >> /etc/sysctl.d/99-kali-rdp.conf
echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.d/99-kali-rdp.conf
sysctl --system 2>/dev/null || true

echo "[OK] Kali optimization complete"
