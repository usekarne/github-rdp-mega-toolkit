#!/usr/bin/env bash
# tools/bash/install.sh - Universal installer for Linux/Mac
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_DIR="${1:-/opt/github-rdp-toolkit}"

echo "============================================================"
echo "  GitHub RDP Mega Toolkit v9.0 - Installer"
echo "============================================================"
echo "  Install dir: $INSTALL_DIR"
echo "============================================================"

# Check root
if [ "$(id -u)" -ne 0 ]; then
    echo "[WARN] Not running as root. Some features may not work."
    echo "       Re-run with: sudo $0 $@"
fi

# Create install dir
mkdir -p "$INSTALL_DIR"

# Copy files
echo "[1/6] Copying files..."
cp -r "$REPO_DIR/core" "$INSTALL_DIR/"
cp -r "$REPO_DIR/tools" "$INSTALL_DIR/"
cp -r "$REPO_DIR/configs" "$INSTALL_DIR/"
cp -r "$REPO_DIR/platforms" "$INSTALL_DIR/"
cp -r "$REPO_DIR/skills" "$INSTALL_DIR/"
cp "$REPO_DIR/version.txt" "$INSTALL_DIR/"
echo "  OK"

# Make scripts executable
echo "[2/6] Setting permissions..."
chmod +x "$INSTALL_DIR"/core/bash/*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR"/tools/bash/*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR"/tools/python/*.py 2>/dev/null || true
echo "  OK"

# Install dependencies
echo "[3/6] Checking dependencies..."
if command -v apt-get &>/dev/null; then
    apt-get update -qq
    apt-get install -y -qq freerdp2-x11 python3 curl openssh-client 2>&1 | tail -2
elif command -v dnf &>/dev/null; then
    dnf install -y freerdp python3 curl openssh-clients 2>&1 | tail -2
elif command -v pacman &>/dev/null; then
    pacman -S --noconfirm freerdp python3 curl openssh 2>&1 | tail -2
fi
echo "  OK"

# Create symlinks
echo "[4/6] Creating symlinks..."
ln -sf "$INSTALL_DIR/tools/bash/rdp-cli.sh" /usr/local/bin/rdp-toolkit 2>/dev/null || true
ln -sf "$INSTALL_DIR/tools/python/fetch-creds.py" /usr/local/bin/rdp-fetch-creds 2>/dev/null || true
ln -sf "$INSTALL_DIR/tools/bash/tunnel-bridge.sh" /usr/local/bin/rdp-bridge 2>/dev/null || true
echo "  OK"

# Bash completion
echo "[5/6] Installing bash completion..."
if [ -d /etc/bash_completion.d ]; then
    cat > /etc/bash_completion.d/rdp-toolkit <<'EOF'
_rdp_toolkit_completion() {
    local cmds="trigger status runs fetch connect save kill kill-run watch help"
    COMPREPLY=($(compgen -W "$cmds" -- "${COMP_WORDS[1]}"))
}
complete -F _rdp_toolkit_completion rdp-toolkit
EOF
fi
echo "  OK"

# Verify
echo "[6/6] Verifying installation..."
if command -v rdp-toolkit &>/dev/null; then
    echo "  OK - rdp-toolkit is in PATH"
else
    echo "  WARN - rdp-toolkit not in PATH. Add $INSTALL_DIR/tools/bash to your PATH."
fi

echo ""
echo "============================================================"
echo "  Installation complete!"
echo "============================================================"
echo ""
echo "  Next steps:"
echo "    1. Set your GitHub PAT:"
echo "       export GH_PAT=ghp_your_token_here"
echo "    2. Trigger an RDP session:"
echo "       rdp-toolkit trigger lite-rdp.yml"
echo "    3. Watch for credentials:"
echo "       rdp-toolkit watch"
echo "    4. Connect:"
echo "       rdp-toolkit connect"
echo ""
