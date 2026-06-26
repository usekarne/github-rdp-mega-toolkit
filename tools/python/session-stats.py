#!/usr/bin/env python3
"""
session-stats.py — Show usage stats for RDP Mega Toolkit workflows.

Reports:
  * Total sessions (completed runs with rdp-credentials artifact)
  * Total hours (sum of run durations)
  * Success rate (conclusion == success / total)
  * Average session length
  * Breakdown by workflow name
  * Breakdown by day (last 14 days)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timezone
from typing import Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fetch_creds as fc  # type: ignore  # noqa: E402

DEFAULT_REPO = os.environ.get("RDP_REPO", "usekarne/github-rdp-mega-toolkit")
DEFAULT_TOKEN = os.environ.get("GH_PAT") or os.environ.get("GITHUB_TOKEN", "")


def parse_iso(s: str) -> Optional[datetime]:
    if not s:
        return None
    try:
        return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def collect_runs(repo: str, token: str, *, limit: int = 100,
                 workflow: Optional[str] = None) -> list:
    """Fetch runs (paginated up to limit)."""
    runs: list = []
    page = 1
    while len(runs) < limit:
        wf_file = None
        if workflow:
            wf_file = workflow if workflow.endswith((".yml", ".yaml")) else workflow + ".yml"
        url = f"{fc.API_BASE}/repos/{repo}/actions/runs?per_page=100&page={page}"
        if wf_file:
            url = (f"{fc.API_BASE}/repos/{repo}/actions/workflows/"
                   f"{os.path.basename(wf_file)}/runs?per_page=100&page={page}")
        try:
            data = fc._get_json(url, token)  # noqa: SLF001
        except fc.APIError as e:  # noqa: SLF001
            print(f"[warn] API error on page {page}: {e}", file=sys.stderr)
            break
        batch = data.get("workflow_runs", [])
        if not batch:
            break
        runs.extend(batch)
        page += 1
        if len(batch) < 100:
            break
    return runs[:limit]


def compute_stats(runs: list) -> dict:
    total = len(runs)
    by_conclusion = defaultdict(int)
    by_workflow = defaultdict(int)
    by_day = defaultdict(int)
    total_seconds = 0
    durations = []

    for r in runs:
        conc = r.get("conclusion") or "in_progress"
        by_conclusion[conc] += 1
        by_workflow[r.get("name", "?")] += 1
        created = parse_iso(r.get("created_at"))
        if created:
            by_day[created.strftime("%Y-%m-%d")] += 1
        # Duration
        if r.get("run_started_at") and r.get("updated_at"):
            start = parse_iso(r["run_started_at"]) or parse_iso(r["created_at"])
            end = parse_iso(r["updated_at"])
            if start and end and end > start:
                dur = (end - start).total_seconds()
                durations.append(dur)
                if conc == "success":
                    total_seconds += dur

    success = by_conclusion.get("success", 0)
    success_rate = (success / total * 100) if total else 0
    avg_minutes = (sum(durations) / len(durations) / 60) if durations else 0
    return {
        "total_runs": total,
        "by_conclusion": dict(by_conclusion),
        "by_workflow": dict(by_workflow),
        "by_day": dict(sorted(by_day.items())[-14:]),
        "success_count": success,
        "success_rate_pct": round(success_rate, 2),
        "total_hours": round(total_seconds / 3600, 2),
        "avg_minutes": round(avg_minutes, 2),
    }


def main(argv=None) -> int:
    p = argparse.ArgumentParser(
        prog="session-stats.py",
        description="Show usage stats for RDP Mega Toolkit workflows.",
    )
    p.add_argument("--repo", default=DEFAULT_REPO)
    p.add_argument("--token", default=DEFAULT_TOKEN)
    p.add_argument("--workflow", default=None, help="Restrict to a single workflow")
    p.add_argument("--limit", type=int, default=200, help="Max runs to analyze")
    p.add_argument("--json", action="store_true")
    args = p.parse_args(argv)

    if not args.token:
        print("ERROR: GitHub token required (GH_PAT env or --token).", file=sys.stderr)
        return 2

    runs = collect_runs(args.repo, args.token, limit=args.limit, workflow=args.workflow)
    if not runs:
        print("No runs found.", file=sys.stderr)
        return 1
    stats = compute_stats(runs)

    if args.json:
        print(json.dumps(stats, indent=2))
        return 0

    print(f"=== RDP Mega Toolkit Stats (last {len(runs)} runs) ===\n")
    print(f"Total sessions:     {stats['total_runs']}")
    print(f"Successful:         {stats['success_count']} ({stats['success_rate_pct']}%)")
    print(f"Total hours:        {stats['total_hours']}h")
    print(f"Avg session length: {stats['avg_minutes']} min")
    print("\nBy conclusion:")
    for k, v in sorted(stats["by_conclusion"].items(), key=lambda x: -x[1]):
        print(f"  {k:<20} {v}")
    print("\nBy workflow:")
    for k, v in sorted(stats["by_workflow"].items(), key=lambda x: -x[1]):
        print(f"  {k:<30} {v}")
    print("\nBy day (last 14):")
    for k, v in stats["by_day"].items():
        print(f"  {k}  {v}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
