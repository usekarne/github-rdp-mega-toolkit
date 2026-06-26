#!/usr/bin/env python3
"""
bulk-kill.py — Cancel all GitHub Actions runs matching a pattern.

Examples:
  python3 bulk-kill.py --pattern kali-rdp
  python3 bulk-kill.py --status in_progress
  python3 bulk-kill.py --older-than 24h
  python3 bulk-kill.py --dry-run --pattern windows-rdp

Pattern is matched (case-insensitive) against workflow name OR branch.
Use --dry-run to preview without cancelling.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from typing import Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fetch_creds as fc  # type: ignore  # noqa: E402

DEFAULT_REPO = os.environ.get("RDP_REPO", "usekarne/github-rdp-mega-toolkit")
DEFAULT_TOKEN = os.environ.get("GH_PAT") or os.environ.get("GITHUB_TOKEN", "")


def parse_duration(s: str) -> int:
    """Parse '24h', '30m', '3600s' into seconds."""
    m = re.match(r"^(\d+)\s*([smhdw])$", s.strip().lower())
    if not m:
        raise ValueError(f"Invalid duration: {s}")
    n = int(m.group(1))
    unit = m.group(2)
    return n * {"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 604800}[unit]


def matches(run: dict, *, pattern: Optional[re.Pattern],
            status: Optional[str], older_than: Optional[int]) -> bool:
    if status and run.get("status") != status:
        return False
    if pattern:
        hay = f"{run.get('name','')} {run.get('head_branch','')}".lower()
        if not pattern.search(hay):
            return False
    if older_than is not None:
        # created_at is ISO 8601 e.g. 2024-01-01T00:00:00Z
        ts = run.get("created_at", "")
        if ts:
            try:
                ct = time.mktime(time.strptime(ts, "%Y-%m-%dT%H:%M:%SZ"))
                if time.time() - ct < older_than:
                    return False
            except ValueError:
                pass
    return True


def main(argv=None) -> int:
    p = argparse.ArgumentParser(
        prog="bulk-kill.py",
        description="Cancel all runs matching a pattern.",
    )
    p.add_argument("--repo", default=DEFAULT_REPO)
    p.add_argument("--token", default=DEFAULT_TOKEN)
    p.add_argument("--pattern", default=None, help="Regex matched against workflow/branch name")
    p.add_argument("--status", default=None, help="Filter by status (in_progress, queued, ...)")
    p.add_argument("--older-than", default=None, help="Only cancel runs older than (e.g. 24h)")
    p.add_argument("--limit", type=int, default=100, help="Scan at most N runs")
    p.add_argument("--dry-run", action="store_true", help="List matches without cancelling")
    p.add_argument("--json", action="store_true")
    args = p.parse_args(argv)

    if not args.token:
        print("ERROR: GitHub token required (GH_PAT env or --token).", file=sys.stderr)
        return 2

    pattern = re.compile(args.pattern, re.IGNORECASE) if args.pattern else None
    older_than = parse_duration(args.older_than) if args.older_than else None

    runs = fc.list_runs(args.repo, args.token, limit=args.limit)
    targets = [r for r in runs if matches(r, pattern=pattern, status=args.status,
                                          older_than=older_than)]

    if args.json:
        out = {"matched": [r["id"] for r in targets], "cancelled": []}
    else:
        print(f"Found {len(targets)} matching run(s).")

    cancelled = []
    for r in targets:
        if args.dry_run:
            if not args.json:
                print(f"  [DRY] would cancel #{r['id']} ({r.get('name')}, {r.get('status')})")
            continue
        url = f"{fc.API_BASE}/repos/{args.repo}/actions/runs/{r['id']}/cancel"
        try:
            fc._request(url, args.token, method="POST")  # noqa: SLF001
            cancelled.append(r["id"])
            if not args.json:
                print(f"  cancelled #{r['id']} ({r.get('name')})")
        except fc.APIError as e:  # noqa: SLF001
            if not args.json:
                print(f"  FAILED #{r['id']}: {e}", file=sys.stderr)

    if args.json:
        out["cancelled"] = cancelled
        print(json.dumps(out, indent=2))
    else:
        print(f"\nCancelled {len(cancelled)}/{len(targets)} run(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
