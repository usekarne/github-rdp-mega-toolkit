#!/usr/bin/env bash
# install.sh — Universal installer for RDP Mega Toolkit (Linux / macOS / WSL)
# Idempotent: safe to re-run.
set -euo pipefail

PKG_NAME="rdp-toolkit"
VERSION="9.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SRC_DIR="${PROJECT_ROOT}/rdp_toolkit"
COMPLETIONS_SRC="${PROJECT_ROOT}/completions"

# ----- detect environment ---------------------------------------------------
OS="$(uname -s)"
case "${OS}" in
    Linux*)  PLATFORM="linux";;
    Darwin*) PLATFORM="macos";;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="windows-wsl";;
    *) echo "ERROR: Unsupported OS: ${OS}" >&2; exit 1;;
esac
if grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
    PLATFORM="wsl"
fi

# System vs user install
if [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
    SYS_INSTALL=1
    OPT_DIR="/opt/rdp-toolkit"
    BIN_DIR="/usr/local/bin"
    COMP_DIR_BASH="/etc/bash_completion.d"
    COMP_DIR_ZSH="/usr/local/share/zsh/site-functions"
else
    SYS_INSTALL=0
    OPT_DIR="${HOME}/.local/share/rdp-toolkit"
    BIN_DIR="${HOME}/.local/bin"
    COMP_DIR_BASH="${HOME}/.local/share/bash-completion/completions"
    COMP_DIR_ZSH="${HOME}/.local/share/zsh/site-functions"
fi

echo "[install] Platform: ${PLATFORM} | System: ${SYS_INSTALL} | Dir: ${OPT_DIR}"

# ----- detect package manager & install deps --------------------------------
detect_pkgmgr() {
    for pm in apt dnf yum pacman zypper brew; do
        command -v "${pm}" >/dev/null 2>&1 && { echo "${pm}"; return 0; }
    done
    echo "none"; return 1
}
PKGMGR="$(detect_pkgmgr || echo none)"
echo "[install] Package manager: ${PKGMGR}"

echo "[install] Installing deps (python3, openssh, freerdp, pyyaml)..."
case "${PKGMGR}" in
    apt)  sudo apt update -y && sudo apt install -y python3 python3-yaml openssh-client freerdp2-x11;;
    dnf|yum) sudo "${PKGMGR}" install -y python3 python3-pyyaml openssh-clients freerdp;;
    pacman)  sudo pacman -S --noconfirm --needed python python-yaml openssh freerdp;;
    zypper)  sudo zypper install -y python3 python3-PyYAML openssh freerdp;;
    brew)    brew install python pyyaml openssh freerdp;;
    none)    echo "[install] No supported pkgmgr; skipping dep install." >&2;;
esac

if ! command -v cloudflared >/dev/null 2>&1; then
    echo "[install] cloudflared not found (optional). Install manually for cloudflare tunnels."
fi

# ----- stage application ----------------------------------------------------
echo "[install] Staging ${PKG_NAME} -> ${OPT_DIR}"
if [ "${SYS_INSTALL}" -eq 1 ]; then
    sudo mkdir -p "${OPT_DIR}"
    sudo rm -rf "${OPT_DIR}/rdp_toolkit"
    sudo cp -a "${SRC_DIR}" "${OPT_DIR}/rdp_toolkit"
    CP="sudo"
else
    mkdir -p "${OPT_DIR}"
    rm -rf "${OPT_DIR}/rdp_toolkit"
    cp -a "${SRC_DIR}" "${OPT_DIR}/rdp_toolkit"
    CP=""
fi

# ----- launcher -------------------------------------------------------------
mkdir -p "${BIN_DIR}"
LAUNCHER="${BIN_DIR}/rdp-toolkit"
echo "[install] Writing launcher: ${LAUNCHER}"
cat > "${LAUNCHER}" <<EOF
#!/usr/bin/env bash
export PYTHONPATH="${OPT_DIR}:\${PYTHONPATH:-}"
exec python3 -m rdp_toolkit "\$@"
EOF
chmod 0755 "${LAUNCHER}"

# ----- completions ----------------------------------------------------------
mkdir -p "${COMP_DIR_BASH}" "${COMP_DIR_ZSH}"
if [ -f "${COMPLETIONS_SRC}/rdp-toolkit.bash" ]; then
    cp -f "${COMPLETIONS_SRC}/rdp-toolkit.bash" "${COMP_DIR_BASH}/rdp-toolkit"
else
    cat > "${COMP_DIR_BASH}/rdp-toolkit" <<'EOF'
_rdp_toolkit_completion() {
    local cur words
    cur="${COMP_WORDS[COMP_CWORD]}"
    words="doctor config tunnel vm rdp session start stop status notify --help --version"
    COMPREPLY=( $(compgen -W "${words}" -- "${cur}") )
}
complete -F _rdp_toolkit_completion rdp-toolkit
EOF
fi
cat > "${COMP_DIR_ZSH}/_rdp-toolkit" <<'EOF'
#compdef rdp-toolkit
_rdp_toolkit() {
    local words="doctor config tunnel vm rdp session start stop status notify --help --version"
    _arguments "*: :(${words})"
}
_rdp_toolkit "$@"
EOF
echo "[install] Bash/zsh completions installed."

# ----- ensure PATH has the launcher dir (best effort) ----------------------
case ":${PATH}:" in
    *":${BIN_DIR}:"*) ;;
    *)
        echo "[install] NOTE: ${BIN_DIR} is not in your PATH. Add this to your shell rc:"
        echo "          export PATH=\"${BIN_DIR}:\$PATH\""
        ;;
esac

# ----- run doctor -----------------------------------------------------------
echo
echo "=================================================="
echo " ${PKG_NAME} v${VERSION} installed!"
echo "=================================================="
echo " Running doctor..."
echo

if "${LAUNCHER}" doctor; then
    echo
    echo "[install] Doctor OK. Run: rdp-toolkit --help"
else
    echo "[install] Doctor reported issues. See output above." >&2
    exit 1
fi
