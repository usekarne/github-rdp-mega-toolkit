# core/powershell/setup-tunnel.ps1 - Multi-provider tunnel manager (v9.0)
# v9.0: NO NGROK. Uses Serveo (SSH, primary) -> localhost.run (SSH) -> Cloudflare (fallback)
. "$PSScriptRoot\utils.ps1"

$Providers = if ($env:TUNNEL_PROVIDERS) { $env:TUNNEL_PROVIDERS -split ',' } else { @('serveo','localhost.run','cloudflare') }
$TunnelUrl  = ''
$TunnelType = ''
$TunnelHost = ''
$TunnelPort = ''

function Try-Serveo {
    Write-Info 'Trying Serveo (SSH-based, no signup, no token)...'
    try {
        $sshExe = (Get-Command ssh -ErrorAction SilentlyContinue).Source
        if (-not $sshExe) {
            Write-Warn 'ssh.exe not found on runner'
            return $false
        }
        Write-Info "ssh.exe: $sshExe"

        $serveoArgs = @(
            '-o', 'StrictHostKeyChecking=no',
            '-o', 'UserKnownHostsFile=NUL',
            '-o', 'ServerAliveInterval=30',
            '-o', 'ServerAliveCountMax=3',
            '-o', 'ExitOnForwardFailure=yes',
            '-R', '3389:localhost:3389',
            '-N',
            'serveo.net'
        )

        $p = Start-Process -FilePath $sshExe `
            -ArgumentList $serveoArgs `
            -NoNewWindow -PassThru `
            -RedirectStandardOutput 'serveo-out.log' `
            -RedirectStandardError 'serveo-err.log'

        for ($i = 0; $i -lt 25; $i++) {
            Start-Sleep -Seconds 2
            foreach ($logFile in @('serveo-err.log','serveo-out.log')) {
                if (Test-Path $logFile) {
                    $content = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
                    if ($content -match 'serveo\.net:(\d+)') {
                        $script:TunnelHost = 'serveo.net'
                        $script:TunnelPort = $Matches[1]
                        $script:TunnelUrl  = "tcp://serveo.net:$($Matches[1])"
                        $script:TunnelType = 'serveo'
                        Write-Ok "Serveo UP: $($script:TunnelUrl)"
                        return $true
                    }
                }
            }
            Write-Host "[TUNNEL] Waiting for serveo... attempt $($i+1)/25"
        }

        Write-Warn 'Serveo did not provide a forwarding URL in 50s'
        if (Test-Path 'serveo-err.log') {
            $c = Get-Content 'serveo-err.log' -Raw -ErrorAction SilentlyContinue
            if ($c) { Write-Host "[SERVEO-ERR] $($c.Substring(0, [math]::Min(500, $c.Length)))" }
        }
        if ($p) { Get-Process -Id $p.Id -ErrorAction SilentlyContinue | Stop-Process -Force }
        return $false
    } catch {
        Write-Warn "Serveo error: $($_.Exception.Message)"
        return $false
    }
}

function Try-LocalhostRun {
    Write-Info 'Trying localhost.run (SSH-based, no signup, no token)...'
    try {
        $sshExe = (Get-Command ssh -ErrorAction SilentlyContinue).Source
        if (-not $sshExe) {
            Write-Warn 'ssh.exe not found on runner'
            return $false
        }

        $lrArgs = @(
            '-o', 'StrictHostKeyChecking=no',
            '-o', 'UserKnownHostsFile=NUL',
            '-o', 'ServerAliveInterval=30',
            '-o', 'ServerAliveCountMax=3',
            '-o', 'ExitOnForwardFailure=yes',
            '-R', '3389:localhost:3389',
            '-N',
            'nokey@localhost.run'
        )

        $p = Start-Process -FilePath $sshExe `
            -ArgumentList $lrArgs `
            -NoNewWindow -PassThru `
            -RedirectStandardOutput 'lr-out.log' `
            -RedirectStandardError 'lr-err.log'

        for ($i = 0; $i -lt 25; $i++) {
            Start-Sleep -Seconds 2
            foreach ($logFile in @('lr-err.log','lr-out.log')) {
                if (Test-Path $logFile) {
                    $content = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
                    if ($content -match '(?:localhost\.run|[\w-]+\.localhost\.run):(\d+)') {
                        $script:TunnelHost = 'localhost.run'
                        $script:TunnelPort = $Matches[1]
                        $script:TunnelUrl  = "tcp://localhost.run:$($Matches[1])"
                        $script:TunnelType = 'localhost.run'
                        Write-Ok "localhost.run UP: $($script:TunnelUrl)"
                        return $true
                    }
                }
            }
            Write-Host "[TUNNEL] Waiting for localhost.run... attempt $($i+1)/25"
        }

        Write-Warn 'localhost.run did not provide a forwarding URL in 50s'
        if (Test-Path 'lr-err.log') {
            $c = Get-Content 'lr-err.log' -Raw -ErrorAction SilentlyContinue
            if ($c) { Write-Host "[LR-ERR] $($c.Substring(0, [math]::Min(500, $c.Length)))" }
        }
        if ($p) { Get-Process -Id $p.Id -ErrorAction SilentlyContinue | Stop-Process -Force }
        return $false
    } catch {
        Write-Warn "localhost.run error: $($_.Exception.Message)"
        return $false
    }
}

