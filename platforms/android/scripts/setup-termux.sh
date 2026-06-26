#!/data/data/com.termux/files/usr/bin/bash
# platforms/android/scripts/setup-termux.sh - One-shot Termux setup for RDP toolkit
set -euo pipefail

echo "============================================================"
echo "  GitHub RDP Mega Toolkit v9.0 - Termux Setup"
echo "============================================================"

# 1. Update packages
echo "[1/6] Updating packages..."
pkg update -y && pkg upgrade -y

# 2. Install core dependencies
echo "[2/6] Installing dependencies..."
pkg install -y openssh curl python git x11-repo
pkg install -y freerdp

# 3. Setup storage access
echo "[3/6] Setting up storage..."
termux-setup-storage 2>/dev/null || true

# 4. Create config directory
echo "[4/6] Creating config directory..."
mkdir -p ~/.github-rdp-toolkit

# 5. Install cloudflared for Android (arm64)
echo "[5/6] Installing cloudflared..."
ARCH=$(uname -m)
case "$ARCH" in
    aarch64) CF_ARCH="arm64" ;;
    armv7l)  CF_ARCH="arm" ;;
    x86_64)  CF_ARCH="amd64" ;;
    *)       CF_ARCH="amd64" ;;
esac
curl -sL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -o $PREFIX/bin/cloudflared
chmod +x $PREFIX/bin/cloudflared

# 6. Create CLI symlink
echo "[6/6] Creating CLI shortcut..."
cat > $PREFIX/bin/rdp-toolkit <<'WRAPPER'
#!/data/data/com.termux/files/usr/bin/bash
exec python3 "$HOME/github-rdp-mega-toolkit/tools/python/rdp-cli.py" "$@"
WRAPPER
chmod +x $PREFIX/bin/rdp-toolkit

echo ""
echo "============================================================"
echo "  Termux setup complete!"
echo "============================================================"
echo ""
echo "  Next steps:"
echo "    1. export GH_PAT=ghp_your_token"
echo "    2. rdp-toolkit trigger lite-rdp.yml"
echo "    3. rdp-toolkit watch"
echo "    4. rdp-toolkit connect"
echo ""
echo "  NOTE: Run 'termux-wake-lock' before long sessions to prevent"
echo "        Android from killing the process."
echo ""
