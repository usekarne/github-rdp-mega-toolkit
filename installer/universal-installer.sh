#!/usr/bin/env bash
# installer/universal-installer.sh - Detects OS and runs appropriate installer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================================"
echo "  GitHub RDP Mega Toolkit v9.0 - Universal Installer"
echo "============================================================"

# Detect OS
OS="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_LIKE="${ID_LIKE:-}"
    case "$OS_ID" in
        kali)    OS="kali" ;;
        ubuntu)  OS="ubuntu" ;;
        debian)  OS="debian" ;;
        arch)    OS="arch" ;;
        *)       case "$OS_LIKE" in
                     *debian*) OS="debian" ;;
                     *arch*)   OS="arch" ;;
                     *)        OS="linux" ;;
                 esac ;;
    esac
elif [ "$(uname)" = "Darwin" ]; then
    OS="macos"
elif [ -n "${TERMUX_VERSION:-}" ]; then
    OS="termux"
fi

echo "  Detected OS: $OS"
echo "============================================================"
echo ""

case "$OS" in
    kali|ubuntu|debian)
        echo "[INFO] Installing for Debian-based Linux ($OS)..."
        bash "$REPO_DIR/tools/bash/install.sh" /opt/github-rdp-toolkit
        ;;
    arch)
        echo "[INFO] Installing for Arch Linux..."
        bash "$REPO_DIR/tools/bash/install.sh" /opt/github-rdp-toolkit
        ;;
    macos)
        echo "[INFO] Installing for macOS..."
        if command -v brew &>/dev/null; then
            brew install freerdp python3 curl openssh
        fi
        bash "$REPO_DIR/tools/bash/install.sh" /usr/local/github-rdp-toolkit
        ;;
    termux)
        echo "[INFO] Installing for Termux (Android)..."
        bash "$REPO_DIR/platforms/android/scripts/setup-termux.sh"
        ;;
    *)
        echo "[WARN] Unknown OS. Attempting generic Linux install..."
        bash "$REPO_DIR/tools/bash/install.sh" /opt/github-rdp-toolkit
        ;;
esac

echo ""
echo "============================================================"
echo "  Installation complete!"
echo "============================================================"
echo ""
echo "  Set your GitHub PAT:"
echo "    export GH_PAT=ghp_your_token_here"
echo ""
echo "  Then trigger a session:"
echo "    rdp-toolkit trigger lite-rdp.yml"
echo "    rdp-toolkit watch"
echo ""
