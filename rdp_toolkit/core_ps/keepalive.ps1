#Requires -Version 7.0
<#
    .SYNOPSIS
        Keeps the GitHub Actions runner session alive for $env:SESSION_HOURS
        by emitting a heartbeat every 5 minutes.

    .DESCRIPTION
        Loops until (StartTime + SESSION_HOURS) is reached, writing a
        timestamped heartbeat line to keepalive.log.  Exits 0 on natural
        expiry, non-zero if SESSION_HOURS is missing or invalid.
#>
[CmdletBinding()]
param(
    [int]$HeartbeatSec = 300  # 5 minutes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/utils.ps1"

if (-not $env:SESSION_HOURS -or $env:SESSION_HOURS -notmatch '^\d+$') {
    Write-Err 'SESSION_HOURS env var is missing or not an integer.'
    exit 1
}
$hours = [int]$env:SESSION_HOURS
if ($hours -le 0) {
    Write-Err "SESSION_HOURS must be > 0 (got $hours)"
    exit 1
}

$start = Get-Date
$end   = $start.AddHours($hours)
Write-Block "Keepalive starting — will run until $end ($hours h)"
Write-Info "Heartbeat interval: $HeartbeatSec s"

$dir = Get-ArtifactDir
$log = Join-Path $dir 'keepalive.log'
"[$($start.ToString('o'))] keepalive start, hours=$hours" | Out-File -FilePath $log -Append -Encoding UTF8

$heartbeatCount = 0
try {
    while ($true) {
        $now = Get-Date
        if ($now -ge $end) {
            Write-Ok "Reached SESSION_HOURS deadline ($end). Exiting."
            break
        }
        $remaining = ($end - $now).TotalMinutes
        $heartbeatCount++

        # Health snapshot so an operator can spot the runner becoming wedged.
        $cpu = (Get-CimInstance Win32_Processor).LoadPercentage
        $mem = Get-CimInstance Win32_OperatingSystem
        $freePct = [math]::Round(($mem.FreePhysicalMemory / $mem.TotalVisibleMemorySize) * 100, 1)
        $svc = Get-Service -Name 'TermService' -ErrorAction SilentlyContinue
        $svcState = if ($svc) { $svc.Status } else { 'missing' }
        $ts = $now.ToString('o')
        $line = "[$ts] heartbeat #$heartbeatCount  remaining=$($remaining.ToString('0.0'))min  cpu=${cpu}%  mem_free=${freePct}%  TermService=$svcState"
        Write-Info $line
        $line | Out-File -FilePath $log -Append -Encoding UTF8

        # Heartbeat every 30 minutes — push a notify ping so the operator
        # can confirm the runner is still responsive.
        if ($heartbeatCount % 6 -eq 0) {
            Send-Notify -Message "RDP session alive — $([math]::Round($remaining,1)) min remaining" -Title 'Heartbeat' | Out-Null
        }
        Start-Sleep -Seconds $HeartbeatSec
    }
} finally {
    $endTs = (Get-Date).ToString('o')
    "[$endTs] keepalive exit, heartbeats=$heartbeatCount" | Out-File -FilePath $log -Append -Encoding UTF8
}
exit 0
