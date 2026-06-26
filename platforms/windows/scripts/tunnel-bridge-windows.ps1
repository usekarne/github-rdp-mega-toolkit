#Requires -Version 5.1
<#
.SYNOPSIS
    Cloudflare bridge for Windows: runs `cloudflared access tcp` against
    a trycloudflare.com (or named) hostname, bridging a remote RDP
    listener to a local port so mstsc.exe / xfreerdp can connect
    through Cloudflare's tunnel.
.DESCRIPTION
    Reads cached tunnel-info.txt (written by fetch-creds-windows.ps1)
    for the cloudflared hostname, then launches:

      cloudflared.exe access tcp --hostname <HOST> --url localhost:<LOCAL_PORT>

    The script:
      * Auto-detects cloudflared.exe (PATH, install dir, Program Files)
      * Verifies the host field is a Cloudflare hostname (contains
        'trycloudflare.com' or your custom domain)
      * Spawns cloudflared in a background process
      * Streams stdout/stderr to a log file under LOCALAPPDATA
      * Waits for the local listener to come up (10s timeout)
      * Returns 0 on success and prints the local connect endpoint
.PARAMETER Host
    Cloudflare hostname to bridge. Default: read from cached tunnel-info.txt.
.PARAMETER LocalPort
    Local TCP port to bind. Default: 3390 (avoids conflict with local RDP).
.PARAMETER RdpPort
    Remote RDP port (informational only; cloudflared access tcp forwards
    to the tunnel endpoint). Default: 3389.
.PARAMETER CloudflaredPath
    Explicit path to cloudflared.exe. Auto-detected if not provided.
.PARAMETER LogFile
    Override the cloudflared log file path.
.PARAMETER Persistent
    Restart cloudflared if it exits (run as a long-lived daemon). Useful
    when launched by a scheduled task.
.PARAMETER NoWait
    Do not wait for the local listener — return immediately after launch.
.PARAMETER StopExisting
    Kill any prior cloudflared.exe started by this script before launching.
.EXAMPLE
    .\tunnel-bridge-windows.ps1
    Bridges cached hostname to localhost:3390.
.EXAMPLE
    .\tunnel-bridge-windows.ps1 -Host 'foo.trycloudflare.com' -LocalPort 3390
.EXAMPLE
    .\tunnel-bridge-windows.ps1 -Persistent
    Runs as a self-restarting daemon.
#>
[CmdletBinding()]
param(
    [string]$Host,
    [int]$LocalPort = 3390,
    [int]$RdpPort = 3389,
    [string]$CloudflaredPath = '',
    [string]$LogFile = '',
    [switch]$Persistent,
    [switch]$NoWait,
    [switch]$StopExisting
)

$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$m) Write-Host "[bridge]  $m" -ForegroundColor Cyan }
function Write-OK    { param([string]$m) Write-Host "[ok]       $m" -ForegroundColor Green }
function Write-Warn2 { param([string]$m) Write-Host "[warn]     $m" -ForegroundColor Yellow }
function Write-Err2  { param([string]$m) Write-Host "[error]    $m" -ForegroundColor Red }

# ----------------------------------------------------------------------
# Resolve cache dir + tunnel host
# ----------------------------------------------------------------------
$cacheDir = Join-Path $env:LOCALAPPDATA 'GitHubRDPToolkit'
$tunnelInfoFile = Join-Path $cacheDir 'tunnel-info.txt'
$tunnelTypeFile = Join-Path $cacheDir 'tunnel-type.txt'

if (-not $Host) {
    if (Test-Path $tunnelInfoFile) {
        $Host = (Get-Content $tunnelInfoFile -Raw).Trim()
    } else {
        Write-Err2 'No host specified and no cached tunnel-info.txt found.'
        Write-Err2 'Run fetch-creds-windows.ps1 first, or pass -Host <hostname>.'
        exit 1
    }
}

if (-not ($Host -match 'trycloudflare\.com$' -or $Host -match '\.')) {
    Write-Warn2 "Host '$Host' does not look like a Cloudflare hostname; proceeding anyway."
}

# ----------------------------------------------------------------------
# Resolve cloudflared.exe
# ----------------------------------------------------------------------
function Find-Cloudflared {
    if ($CloudflaredPath -and (Test-Path $CloudflaredPath)) { return $CloudflaredPath }
    $cmd = Get-Command cloudflared.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:ProgramFiles 'GitHubRDPToolkit\bin\cloudflared.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'cloudflared\cloudflared.exe'),
        (Join-Path $env:ProgramFiles 'cloudflared\cloudflared.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\cloudflared.exe'),
        (Join-Path $env:LOCALAPPDATA 'cloudflared\cloudflared.exe')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return $null
}

$cfPath = Find-Cloudflared
if (-not $cfPath) {
    Write-Err2 'cloudflared.exe not found.'
    Write-Err2 'Install it via one of:'
    Write-Err2 '  winget install Cloudflare.cloudflared'
    Write-Err2 '  choco install cloudflared'
    Write-Err2 '  scoop install cloudflared'
    Write-Err2 '  Or pass -CloudflaredPath <path-to-cloudflared.exe>'
    exit 1
}
Write-OK "cloudflared: $cfPath"

