#!/usr/bin/env bash
# core/bash/setup-venv.sh - Start virtual environment based on VENV_TYPE
set -euo pipefail
source "$(dirname "$0")/utils.sh"

VENV_TYPE="${VENV_TYPE:-none}"
log_block "SETUP VENV - type=$VENV_TYPE"

case "$VENV_TYPE" in
    docker)
        log_info 'Starting Docker container...'
        if command -v docker &>/dev/null; then
            COMPOSE_FILE="$(dirname "$0")/../../venvs/docker/docker-compose.yml"
            if [ -f "$COMPOSE_FILE" ]; then
                docker compose -f "$COMPOSE_FILE" up -d 2>&1 | tail -3
                log_ok 'Docker containers started'
            else
                log_warn "Compose file not found: $COMPOSE_FILE"
            fi
        else
            log_warn 'Docker not installed'
        fi
        ;;
    vagrant)
        log_info 'Starting Vagrant VM...'
        if command -v vagrant &>/dev/null; then
            VAGRANT_DIR="$(dirname "$0")/../../venvs/vagrant"
            if [ -d "$VAGRANT_DIR" ]; then
                cd "$VAGRANT_DIR"
                vagrant up 2>&1 | tail -5
                log_ok 'Vagrant VM started'
            else
                log_warn "Vagrant dir not found: $VAGRANT_DIR"
            fi
        else
            log_warn 'Vagrant not installed'
        fi
        ;;
    podman)
        log_info 'Starting Podman pod...'
        if command -v podman &>/dev/null; then
            log_ok 'Podman available (manual pod start required)'
        else
            log_warn 'Podman not installed'
        fi
        ;;
    none)
        log_info 'No virtual environment requested (VENV_TYPE=none)'
        ;;
    *)
        log_warn "Unknown VENV_TYPE: $VENV_TYPE (valid: docker, vagrant, podman, none)"
        ;;
esac

log_ok 'VENV setup complete'
