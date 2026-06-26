#!/usr/bin/env bash
# rotate-password.sh — rotate the local RDP user's password and update
# the artifact files so the Python runner can pick up the new credential.

set -euo pipefail
# shellcheck source=utils.sh
. "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

USERNAME="${RDP_USERNAME:-runner}"

write_block "Rotating password for user '$USERNAME'"

require_root

if ! id "$USERNAME" >/dev/null 2>&1; then
    write_err "User '$USERNAME' does not exist."
    exit 1
fi

NEW_PW="$(new_random_password 24)"
echo "${USERNAME}:${NEW_PW}" | chpasswd
write_ok 'Local user password updated.'

DIR="$(ensure_artifact_dir)"
printf '%s' "$NEW_PW" > "${DIR}/rdp-password.txt"
printf '%s' "$NEW_PW" > "${DIR}/RDP_PASSWORD.txt"
chmod 0600 "${DIR}/rdp-password.txt" "${DIR}/RDP_PASSWORD.txt" 2>/dev/null || true

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[${TS}] password rotated for ${USERNAME}" >> "${DIR}/password-rotations.log"

# Update rdp-summary.json if it exists.
if [[ -f "${DIR}/rdp-summary.json" ]]; then
    if command -v jq >/dev/null 2>&1; then
        local_tmp="${DIR}/rdp-summary.json.tmp"
        jq --arg ts "$TS" '. + {password_rotated_at: $ts}' \
            "${DIR}/rdp-summary.json" > "$local_tmp" && mv "$local_tmp" "${DIR}/rdp-summary.json"
    else
        python3 - "${DIR}/rdp-summary.json" "$TS" <<'PY' || true
import json, sys
path, ts = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
    data['password_rotated_at'] = ts
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    print(f'rotate: could not update summary: {e}', file=sys.stderr)
PY
    fi
fi

write_ok "Wrote ${DIR}/rdp-password.txt and ${DIR}/RDP_PASSWORD.txt"
write_info 'New password (visible in artifact):'
printf '%s\n' "$NEW_PW" >&2

send_notify "RDP password rotated for user '${USERNAME}'." 'Password rotation' || true

write_block 'rotate-password.sh complete'
exit 0
