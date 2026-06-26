#!/usr/bin/env python3
"""
rdp-cli.py — Full Python CLI for GitHub RDP Mega Toolkit v9.

Subcommands:
  trigger     Trigger a workflow run on GitHub Actions
  status      Show status of latest / specific run
  runs        List recent runs (with --workflow filter)
  fetch       Fetch credential artifact (see fetch-creds.py for full options)
  connect     Build & print ready-to-paste xfreerdp command
  kill        Cancel the most recent in-progress run
  kill-run    Cancel a specific run-id
  watch       Poll until a run completes / artifact appears
  help        Show help

Python 3.8+. Only stdlib.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from typing import Optional

# Re-use fetch-creds as a sibling module
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fetch_creds as fc  # type: ignore  # noqa: E402

DEFAULT_REPO = os.environ.get("RDP_REPO", "usekarne/github-rdp-mega-toolkit")
DEFAULT_TOKEN = os.environ.get("GH_PAT") or os.environ.get("GITHUB_TOKEN", "")


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_trigger(args: argparse.Namespace) -> int:
    """Trigger a workflow via workflow_dispatch."""
    wf = args.workflow
    if not wf.endswith((".yml", ".yaml")):
        wf = wf + ".yml"
    url = f"{fc.API_BASE}/repos/{args.repo}/actions/workflows/{wf}/dispatches"
    payload = {"ref": args.ref}
    if args.inputs:
        # Parse KEY=VAL,KEY2=VAL2,...
        for pair in args.inputs.split(","):
            if "=" not in pair:
                continue
            k, v = pair.split("=", 1)
            payload.setdefault("inputs", {})[k.strip()] = v.strip()
    body = json.dumps(payload).encode("utf-8")
    try:
        fc._request(url, args.token, method="POST")  # noqa: SLF001
    except fc.APIError as e:  # noqa: SLF001
        print(f"ERROR triggering workflow: {e}", file=sys.stderr)
        return 1
    print(f"Triggered {wf} on {args.repo}@{args.ref}")
    if args.inputs:
        print(f"  inputs: {payload.get('inputs', {})}")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    runs = fc.list_runs(args.repo, args.token, branch=args.branch, limit=1)
    if not runs:
        print("No runs found.", file=sys.stderr)
        return 1
    run = runs[0] if not args.run_id else next(
        (r for r in fc.list_runs(args.repo, args.token, limit=30)
         if r["id"] == args.run_id), None
    )
    if not run:
        print(f"Run {args.run_id} not found.", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(run, indent=2))
        return 0
    print(f"Run #{run['id']}")
    print(f"  workflow: {run.get('name', '?')}")
    print(f"  branch:   {run.get('head_branch', '?')}")
    print(f"  status:   {run.get('status', '?')} / {run.get('conclusion', '?')}")
    print(f"  created:  {run.get('created_at')}")
    print(f"  url:      {run['html_url']}")
    return 0


def cmd_runs(args: argparse.Namespace) -> int:
    wf = args.workflow
    wf_file = None
    if wf:
        wf_file = wf if wf.endswith((".yml", ".yaml")) else wf + ".yml"
    runs = fc.list_runs(args.repo, args.token, workflow_file=wf_file,
                        branch=args.branch, limit=args.limit)
    if args.json:
        print(json.dumps(runs, indent=2))
        return 0
    if not runs:
        print("(no runs)")
        return 0
    print(f"{'ID':>10}  {'STATUS':<12} {'CONCLUSION':<12} {'BRANCH':<14} WORKFLOW")
    for r in runs:
        print(f"{r['id']:>10}  {r.get('status','?'):<12} "
              f"{str(r.get('conclusion','-')):<12} "
              f"{r.get('head_branch','?'):<14} {r.get('name','?')}")
    return 0


def cmd_fetch(args: argparse.Namespace) -> int:
    # Delegate to fetch-creds with all the same args.
    fc_args = argparse.Namespace(
        repo=args.repo, token=args.token, branch=args.branch,
        run_id=args.run_id, artifact=args.artifact, limit=args.limit,
        watch=args.watch, timeout=args.timeout,
        connect=args.connect, save=args.save, json=args.json,
        size=args.size,
    )
    return fc.main(fc_args)


def cmd_connect(args: argparse.Namespace) -> int:
    # Find run with artifact, fetch & parse, print connect command.
    try:
        run = fc.resolve_run(args.repo, args.token, argparse.Namespace(
            run_id=args.run_id, artifact=args.artifact,
            branch=args.branch, limit=args.limit, watch=False, timeout=0,
        ))
    except fc.APIError as e:  # noqa: SLF001
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    zip_bytes = fc.download_artifact(args.repo, args.token,
                                     run["_artifact"]["archive_download_url"])
    files = fc.extract_zip(zip_bytes)
    creds: dict = {}
    for fname in ("connect-info.txt", "tunnel-info.txt",
                  "RDP_USERNAME.txt", "RDP_PASSWORD.txt"):
        if fname in files:
            txt = files[fname]
            if "=" in txt and any(k + "=" in txt for k in fc.KNOWN_KEYS):
                creds.update(fc.parse_kv(txt))
            else:
                key = fname.replace(".txt", "").upper()
                creds[key] = fc.parse_plain(txt)
    for k, fname in (("TUNNEL_TYPE", "tunnel-type.txt"),
                     ("TUNNEL_HOST", "tunnel-host.txt"),
                     ("TUNNEL_PORT", "tunnel-port.txt")):
        if fname in files:
            creds[k] = fc.parse_plain(files[fname])
    cmd = fc.build_connect_cmd(creds, size=args.size, extra=args.extra)
    print(cmd)
    return 0


def cmd_kill(args: argparse.Namespace) -> int:
    runs = fc.list_runs(args.repo, args.token, branch=args.branch, limit=args.limit)
    target = None
    for r in runs:
        if r.get("status") in ("in_progress", "queued", "waiting"):
            target = r
            break
    if not target:
        print("No in-progress run to cancel.", file=sys.stderr)
        return 1
    return _cancel(args.repo, args.token, target["id"])


def cmd_kill_run(args: argparse.Namespace) -> int:
    return _cancel(args.repo, args.token, args.run_id)


def _cancel(repo: str, token: str, run_id: int) -> int:
    url = f"{fc.API_BASE}/repos/{repo}/actions/runs/{run_id}/cancel"
    try:
        fc._request(url, token, method="POST")  # noqa: SLF001
    except fc.APIError as e:  # noqa: SLF001
        print(f"ERROR cancelling run {run_id}: {e}", file=sys.stderr)
        return 1
    print(f"Cancelled run {run_id}")
    return 0


def cmd_watch(args: argparse.Namespace) -> int:
    print(f"Watching {args.repo} for new artifact... (timeout {args.timeout}s, "
          f"poll every {args.poll}s)", file=sys.stderr)
    deadline = time.time() + args.timeout
    last_id = None
    while time.time() < deadline:
        try:
            run = fc.find_run_with_artifact(
                args.repo, args.token, args.artifact,
                branch=args.branch, limit=args.limit,
            )
        except fc.APIError as e:  # noqa: SLF001
            print(f"[watch] API error: {e}", file=sys.stderr)
            time.sleep(args.poll)
            continue
        if run and run["id"] != last_id:
            print(f"[watch] Artifact available in run #{run['id']}", file=sys.stderr)
            if args.json:
                print(json.dumps({"run_id": run["id"], "url": run["html_url"]}))
            else:
                print(f"Run #{run['id']}: {run['html_url']}")
            return 0
        time.sleep(args.poll)
    print("[watch] Timed out.", file=sys.stderr)
    return 1


def cmd_help(args: argparse.Namespace) -> int:
    args.parser.print_help()
    return 0


# ---------------------------------------------------------------------------
# Argparse plumbing
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="rdp-cli.py",
        description="RDP Mega Toolkit v9 — unified CLI",
    )
    p.add_argument("--repo", default=DEFAULT_REPO, help="owner/repo (default: env RDP_REPO)")
    p.add_argument("--token", default=DEFAULT_TOKEN, help="GitHub PAT (default: env GH_PAT)")
    p.add_argument("--json", action="store_true", help="Machine-readable JSON output")

    sub = p.add_subparsers(dest="cmd", required=True)

    # trigger
    sp = sub.add_parser("trigger", help="Trigger a workflow_dispatch")
    sp.add_argument("workflow", help="Workflow name (kali-rdp) or filename (kali-rdp.yml)")
    sp.add_argument("--ref", default="main", help="Branch/tag to run on")
    sp.add_argument("--inputs", default=None, help="Comma-separated KEY=VAL inputs")
    sp.set_defaults(func=cmd_trigger)

    # status
    sp = sub.add_parser("status", help="Show status of latest / specific run")
    sp.add_argument("--run-id", type=int, default=None)
    sp.add_argument("--branch", default=None)
    sp.set_defaults(func=cmd_status)

    # runs
    sp = sub.add_parser("runs", help="List recent runs")
    sp.add_argument("--workflow", default=None)
    sp.add_argument("--branch", default=None)
    sp.add_argument("--limit", type=int, default=20)
    sp.set_defaults(func=cmd_runs)

    # fetch
    sp = sub.add_parser("fetch", help="Fetch credential artifact")
    sp.add_argument("--run-id", type=int, default=None)
    sp.add_argument("--branch", default=None)
    sp.add_argument("--artifact", default=fc.ARTIFACT_NAME)
    sp.add_argument("--limit", type=int, default=30)
    sp.add_argument("--watch", action="store_true")
    sp.add_argument("--timeout", type=int, default=fc.DEFAULT_WATCH_TIMEOUT)
    sp.add_argument("--connect", action="store_true")
    sp.add_argument("--save", default=None, metavar="DIR")
    sp.add_argument("--size", default="1280x720")
    sp.set_defaults(func=cmd_fetch)

    # connect
    sp = sub.add_parser("connect", help="Build & print xfreerdp command")
    sp.add_argument("--run-id", type=int, default=None)
    sp.add_argument("--branch", default=None)
    sp.add_argument("--artifact", default=fc.ARTIFACT_NAME)
    sp.add_argument("--limit", type=int, default=30)
    sp.add_argument("--size", default="1280x720")
    sp.add_argument("--extra", default="", help="Extra xfreerdp flags")
    sp.set_defaults(func=cmd_connect)

    # kill
    sp = sub.add_parser("kill", help="Cancel most recent in-progress run")
    sp.add_argument("--branch", default=None)
    sp.add_argument("--limit", type=int, default=20)
    sp.set_defaults(func=cmd_kill)

    # kill-run
    sp = sub.add_parser("kill-run", help="Cancel a specific run-id")
    sp.add_argument("run_id", type=int)
    sp.set_defaults(func=cmd_kill_run)

    # watch
    sp = sub.add_parser("watch", help="Poll until new artifact appears")
    sp.add_argument("--branch", default=None)
    sp.add_argument("--artifact", default=fc.ARTIFACT_NAME)
    sp.add_argument("--limit", type=int, default=20)
    sp.add_argument("--poll", type=int, default=15)
    sp.add_argument("--timeout", type=int, default=fc.DEFAULT_WATCH_TIMEOUT)
    sp.set_defaults(func=cmd_watch)

    # help
    sp = sub.add_parser("help", help="Show this help")
    sp.set_defaults(func=cmd_help, parser=p)

    return p


def main(argv=None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.token and args.cmd not in ("help",):
        print("ERROR: GitHub token required. Set GH_PAT env var or use --token.",
              file=sys.stderr)
        return 2
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
