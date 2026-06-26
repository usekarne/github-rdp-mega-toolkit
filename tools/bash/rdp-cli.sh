#!/usr/bin/env bash
# tools/bash/rdp-cli.sh - Bash CLI for GitHub RDP Mega Toolkit v9.0
# Commands: trigger, status, runs, fetch, connect, save, kill, kill-run, watch, help
set -euo pipefail

REPO="${GH_REPO:-usekarne/github-rdp-mega-toolkit}"
PAT="${GH_PAT:?set GH_PAT env var with your GitHub PAT}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON_FETCH="${SCRIPT_DIR}/../python/fetch-creds.py"

cmd="${1:-help}"
shift || true

usage() {
  cat <<EOF
GitHub RDP Mega Toolkit v9.0 - Bash CLI

USAGE:  GH_PAT=ghp_xxx rdp-cli.sh <command> [options]

COMMANDS:
  trigger [workflow]   Trigger a workflow (default: lite-rdp.yml)
  status               Show active runs
  runs [N]             Show last N runs (default 10)
  fetch [run-id]       Fetch and print credentials from latest or specific run
  connect [run-id]     Print ready-to-paste xfreerdp command
  save [dir] [run-id]  Download artifact and extract to dir (default: ./rdp-creds)
  kill                 Cancel all in-progress runs
  kill-run <run-id>    Cancel a specific run
  watch                Poll until latest run produces rdp-credentials artifact
  help                 Show this help

ENV VARS:
  GH_PAT (required)    GitHub PAT with actions:read + actions:write
  GH_REPO (optional)   Override repo (default: $REPO)

EXAMPLES:
  GH_PAT=ghp_xxx ./rdp-cli.sh trigger lite-rdp.yml
  GH_PAT=ghp_xxx ./rdp-cli.sh watch
  GH_PAT=ghp_xxx ./rdp-cli.sh connect
EOF
}

api() {
  local method="$1"; shift
  local path="$1"; shift
  local data="${1:-}"
  if [ -n "$data" ]; then
    curl -s -X "$method" \
      -H "Authorization: bearer $PAT" \
      -H "Accept: application/vnd.github+json" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "https://api.github.com/repos/$REPO/$path"
  else
    curl -s -X "$method" \
      -H "Authorization: bearer $PAT" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$REPO/$path"
  fi
}

case "$cmd" in
  trigger)
    wf="${1:-lite-rdp.yml}"
    echo "Triggering $wf on $REPO..."
    api POST "actions/workflows/$wf/dispatches" '{"ref":"main"}' -w '\nHTTP %{http_code}\n' -o /dev/null
    ;;
  status)
    echo "=== Active runs ==="
    for s in in_progress queued waiting; do
      api GET "actions/runs?status=$s&per_page=20" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('workflow_runs', []):
    print(f'  {r[\"id\"]}  {r[\"name\"]:<35}  {r[\"status\"]:<15}  {r.get(\"conclusion\") or \"-\"}')
"
    done
    ;;
  runs)
    n="${1:-10}"
    api GET "actions/runs?per_page=$n" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('workflow_runs', []):
    print(f'  {r[\"id\"]}  {r[\"name\"]:<35}  {r[\"status\"]:<15}  {r.get(\"conclusion\") or \"-\"}  {r[\"created_at\"]}')
"
    ;;
  fetch|connect)
    python3 "$PYTHON_FETCH" ${1:+--run-id $1} --connect
    ;;
  save)
    dir="${1:-./rdp-creds}"
    rid="${2:-}"
    python3 "$PYTHON_FETCH" ${rid:+--run-id $rid} --save "$dir"
    echo "Extracted to: $dir"
    ls -la "$dir"
    ;;
  kill)
    echo "Cancelling all in-progress runs..."
    for s in in_progress queued waiting; do
      api GET "actions/runs?status=$s&per_page=100" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('workflow_runs', []):
    print(r['id'])
" | while read -r rid; do
        api POST "actions/runs/$rid/cancel" -o /dev/null -w "  cancelled $rid  HTTP %{http_code}\n"
      done
    done
    ;;
  kill-run)
    rid="${1:?usage: rdp-cli.sh kill-run <run-id>}"
    api POST "actions/runs/$rid/cancel" -w "HTTP %{http_code}\n" -o /dev/null
    ;;
  watch)
    python3 "$PYTHON_FETCH" --watch --connect
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $cmd"
    usage
    exit 1
    ;;
esac
