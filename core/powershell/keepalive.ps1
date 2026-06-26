# core/powershell/keepalive.ps1 - Hold the RDP session open with heartbeat logging
. "$PSScriptRoot\utils.ps1"

$Hours = if ($env:SESSION_HOURS) { [double]$env:SESSION_HOURS } else { 6 }
$HeartbeatSec = if ($env:HEARTBEAT_SEC) { [int]$env:HEARTBEAT_SEC } else { 300 }

$end = (Get-Date).AddHours($Hours)
Write-Block "KEEP ALIVE - ${Hours}hr session, heartbeat every ${HeartbeatSec}s"
Write-Info "Session will end at $end (UTC)"

$iter = 0
while ((Get-Date) -lt $end) {
    $iter++
    $rem = [math]::Round(($end - (Get-Date)).TotalSeconds)
    $h = [math]::Floor($rem / 3600)
    $m = [math]::Floor(($rem - ($h * 3600)) / 60)
    $s = $rem - ($h * 3600) - ($m * 60)

    $rdpPort = if (Test-Port -Port 3389) { 'OK' } else { 'DOWN' }
    $tunnel  = if ($env:TUNNEL_URL) { $env:TUNNEL_URL } else { 'n/a' }

    Write-Host "[Heartbeat #$iter] Remaining: ${h}h ${m}m ${s}s | RDP: $rdpPort | Tunnel: $tunnel"

    if ($iter % 6 -eq 0) {
        Send-Notify -Title "RDP Heartbeat #$iter" -Body "Remaining: ${h}h ${m}m`nRDP port: $rdpPort`nTunnel: $tunnel"
    }

    Start-Sleep -Seconds $HeartbeatSec
}

Write-Warn 'Session time expired.'
