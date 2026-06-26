#!/usr/bin/env bash
# platforms/kali/scripts/install-kali-tools.sh - Install Kali security tools
set -euo pipefail

TOOLS="nmap wireshark metasploit-framework burpsuite sqlmap hydra john aircrack-ng gobuster dirb nikto whatweb wpscan masscan netcat-traditional tcpdump radare2 binwalk steghide exiftool hashcat crunch seclists wordlists"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

for tool in $TOOLS; do
    echo "[INFO] Installing $tool..."
    apt-get install -y -qq "$tool" 2>&1 | tail -1 && echo "[OK] $tool" || echo "[WARN] $tool failed"
done

echo "[OK] Kali tools installation complete"
