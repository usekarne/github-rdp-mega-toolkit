#!/usr/bin/env bash
# uninstall.sh — Universal uninstaller for RDP Mega Toolkit
set -euo pipefail

PKG_NAME="rdp-toolkit"

# ----- locate install dir ---------------------------------------------------
if [ -d "/opt/rdp-toolkit" ]; then
    OPT_DIR="/opt/rdp-toolkit"
    SYS_INSTALL=1
elif [ -d "${HOME}/.local/share/rdp-toolkit" ]; then
    OPT_DIR="${HOME}/.local/share/rdp-toolkit"
    SYS_INSTALL=0
else
    echo "[uninstall] ${PKG_NAME} does not appear to be installed. Nothing to do."
    exit 0
fi

if [ "${SYS_INSTALL}" -eq 1 ]; then
    SUDO="sudo"
    BIN_DIR="/usr/local/bin"
    COMP_BASH="/etc/bash_completion.d/rdp-toolkit"
    COMP_ZSH="/usr/local/share/zsh/site-functions/_rdp-toolkit"
else
    SUDO=""
    BIN_DIR="${HOME}/.local/bin"
    COMP_BASH="${HOME}/.local/share/bash-completion/completions/rdp-toolkit"
    COMP_ZSH="${HOME}/.local/share/zsh/site-functions/_rdp-toolkit"
fi

CONFIG_DIR="${HOME}/.config/rdp-toolkit"
LAUNCHER="${BIN_DIR}/rdp-toolkit"

echo "[uninstall] Install dir:  ${OPT_DIR}"
echo "[uninstall] Launcher:     ${LAUNCHER}"
echo "[uninstall] System mode:  ${SYS_INSTALL}"
echo

# ----- stop any running tunnels / processes ---------------------------------
echo "[uninstall] Stopping running ${PKG_NAME} processes..."
if [ -x "${LAUNCHER}" ]; then
    "${LAUNCHER}" tunnel stop-all >/dev/null 2>&1 || true
    "${LAUNCHER}" session stop-all >/dev/null 2>&1 || true
fi
pkill -f "rdp_toolkit" 2>/dev/null || true
pkill -f "rdp-toolkit" 2>/dev/null || true
sleep 1

# Kill stray tunnel helpers (cloudflared, ssh -R serveo, etc.)
pkill -f "cloudflared.*tunnel" 2>/dev/null || true
pkill -f "ssh.*-R 80:localhost" 2>/dev/null || true

# ----- remove install dir ---------------------------------------------------
echo "[uninstall] Removing ${OPT_DIR}"
${SUDO} rm -rf "${OPT_DIR}"

# ----- remove launcher ------------------------------------------------------
if [ -e "${LAUNCHER}" ] || [ -L "${LAUNCHER}" ]; then
    echo "[uninstall] Removing launcher: ${LAUNCHER}"
    ${SUDO} rm -f "${LAUNCHER}"
fi

# ----- remove completions ---------------------------------------------------
for f in "${COMP_BASH}" "${COMP_ZSH}"; do
    if [ -e "${f}" ] || [ -L "${f}" ]; then
        echo "[uninstall] Removing completion: ${f}"
        ${SUDO} rm -f "${f}"
    fi
done

# ----- optionally keep config dir -------------------------------------------
echo
if [ -d "${CONFIG_DIR}" ]; then
    if [ -t 0 ] && [ -t 1 ]; then
        read -r -p "Remove config directory ${CONFIG_DIR}? [y/N] " answer < /dev/tty
    else
        answer="N"
    fi
    case "${answer}" in
        y|Y|yes|YES)
            rm -rf "${CONFIG_DIR}"
            echo "[uninstall] Config directory removed."
            ;;
        *)
            echo "[uninstall] Config directory kept at ${CONFIG_DIR}"
            ;;
    esac
fi

echo
echo "=================================================="
echo " ${PKG_NAME} has been uninstalled."
echo "=================================================="
echo " Thank you for using RDP Mega Toolkit."
echo " Reinstall anytime: ./install.sh"
echo "=================================================="
