#!/usr/bin/env bash
# core/bash/setup-rdp.sh - Configure Ubuntu/Debian/Kali with XFCE + xrdp
set -euo pipefail
source "$(dirname "$0")/utils.sh"

USER_NAME="${RDP_USER:-runner}"
PASSWORD="${RDP_MASTER_PASSWORD:-$(gen_password 24)}"
PASSWORD="$(ensure_complexity "$PASSWORD")"

log_block "SETUP RDP UBUNTU - user=$USER_NAME"

# 1. Install XFCE + xrdp
export DEBIAN_FRONTEND=noninteractive
log_info "Installing XFCE + xrdp..."
apt-get update -qq 2>&1 | tail -2
apt-get install -y -qq xfce4 xfce4-goodies xrdp dbus-x11 curl wget 2>&1 | tail -3
log_ok "XFCE + xrdp installed"

# 2. Create user
if ! id "$USER_NAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USER_NAME"
    echo "${USER_NAME}:${PASSWORD}" | chpasswd
    usermod -aG sudo "$USER_NAME"
    echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USER_NAME}"
    log_ok "User $USER_NAME created"
else
    echo "${USER_NAME}:${PASSWORD}" | chpasswd
    log_ok "User $USER_NAME password updated"
fi

# 3. Configure xrdp session
echo "startxfce4" > "/home/${USER_NAME}/.xsession"
chown "$USER_NAME:$USER_NAME" "/home/${USER_NAME}/.xsession"

# 4. xrdp port 3389
sed -i 's/^port=.*/port=3389/' /etc/xrdp/xrdp.ini
systemctl enable xrdp 2>/dev/null || true
systemctl restart xrdp 2>/dev/null || service xrdp restart 2>/dev/null || true

# 5. Wait for port 3389
for i in $(seq 1 15); do
    if ss -tln 2>/dev/null | grep -q ':3389 '; then
        log_ok "Port 3389 listening"
        break
    fi
    sleep 2
done

# 6. Save credentials (printf to avoid trailing newline)
printf '%s' "$PASSWORD" > rdp-password.txt
printf 'RDP_USERNAME=%s' "$USER_NAME" > RDP_USERNAME.txt
printf 'RDP_PASSWORD=%s' "$PASSWORD" > RDP_PASSWORD.txt
echo "[ARTIFACT] RDP_USERNAME=$USER_NAME"
echo "[ARTIFACT] RDP_PASSWORD=$PASSWORD"

# 7. Expose to GITHUB_ENV
if [ -n "${GITHUB_ENV:-}" ]; then
    echo "RDP_USER=$USER_NAME" >> "$GITHUB_ENV"
    echo "RDP_PASS=$PASSWORD"  >> "$GITHUB_ENV"
fi

log_ok "Ubuntu RDP setup complete"
