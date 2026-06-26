#!/usr/bin/env bash
# installer/pre-install-check.sh - Check system requirements before install
set -euo pipefail

echo "=== Pre-Install System Check ==="
echo ""

PASS=0
FAIL=0

check() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo "  [OK]   $name"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $name"
        FAIL=$((FAIL + 1))
    fi
}

check "bash"      "command -v bash"
check "curl"      "command -v curl"
check "python3"   "command -v python3"
check "ssh"       "command -v ssh"
check "xfreerdp"  "command -v xfreerdp"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "[WARN] Some dependencies are missing. Install them before continuing:"
    echo "  Debian/Ubuntu/Kali: sudo apt install curl python3 openssh-client freerdp2-x11"
    echo "  Arch:               sudo pacman -S curl python3 openssh freerdp"
    echo "  macOS:              brew install curl python3 openssh freerdp"
    exit 1
fi

echo "[OK] All requirements met. Ready to install."
