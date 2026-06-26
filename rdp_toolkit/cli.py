"""Argparse-based CLI for RDP Mega Toolkit v9.

Every subcommand delegates to a sibling subpackage (``rdp.runner``,
``tunnel.manager``, ``vm.manager``, ``platforms.installer``).  Those
imports are done *lazily* inside each handler so that ``python -m
rdp_toolkit --help`` and ``doctor`` keep working even when some
subpackages are still under construction by other agents.
"""
from __future__ import annotations

import argparse
import sys
from typing import Any, Callable, List, Optional

from . import __version__
from .config import generate_config, load_config
from .utils.system import detect_platform, is_root, which

__all__ = ["main", "build_parser"]


# --------------------------------------------------------------------------- #
# Output helpers — every line printed by the CLI is prefixed for grep-ability.
# --------------------------------------------------------------------------- #
def info(msg: str) -> None:
    print(f"[INFO] {msg}")


def ok(msg: str) -> None:
    print(f"[OK]   {msg}")


def warn(msg: str) -> None:
    print(f"[WARN] {msg}")


def err(msg: str) -> None:
    print(f"[ERR]  {msg}", file=sys.stderr)


# --------------------------------------------------------------------------- #
# Lazy importers — keep the top-level import graph small and resilient.
# --------------------------------------------------------------------------- #
def _import_rdp():
    from .rdp import runner

    return runner


def _import_tunnel():
    from .tunnel import manager

    return manager


def _import_vm():
    from .vm import manager

    return manager


def _import_platforms():
    from .platforms import installer

    return installer


def _missing_module(name: str) -> int:
    err(
        f"Module '{name}' is not available yet. "
        "Other agents are building it — re-run after the package is complete."
    )
    return 2


# --------------------------------------------------------------------------- #
# Subcommand handlers
# --------------------------------------------------------------------------- #
def cmd_install(args: argparse.Namespace) -> int:
    plat = args.platform or detect_platform()
    info(f"Installing dependencies for platform: {plat}")
    if not is_root() and plat in ("kali", "ubuntu"):
        warn("Not running as root — some packages may fail. Re-run with sudo if so.")
    try:
        installer = _import_platforms()
    except ImportError:
        return _missing_module("rdp_toolkit.platforms.installer")
    try:
        result = installer.install_for_platform(plat)
        ok(f"Install complete: {result}")
    except Exception as exc:  # pragma: no cover - depends on sibling module
        err(f"Install failed: {exc}")
        return 3
    return 0


def cmd_start(args: argparse.Namespace) -> int:
    info(f"Starting RDP session: profile={args.profile}, hours={args.hours}")
    try:
        runner = _import_rdp()
    except ImportError:
        return _missing_module("rdp_toolkit.rdp.runner")
    try:
        run = runner.start_session(profile=args.profile, hours=args.hours)
        run_id = run.get("id", "?") if isinstance(run, dict) else "?"
        ok(f"Session started: run-id={run_id}")
        if isinstance(run, dict):
            if run.get("tunnel_url"):
                info(f"Tunnel URL: {run['tunnel_url']}")
            if run.get("password"):
                info(f"Password: {run['password']}")
    except Exception as exc:  # pragma: no cover - depends on sibling module
        err(f"Failed to start session: {exc}")
        return 3
    return 0


def cmd_stop(args: argparse.Namespace) -> int:
    info("Stopping active RDP session(s)...")
    try:
        runner = _import_rdp()
    except ImportError:
        return _missing_module("rdp_toolkit.rdp.runner")
    try:
        stopped = runner.stop_all()
        ok(f"Stopped {stopped} session(s).")
    except Exception as exc:  # pragma: no cover - depends on sibling module
        err(f"Stop failed: {exc}")
        return 3
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    info("Active runs:")
    try:
        runner = _import_rdp()
    except ImportError:
        return _missing_module("rdp_toolkit.rdp.runner")
    try:
        runs = runner.list_runs() or []
    except Exception as exc:  # pragma: no cover - depends on sibling module
        err(f"Status failed: {exc}")
        return 3
    if not runs:
        info("  (no active runs)")
        return 0
    for run in runs:
        rid = str(run.get("id", "?"))[:12]
        status = str(run.get("status", "?"))[:8]
        tunnel = run.get("tunnel_url") or run.get("tunnel") or "n/a"
        print(f"  - {rid:12} | {status:8} | tunnel={tunnel}")
    ok(f"{len(runs)} active run(s).")
    return 0


