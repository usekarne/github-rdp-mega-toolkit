#Requires -Version 7.0
<#
    .SYNOPSIS
        Applies a system-optimisation profile (productivity / gaming / minimal)
        to the Windows runner.

    .DESCRIPTION
        Profiles control which services are disabled, which telemetry
        switches are flipped, what visual effects are used, what power plan
        is active, and whether sleep is allowed.

        All changes are reversible — the cleanup script re-enables anything
        that should come back at session end.
#>
[CmdletBinding()]
param(
    [ValidateSet('productivity', 'gaming', 'minimal')]
    [string]$Profile = 'productivity'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/utils.ps1"

Write-Block "Applying Windows profile: $Profile"

# ---------------------------------------------------------------------------
# Services to disable per profile
# ---------------------------------------------------------------------------
$serviceMatrix = @{
    productivity = @(
        'DiagTrack', 'WSearch', 'SysMain', 'DiagnosisHost'
    )
    gaming = @(
        'DiagTrack', 'WSearch', 'SysMain', 'DiagnosisHost', 'wuauserv'
    )
    minimal = @(
        'DiagTrack', 'WSearch', 'SysMain', 'DiagnosisHost', 'wuauserv',
        'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc',
        'WMPNetworkSvc', 'Fax', 'fhsvc', 'SCardSvr', 'SCPolicySvr'
    )
}
$services = $serviceMatrix[$Profile]
foreach ($svc in $services) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if (-not $s) {
        Write-Warn "Service '$svc' not present — skipping."
        continue
    }
    try {
        if ($s.Status -eq 'Running') {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        }
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Ok "Disabled service: $svc"
    } catch {
        Write-Warn "Could not disable '$svc': $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Disable Xbox services explicitly for gaming & minimal (they interfere
# with input latency and consume RAM on tiny VMs).
# ---------------------------------------------------------------------------
if ($Profile -in @('gaming', 'minimal')) {
    foreach ($svc in @('XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc')) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -eq 'Running') {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Telemetry — set registry keys to disable (or restrict to 'security' only).
# ---------------------------------------------------------------------------
Write-Block 'Disabling telemetry'
$telemetryKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
if (-not (Test-Path $telemetryKey)) {
    New-Item -Path $telemetryKey -Force | Out-Null
}
Set-ItemProperty -Path $telemetryKey -Name 'AllowTelemetry' -Value 0 -Type DWord -Force
Set-ItemProperty -Path $telemetryKey -Name 'MaxTelemetryAllowed' -Value 0 -Type DWord -Force
Write-Ok 'AllowTelemetry=0 (security-only)'

# Disable Cortana (no-op on Server, fine on client SKUs).
$cortanaKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
if (-not (Test-Path $cortanaKey)) {
    New-Item -Path $cortanaKey -Force | Out-Null
}
Set-ItemProperty -Path $cortanaKey -Name 'AllowCortana' -Value 0 -Type DWord -Force
Set-ItemProperty -Path $cortanaKey -Name 'AllowSearchToUseLocation' -Value 0 -Type DWord -Force
Write-Ok 'Cortana + search-location disabled'

# ---------------------------------------------------------------------------
# Visual effects — set VisualFXSetting to match profile
#   0 = let Windows choose  1 = best appearance  2 = best performance  3 = custom
# ---------------------------------------------------------------------------
Write-Block 'Setting visual effects'
$visualValue = switch ($Profile) {
    'productivity' { 0 }
    'gaming'       { 2 }   # best performance (input latency)
    'minimal'      { 2 }
}
$visualKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
if (-not (Test-Path $visualKey)) {
    New-Item -Path $visualKey -Force | Out-Null
}
Set-ItemProperty -Path $visualKey -Name 'VisualFXSetting' -Value $visualValue -Type DWord -Force
Write-Ok "VisualFXSetting=$visualValue"

# ---------------------------------------------------------------------------
# Disable sleep / hibernate; require password on wake.
# ---------------------------------------------------------------------------
Write-Block 'Disabling sleep / hibernate'
powercfg /change standby-timeout-ac 0 | Out-Null
powercfg /change standby-timeout-dc 0 | Out-Null
powercfg /change hibernate-timeout-ac 0 | Out-Null
powercfg /change hibernate-timeout-dc 0 | Out-Null
powercfg /change monitor-timeout-ac 10 | Out-Null
powercfg /change monitor-timeout-dc 5 | Out-Null
powercfg /hibernate off | Out-Null
Write-Ok 'Sleep / hibernate disabled (monitor dims only)'

# ---------------------------------------------------------------------------
# High Performance power plan (active)
# ---------------------------------------------------------------------------
Write-Block 'Setting High Performance power plan'
$guid = (powercfg /list | Select-String 'High performance').ToString() -replace '.*:\s*', ''
if ($guid) {
    $guid = ($guid -split '\s+')[0]
    powercfg /setactive $guid | Out-Null
    Write-Ok "Power plan GUID active: $guid"
} else {
    Write-Warn 'High performance plan not found — copying from balanced.'
    $dup = (powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61) 2>&1
    if ($dup -match '([0-9a-f-]{36})') {
        powercfg /setactive $Matches[1] | Out-Null
        Write-Ok "Duplicated high-performance plan: $($Matches[1])"
    }
}

# ---------------------------------------------------------------------------
# Gaming extras: enable Game Mode, disable Game Bar auto-launch.
# ---------------------------------------------------------------------------
if ($Profile -eq 'gaming') {
    Write-Block 'Gaming extras'
    $gmKey = 'HKCU:\Software\Microsoft\GameBar'
    if (-not (Test-Path $gmKey)) { New-Item -Path $gmKey -Force | Out-Null }
    Set-ItemProperty -Path $gmKey -Name 'AutoGameModeEnabled' -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $gmKey -Name 'AllowAutoGameMode'   -Value 1 -Type DWord -Force
    Write-Ok 'Game Mode enabled'
}

Write-Block "optimize-windows.ps1 ($Profile) complete"
exit 0
