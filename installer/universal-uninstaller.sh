#!/usr/bin/env bash
# installer/universal-uninstaller.sh - Detects OS and runs appropriate uninstaller
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================================"
echo "  GitHub RDP Mega Toolkit v9.0 - Universal Uninstaller"
echo "============================================================"

# Detect install location
if [ -d /opt/github-rdp-toolkit ]; then
    INSTALL_DIR="/opt/github-rdp-toolkit"
elif [ -d /usr/local/github-rdp-toolkit ]; then
    INSTALL_DIR="/usr/local/github-rdp-toolkit"
else
    echo "[WARN] Toolkit installation not found."
    exit 0
fi

echo "  Removing: $INSTALL_DIR"
bash "$REPO_DIR/tools/bash/uninstall.sh" "$INSTALL_DIR"

echo "  Done."