def cmd_connect(args: argparse.Namespace) -> int:
    try:
        runner = _import_rdp()
    except ImportError:
        return _missing_module("rdp_toolkit.rdp.runner")
    try:
        cmd_str = runner.connect_command(args.run_id)
    except Exception as exc:  # pragma: no cover - depends on sibling module
        err(f"Connect failed: {exc}")
        return 3
    ok("Ready-to-paste xfreerdp command:")
    print(cmd_str)
    return 0


def cmd_config(args: argparse.Namespace) -> int:
    plat = args.platform or detect_platform()
    info(f"Generating config for platform: {plat}")
    try:
        path = generate_config(platform=plat)
    except Exception as exc:
        err(f"Config generation failed: {exc}")
        return 3
    ok(f"Config written: {path}")
    return 0


def cmd_tunnel(args: argparse.Namespace) -> int:
    try:
        manager = _import_tunnel()
    except ImportError:
        return _missing_module("rdp_toolkit.tunnel.manager")
    try:
        if args.action == "list":
            tunnels = manager.list_tunnels() or []
            if not tunnels:
                info("No tunnels configured.")
            for t in tunnels:
                prov = str(t.get("provider", "?"))[:14]
                url = t.get("url") or t.get("endpoint") or "n/a"
                print(f"  - {prov:14} | {url}")
            ok(f"{len(tunnels)} tunnel(s).")
        elif args.action == "status":
            statuses = manager.status() or {}
            if not statuses:
                info("No tunnel status available.")
            for prov, st in statuses.items():
                alive = st.get("alive", False) if isinstance(st, dict) else False
                tag = "[OK]  " if alive else "[--]  "
                url = (st.get("url") if isinstance(st, dict) else None) or "n/a"
                print(f"  {tag} {prov:14} | {url}")
        elif args.action == "test":
            provider = args.provider or "all"
            info(f"Testing tunnel provider(s): {provider}")
            result = manager.test(provider)
            ok(f"Tunnel test result: {result}")
    except Exception as exc:  # pragma: no cover - depends on sibling module
        err(f"Tunnel command failed: {exc}")
        return 3
    return 0


def cmd_vm(args: argparse.Namespace) -> int:
    try:
        manager = _import_vm()
    except ImportError:
        return _missing_module("rdp_toolkit.vm.manager")
    name = args.name or "kali"
    try:
        if args.action == "start":
            info(f"Starting VM: {name}")
            manager.start(name)
            ok(f"VM '{name}' started.")
        elif args.action == "stop":
            info(f"Stopping VM: {name}")
            manager.stop(name)
            ok(f"VM '{name}' stopped.")
        elif args.action == "shell":
            info(f"Opening shell in VM: {name}")
            manager.shell(name)
    except Exception as exc:  # pragma: no cover - depends on sibling module
        err(f"VM command failed: {exc}")
        return 3
    return 0


def cmd_rotate(args: argparse.Namespace) -> int:
    target = args.run_id or "latest"
    info(f"Rotating password for run: {target}")
    try:
        runner = _import_rdp()
    except ImportError:
        return _missing_module("rdp_toolkit.rdp.runner")
    try:
        new_pwd = runner.rotate_password(args.run_id)
        ok("Password rotated.")
        info(f"New password: {new_pwd}")
    except Exception as exc:  # pragma: no cover - depends on sibling module
        err(f"Rotate failed: {exc}")
        return 3
    return 0


def cmd_kill(args: argparse.Namespace) -> int:
    target = args.target or "all"
    info(f"Killing run(s): {target}")
    try:
        runner = _import_rdp()
    except ImportError:
        return _missing_module("rdp_toolkit.rdp.runner")
    try:
        killed = runner.kill(target)
        ok(f"Killed {killed} run(s).")
    except Exception as exc:  # pragma: no cover - depends on sibling module
        err(f"Kill failed: {exc}")
        return 3
    return 0


def cmd_doctor(args: argparse.Namespace) -> int:
    info(f"RDP Mega Toolkit v{__version__} — diagnostics")
    plat = detect_platform()
    print(f"  Platform:    {plat}")
    print(f"  Root/Admin:  {is_root()}")
    print(f"  Python:      {sys.version.split()[0]}")
    print(f"  Config dir:  ~/.config/rdp-toolkit/")

    binaries = ["xfreerdp", "xfreerdp2", "ssh", "socat", "curl", "cloudflared", "docker", "lt"]
    found = 0
    for binary in binaries:
        path = which(binary)
        tag = "[OK]   " if path else "[MISS] "
        print(f"  {tag} {binary:12} {path or 'not found'}")
        if path:
            found += 1
    info(f"Binaries found: {found}/{len(binaries)}")

    # Probe sibling subpackages without executing their logic.
    submodules = {
        "rdp.runner": "from .rdp import runner",
        "tunnel.manager": "from .tunnel import manager",
        "vm.manager": "from .vm import manager",
        "platforms.installer": "from .platforms import installer",
        "notify": "from .notify import notifier",
    }
    import importlib

    for label, stmt in submodules.items():
        mod_name = stmt.split()[-1]
        try:
            importlib.import_module(f"rdp_toolkit.{label}" if "." in label else f"rdp_toolkit.{mod_name}")
            print(f"  [OK]   module {label}")
        except Exception:
            print(f"  [PEND] module {label} (not built yet)")

    try:
        cfg = load_config()
        ok(
            f"Config OK: platform={cfg.get('platform')}, "
            f"profile={cfg.get('profile')}, "
            f"hours={cfg.get('session', {}).get('hours')}"
        )
    except Exception as exc:
        err(f"Config load failed: {exc}")
        return 3
    return 0


