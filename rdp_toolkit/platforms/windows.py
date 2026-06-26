"""Windows setup helpers (used on a Windows runner).

These wrap common Windows-specific actions: enabling RDP, creating the
runner user, opening firewall rules, and downloading cloudflared.exe.  The
heavy lifting is in ``core_ps/*.ps1``; this module exposes Python-friendly
wrappers for use from the CLI / installer dispatcher.
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import List, Optional

from ..utils.system import run, which

__all__ = [
    "is_windows",
    "powershell_available",
    "run_ps_script",
    "enable_rdp",
    "disable_rdp",
    "create_runner_user",
    "open_firewall_3389",
    "close_firewall_3389",
    "download_cloudflared",
    "set_high_performance_plan",
    "disable_sleep",
]


def is_windows() -> bool:
    """Return ``True`` when running on a Windows NT kernel."""
    return os.name == "nt"


def powershell_available() -> bool:
    """Return ``True`` when PowerShell 7+ (``pwsh``) or Windows PowerShell is available."""
    return bool(which("pwsh") or which("powershell"))


def _ps_binary() -> str:
    return which("pwsh") or which("powershell") or "powershell"


def run_ps_script(
    script: Path,
    *,
    args: Optional[List[str]] = None,
    capture: bool = True,
    check: bool = False,
) -> subprocess.CompletedProcess:
    """Invoke a PowerShell script with -NoProfile and -ExecutionPolicy Bypass."""
    if not script.exists():
        raise FileNotFoundError(f"PowerShell script not found: {script}")
    cmd = [
        _ps_binary(),
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", str(script),
    ]
    if args:
        cmd.extend(args)
    return run(cmd, capture=capture, check=check)


def enable_rdp() -> subprocess.CompletedProcess:
    """Enable RDP in registry + start TermService via PowerShell."""
    # Equivalent to:
    #   Set-ItemProperty 'HKLM:\...\Terminal Server' -Name fDenyTSConnections -Value 0
    ps = (
        "$ErrorActionPreference='Stop';"
        "$k='HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server';"
        "Set-ItemProperty -Path $k -Name fDenyTSConnections -Value 0 -Type DWord -Force;"
        "$ws = Join-Path $k 'WinStations\\RDP-Tcp';"
        "if (Test-Path $ws) { Set-ItemProperty -Path $ws -Name UserAuthentication -Value 0 -Type DWord -Force };"
        "Set-Service -Name TermService -StartupType Automatic;"
        "Start-Service -Name TermService"
    )
    return run([_ps_binary(), "-NoProfile", "-Command", ps], capture=True, check=False)


def disable_rdp() -> subprocess.CompletedProcess:
    """Inverse of :func:`enable_rdp`."""
    ps = (
        "$ErrorActionPreference='Continue';"
        "$k='HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server';"
        "Set-ItemProperty -Path $k -Name fDenyTSConnections -Value 1 -Type DWord -Force;"
        "Stop-Service -Name TermService -Force -ErrorAction SilentlyContinue;"
        "Set-Service -Name TermService -StartupType Disabled -ErrorAction SilentlyContinue"
    )
    return run([_ps_binary(), "-NoProfile", "-Command", ps], capture=True, check=False)


def create_runner_user(
    username: str = "runner",
    password: Optional[str] = None,
) -> subprocess.CompletedProcess:
    """Create the local ``runner`` user with the given (or generated) password."""
    if password is None:
        # Defer to New-RandomPassword in utils.ps1 via a tiny script.
        script_dir = Path(__file__).resolve().parent.parent / "core_ps"
        pw_script = (
            f". '{script_dir / 'utils.ps1'}'; "
            "New-RandomPassword"
        )
        proc = run([_ps_binary(), "-NoProfile", "-Command", pw_script],
                   capture=True, check=True)
        password = proc.stdout.strip()
    ps = (
        f"$u='{username}'; $p='{password}'; "
        "$ErrorActionPreference='Stop';"
        "if (Get-LocalUser -Name $u -ErrorAction SilentlyContinue) { "
        "  Set-LocalUser -Name $u -Password ($p | ConvertTo-SecureString -AsPlainText -Force) "
        "} else { "
        "  New-LocalUser -Name $u -Password ($p | ConvertTo-SecureString -AsPlainText -Force) "
        "    -FullName 'RDP Runner' -Description 'GitHub Actions RDP runner' "
        "    -PasswordNeverExpires -UserMayNotChangePassword | Out-Null "
        "}; "
        "Add-LocalGroupMember -Group Administrators -Member $u -ErrorAction SilentlyContinue; "
        "Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $u -ErrorAction SilentlyContinue"
    )
    return run([_ps_binary(), "-NoProfile", "-Command", ps], capture=True, check=False)


def open_firewall_3389() -> subprocess.CompletedProcess:
    """Allow inbound TCP + UDP 3389."""
    ps = (
        "$ErrorActionPreference='Continue';"
        "Get-NetFirewallRule -Name 'RDP-Mega-Toolkit-*' -ErrorAction SilentlyContinue | "
        "  Remove-NetFirewallRule -ErrorAction SilentlyContinue;"
        "New-NetFirewallRule -Name 'RDP-Mega-Toolkit-TCP-In' -DisplayName 'RDP-Mega-Toolkit-TCP-In' "
        "  -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 -Profile Any | Out-Null;"
        "New-NetFirewallRule -Name 'RDP-Mega-Toolkit-UDP-In' -DisplayName 'RDP-Mega-Toolkit-UDP-In' "
        "  -Direction Inbound -Action Allow -Protocol UDP -LocalPort 3389 -Profile Any | Out-Null"
    )
    return run([_ps_binary(), "-NoProfile", "-Command", ps], capture=True, check=False)


def close_firewall_3389() -> subprocess.CompletedProcess:
    """Remove the toolkit's inbound 3389 firewall rules."""
    ps = (
        "$ErrorActionPreference='Continue';"
        "Get-NetFirewallRule -DisplayName 'RDP-Mega-Toolkit-*' -ErrorAction SilentlyContinue | "
        "  Remove-NetFirewallRule -ErrorAction SilentlyContinue"
    )
    return run([_ps_binary(), "-NoProfile", "-Command", ps], capture=True, check=False)


