#Requires -Version 7.0
<#
    .SYNOPSIS
        Reverses everything setup-rdp + setup-tunnel did.

    .DESCRIPTION
        Designed to be safe to run multiple times and to run on
        `if: always()` — every step is wrapped in try/catch.

        Steps:
          1. Kill any SSH / cloudflared tunnel jobs.
          2. Remove firewall rules RDP-Mega-Toolkit-*.
          3. Stop TermService and disable it.
          4. Disable RDP in registry.
          5. Remove the local 'runner' user (if present).
          6. Remove artifact files (configurable via KEEP_ARTIFACTS=1).
#>
[CmdletBinding()]
param(
    [string]$Username = 'runner'
)

Set-StrictMode -Version Latest
# Deliberately NON-STOP — cleanup must be best-effort.
$ErrorActionPreference = 'Continue'

. "$PSScriptRoot/utils.ps1"

function Invoke-SafeStep {
    [CmdletBinding()]
    param([string]$Name, [scriptblock]$Block)
    try {
        & $Block
    } catch {
        Write-Warn "Step '$Name' failed: $($_.Exception.Message)"
    }
}

Write-Block 'cleanup.ps1 — best-effort teardown'

# ---------------------------------------------------------------------------
# 1. Kill tunnels
# ---------------------------------------------------------------------------
Invoke-SafeStep 'Stop tunnel jobs' {
    # Tunnel SSH / cloudflared processes spawned by setup-tunnel.ps1.
    $names = @('ssh', 'cloudflared')
    foreach ($n in $names) {
        Get-Process -Name $n -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -and $_.Path -match 'rdp' -or $_.CommandLine -match 'serveo|localhost\.run|trycloudflare' } |
            ForEach-Object {
                Write-Info "Killing tunnel process $($_.Id) ($($_.Name))"
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
    }
    # PowerShell background jobs created by Start-Job.
    Get-Job -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -in @('serveo', 'localhostrun', 'cloudflared')
    } | ForEach-Object {
        Write-Info "Stopping job $($_.Name) (id $($_.Id))"
        Stop-Job $_ -ErrorAction SilentlyContinue
        Remove-Job $_ -Force -ErrorAction SilentlyContinue
    }
    Write-Ok 'Tunnel processes cleaned up'
}

# ---------------------------------------------------------------------------
# 2. Remove firewall rules
# ---------------------------------------------------------------------------
Invoke-SafeStep 'Remove firewall rules' {
    Get-NetFirewallRule -DisplayName 'RDP-Mega-Toolkit-*' -ErrorAction SilentlyContinue |
        ForEach-Object {
            Write-Info "Removing firewall rule $($_.DisplayName)"
            Remove-NetFirewallRule -Name $_.Name -ErrorAction SilentlyContinue
        }
    Get-NetFirewallRule -Name 'RDP-Mega-Toolkit-*' -ErrorAction SilentlyContinue |
        ForEach-Object {
            Remove-NetFirewallRule -Name $_.Name -ErrorAction SilentlyContinue
        }
    Write-Ok 'Firewall rules removed'
}

# ---------------------------------------------------------------------------
# 3. Stop + disable TermService
# ---------------------------------------------------------------------------
Invoke-SafeStep 'Stop TermService' {
    $svc = Get-Service -Name 'TermService' -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -eq 'Running') {
            Stop-Service -Name 'TermService' -Force -ErrorAction SilentlyContinue
            Write-Ok 'TermService stopped'
        }
        Set-Service -Name 'TermService' -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Ok 'TermService set to Disabled'
    } else {
        Write-Warn 'TermService not found.'
    }
}

# ---------------------------------------------------------------------------
# 4. Disable RDP in registry
# ---------------------------------------------------------------------------
Invoke-SafeStep 'Disable RDP in registry' {
    $tsKey = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
    if (Test-Path $tsKey) {
        Set-ItemProperty -Path $tsKey -Name 'fDenyTSConnections' -Value 1 -Type DWord -Force
        Write-Ok 'fDenyTSConnections set to 1 (RDP disabled)'
    }
    $winStations = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
    if (Test-Path $winStations) {
        Set-ItemProperty -Path $winStations -Name 'UserAuthentication' -Value 1 -Type DWord -Force
    }
}

# ---------------------------------------------------------------------------
# 5. Remove local user
# ---------------------------------------------------------------------------
Invoke-SafeStep "Remove local user '$Username'" {
    $u = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if ($u) {
        # Best-effort remove from groups first.
        Remove-LocalGroupMember -Group 'Administrators'       -Member $Username -ErrorAction SilentlyContinue
        Remove-LocalGroupMember -Group 'Remote Desktop Users' -Member $Username -ErrorAction SilentlyContinue
        Remove-LocalUser -Name $Username -ErrorAction SilentlyContinue
        Write-Ok "User '$Username' removed"
    } else {
        Write-Warn "User '$Username' not present."
    }
}

# ---------------------------------------------------------------------------
# 6. Remove artifact files (unless KEEP_ARTIFACTS=1)
# ---------------------------------------------------------------------------
Invoke-SafeStep 'Clean artifact files' {
    if ($env:KEEP_ARTIFACTS -eq '1') {
        Write-Info 'KEEP_ARTIFACTS=1 — leaving artifact files in place.'
        return
    }
    $dir = Get-ArtifactDir
    $files = @(
        'rdp-password.txt', 'RDP_USERNAME.txt', 'RDP_PASSWORD.txt',
        'rdp-summary.json',
        'tunnel-info.txt', 'tunnel-type.txt', 'tunnel-host.txt', 'tunnel-port.txt',
        'connect-info.txt',
        'serveo.log', 'localhostrun.log', 'cloudflared.log',
        'keepalive.log', 'health-status.json'
    )
    foreach ($f in $files) {
        $p = Join-Path $dir $f
        if (Test-Path $p) {
            Remove-Item -Path $p -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Ok 'Artifact files removed'
}

Write-Block 'cleanup.ps1 complete'
exit 0
