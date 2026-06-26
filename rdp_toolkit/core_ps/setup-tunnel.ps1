#Requires -Version 7.0
<#
    .SYNOPSIS
        Establishes a public TCP tunnel to local RDP (3389) using one of
        serveo / localhost.run / cloudflare — NO NGROK.

    .DESCRIPTION
        Reads $env:TUNNEL_PROVIDERS (comma-separated, default:
        'serveo,localhost.run,cloudflare') and tries each in order.
        First provider that exposes a routable hostname:port wins.

        Output files (written to $env:RDP_ARTIFACT_DIR or ./rdp-artifacts):
          tunnel-info.txt   — human-readable summary
          tunnel-type.txt   — 'serveo' | 'localhost.run' | 'cloudflare'
          tunnel-host.txt   — hostname
          tunnel-port.txt   — remote port (for SSH-based providers)
          connect-info.txt  — TWO lines (BRIDGE_CMD\r\nCONNECT_CMD) so the
                               Python runner can splitlines() reliably.
#>
[CmdletBinding()]
param(
    [int]$LocalPort = 3389,
    [int]$ConnectTimeoutSec = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/utils.ps1"

$dir = Get-ArtifactDir
$providers = if ($env:TUNNEL_PROVIDERS) {
    $env:TUNNEL_PROVIDERS -split ',\s*' | Where-Object { $_ }
} else {
    @('serveo', 'localhost.run', 'cloudflare')
}
Write-Info "Tunnel providers (priority): $($providers -join ' -> ')"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Test-SshAvailable {
    $ssh = Get-Command ssh -ErrorAction SilentlyContinue
    if (-not $ssh) {
        Write-Warn 'ssh client not found on PATH — skipping SSH-based providers.'
        return $false
    }
    return $true
}

function Save-TunnelInfo {
    [CmdletBinding()]
    param(
        [string]$Type,
        [string]$Host,
        [int]$Port,
        [string]$BridgeCmd,
        [string]$ConnectCmd,
        [string]$Extra = ''
    )
    $info = @(
        "Tunnel type: $Type",
        "Host:        $Host",
        "Port:        $Port",
        "Local port:  $LocalPort",
        "Started at:  $((Get-Date).ToString('o'))",
        "Public IP:   $(Get-PublicIp)",
        if ($Extra) { $Extra } else { '' }
    ) | Where-Object { $_ } -join "`n"

    Set-Content -Path (Join-Path $dir 'tunnel-info.txt')  -Value $info -Encoding UTF8
    Set-Content -Path (Join-Path $dir 'tunnel-type.txt')  -Value $Type -NoNewline -Encoding UTF8
    Set-Content -Path (Join-Path $dir 'tunnel-host.txt')  -Value $Host -NoNewline -Encoding UTF8
    Set-Content -Path (Join-Path $dir 'tunnel-port.txt')  -Value $Port -NoNewline -Encoding UTF8
    # IMPORTANT: two separate lines joined by CRLF (per runner.py spec).
    $conn = "$BridgeCmd`r`n$ConnectCmd"
    Set-Content -Path (Join-Path $dir 'connect-info.txt') -Value $conn -NoNewline -Encoding UTF8
    Write-Ok "Saved tunnel artifacts to $dir"
    Write-Info "BRIDGE_CMD:   $BridgeCmd"
    Write-Info "CONNECT_CMD:  $ConnectCmd"
}

function New-BackgroundJob {
    [CmdletBinding()]
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock
    )
    $j = Start-Job -Name $Name -ScriptBlock $ScriptBlock
    return $j
}

# ---------------------------------------------------------------------------
# Provider: serveo
# ---------------------------------------------------------------------------

function Try-Serveo {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    if (-not (Test-SshAvailable)) { return $false }
    Write-Block 'Trying provider: serveo'
    $logFile = Join-Path $dir 'serveo.log'
    $sb = {
        param($lp, $lf)
        & ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null `
             -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes `
             -R "3389:localhost:$lp" -N serveo.net *>&1 |
             Tee-Object -FilePath $lf
    }
    $job = Start-Job -Name 'serveo' -ScriptBlock $sb -ArgumentList $LocalPort, $logFile
    $deadline = (Get-Date).AddSeconds($ConnectTimeoutSec)
    $found = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 700
        if (Test-Path $logFile) {
            $log = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
            if ($log -match 'serveo\.net:(\d{2,5})') {
                $found = $Matches[1]
                break
            }
            if ($log -match 'Forwarding\s+TCP\s+remote\s+\[(\d+)\]\s+from\s+serveo\.net') {
                $found = $Matches[1]
                break
            }
        }
        if ($job.State -eq 'Failed' -or $job.State -eq 'Completed') {
            Write-Warn "serveo job ended ($($job.State))"
            break
        }
    }
    if (-not $found) {
        Write-Warn 'serveo did not expose a remote port in time'
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return $false
    }
    $host_ = 'serveo.net'
    $port  = [int]$found
    Write-Ok "serveo remote: $host_`:$port"

    $bridge  = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -R 3389:localhost:3389 -N serveo.net"
    $connect = "xfreerdp /v:serveo.net:$port /u:runner /cert:ignore /dynamic-resolution"
    Save-TunnelInfo -Type 'serveo' -Host $host_ -Port $port `
        -BridgeCmd $bridge -ConnectCmd $connect `
        -Extra "ssh pid (job): $($job.Id)"
    return $true
}

# ---------------------------------------------------------------------------
# Provider: localhost.run
# ---------------------------------------------------------------------------

