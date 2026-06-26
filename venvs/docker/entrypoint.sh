#!/usr/bin/env bash
# venvs/docker/entrypoint.sh - Container entrypoint for Kali RDP Docker image
set -euo pipefail

echo "[INFO] Starting Kali RDP Docker container..."

# Create runner user if not exists
if ! id runner &>/dev/null; then
    useradd -m -s /bin/bash runner
    echo "runner:runner" | chpasswd
    usermod -aG sudo runner
    echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner
fi

# Configure XFCE session
echo "startxfce4" > /home/runner/.xsession
chown runner:runner /home/runner/.xsession

# Start xrdp
xrdp-sesexec 2>/dev/null || true
xrdp 2>/dev/null || true

echo "[OK] RDP available on port 3389"
echo "[INFO] Connect with: xfreerdp /v:localhost:3389 /u:runner /p:runner /cert:ignore"

# Keep container running
exec tail -f /dev/null