# ----------------------------------------------------------------------
# Resolve log file
# ----------------------------------------------------------------------
if (-not $LogFile) {
    $null = New-Item -ItemType Directory -Path $cacheDir -Force
    $LogFile = Join-Path $cacheDir 'cloudflared-bridge.log'
}

# ----------------------------------------------------------------------
# Stop any existing cloudflared started by us
# ----------------------------------------------------------------------
if ($StopExisting) {
    Write-Step 'Stopping existing cloudflared processes...'
    Get-Process -Name 'cloudflared' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $_ | Stop-Process -Force -ErrorAction SilentlyContinue
            Write-OK "Killed cloudflared PID $($_.Id)"
        } catch { }
    }
}

# ----------------------------------------------------------------------
# Build cloudflared arguments
# ----------------------------------------------------------------------
$cfArgs = @(
    'access','tcp',
    '--hostname', $Host,
    '--url', "localhost:$LocalPort"
)

# ----------------------------------------------------------------------
# Persistent loop vs. one-shot
# ----------------------------------------------------------------------
function Invoke-Bridge {
    param([string]$LogFile)
    Write-Step "Starting cloudflared: $($cfArgs -join ' ')"
    Write-Host "  Bridging : $Host -> localhost:$LocalPort" -ForegroundColor White
    Write-Host "  Log file : $LogFile" -ForegroundColor DarkGray
    Write-Host ''

    # Start process with output redirected to log
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $cfPath
    $psi.Arguments              = ($cfArgs | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    $psi.WorkingDirectory       = (Split-Path -Parent $cfPath)

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    # Stream output to log file (and capture stderr to a string for diagnostics)
    $script:stderrBuilder = New-Object System.Text.StringBuilder
    $outScript = {
        if ($EventArgs.Data) {
            Add-Content -Path $Event.MessageData -Value $EventArgs.Data -Encoding ASCII
        }
    }
    $errScript = {
        if ($EventArgs.Data) {
            Add-Content -Path $Event.MessageData -Value $EventArgs.Data -Encoding ASCII
            [void]$script:stderrBuilder.AppendLine($EventArgs.Data)
        }
    }
    Register-ObjectEvent -InputObject $proc -EventName 'OutputDataReceived' -Action $outScript -MessageData $LogFile | Out-Null
    Register-ObjectEvent -InputObject $proc -EventName 'ErrorDataReceived'  -Action $errScript -MessageData $LogFile | Out-Null

    [void]$proc.Start()
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()

    # Save PID for monitoring
    $pidFile = Join-Path $cacheDir 'cloudflared-bridge.pid'
    $proc.Id | Out-File -FilePath $pidFile -Encoding ASCII -NoNewline
    Write-OK "cloudflared PID: $($proc.Id)"

    # Wait for listener
    if (-not $NoWait) {
        Write-Step "Waiting for localhost:$LocalPort to accept connections (max 10s)..."
        $ok = $false
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Milliseconds 500
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $tcp.Connect('127.0.0.1', $LocalPort)
                $tcp.Close()
                $ok = $true
                break
            } catch {
                # Not yet
            }
        }
        if ($ok) {
            Write-OK "Bridge is UP. Connect mstsc/xfreerdp to: localhost:$LocalPort"
        } else {
            Write-Warn2 "Bridge listener not ready after 10s — cloudflared may still be establishing the tunnel."
            Write-Warn2 "Check log: $LogFile"
        }
    }

    return $proc
}

if ($Persistent) {
    Write-Step 'Persistent mode: relaunching cloudflared if it exits.'
    while ($true) {
        $proc = Invoke-Bridge -LogFile $LogFile
        if ($null -eq $proc) { Start-Sleep -Seconds 5; continue }
        $proc.WaitForExit()
        $rc = $proc.ExitCode
        Write-Warn2 "cloudflared exited (rc=$rc). Restarting in 5s..."
        Start-Sleep -Seconds 5
    }
} else {
    $proc = Invoke-Bridge -LogFile $LogFile
    if ($NoWait) {
        Write-OK 'Launched (non-blocking). Cloudflared will run in the background.'
        Write-Host "  To stop: Get-Process cloudflared | Stop-Process -Force" -ForegroundColor DarkGray
        return
    }
    # In one-shot + wait mode, keep the script running until Ctrl+C
    Write-Host ''
    Write-Host 'Bridge is running. Press Ctrl+C to stop.' -ForegroundColor Yellow
    try {
        while (-not $proc.HasExited) { Start-Sleep -Seconds 1 }
    } catch [System.Threading.ThreadInterruptedException] {
        # Ctrl+C
    } finally {
        if (-not $proc.HasExited) {
            try { $proc.Kill() } catch { }
        }
        Write-OK 'Bridge stopped.'
    }
}
