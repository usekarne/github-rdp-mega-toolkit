#!/usr/bin/env python3
"""
fetch-creds.py - Client-side tool to fetch the latest RDP credentials artifact
from the GitHub RDP Mega Toolkit v9.0 repo.

USAGE:
    export GH_PAT='ghp_xxxx'
    export GH_REPO='usekarne/github-rdp-mega-toolkit'   # optional, default below
    python3 fetch-creds.py                  # fetch most recent successful run
    python3 fetch-creds.py --run-id 12345   # fetch specific run
    python3 fetch-creds.py --watch          # poll until artifact appears
    python3 fetch-creds.py --connect        # print ready-to-paste xfreerdp command
    python3 fetch-creds.py --save /tmp/     # extract artifact to /tmp/
    python3 fetch-creds.py --json           # machine-readable JSON output
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request
import zipfile
import io

DEFAULT_REPO = 'usekarne/github-rdp-mega-toolkit'
ARTIFACT_NAME = 'rdp-credentials'


def headers(pat):
    return {
        'Authorization': f'Bearer {pat}',
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'rdp-toolkit-v9-fetch-creds',
    }


def api_get(url, pat):
    req = urllib.request.Request(url, headers=headers(pat))
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def api_get_bytes(url, pat):
    req = urllib.request.Request(url, headers=headers(pat))
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def find_latest_run_with_artifact(repo, pat):
    """Find the most recent run that has the rdp-credentials artifact."""
    runs = api_get(f'https://api.github.com/repos/{repo}/actions/runs?per_page=30', pat)
    for r in runs.get('workflow_runs', []):
        # Skip cancelled/failed runs
        if r.get('conclusion') in ('cancelled', 'failure'):
            continue
        if r['status'] not in ('in_progress', 'completed'):
            continue
        arts = api_get(f'https://api.github.com/repos/{repo}/actions/runs/{r["id"]}/artifacts', pat)
        for a in arts.get('artifacts', []):
            if a['name'] == ARTIFACT_NAME:
                return r, a
    return None, None


def fetch_artifact(artifact, pat, save_dir=None):
    blob = api_get_bytes(artifact['archive_download_url'], pat)
    with zipfile.ZipFile(io.BytesIO(blob)) as zf:
        files = {n: zf.read(n).decode('utf-8', errors='replace') for n in zf.namelist()}
        if save_dir:
            os.makedirs(save_dir, exist_ok=True)
            zf.extractall(save_dir)
    return files


def parse_kv(content):
    """Parse KEY=VALUE format files.
    Robust to single-line 'K1=V1K2=V2' (legacy bug) and proper multi-line format.
    Looks for known keys with regex backfill using key-boundary lookahead.
    """
    out = {}
    known_keys = ['BRIDGE_CMD', 'CONNECT_CMD', 'RDP_USERNAME', 'RDP_PASSWORD',
                  'TUNNEL_TYPE', 'TUNNEL_HOST', 'TUNNEL_PORT', 'TUNNEL_URL']
    # Pass 1: line-by-line (works for properly-formatted multi-line files)
    for line in content.splitlines():
        if '=' in line:
            k, v = line.split('=', 1)
            k = k.strip()
            if k in known_keys:
                out[k] = v.strip()
    # Pass 2: regex backfill with key-boundary lookahead (handles single-line concat bug)
    boundary = '(?:BRIDGE_CMD=|CONNECT_CMD=|RDP_USERNAME=|RDP_PASSWORD=|TUNNEL_TYPE=|TUNNEL_HOST=|TUNNEL_PORT=|TUNNEL_URL=|$)'
    for key in known_keys:
        m = re.search(rf'{key}=([^\r\n]*?)(?={boundary})', content)
        if m:
            extracted = m.group(1).strip()
            # If the existing value contains a known key marker, replace with cleaner extraction
            if key not in out or any(k + '=' in out[key] for k in known_keys if k != key):
                out[key] = extracted
    return out


def main():
    p = argparse.ArgumentParser(description='Fetch RDP credentials artifact (v9.0)')
    p.add_argument('--repo', default=os.environ.get('GH_REPO', DEFAULT_REPO))
    p.add_argument('--pat',  default=os.environ.get('GH_PAT'))
    p.add_argument('--run-id', help='Specific run ID to fetch from')
    p.add_argument('--watch', action='store_true', help='Poll until artifact appears')
    p.add_argument('--connect', action='store_true', help='Print ready-to-paste xfreerdp command')
    p.add_argument('--save', help='Directory to extract artifact to')
    p.add_argument('--json', action='store_true', help='Print as JSON')
    args = p.parse_args()

    if not args.pat:
        print('ERROR: set GH_PAT env var or pass --pat', file=sys.stderr)
        return 2

    # Either fetch specific run or search for latest
    if args.run_id:
        try:
            arts = api_get(f'https://api.github.com/repos/{args.repo}/actions/runs/{args.run_id}/artifacts', args.pat)
        except Exception as e:
            print(f'ERROR: {e}', file=sys.stderr); return 1
        artifact = None
        for a in arts.get('artifacts', []):
            if a['name'] == ARTIFACT_NAME:
                artifact = a
                break
        if not artifact:
            print(f'No {ARTIFACT_NAME} artifact in run {args.run_id}', file=sys.stderr)
            return 1
    else:
        # Watch mode: poll until found
        deadline = time.time() + 600
        run = None
        while True:
            try:
                run, artifact = find_latest_run_with_artifact(args.repo, args.pat)
            except Exception as e:
                print(f'API error: {e}', file=sys.stderr); run, artifact = None, None
            if artifact:
                break
            if not args.watch:
                print('No artifact found. Try --watch to wait for one.', file=sys.stderr)
                return 1
            if time.time() > deadline:
                print('Timed out waiting for artifact', file=sys.stderr); return 2
            print(f'[{int(time.time())}] waiting for artifact...')
            time.sleep(15)

    print(f'Found artifact id={artifact["id"]} size={artifact["size_in_bytes"]}', file=sys.stderr)
    files = fetch_artifact(artifact, args.pat, args.save)

    # Parse all artifact files
    def plain(name):
        return files.get(name, '').strip()

    def kv_value(name, key):
        c = files.get(name, '')
        d = parse_kv(c)
        return d.get(key, c.strip())

    info = parse_kv(files.get('connect-info.txt', ''))
    info['RDP_USERNAME'] = kv_value('RDP_USERNAME.txt', 'RDP_USERNAME') or 'runner'
    info['RDP_PASSWORD'] = plain('rdp-password.txt') or kv_value('RDP_PASSWORD.txt', 'RDP_PASSWORD')
    info['TUNNEL_TYPE']  = plain('tunnel-type.txt')
    info['TUNNEL_HOST']  = plain('tunnel-host.txt')
    info['TUNNEL_PORT']  = plain('tunnel-port.txt')
    info['TUNNEL_URL']   = plain('tunnel-info.txt')

    if args.json:
        print(json.dumps(info, indent=2))
        return 0

    if args.connect:
        if info.get('BRIDGE_CMD'):
            print('# Step 1: Run this in a separate terminal (keep it running):')
            print(f'{info["BRIDGE_CMD"]}')
            print()
            print('# Step 2: Connect with xfreerdp:')
        print(info.get('CONNECT_CMD', '(no CONNECT_CMD found in artifact)'))
        return 0

    # Default: print summary
    print('=' * 60)
    print(f'  Tunnel:     {info.get("TUNNEL_TYPE")}')
    print(f'  Host:       {info.get("TUNNEL_HOST")}')
    print(f'  Port:       {info.get("TUNNEL_PORT")}')
    print(f'  Username:   {info.get("RDP_USERNAME")}')
    print(f'  Password:   {info.get("RDP_PASSWORD")}')
    print(f'  URL:        {info.get("TUNNEL_URL")}')
    if info.get('BRIDGE_CMD'):
        print(f'  Bridge:     {info["BRIDGE_CMD"]}')
    print(f'  Connect:    {info.get("CONNECT_CMD")}')
    print('=' * 60)
    return 0


if __name__ == '__main__':
    sys.exit(main())