# --------------------------------------------------------------------------- #
# Argument parser construction
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="rdp_toolkit",
        description="GitHub RDP Mega Toolkit v9 — cross-platform RDP automation.",
    )
    parser.add_argument(
        "-V", "--version", action="version", version=f"rdp_toolkit {__version__}"
    )
    sub = parser.add_subparsers(dest="command", required=True, metavar="<command>")

    # install ------------------------------------------------------------- #
    p = sub.add_parser("install", help="install platform dependencies")
    p.add_argument(
        "--platform",
        choices=["kali", "windows", "android", "ubuntu"],
        default=None,
        help="target platform (default: auto-detect)",
    )
    p.set_defaults(func=cmd_install)

    # start --------------------------------------------------------------- #
    p = sub.add_parser("start", help="start an RDP session")
    p.add_argument("--hours", type=int, default=6, help="session duration in hours")
    p.add_argument(
        "--profile",
        choices=["productivity", "gaming", "minimal"],
        default="productivity",
        help="optimization profile",
    )
    p.set_defaults(func=cmd_start)

    # stop ---------------------------------------------------------------- #
    p = sub.add_parser("stop", help="stop active RDP session(s)")
    p.set_defaults(func=cmd_stop)

    # status -------------------------------------------------------------- #
    p = sub.add_parser("status", help="show active runs")
    p.set_defaults(func=cmd_status)

    # connect ------------------------------------------------------------- #
    p = sub.add_parser("connect", help="print ready-to-paste xfreerdp command")
    p.add_argument("run_id", nargs="?", default=None, help="run-id (default: latest)")
    p.set_defaults(func=cmd_connect)

    # config -------------------------------------------------------------- #
    p = sub.add_parser("config", help="auto-generate YAML config")
    p.add_argument(
        "--platform",
        choices=["kali", "windows", "android", "ubuntu"],
        default=None,
        help="target platform (default: auto-detect)",
    )
    p.set_defaults(func=cmd_config)

    # tunnel -------------------------------------------------------------- #
    p = sub.add_parser("tunnel", help="manage tunnels")
    p.add_argument("action", choices=["list", "status", "test"], help="tunnel sub-action")
    p.add_argument("provider", nargs="?", default=None, help="provider name (for 'test')")
    p.set_defaults(func=cmd_tunnel)

    # vm ------------------------------------------------------------------ #
    p = sub.add_parser("vm", help="manage Docker VMs")
    p.add_argument("action", choices=["start", "stop", "shell"], help="vm sub-action")
    p.add_argument(
        "name",
        nargs="?",
        default="kali",
        choices=["kali", "ubuntu", "windows"],
        help="VM name (default: kali)",
    )
    p.set_defaults(func=cmd_vm)

    # rotate -------------------------------------------------------------- #
    p = sub.add_parser("rotate", help="rotate password for a run")
    p.add_argument("run_id", nargs="?", default=None, help="run-id (default: latest)")
    p.set_defaults(func=cmd_rotate)

    # kill ---------------------------------------------------------------- #
    p = sub.add_parser("kill", help="cancel runs")
    p.add_argument(
        "target",
        nargs="?",
        default="all",
        help="run-id or 'all' (default: all)",
    )
    p.set_defaults(func=cmd_kill)

    # doctor -------------------------------------------------------------- #
    p = sub.add_parser("doctor", help="diagnose installation")
    p.set_defaults(func=cmd_doctor)

    return parser


def main(argv: Optional[List[str]] = None) -> int:
    """CLI entry point. Returns a POSIX exit code."""
    parser = build_parser()
    args = parser.parse_args(argv)
    func: Callable[[argparse.Namespace], Any] = args.func
    try:
        rc = func(args)
    except KeyboardInterrupt:
        warn("Interrupted by user.")
        return 130
    return int(rc or 0)
