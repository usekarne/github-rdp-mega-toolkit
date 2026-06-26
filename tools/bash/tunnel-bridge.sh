#!/usr/bin/env bash
# tools/bash/tunnel-bridge.sh - Client-side Cloudflare tunnel bridge for xfreerdp
# Use this when the GitHub workflow fell back to Cloudflare (no direct host:port)
set -euo pipefail

HOST="${1:?usage: tunnel-bridge.sh <trycloudflare-hostname> [local_port]}"
LOCAL_PORT="${2:-33890}"

# Check if cloudflared is installed
if ! command -v cloudflared &>/dev/null; then
    echo "[ERROR] cloudflared is not installed."
    echo ""
    echo "Install it first:"
    echo "  # Debian/Ubuntu/Kali:"
    echo "  curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared"
    echo "  chmod +x /usr/local/bin/cloudflared"
    echo "  # OR via apt:  sudo apt install cloudflared"
    exit 1
fi

# Strip protocol if user pasted full URL
HOST="${HOST#https://}"
HOST="${HOST#http://}"

echo "============================================================"
echo "  Cloudflare RDP Tunnel Bridge (v9.0)"
echo "============================================================"
echo "  Remote host : $HOST"
echo "  Local port  : localhost:$LOCAL_PORT"
echo "  Connect with: xfreerdp /v:localhost:$LOCAL_PORT /u:runner /p:PASSWORD /cert:ignore +clipboard +auto-reconnect /size:1280x720"
echo "============================================================"
echo ""
echo "Press Ctrl+C to stop the bridge."
echo ""

exec cloudflared access tcp --hostname "$HOST" --url "localhost:$LOCAL_PORT"