def download_cloudflared(dest: Path) -> Path:
    """Download cloudflared.exe into ``dest`` (overwriting if present)."""
    if not is_windows():
        raise RuntimeError("download_cloudflared is Windows-only")
    url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    # Use PowerShell's Invoke-WebRequest so we don't depend on curl being on PATH.
    ps = (
        f"$ErrorActionPreference='Stop';"
        f"Invoke-WebRequest -Uri '{url}' -OutFile '{dest}' -UseBasicParsing -TimeoutSec 60"
    )
    proc = run([_ps_binary(), "-NoProfile", "-Command", ps], capture=True, check=True)
    if not dest.exists():
        raise RuntimeError(
            f"cloudflared download reported success but {dest} does not exist"
        )
    return dest


def set_high_performance_plan() -> subprocess.CompletedProcess:
    """Activate the High Performance power plan."""
    ps = (
        "$ErrorActionPreference='Continue';"
        "$g = (powercfg /list | Select-String 'High performance');"
        "if ($g) { $id = ($g.ToString() -split '\\s+' | Select-Object -Skip 2 | Select-Object -First 1); "
        "  if ($id) { powercfg /setactive $id | Out-Null } }"
    )
    return run([_ps_binary(), "-NoProfile", "-Command", ps], capture=True, check=False)


def disable_sleep() -> subprocess.CompletedProcess:
    """Disable sleep + hibernate (monitor dims only)."""
    ps = (
        "powercfg /change standby-timeout-ac 0; "
        "powercfg /change standby-timeout-dc 0; "
        "powercfg /change hibernate-timeout-ac 0; "
        "powercfg /change hibernate-timeout-dc 0; "
        "powercfg /hibernate off"
    )
    return run([_ps_binary(), "-NoProfile", "-Command", ps], capture=True, check=False)
