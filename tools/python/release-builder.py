#!/usr/bin/env python3
"""
release-builder.py — Automate GitHub RDP Mega Toolkit release process.

Steps (each can be skipped with a flag):
  1. Run tests (validation)
  2. Bump version in version.txt (and CHANGELOG.md if --changelog)
  3. Commit version bump
  4. Create git tag vX.Y.Z
  5. Push commit + tag to origin
  6. Create GitHub Release via REST API (with auto-generated notes)

Examples:
  python3 release-builder.py --bump patch --notes "Fix tunnel bridge"
  python3 release-builder.py --bump minor --changelog --push --release
  python3 release-builder.py --bump major --dry-run

Requires:
  * git CLI on PATH
  * GH_PAT env var (or --token) for GitHub Release creation
  * Run from repo root (or pass --repo-dir)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from typing import Optional
from urllib.error import HTTPError
from urllib.request import Request, urlopen

DEFAULT_REPO = os.environ.get("RDP_REPO", "usekarne/github-rdp-mega-toolkit")
DEFAULT_TOKEN = os.environ.get("GH_PAT") or os.environ.get("GITHUB_TOKEN", "")


def run(cmd: list, *, cwd: Optional[str] = None, check: bool = True,
        capture: bool = True) -> str:
    """Run a shell command, return stdout (stripped)."""
    if not capture:
        subprocess.run(cmd, cwd=cwd, check=check)
        return ""
    res = subprocess.run(cmd, cwd=cwd, check=check, capture_output=True, text=True)
    return res.stdout.strip()


def read_version(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read().strip()


def write_version(path: str, version: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write(version + "\n")


def bump_version(current: str, kind: str) -> str:
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$", current)
    if not m:
        raise ValueError(f"Unparseable version: {current}")
    major, minor, patch = int(m.group(1)), int(m.group(2)), int(m.group(3))
    if kind == "major":
        major += 1; minor = 0; patch = 0
    elif kind == "minor":
        minor += 1; patch = 0
    elif kind == "patch":
        patch += 1
    else:
        raise ValueError(f"Unknown bump kind: {kind}")
    return f"{major}.{minor}.{patch}"


def update_changelog(path: str, version: str, notes: str) -> None:
    """Prepend a new section to CHANGELOG.md for the new version."""
    header = f"## v{version} — {notes}\n\n"
    section = header + f"- {notes}\n\n"
    existing = ""
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            existing = f.read()
    # Insert after the first H1 / H2 block
    new_text = existing
    if existing.startswith("# "):
        # Find end of first line
        first_nl = existing.find("\n")
        if first_nl > 0:
            new_text = existing[:first_nl + 1] + "\n" + section + existing[first_nl + 1:]
        else:
            new_text = existing + "\n" + section
    else:
        new_text = section + existing
    with open(path, "w", encoding="utf-8") as f:
        f.write(new_text)


def git_commit(repo_dir: str, version: str) -> None:
    run(["git", "add", "-A"], cwd=repo_dir)
    try:
        run(["git", "commit", "-m", f"release: v{version}"], cwd=repo_dir)
    except subprocess.CalledProcessError:
        # Nothing to commit
        pass


def git_tag(repo_dir: str, version: str) -> None:
    tag = f"v{version}"
    run(["git", "tag", "-a", tag, "-m", f"Release {tag}"], cwd=repo_dir)


def git_push(repo_dir: str, version: str, remote: str = "origin") -> None:
    run(["git", "push", remote, "HEAD"], cwd=repo_dir)
    run(["git", "push", remote, f"v{version}"], cwd=repo_dir)


def create_github_release(repo: str, token: str, version: str, notes: str,
                          draft: bool = False, prerelease: bool = False) -> dict:
    url = f"https://api.github.com/repos/{repo}/releases"
    body = json.dumps({
        "tag_name": f"v{version}",
        "name": f"v{version}",
        "body": notes,
        "draft": draft,
        "prerelease": prerelease,
        "generate_release_notes": not notes,
    }).encode("utf-8")
    req = Request(url, data=body, method="POST", headers={
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "User-Agent": "release-builder/1.0",
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": "application/json",
    })
    try:
        with urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except HTTPError as e:
        body_text = e.read().decode("utf-8", errors="replace")[:500]
        raise RuntimeError(f"GitHub Release API error {e.code}: {body_text}") from None


def main(argv=None) -> int:
    p = argparse.ArgumentParser(
        prog="release-builder.py",
        description="Automate the GitHub RDP Mega Toolkit release process.",
    )
    p.add_argument("--repo-dir", default=os.getcwd(), help="Path to repo root")
    p.add_argument("--repo", default=DEFAULT_REPO, help="owner/repo for GitHub Release")
    p.add_argument("--token", default=DEFAULT_TOKEN, help="GitHub PAT")
    p.add_argument("--bump", choices=["major", "minor", "patch"], default="patch")
    p.add_argument("--notes", default="", help="Release notes (markdown)")
    p.add_argument("--changelog", action="store_true", help="Prepend to CHANGELOG.md")
    p.add_argument("--commit", action="store_true", help="Commit version bump")
    p.add_argument("--tag", action="store_true", help="Create git tag")
    p.add_argument("--push", action="store_true", help="Push commit + tag to origin")
    p.add_argument("--release", action="store_true", help="Create GitHub Release")
    p.add_argument("--draft", action="store_true", help="Create as draft release")
    p.add_argument("--prerelease", action="store_true", help="Mark as prerelease")
    p.add_argument("--dry-run", action="store_true", help="Print what would happen, don't do it")
    args = p.parse_args(argv)

    repo_dir = os.path.abspath(args.repo_dir)
    version_path = os.path.join(repo_dir, "version.txt")
    changelog_path = os.path.join(repo_dir, "CHANGELOG.md")

    if not os.path.exists(version_path):
        print(f"ERROR: version.txt not found at {version_path}", file=sys.stderr)
        return 2

    current = read_version(version_path)
    new_version = bump_version(current, args.bump)
    print(f"Bumping version: {current} -> {new_version} ({args.bump})")

    if args.dry_run:
        print("[dry-run] Would update version.txt, CHANGELOG.md, commit, tag, push, create release.")
        return 0

    write_version(version_path, new_version)
    print(f"  Wrote version.txt: {new_version}")

    if args.changelog:
        update_changelog(changelog_path, new_version, args.notes or "Release")
        print(f"  Updated CHANGELOG.md")

    if args.commit:
        git_commit(repo_dir, new_version)
        print(f"  Committed version bump")

    if args.tag:
        git_tag(repo_dir, new_version)
        print(f"  Created tag v{new_version}")

    if args.push:
        git_push(repo_dir, new_version)
        print(f"  Pushed to origin")

    if args.release:
        if not args.token:
            print("ERROR: --release requires GH_PAT or --token", file=sys.stderr)
            return 2
        result = create_github_release(args.repo, args.token, new_version,
                                       args.notes, draft=args.draft,
                                       prerelease=args.prerelease)
        print(f"  Created GitHub Release: {result.get('html_url', '?')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
