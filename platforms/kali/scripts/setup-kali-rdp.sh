#!/usr/bin/env bash
# platforms/kali/scripts/setup-kali-rdp.sh - Full Kali RDP setup with XFCE + xrdp
set -euo pipefail

USER_NAME="${RDP_USER:-runner}"
PASSWORD="${RDP_MASTER_PASSWORD:-$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9!@#$%' | head -c 24)}"

echo "============================================================"
echo "  Kali Linux RDP Setup v9.0"
echo "============================================================"

# 1. Install xrdp + XFCE
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq xrdp xfce4 xfce4-goodies dbus-x11 kali-defaults 2>&1 | tail -3

# 2. Create user
if ! id "$USER_NAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USER_NAME"
    echo "${USER_NAME}:${PASSWORD}" | chpasswd
    usermod -aG sudo "$USER_NAME"
    echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USER_NAME}"
fi

# 3. Configure XFCE session
echo "startxfce4" > "/home/${USER_NAME}/.xsession"
chown "$USER_NAME:$USER_NAME" "/home/${USER_NAME}/.xsession"

# 4. xrdp config
sed -i 's/^port=.*/port=3389/' /etc/xrdp/xrdp.ini
systemctl enable xrdp
systemctl restart xrdp

# 5. Wait for port 3389
for i in $(seq 1 15); do
    if ss -tln | grep -q ':3389 '; then
        echo "[OK] Port 3389 listening"
        break
    fi
    sleep 2
done

# 6. Save credentials
printf '%s' "$PASSWORD" > rdp-password.txt
printf 'RDP_USERNAME=%s' "$USER_NAME" > RDP_USERNAME.txt
printf 'RDP_PASSWORD=%s' "$PASSWORD" > RDP_PASSWORD.txt

echo "============================================================"
echo "  Kali RDP ready - user=$USER_NAME"
echo "  Password: $PASSWORD"
echo "============================================================"
