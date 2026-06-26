#!/bin/bash
# =============================================================================
# build-deb.sh — Build the github-rdp-toolkit Debian (.deb) package
# =============================================================================
# This script assembles a proper Debian package structure under a clean
# working directory, copies in the toolkit scripts, man pages, desktop entry,
# and bash completion, then invokes `dpkg-deb --build` to produce
# `github-rdp-toolkit_9.0.0_all.deb`.
#
# Usage:
#   ./build-deb.sh                # Build only
#   ./build-deb.sh --sign         # Build + GPG sign the .deb
#   ./build-deb.sh --sign-key FPR # Build + GPG sign with specific key
#
# Requirements (Kali / Debian):
#   - dpkg-deb (dpkg-dev)
#   - dpkg-sig (optional, for --sign)
#   - A working GPG key (optional)
#
# Exit codes:
#   0  success
#   1  general failure
#   2  missing dependency
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PKG_NAME="github-rdp-toolkit"
PKG_VERSION="9.0.0"
PKG_ARCH="all"
PKG_DIR="${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}"
DEB_FILE="${PKG_DIR}.deb"

# Resolve paths relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo root is ../../.. from platforms/kali/package/
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Source locations
TOOLKIT_SRC="${REPO_ROOT}"
DEBIAN_TMPL_DIR="${SCRIPT_DIR}/DEBIAN"
MAN_SRC="${SCRIPT_DIR}/man"
DESKTOP_SRC="${SCRIPT_DIR}/${PKG_NAME}.desktop"
COMPLETION_SRC="${SCRIPT_DIR}/rdp-toolkit-completion.bash"

# Build area
BUILD_ROOT="${SCRIPT_DIR}/build"
BUILD_DIR="${BUILD_ROOT}/${PKG_DIR}"

# Optional signing
DO_SIGN=0
GPG_KEY=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf '[build-deb] %s\n' "$*" >&2; }
err()  { printf '[build-deb][ERROR] %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign)
            DO_SIGN=1
            shift
            ;;
        --sign-key)
            DO_SIGN=1
            GPG_KEY="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,30p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
command -v dpkg-deb >/dev/null 2>&1 || die "dpkg-deb not found. Install 'dpkg-dev'."
command -v fakeroot   >/dev/null 2>&1 || log "WARNING: fakeroot not found; building as regular user."

if [[ ! -d "${DEBIAN_TMPL_DIR}" ]]; then
    die "DEBIAN template dir not found: ${DEBIAN_TMPL_DIR}"
fi

# Make sure the toolkit source has the expected core/tools dirs
[[ -d "${TOOLKIT_SRC}" ]] || die "Toolkit source not found: ${TOOLKIT_SRC}"

# ---------------------------------------------------------------------------
# Clean & recreate the build tree
# ---------------------------------------------------------------------------
log "Cleaning previous build tree..."
rm -rf "${BUILD_ROOT}"
mkdir -p "${BUILD_DIR}"

# Standard filesystem layout inside the .deb (relative to /)
mkdir -p "${BUILD_DIR}/opt/${PKG_NAME}/core/bash"
mkdir -p "${BUILD_DIR}/opt/${PKG_NAME}/core/powershell"
mkdir -p "${BUILD_DIR}/opt/${PKG_NAME}/tools/bash"
mkdir -p "${BUILD_DIR}/opt/${PKG_NAME}/tools/python"
mkdir -p "${BUILD_DIR}/opt/${PKG_NAME}/configs"
mkdir -p "${BUILD_DIR}/opt/${PKG_NAME}/platforms/kali"
mkdir -p "${BUILD_DIR}/usr/share/man/man1"
mkdir -p "${BUILD_DIR}/usr/share/applications"
mkdir -p "${BUILD_DIR}/etc/bash_completion.d"
mkdir -p "${BUILD_DIR}/etc/github-rdp-toolkit"

# ---------------------------------------------------------------------------
# DEBIAN control files
# ---------------------------------------------------------------------------
log "Writing DEBIAN control files..."
mkdir -p "${BUILD_DIR}/DEBIAN"

# Generate the control file from the template (substitute version etc.)
if [[ -f "${DEBIAN_TMPL_DIR}/control.template" ]]; then
    sed \
        -e "s|@PKG_NAME@|${PKG_NAME}|g" \
        -e "s|@PKG_VERSION@|${PKG_VERSION}|g" \
        -e "s|@PKG_ARCH@|${PKG_ARCH}|g" \
        "${DEBIAN_TMPL_DIR}/control.template" > "${BUILD_DIR}/DEBIAN/control"
else
    die "control.template not found in ${DEBIAN_TMPL_DIR}"
fi

# Copy maintainer scripts and make executable
for f in postinst prerm postrm preinst; do
    if [[ -f "${DEBIAN_TMPL_DIR}/${f}" ]]; then
        install -m 0755 "${DEBIAN_TMPL_DIR}/${f}" "${BUILD_DIR}/DEBIAN/${f}"
    fi
done

