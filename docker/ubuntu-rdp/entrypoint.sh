#!/usr/bin/env bash
# =============================================================================
# entrypoint.sh — Ubuntu RDP container bootstrap (rdp-mega-toolkit v9)
#   1. Create / configure the RDP user from env vars (RDP_USER, RDP_PASS).
#   2. Start sshd.
#   3. Start xrdp-sesman + xrdp on :3389.
#   4. Tail logs to keep the container alive.
#   5. Trap SIGTERM/SIGINT for clean shutdown.
# =============================================================================
set -euo pipefail

log() { printf '[entrypoint][%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >&2; }

: "${RDP_USER:=ubuntu}"
: "${RDP_PASS:=ubuntu}"
: "${RDP_UID:=1000}"
: "${RDP_GID:=1000}"
: "${ENABLE_SSH:=true}"
: "${ENABLE_XRDP:=true}"
: "${XRDP_PORT:=3389}"

log "Ubuntu RDP entrypoint starting"
log "user='${RDP_USER}' uid=${RDP_UID} gid=${RDP_GID} xrdp_port=${XRDP_PORT} ssh=${ENABLE_SSH}"

# ---------- user / group setup ------------------------------------------------
ensure_account() {
    local name="$1" uid="$2" gid="$3"
    if ! getent group "${name}" >/dev/null 2>&1; then groupadd -g "${gid}" "${name}"; fi
    if id -u "${name}" >/dev/null 2>&1; then
        usermod -u "${uid}" -g "${gid}" -d "/home/${name}" -s /bin/bash "${name}" 2>/dev/null || true
    else
        useradd -m -u "${uid}" -g "${gid}" -d "/home/${name}" -s /bin/bash "${name}"
    fi
}
ensure_account "${RDP_USER}" "${RDP_UID}" "${RDP_GID}"

# Rotate password on every boot so env-driven changes take effect.
echo "${RDP_USER}:${RDP_PASS}" | chpasswd
echo "${RDP_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${RDP_USER}"
chmod 0440 "/etc/sudoers.d/${RDP_USER}"

# Make sure every user gets an XFCE4 xsession.
mkdir -p "/home/${RDP_USER}"
[[ -f "/home/${RDP_USER}/.xsession" ]] \
    || cp /etc/skel/.xsession "/home/${RDP_USER}/.xsession" 2>/dev/null \
    || echo "xfce4-session" > "/home/${RDP_USER}/.xsession"
chown "${RDP_UID}:${RDP_GID}" "/home/${RDP_USER}/.xsession"
chmod +x "/home/${RDP_USER}/.xsession"

# ---------- runtime dirs ------------------------------------------------------
mkdir -p /run/sshd /run/xrdp /var/log/xrdp /var/lib/xrdp
ssh-keygen -A >/dev/null 2>&1 || true

# ---------- sshd --------------------------------------------------------------
if [[ "${ENABLE_SSH}" == "true" ]]; then
    log "starting sshd"
    /usr/sbin/sshd
else
    log "sshd disabled (ENABLE_SSH=${ENABLE_SSH})"
fi

# ---------- xrdp + signal handling -------------------------------------------
cleanup() {
    log "received shutdown signal, stopping services"
    xrdp-sesman --kill 2>/dev/null || true
    pkill -TERM -x xrdp 2>/dev/null || true
    pkill -TERM -x sshd  2>/dev/null || true
    sleep 1
    pkill -KILL -x xrdp 2>/dev/null || true
    pkill -KILL -x xrdp-sesman 2>/dev/null || true
    log "shutdown complete"
    exit 0
}
trap cleanup TERM INT

if [[ "${ENABLE_XRDP}" == "true" ]]; then
    log "starting xrdp-sesman"
    xrdp-sesman --nodaemon &
    sleep 1
    log "starting xrdp on :${XRDP_PORT}"
    xrdp --nodaemon &
else
    log "xrdp disabled (ENABLE_XRDP=${ENABLE_XRDP})"
fi

# ---------- keep-alive --------------------------------------------------------
log "ready — RDP on tcp/${XRDP_PORT}, SSH on tcp/22"
tail -F /var/log/xrdp/xrdp.log /var/log/xrdp/sesman.log 2>/dev/null \
    || exec sleep infinity
