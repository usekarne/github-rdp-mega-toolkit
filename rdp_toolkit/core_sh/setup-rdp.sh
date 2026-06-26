#!/usr/bin/env bash
# setup-rdp.sh — install xrdp + xfce4 (or kali-desktop-xfce on Kali),
# create the runner user, start xrdp.  Designed to be idempotent.
#
# NO NGROK.  Tunnel setup lives in setup-tunnel.sh.

set -euo pipefail
# shellcheck source=utils.sh
. "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

require_root

USERNAME="${RDP_USERNAME:-runner}"
PASSWORD="${RDP_MASTER_PASSWORD:-}"
LOCAL_PORT="${RDP_LOCAL_PORT:-3389}"

write_block "setup-rdp.sh — user=$USERNAME, port=$LOCAL_PORT"

# ---------------------------------------------------------------------------
# Generate password if not supplied
# ---------------------------------------------------------------------------
if [[ -z "$PASSWORD" ]]; then
    write_warn 'RDP_MASTER_PASSWORD env not set — generating a strong password.'
    PASSWORD="$(new_random_password 24)"
fi

# ---------------------------------------------------------------------------
# Detect distro and install the right package set
# ---------------------------------------------------------------------------
install_kali() {
    write_info 'Detected Kali Linux — installing kali-desktop-xfce + xrdp'
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends \
        kali-desktop-xfce xrdp xorgxrdp dbus-x11 policykit-1 \
        sudo curl ca-certificates
}

install_debian_ubuntu() {
    write_info 'Detected Debian/Ubuntu — installing xfce4 + xrdp'
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends \
        xfce4 xfce4-goodies xrdp xorgxrdp dbus-x11 \
        sudo curl ca-certificates
}

install_fedora() {
    write_info 'Detected Fedora/RHEL — installing xfce + xrdp'
    dnf install -y --setopt=install_weak_deps=False \
        @xfce-desktop-environment xrdp xorgxrdp dbus-x11 \
        sudo curl ca-certificates
}

install_arch() {
    write_info 'Detected Arch — installing xfce4 + xrdp'
    pacman -Sy --noconfirm --needed xfce4 xfce4-goodies xrdp xorgxrdp \
        sudo curl ca-certificates dbus
}

install_termux() {
    write_info 'Termux detected — installing proot RDP stack'
    pkg update -y
    pkg install -y x11-repo
    pkg install -y proot-distro termux-x11-nightly xfce4 xrdp \
        openssh curl ca-certificates
}

# ---------------------------------------------------------------------------
# Create / update the runner user
# ---------------------------------------------------------------------------
create_user() {
    write_info "Ensuring local user '$USERNAME' exists."
    if id "$USERNAME" >/dev/null 2>&1; then
        write_warn "User '$USERNAME' already exists — resetting password."
        echo "${USERNAME}:${PASSWORD}" | chpasswd
    else
        # --gecos '' avoids interactive finger info prompts.
        useradd -m -s /bin/bash -c 'RDP Runner' "$USERNAME"
        echo "${USERNAME}:${PASSWORD}" | chpasswd
    fi

    # Sudo (passwordless for the runner account — convenience on CI).
    if command -v usermod >/dev/null 2>&1; then
        if getent group sudo >/dev/null 2>&1; then
            usermod -aG sudo "$USERNAME" || true
        fi
        if getent group wheel >/dev/null 2>&1; then
            usermod -aG wheel "$USERNAME" || true
        fi
    fi

    # passwordless sudo for the runner
    local sudoers_file="/etc/sudoers.d/${USERNAME}"
    if [[ -d /etc/sudoers.d ]]; then
        echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "$sudoers_file"
        chmod 0440 "$sudoers_file"
    fi
    write_ok "User '$USERNAME' ready (passwordless sudo enabled)"
}