function Try-LocalhostRun {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    if (-not (Test-SshAvailable)) { return $false }
    Write-Block 'Trying provider: localhost.run'
    $logFile = Join-Path $dir 'localhostrun.log'
    $sb = {
        param($lp, $lf)
        & ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null `
             -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes `
             -R "3389:localhost:$lp" nokey@localhost.run *>&1 |
             Tee-Object -FilePath $lf
    }
    $job = Start-Job -Name 'localhostrun' -ScriptBlock $sb -ArgumentList $LocalPort, $logFile
    $deadline = (Get-Date).AddSeconds($ConnectTimeoutSec)
    $found = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 700
        if (Test-Path $logFile) {
            $log = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
            # localhost.run prints: "Tunnel status: online" + a line like:
            #   Forwarding from: https://<sub>.lhr.life -> 3389:localhost:3389
            # For TCP we need the host part.
            if ($log -match '([a-z0-9-]+)\.lhr\.life') {
                $found = $Matches[1] + '.lhr.life'
                break
            }
            if ($log -match 'Forwarding.*?([\w.-]+)\.localhost\.run') {
                $found = $Matches[1] + '.localhost.run'
                break
            }
        }
        if ($job.State -eq 'Failed' -or $job.State -eq 'Completed') {
            Write-Warn "localhost.run job ended ($($job.State))"
            break
        }
    }
    if (-not $found) {
        Write-Warn 'localhost.run did not expose a host in time'
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return $false
    }
    # localhost.run exposes 443 -> 3389 over TCP via a wrapper, so port is 443.
    $port = 443
    Write-Ok "localhost.run remote: $found`:$port"
    $bridge  = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -R 3389:localhost:3389 nokey@localhost.run"
    $connect = "xfreerdp /v:$found:$port /u:runner /cert:ignore /dynamic-resolution"
    Save-TunnelInfo -Type 'localhost.run' -Host $found -Port $port `
        -BridgeCmd $bridge -ConnectCmd $connect `
        -Extra "ssh pid (job): $($job.Id)"
    return $true
}

# ---------------------------------------------------------------------------
# Provider: cloudflare (cloudflared.exe)
# ---------------------------------------------------------------------------

function Try-Cloudflare {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    Write-Block 'Trying provider: cloudflare'
    $cf = Get-Command cloudflared -ErrorAction SilentlyContinue
    if (-not $cf) {
        $exePath = Join-Path $dir 'cloudflared.exe'
        if (-not (Test-Path $exePath)) {
            Write-Info 'Downloading cloudflared.exe ...'
            $url = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
            try {
                Invoke-WebRequest -Uri $url -OutFile $exePath -UseBasicParsing -TimeoutSec 60
            } catch {
                Write-Warn "cloudflared download failed: $($_.Exception.Message)"
                return $false
            }
        }
        $cfCmd = $exePath
    } else {
        $cfCmd = $cf.Source
    }

    $logFile = Join-Path $dir 'cloudflared.log'
    $sb = {
        param($cmd, $lp, $lf)
        & $cmd tunnel --url "tcp://localhost:$lp" *>&1 |
            Tee-Object -FilePath $lf
    }
    $job = Start-Job -Name 'cloudflared' -ScriptBlock $sb -ArgumentList $cfCmd, $LocalPort, $logFile
    $deadline = (Get-Date).AddSeconds($ConnectTimeoutSec + 15)
    $found = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 800
        if (Test-Path $logFile) {
            $log = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
            if ($log -match '([\w-]+)\.trycloudflare\.com') {
                $found = $Matches[1] + '.trycloudflare.com'
                break
            }
        }
        if ($job.State -eq 'Failed' -or $job.State -eq 'Completed') {
            Write-Warn "cloudflared job ended ($($job.State))"
            break
        }
    }
    if (-not $found) {
        Write-Warn 'cloudflared did not expose a trycloudflare host in time'
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return $false
    }
    # Cloudflare quick tunnels for TCP use port 443.
    $port = 443
    Write-Ok "cloudflare remote: $found`:$port"
    $bridge  = "$cfCmd tunnel --url tcp://localhost:3389"
    $connect = "xfreerdp /v:$found:$port /u:runner /cert:ignore /dynamic-resolution"
    Save-TunnelInfo -Type 'cloudflare' -Host $found -Port $port `
        -BridgeCmd $bridge -ConnectCmd $connect `
        -Extra "cloudflared pid (job): $($job.Id)"
    return $true
}

# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

$success = $false
foreach ($p in $providers) {
    $p = $p.Trim().ToLower()
    $ok = $false
    switch ($p) {
        'serveo'        { $ok = Try-Serveo }
        'localhost.run' { $ok = Try-LocalhostRun }
        'cloudflare'    { $ok = Try-Cloudflare }
        default         { Write-Warn "Unknown provider: '$p' — skipping." }
    }
    if ($ok) { $success = $true; break }
}

if (-not $success) {
    Write-Err 'All tunnel providers failed.'
    # Leave a stub so the runner can detect the failure mode.
    Set-Content -Path (Join-Path $dir 'tunnel-type.txt') -Value 'failed' -NoNewline -Encoding UTF8
    Set-Content -Path (Join-Path $dir 'tunnel-info.txt')  -Value 'All tunnel providers failed.' -Encoding UTF8
    Send-Notify -Message 'All RDP tunnel providers failed — manual intervention required.' -Title 'Tunnel failure' | Out-Null
    exit 1
}

Write-Block 'setup-tunnel.ps1 complete'
exit 0
