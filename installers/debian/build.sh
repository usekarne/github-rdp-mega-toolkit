#!/usr/bin/env bash
# build.sh — Build rdp-toolkit .deb package
# Usage:  ./build.sh   (from inside installers/debian/)
set -euo pipefail

PKG_NAME="rdp-toolkit"
VERSION="9.0.0"
ARCH="all"
BUILD_DIR="${PKG_NAME}_${VERSION}_${ARCH}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SRC_DIR="${PROJECT_ROOT}/rdp_toolkit"
SCRIPTS_SRC="${PROJECT_ROOT}/scripts"
COMPLETIONS_SRC="${PROJECT_ROOT}/completions"

# ----- preflight ------------------------------------------------------------
if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "ERROR: dpkg-deb is not installed. Run: sudo apt install dpkg-dev" >&2
    exit 1
fi

if [ ! -d "${SRC_DIR}" ]; then
    echo "ERROR: Source directory not found: ${SRC_DIR}" >&2
    echo "       Run this script from the project root or installers/debian/." >&2
    exit 1
fi

echo "[build] Cleaning previous build artifacts..."
rm -rf "${SCRIPT_DIR}/${BUILD_DIR}"

# ----- stage files ----------------------------------------------------------
DEBIAN_DIR="${SCRIPT_DIR}/${BUILD_DIR}/DEBIAN"
OPT_DIR="${SCRIPT_DIR}/${BUILD_DIR}/opt/rdp-toolkit"
ETC_DIR="${SCRIPT_DIR}/${BUILD_DIR}/etc/bash_completion.d"

mkdir -p "${DEBIAN_DIR}" "${OPT_DIR}" "${ETC_DIR}"

echo "[build] Staging DEBIAN control files..."
install -m 0644 "${SCRIPT_DIR}/control"   "${DEBIAN_DIR}/control"
install -m 0755 "${SCRIPT_DIR}/postinst"  "${DEBIAN_DIR}/postinst"
install -m 0755 "${SCRIPT_DIR}/prerm"     "${DEBIAN_DIR}/prerm"
install -m 0755 "${SCRIPT_DIR}/postrm"    "${DEBIAN_DIR}/postrm"

echo "[build] Staging application files into /opt/rdp-toolkit/ ..."
# Use rsync if available (clean excludes), fall back to cp + find prune
if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude '__pycache__' --exclude '*.pyc' \
          --exclude '.pytest_cache' --exclude '.mypy_cache' \
          "${SRC_DIR}/" "${OPT_DIR}/rdp_toolkit/"
else
    cp -a "${SRC_DIR}" "${OPT_DIR}/rdp_toolkit"
    find "${OPT_DIR}" -type d -name '__pycache__' -prune -exec rm -rf {} \; 2>/dev/null || true
    find "${OPT_DIR}" -type f -name '*.pyc' -delete 2>/dev/null || true
fi

if [ -d "${SCRIPTS_SRC}" ]; then
    mkdir -p "${OPT_DIR}/scripts"
    cp -a "${SCRIPTS_SRC}/." "${OPT_DIR}/scripts/"
    chmod 0755 "${OPT_DIR}/scripts/"*.sh 2>/dev/null || true
fi

if [ -d "${COMPLETIONS_SRC}" ]; then
    mkdir -p "${OPT_DIR}/completions"
    cp -a "${COMPLETIONS_SRC}/." "${OPT_DIR}/completions/"
fi

# Vendored bash completion fallback
if [ ! -f "${OPT_DIR}/completions/rdp-toolkit.bash" ]; then
    mkdir -p "${OPT_DIR}/completions"
    cat > "${OPT_DIR}/completions/rdp-toolkit.bash" <<'EOF'
_rdp_toolkit_completion() {
    local cur words
    cur="${COMP_WORDS[COMP_CWORD]}"
    words="doctor config tunnel vm rdp session start stop status notify --help --version"
    COMPREPLY=( $(compgen -W "${words}" -- "${cur}") )
}
complete -F _rdp_toolkit_completion rdp-toolkit
EOF
fi

# ----- fix permissions ------------------------------------------------------
echo "[build] Setting ownership & permissions..."
find "${SCRIPT_DIR}/${BUILD_DIR}" -type d -exec chmod 0755 {} \;
find "${OPT_DIR}" -type f -name '*.py' -exec chmod 0644 {} \;
find "${OPT_DIR}" -type f -name '*.sh' -exec chmod 0755 {} \;
# Maintain a launcher script
if [ ! -f "${OPT_DIR}/scripts/rdp-toolkit" ]; then
    mkdir -p "${OPT_DIR}/scripts"
    cat > "${OPT_DIR}/scripts/rdp-toolkit" <<'EOF'
#!/usr/bin/env bash
exec python3 -m rdp_toolkit "$@"
EOF
fi
chmod 0755 "${OPT_DIR}/scripts/rdp-toolkit"

# Set ownership to root:root if running as root (fakeroot-friendly)
if [ "$(id -u)" -eq 0 ]; then
    chown -R root:root "${SCRIPT_DIR}/${BUILD_DIR}"
fi

# ----- build ----------------------------------------------------------------
echo "[build] Building .deb package..."
(
    cd "${SCRIPT_DIR}"
    dpkg-deb --build --root-owner-group "${BUILD_DIR}"
)

DEB_FILE="${SCRIPT_DIR}/${BUILD_DIR}.deb"
if [ ! -f "${DEB_FILE}" ]; then
    echo "ERROR: .deb was not created." >&2
    exit 1
fi

echo
echo "=================================================="
echo " BUILD SUCCESS"
echo "=================================================="
echo " Output:  ${DEB_FILE}"
echo " Size:    $(du -h "${DEB_FILE}" | cut -f1)"
echo " Install: sudo apt install ./${BUILD_DIR}.deb"
echo "=================================================="
