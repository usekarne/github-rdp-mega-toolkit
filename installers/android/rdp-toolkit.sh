#!/usr/bin/env bash
# rdp-toolkit.sh — Termux wrapper that invokes the Python package.
# This file is copied to $PREFIX/bin/rdp-toolkit by setup-termux.sh
# and may be re-written by the installer to embed the absolute lib path.
set -euo pipefail

# Locate the installed rdp_toolkit package.
# Order of preference:
#   1. PYTHONPATH already set by caller
#   2. $PREFIX/share/rdp-toolkit/  (Termux default install location)
#   3. ./rdp_toolkit (development checkout)
PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
LIB_DIR="${PREFIX_DIR}/share/rdp-toolkit"

if [ -d "${LIB_DIR}/rdp_toolkit" ]; then
    export PYTHONPATH="${LIB_DIR}:${PYTHONPATH:-}"
elif [ -d "$(pwd)/rdp_toolkit" ]; then
    export PYTHONPATH="$(pwd):${PYTHONPATH:-}"
fi

# Locate python3 (Termux ships `python`, others may ship `python3`)
if command -v python3 >/dev/null 2>&1; then
    PY=python3
elif command -v python >/dev/null 2>&1; then
    PY=python
else
    echo "ERROR: python3 not found. Run: pkg install python" >&2
    exit 127
fi

if ! "${PY}" -c "import rdp_toolkit" >/dev/null 2>&1; then
    echo "ERROR: rdp_toolkit package not importable." >&2
    echo "       Set PYTHONPATH or re-run setup-termux.sh." >&2
    exit 1
fi

exec "${PY}" -m rdp_toolkit "$@"
