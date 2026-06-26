#!/usr/bin/env bash
# install-software.sh — install the catalogue declared in
# configs/software-list.json using apt / dnf / pacman / pkg (Termux).

set -euo pipefail
# shellcheck source=utils.sh
. "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

CONFIG_PATH="${SOFTWARE_LIST_PATH:-}"

# ---------------------------------------------------------------------------
# Locate the catalogue (allow override, else search a few well-known spots).
# ---------------------------------------------------------------------------
find_config() {
    if [[ -n "$CONFIG_PATH" && -f "$CONFIG_PATH" ]]; then
        echo "$CONFIG_PATH"
        return 0
    fi
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local candidates=(
        "${script_dir}/../../configs/software-list.json"
        "${script_dir}/../configs/software-list.json"
        "$(pwd)/configs/software-list.json"
        "${RDP_ARTIFACT_DIR}/software-list.json"
    )
    local c
    for c in "${candidates[@]}"; do
        # Resolve and check.
        local resolved
        resolved="$(readlink -f "$c" 2>/dev/null || true)"
        if [[ -n "$resolved" && -f "$resolved" ]]; then
            echo "$resolved"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Pick the right package manager key from the JSON.
# ---------------------------------------------------------------------------
detect_pm_key() {
    if is_android_termux; then
        echo 'pkg'
    elif command -v apt-get >/dev/null 2>&1; then
        echo 'apt'
    elif command -v dnf >/dev/null 2>&1; then
        echo 'dnf'
    elif command -v pacman >/dev/null 2>&1; then
        echo 'pacman'
    else
        echo ''
    fi
}

# ---------------------------------------------------------------------------
# Install a single package via the detected package manager.
# install_pkg KEY VALUE
# ---------------------------------------------------------------------------
install_pkg() {
    local key="$1"
    local value="$2"
    case "$key" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -y --no-install-recommends "$value" 2>&1 || return 1
            ;;
        dnf)
            dnf install -y --setopt=install_weak_deps=False "$value" 2>&1 || return 1
            ;;
        pacman)
            pacman -Sy --noconfirm --needed "$value" 2>&1 || return 1
            ;;
        pkg)
            pkg install -y "$value" 2>&1 || return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Parse the catalogue WITHOUT jq (fallback) or WITH jq when present.
# Returns 0 on success, prints a TSV: name<TAB>key<TAB>value<TAB>enabled<TAB>optional
# ---------------------------------------------------------------------------
parse_catalog() {
    local cfg="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -r '.packages[] | [.name, (.winget // ""), (.choco // ""), (.apt // ""), (.dnf // ""), (.pacman // ""), (.pkg // ""), (.enabled // false), (.optional // false)] | @tsv' "$cfg"
    else
        # Minimal Python fallback (always present on CI runners).
        python3 - "$cfg" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for p in data.get('packages', []):
    print('\t'.join([
        str(p.get('name','')),
        str(p.get('winget','') or ''),
        str(p.get('choco','') or ''),
        str(p.get('apt','') or ''),
        str(p.get('dnf','') or ''),
        str(p.get('pacman','') or ''),
        str(p.get('pkg','') or ''),
        str(bool(p.get('enabled', False))).lower(),
        str(bool(p.get('optional', False))).lower(),
    ]))
PY
    fi
}

# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
main() {
    local cfg
    if ! cfg="$(find_config)"; then
        write_err 'Could not find configs/software-list.json.'
        exit 1
    fi
    write_block "Installing software from $cfg"

    local pm_key
    pm_key="$(detect_pm_key)"
    if [[ -z "$pm_key" ]]; then
        write_warn 'No supported package manager detected — nothing to install.'
        exit 0
    fi
    write_info "Package manager key: $pm_key"

    # Refresh package indices once.
    case "$pm_key" in
        apt)  apt-get update -y 2>&1 | tail -n1 || true ;;
        dnf)  dnf makecache 2>&1 | tail -n1 || true ;;
        pacman) pacman -Sy 2>&1 | tail -n1 || true ;;
        pkg)  pkg update -y 2>&1 | tail -n1 || true ;;
    esac

    # Map pm_key -> column index in the TSV.
    # Columns: name, winget, choco, apt, dnf, pacman, pkg, enabled, optional
    local col
    case "$pm_key" in
        apt)    col=4 ;;
        dnf)    col=5 ;;
        pacman) col=6 ;;
        pkg)    col=7 ;;
    esac

    local installed=0 skipped=0 failed=0
    while IFS=$'\t' read -r name winget choco apt_v dnf_v pacman_v pkg_v enabled optional; do
        if [[ "$enabled" != "true" ]]; then
            write_info "SKIP  $name (enabled=false)"
            skipped=$((skipped+1))
            continue
        fi

        # Pull the right column value.
        local value=''
        case "$col" in
            4) value="$apt_v" ;;
            5) value="$dnf_v" ;;
            6) value="$pacman_v" ;;
            7) value="$pkg_v" ;;
        esac
        if [[ -z "$value" ]]; then
            write_warn "SKIP  $name (no $pm_key mapping)"
            skipped=$((skipped+1))
            continue
        fi

        write_info "INSTALL $name ($value)"
        if install_pkg "$pm_key" "$value" >"${RDP_ARTIFACT_DIR}/install-${value}.log" 2>&1; then
            write_ok "$name installed"
            installed=$((installed+1))
        else
            failed=$((failed+1))
            if [[ "$optional" == "true" ]]; then
                write_warn "Optional package failed: $name"
            else
                write_err "REQUIRED package failed: $name"
            fi
        fi
    done < <(parse_catalog "$cfg")

    write_block 'install-software.sh summary'
    write_info "Installed: $installed  Skipped: $skipped  Failed: $failed"

    if (( failed > 0 )); then
        write_warn 'Some packages failed — see logs in artifact dir.'
        exit 2
    fi
    exit 0
}

main "$@"
