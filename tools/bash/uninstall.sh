#!/usr/bin/env bash
# tools/bash/uninstall.sh - Universal uninstaller
set -euo pipefail

INSTALL_DIR="${1:-/opt/github-rdp-toolkit}"

echo "============================================================"
echo "  GitHub RDP Mega Toolkit v9.0 - Uninstaller"
echo "============================================================"
echo "  Removing: $INSTALL_DIR"
echo "============================================================"

# Remove symlinks
rm -f /usr/local/bin/rdp-toolkit 2>/dev/null || true
rm -f /usr/local/bin/rdp-fetch-creds 2>/dev/null || true
rm -f /usr/local/bin/rdp-bridge 2>/dev/null || true

# Remove bash completion
rm -f /etc/bash_completion.d/rdp-toolkit 2>/dev/null || true

# Remove install dir
rm -rf "$INSTALL_DIR"

echo "  Done. Toolkit removed."