# conffiles (preserve user edits)
if [[ -f "${DEBIAN_TMPL_DIR}/conffiles" ]]; then
    install -m 0644 "${DEBIAN_TMPL_DIR}/conffiles" "${BUILD_DIR}/DEBIAN/conffiles"
fi

# Optional changelog, triggers
for opt in changelog triggers templates; do
    if [[ -f "${DEBIAN_TMPL_DIR}/${opt}" ]]; then
        install -m 0644 "${DEBIAN_TMPL_DIR}/${opt}" "${BUILD_DIR}/DEBIAN/${opt}"
    fi
done

# ---------------------------------------------------------------------------
# Copy toolkit scripts into /opt/github-rdp-toolkit/
# ---------------------------------------------------------------------------
log "Copying toolkit scripts into /opt/${PKG_NAME}/..."

# Core bash scripts
if [[ -d "${TOOLKIT_SRC}/core/bash" ]]; then
    cp -r "${TOOLKIT_SRC}/core/bash/." "${BUILD_DIR}/opt/${PKG_NAME}/core/bash/" 2>/dev/null || true
fi
# Core powershell (kept for cross-platform completeness)
if [[ -d "${TOOLKIT_SRC}/core/powershell" ]]; then
    cp -r "${TOOLKIT_SRC}/core/powershell/." "${BUILD_DIR}/opt/${PKG_NAME}/core/powershell/" 2>/dev/null || true
fi
# Tools — bash
if [[ -d "${TOOLKIT_SRC}/tools/bash" ]]; then
    cp -r "${TOOLKIT_SRC}/tools/bash/." "${BUILD_DIR}/opt/${PKG_NAME}/tools/bash/" 2>/dev/null || true
fi
# Tools — python
if [[ -d "${TOOLKIT_SRC}/tools/python" ]]; then
    cp -r "${TOOLKIT_SRC}/tools/python/." "${BUILD_DIR}/opt/${PKG_NAME}/tools/python/" 2>/dev/null || true
fi
# Configs
if [[ -d "${TOOLKIT_SRC}/configs" ]]; then
    cp -r "${TOOLKIT_SRC}/configs/." "${BUILD_DIR}/opt/${PKG_NAME}/configs/" 2>/dev/null || true
fi
# Kali platform files
if [[ -d "${TOOLKIT_SRC}/platforms/kali/configs" ]]; then
    cp -r "${TOOLKIT_SRC}/platforms/kali/configs" "${BUILD_DIR}/opt/${PKG_NAME}/platforms/kali/" 2>/dev/null || true
fi
if [[ -d "${TOOLKIT_SRC}/platforms/kali/scripts" ]]; then
    cp -r "${TOOLKIT_SRC}/platforms/kali/scripts" "${BUILD_DIR}/opt/${PKG_NAME}/platforms/kali/" 2>/dev/null || true
fi

# Copy version.txt
if [[ -f "${TOOLKIT_SRC}/version.txt" ]]; then
    install -m 0644 "${TOOLKIT_SRC}/version.txt" "${BUILD_DIR}/opt/${PKG_NAME}/version.txt"
else
    echo "${PKG_VERSION}" > "${BUILD_DIR}/opt/${PKG_NAME}/version.txt"
fi

# Make all scripts executable
find "${BUILD_DIR}/opt/${PKG_NAME}" -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} +
log "All .sh and .py files marked executable."