# ---------------------------------------------------------------------------
# Configure xrdp
# ---------------------------------------------------------------------------
configure_xrdp() {
    write_info 'Configuring xrdp to use xfce4'
    # Ensure the user's xsession is xfce4.
    local home_dir
    home_dir="$(getent passwd "$USERNAME" | cut -d: -f6)"
    if [[ -n "$home_dir" && -d "$home_dir" ]]; then
        echo 'xfce4-session' > "${home_dir}/.xsession"
        chown "$USERNAME:$USERNAME" "${home_dir}/.xsession"
        chmod 0644 "${home_dir}/.xsession"
    fi

    # /etc/xrdp/startwm.sh: ensure xfce4 is the default session.
    if [[ -f /etc/xrdp/startwm.sh ]]; then
        if ! grep -q 'xfce4-session' /etc/xrdp/startwm.sh; then
            sed -i '/^exec.*session$/d' /etc/xrdp/startwm.sh || true
            echo 'exec xfce4-session' >> /etc/xrdp/startwm.sh
        fi
    fi

    # Bind xrdp to localhost (tunnel will forward).  Default port 3389.
    if [[ -f /etc/xrdp/xrdp.ini ]]; then
        sed -i 's|^port=.*|port=3389|' /etc/xrdp/xrdp.ini
        sed -i 's|^usevsock=.*|usevsock=false|' /etc/xrdp/xrdp.ini
    fi

    # Security: use any bpp + disable bitmap compression off.
    if [[ -f /etc/xrdp/xrdp.ini ]]; then
        sed -i 's|^max_bpp=.*|max_bpp=32|' /etc/xrdp/xrdp.ini || true
    fi

    # Allow root if needed (not recommended but useful for some CI images).
    if [[ -f /etc/xrdp/sesman.ini ]]; then
        sed -i 's|^TerminalServerUsers=.*|TerminalServerUsers=|' /etc/xrdp/sesman.ini || true
        sed -i 's|^AlwaysGroupCheck=.*|AlwaysGroupCheck=false|' /etc/xrdp/sesman.ini || true
    fi
}

start_xrdp() {
    write_info 'Starting xrdp service'
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable xrdp 2>/dev/null || true
        systemctl restart xrdp 2>/dev/null || systemctl restart xrdp.service 2>/dev/null || true
        sleep 2
        if systemctl is-active --quiet xrdp; then
            write_ok 'xrdp is running (systemd)'
        else
            write_warn 'xrdp did not come up under systemd — trying direct.'
            xrdp-sesman || true
            xrdp || true
        fi
    else
        # SysV / no systemd (Alpine, some Termux proot)
        xrdp-sesman || true
        xrdp || true
    fi

    # Wait for port to come up.
    local tries=0
    while (( tries < 10 )); do
        if test_port 127.0.0.1 "$LOCAL_PORT" 1; then
            write_ok "xrdp listening on 127.0.0.1:$LOCAL_PORT"
            return 0
        fi
        sleep 1
        tries=$((tries+1))
    done
    write_warn "xrdp port $LOCAL_PORT did not come up in time."
}

# ---------------------------------------------------------------------------
# Persist credentials to artifact dir
# ---------------------------------------------------------------------------
persist_artifacts() {
    local dir
    dir="$(ensure_artifact_dir)"
    printf '%s' "$PASSWORD" > "${dir}/rdp-password.txt"
    printf '%s' "$USERNAME" > "${dir}/RDP_USERNAME.txt"
    printf '%s' "$PASSWORD" > "${dir}/RDP_PASSWORD.txt"

    local pub_ip
    pub_ip="$(get_public_ip)"

    cat > "${dir}/rdp-summary.json" <<EOF
{
  "username": "${USERNAME}",
  "port": ${LOCAL_PORT},
  "public_ip": "${pub_ip}",
  "host": "$(hostname)",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    chmod 0600 "${dir}/rdp-password.txt" "${dir}/RDP_PASSWORD.txt" 2>/dev/null || true
    write_ok "Wrote credentials to ${dir}"
}

# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
main() {
    if is_android_termux; then
        install_termux
    elif is_kali; then
        install_kali
    elif command -v apt-get >/dev/null 2>&1; then
        install_debian_ubuntu
    elif command -v dnf >/dev/null 2>&1; then
        install_fedora
    elif command -v pacman >/dev/null 2>&1; then
        install_arch
    else
        write_err 'Unsupported distro: cannot install xrdp automatically.'
        exit 1
    fi

    create_user
    configure_xrdp
    start_xrdp
    persist_artifacts

    send_notify "RDP ready on $(hostname) — user '${USERNAME}', port ${LOCAL_PORT}" 'RDP setup complete' || true

    write_block 'setup-rdp.sh complete'
}

main "$@"