function Try-Cloudflare {
    Write-Info 'Trying Cloudflare Quick Tunnel...'
    try {
        $cfUrl = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
        Invoke-WebRequest -Uri $cfUrl -OutFile 'cloudflared.exe' -UseBasicParsing
        Write-Info 'cloudflared.exe downloaded'

        Start-Process -FilePath '.\cloudflared.exe' `
            -ArgumentList 'tunnel','--no-autoupdate','--url','tcp://localhost:3389' `
            -NoNewWindow `
            -RedirectStandardOutput 'cf-out.log' `
            -RedirectStandardError 'cf-err.log' | Out-Null

        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 2
            foreach ($logFile in @('cf-err.log','cf-out.log')) {
                if (Test-Path $logFile) {
                    $content = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
                    if ($content -match '(https://[a-z0-9-]+\.trycloudflare\.com)') {
                        $script:TunnelUrl  = $Matches[1]
                        $script:TunnelHost = $script:TunnelUrl -replace '^https://',''
                        $script:TunnelPort = '443'
                        $script:TunnelType = 'cloudflare'
                        Write-Ok "Cloudflare UP: $($script:TunnelUrl)"
                        return $true
                    }
                }
            }
            Write-Host "[TUNNEL] Waiting for cloudflared... attempt $($i+1)/30"
        }

        Write-Warn 'Cloudflare did not come up in 60s'
        if (Test-Path 'cf-err.log') {
            $c = Get-Content 'cf-err.log' -Raw -ErrorAction SilentlyContinue
            if ($c) { Write-Host "[CF-ERR] $($c.Substring(0, [math]::Min(500, $c.Length)))" }
        }
        Get-Process -Name 'cloudflared' -ErrorAction SilentlyContinue | Stop-Process -Force
        Remove-Item 'cloudflared.exe' -Force -ErrorAction SilentlyContinue
        return $false
    } catch {
        Write-Warn "Cloudflare error: $($_.Exception.Message)"
        return $false
    }
}

Write-Block "SETUP TUNNEL v9.0 - providers: $($Providers -join ', ')"

foreach ($p in $Providers) {
    $p = $p.Trim().ToLower()
    if ($p -eq 'serveo'        -and -not $TunnelUrl) { if (Try-Serveo)        { break } }
    if ($p -eq 'localhost.run' -and -not $TunnelUrl) { if (Try-LocalhostRun)  { break } }
    if ($p -eq 'cloudflare'    -and -not $TunnelUrl) { if (Try-Cloudflare)    { break } }
}

if ([string]::IsNullOrWhiteSpace($TunnelUrl)) {
    $ip = Get-PublicIp
    $TunnelUrl  = $ip
    $TunnelHost = $ip
    $TunnelPort = '3389'
    $TunnelType = 'direct-ip-wont-work'
    Write-Warn "ALL TUNNELS FAILED. Direct IP $ip will NOT work for RDP."
}

Write-Info "FINAL: type=$TunnelType host=$TunnelHost port=$TunnelPort url=$TunnelUrl"

# Build connect command based on tunnel type
$Pwd = Get-Content 'rdp-password.txt' -Raw -ErrorAction SilentlyContinue
if ([string]::IsNullOrWhiteSpace($Pwd)) { $Pwd = $env:RDP_PASS }
$BridgeCmd  = ''
$ConnectCmd = ''
if ($TunnelType -eq 'serveo' -or $TunnelType -eq 'localhost.run') {
    # Direct host:port - no client bridge needed
    $ConnectCmd = "xfreerdp /v:${TunnelHost}:${TunnelPort} /u:runner /p:'$Pwd' /cert:ignore +clipboard +auto-reconnect /size:1280x720"
} elseif ($TunnelType -eq 'cloudflare') {
    # Needs local cloudflared bridge
    $BridgeCmd  = "cloudflared access tcp --hostname $TunnelHost --url localhost:33890"
    $ConnectCmd = "xfreerdp /v:localhost:33890 /u:runner /p:'$Pwd' /cert:ignore +clipboard +auto-reconnect /size:1280x720"
} else {
    $ConnectCmd = "xfreerdp /v:${TunnelHost}:${TunnelPort} /u:runner /p:'$Pwd' /cert:ignore +clipboard +auto-reconnect /size:1280x720"
}

# Save artifacts - all -Encoding ASCII -NoNewline; BRIDGE_CMD and CONNECT_CMD on SEPARATE lines
$TunnelUrl  | Out-File -FilePath 'tunnel-info.txt'  -Encoding ASCII -NoNewline
$TunnelType | Out-File -FilePath 'tunnel-type.txt'   -Encoding ASCII -NoNewline
$TunnelHost | Out-File -FilePath 'tunnel-host.txt'   -Encoding ASCII -NoNewline
$TunnelPort | Out-File -FilePath 'tunnel-port.txt'   -Encoding ASCII -NoNewline
"BRIDGE_CMD=$BridgeCmd`r`nCONNECT_CMD=$ConnectCmd" | Out-File -FilePath 'connect-info.txt' -Encoding ASCII -NoNewline

# Expose to env
"TUNNEL_URL=$TunnelUrl"   | Out-File -Append -Encoding utf8 $env:GITHUB_ENV
"TUNNEL_TYPE=$TunnelType" | Out-File -Append -Encoding utf8 $env:GITHUB_ENV
"TUNNEL_HOST=$TunnelHost" | Out-File -Append -Encoding utf8 $env:GITHUB_ENV
"TUNNEL_PORT=$TunnelPort" | Out-File -Append -Encoding utf8 $env:GITHUB_ENV

Send-Notify -Title 'RDP Tunnel UP' -Body "Type: $TunnelType`nHost: $TunnelHost`nPort: $TunnelPort`nURL: $TunnelUrl"

Write-Block "TUNNEL READY - $TunnelType"
Write-Host "|  Host:     $TunnelHost"
Write-Host "|  Port:     $TunnelPort"
Write-Host "|  URL:      $TunnelUrl"
if ($BridgeCmd) { Write-Host "|  Bridge:   $BridgeCmd" }
Write-Host "|  Connect:  $ConnectCmd"
Write-Host "+============================================================+"