# ---------------------------------------------------------------------------
# Man pages → /usr/share/man/man1/
# ---------------------------------------------------------------------------
log "Installing man pages..."
if [[ -d "${MAN_SRC}" ]]; then
    for manpage in "${MAN_SRC}"/*.1; do
        [[ -f "${manpage}" ]] || continue
        install -m 0644 "${manpage}" "${BUILD_DIR}/usr/share/man/man1/"
        # Compress man pages with gzip (Debian policy)
        gzip -9n "${BUILD_DIR}/usr/share/man/man1/$(basename "${manpage}")"
    done
fi

# ---------------------------------------------------------------------------
# Desktop entry → /usr/share/applications/
# ---------------------------------------------------------------------------
log "Installing desktop entry..."
if [[ -f "${DESKTOP_SRC}" ]]; then
    install -m 0644 "${DESKTOP_SRC}" "${BUILD_DIR}/usr/share/applications/$(basename "${DESKTOP_SRC}")"
fi

# ---------------------------------------------------------------------------
# Bash completion → /etc/bash_completion.d/
# ---------------------------------------------------------------------------
log "Installing bash completion..."
if [[ -f "${COMPLETION_SRC}" ]]; then
    install -m 0644 "${COMPLETION_SRC}" "${BUILD_DIR}/etc/bash_completion.d/rdp-toolkit"
fi

# ---------------------------------------------------------------------------
# System-wide config files (conffiles)
# ---------------------------------------------------------------------------
log "Installing system-wide config defaults..."
cat > "${BUILD_DIR}/etc/github-rdp-toolkit/config.env" <<EOF
# github-rdp-toolkit system-wide defaults
# Edit this file to change defaults; it will be preserved on upgrade.
GITHUB_RDP_TOOLKIT_HOME=/opt/${PKG_NAME}
GITHUB_RDP_DEFAULT_TUNNEL=serveo
GITHUB_RDP_DEFAULT_DESKTOP=xfce
GITHUB_RDP_SSH_PORT=3389
GITHUB_RDP_PERSISTENCE=false
EOF
chmod 0644 "${BUILD_DIR}/etc/github-rdp-toolkit/config.env"

# ---------------------------------------------------------------------------
# Verify DEBIAN/control syntax
# ---------------------------------------------------------------------------
log "Verifying DEBIAN/control syntax..."
if ! dpkg-checkbuilddeps >/dev/null 2>&1; then
    : # dpkg-checkbuilddeps checks build-deps, not strictly required for our control
fi

# Basic field validation
if ! grep -qE '^Package:' "${BUILD_DIR}/DEBIAN/control"; then
    die "control file missing Package field"
fi
if ! grep -qE '^Version:' "${BUILD_DIR}/DEBIAN/control"; then
    die "control file missing Version field"
fi
if ! grep -qE '^Architecture:' "${BUILD_DIR}/DEBIAN/control"; then
    die "control file missing Architecture field"
fi
if ! grep -qE '^Maintainer:' "${BUILD_DIR}/DEBIAN/control"; then
    die "control file missing Maintainer field"
fi
if ! grep -qE '^Description:' "${BUILD_DIR}/DEBIAN/control"; then
    die "control file missing Description field"
fi
log "Control file OK."

# Compute Installed-Size (kB) and inject it
INSTALLED_SIZE=$(du -sk "${BUILD_DIR}" | awk '{print $1}')
# Insert Installed-Size after Architecture line
if ! grep -q '^Installed-Size:' "${BUILD_DIR}/DEBIAN/control"; then
    sed -i "/^Architecture:/a Installed-Size: ${INSTALLED_SIZE}" "${BUILD_DIR}/DEBIAN/control"
fi
log "Installed-Size: ${INSTALLED_SIZE} kB"

# ---------------------------------------------------------------------------
# Fix ownership to root:root (best-effort; falls back gracefully)
# ---------------------------------------------------------------------------
if [[ "$(id -u)" -eq 0 ]]; then
    chown -R root:root "${BUILD_DIR}"
elif command -v fakeroot >/dev/null 2>&1; then
    : # fakeroot wraps the dpkg-deb step below
fi

# ---------------------------------------------------------------------------
# Build the .deb
# ---------------------------------------------------------------------------
log "Building ${DEB_FILE}..."
if command -v fakeroot >/dev/null 2>&1 && [[ "$(id -u)" -ne 0 ]]; then
    fakeroot dpkg-deb --build --root-owner-group "${BUILD_DIR}" "${BUILD_ROOT}/${DEB_FILE}"
else
    dpkg-deb --build --root-owner-group "${BUILD_DIR}" "${BUILD_ROOT}/${DEB_FILE}"
fi

log "Built: ${BUILD_ROOT}/${DEB_FILE}"

# ---------------------------------------------------------------------------
# Verify the package
# ---------------------------------------------------------------------------
log "Verifying package..."
dpkg-deb --info  "${BUILD_ROOT}/${DEB_FILE}" >/dev/null || die "dpkg-deb --info failed"
dpkg-deb --contents "${BUILD_ROOT}/${DEB_FILE}" >/dev/null || die "dpkg-deb --contents failed"
log "Package verified OK."

# Optionally lint with lintian if available
if command -v lintian >/dev/null 2>&1; then
    log "Running lintian (warnings are non-fatal)..."
    lintian --no-tag-display-limit --fail-on error "${BUILD_ROOT}/${DEB_FILE}" || \
        log "lintian reported issues (review above)."
else
    log "lintian not installed; skipping deeper lint."
fi

# ---------------------------------------------------------------------------
# Optional GPG signing (via dpkg-sig)
# ---------------------------------------------------------------------------
if [[ "${DO_SIGN}" -eq 1 ]]; then
    if ! command -v dpkg-sig >/dev/null 2>&1; then
        err "dpkg-sig not installed; cannot sign. Run: sudo apt-get install dpkg-sig"
        exit 2
    fi
    log "Signing package with GPG..."
    SIGN_ARGS=("--sign" "builder")
    if [[ -n "${GPG_KEY}" ]]; then
        SIGN_ARGS+=("--gpg-options=--local-user=${GPG_KEY}")
    fi
    dpkg-sig "${SIGN_ARGS[@]}" "${BUILD_ROOT}/${DEB_FILE}" || die "GPG signing failed."
    log "Package signed."
fi

# ---------------------------------------------------------------------------
# Done — emit summary
# ---------------------------------------------------------------------------
log "----------------------------------------"
log " Build complete"
log "----------------------------------------"
log " Package:  ${BUILD_ROOT}/${DEB_FILE}"
log " Size:     $(du -h "${BUILD_ROOT}/${DEB_FILE}" | awk '{print $1}')"
log " Install:  sudo dpkg -i ${BUILD_ROOT}/${DEB_FILE}"
log " Inspect:  dpkg-deb -c ${BUILD_ROOT}/${DEB_FILE}"
log "----------------------------------------"
exit 0
