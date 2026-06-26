#!/data/data/com.termux/files/usr/bin/bash
# platforms/android/scripts/connect-android.sh - Connect to RDP from Termux
set -euo pipefail

CREDS_FILE="${HOME}/.github-rdp-toolkit/last-creds.json"

if [ ! -f "$CREDS_FILE" ]; then
    echo "[ERROR] No cached credentials. Run 'rdp-toolkit fetch' first."
    exit 1
fi

# Parse credentials
TUNNEL_TYPE=$(python3 -c "import json;d=json.load(open('$CREDS_FILE'));print(d.get('TUNNEL_TYPE',''))")
TUNNEL_HOST=$(python3 -c "import json;d=json.load(open('$CREDS_FILE'));print(d.get('TUNNEL_HOST',''))")
TUNNEL_PORT=$(python3 -c "import json;d=json.load(open('$CREDS_FILE'));print(d.get('TUNNEL_PORT',''))")
PASSWORD=$(python3 -c "import json;d=json.load(open('$CREDS_FILE'));print(d.get('RDP_PASSWORD',''))")

# Acquire wake lock to prevent Android from killing the process
termux-wake-lock 2>/dev/null || true

if [ "$TUNNEL_TYPE" = "cloudflare" ]; then
    echo "[INFO] Cloudflare tunnel - starting bridge..."
    # Start bridge in background
    nohup cloudflared access tcp --hostname "$TUNNEL_HOST" --url localhost:33890 > /dev/null 2>&1 &
    sleep 5
    xfreerdp /v:localhost:33890 /u:runner /p:"$PASSWORD" /cert:ignore +clipboard /size:1280x720
else
    # Direct connection (serveo/localhost.run)
    xfreerdp /v:"${TUNNEL_HOST}:${TUNNEL_PORT}" /u:runner /p:"$PASSWORD" /cert:ignore +clipboard /size:1280x720
fi

# Release wake lock
termux-wake-unlock 2>/dev/null || true
