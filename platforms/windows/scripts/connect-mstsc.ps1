#Requires -Version 5.1
<#
.SYNOPSIS
    Connect to an RDP session using mstsc.exe (Windows native RDP client).
.DESCRIPTION
    Reads cached credentials from "$env:LOCALAPPDATA\GitHubRDPToolkit"
    (written by fetch-creds-windows.ps1) and launches mstsc.exe against
    the tunnel endpoint.

    Generates a temporary .rdp file (or uses the bundled template) so
    that all mstsc options (size, color depth, clipboard redirect,
    auto-reconnect, etc.) are applied deterministically.

    Falls back to launching mstsc.exe with command-line arguments if
    .rdp generation fails.
.PARAMETER Host
    Override the RDP host:port. If omitted, reads from cached tunnel-info.txt.
.PARAMETER Username
    Override the RDP username. Default: runner.
.PARAMETER Password
    Override the RDP password. If omitted, reads from cached RDP_PASSWORD.txt.
.PARAMETER Width
    Desktop width. Default: 1280.
.PARAMETER Height
    Desktop height. Default: 720.
.PARAMETER RdpTemplate
    Path to an .rdp template to use. Default: bundled mstsc-template.rdp.
.PARAMETER NoEdit
    Do not auto-edit the .rdp file before launching (use as-is).
.PARAMETER Wait
    Wait for mstsc.exe to exit before returning.
.EXAMPLE
    .\connect-mstsc.ps1
    Connects using cached credentials.
.EXAMPLE
    .\connect-mstsc.ps1 -Host 'localhost:3390' -Username runner -Password 'P@ss'
    Connects to a specific endpoint with given credentials.
#>
[CmdletBinding()]
param(
    [string]$Host,
    [string]$Username,
    [string]$Password,
    [int]$Width  = 1280,
    [int]$Height = 720,
    [string]$RdpTemplate = '',
    [switch]$NoEdit,
    [switch]$Wait
)

$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$m) Write-Host "[mstsc]   $m" -ForegroundColor Cyan }
function Write-OK    { param([string]$m) Write-Host "[ok]      $m" -ForegroundColor Green }
function Write-Warn2 { param([string]$m) Write-Host "[warn]    $m" -ForegroundColor Yellow }
function Write-Err2  { param([string]$m) Write-Host "[error]   $m" -ForegroundColor Red }

# ----------------------------------------------------------------------
# Resolve credentials cache dir
# ----------------------------------------------------------------------
$cacheDir = Join-Path $env:LOCALAPPDATA 'GitHubRDPToolkit'
$credFile       = Join-Path $cacheDir 'RDP_PASSWORD.txt'
$credFileLower  = Join-Path $cacheDir 'rdp-password.txt'
$userFile       = Join-Path $cacheDir 'RDP_USERNAME.txt'
$tunnelInfoFile = Join-Path $cacheDir 'tunnel-info.txt'

# ----------------------------------------------------------------------
# Resolve host:port
# ----------------------------------------------------------------------
if (-not $Host) {
    if (Test-Path $tunnelInfoFile) {
        $Host = (Get-Content $tunnelInfoFile -Raw).Trim()
    } else {
        Write-Err2 'No host specified and no cached tunnel-info.txt found.'
        Write-Err2 "Run fetch-creds-windows.ps1 first, or pass -Host <host:port>."
        exit 1
    }
}

# ----------------------------------------------------------------------
# Resolve username
# ----------------------------------------------------------------------
if (-not $Username) {
    if (Test-Path $userFile) {
        $Username = (Get-Content $userFile -Raw).Trim()
    } else {
        $Username = 'runner'
    }
}

# ----------------------------------------------------------------------
# Resolve password
# ----------------------------------------------------------------------
if (-not $Password) {
    foreach ($f in @($credFile, $credFileLower)) {
        if (Test-Path $f) {
            $Password = (Get-Content $f -Raw).Trim()
            break
        }
    }
}
if (-not $Password) {
    Write-Warn2 'No password provided. mstsc will prompt for credentials.'
}

# ----------------------------------------------------------------------
# Resolve mstsc.exe
# ----------------------------------------------------------------------
$mstsc = Join-Path $env:WINDIR 'System32\mstsc.exe'
if (-not (Test-Path $mstsc)) {
    Write-Err2 "mstsc.exe not found at: $mstsc"
    Write-Err2 'mstsc.exe is built into all Windows editions; the host install may be damaged.'
    exit 1
}

# ----------------------------------------------------------------------
# Build .rdp file
# ----------------------------------------------------------------------
$rdpTemplateDefault = Join-Path $env:ProgramFiles 'GitHubRDPToolkit\platforms\windows\configs\mstsc-template.rdp'
if (-not $RdpTemplate) { $RdpTemplate = $rdpTemplateDefault }

if (-not (Test-Path $RdpTemplate)) {
    Write-Warn2 "RDP template not found: $RdpTemplate — using inline defaults."
    $rdpContent = @"
full address:s:$Host
username:s:$Username
prompt for credentials:i:0
authentication level:i:0
enablecredsspsupport:i:0
screen mode id:i:2
desktopwidth:i:$Width
desktopheight:i:$Height
session bpp:i:32
compression:i:1
redirectclipboard:i:1
redirectprinters:i:1
allow font smoothing:i:1
bandwidthautodetect:i:1
networkautodetect:i:1
bitmapcachepersistenable:i:1
autoreconnection enabled:i:1
dynamic resolution:i:1
smart sizing:i:1
"@
} elseif ($NoEdit) {
    $rdpContent = Get-Content $RdpTemplate -Raw
} else {
    Write-Step "Using template: $RdpTemplate"
    $rdpContent = Get-Content $RdpTemplate -Raw
    # Replace placeholders
    $rdpContent = $rdpContent -replace 'full address:s:.*', "full address:s:$Host"
    $rdpContent = $rdpContent -replace 'username:s:.*',     "username:s:$Username"
    $rdpContent = $rdpContent -replace 'desktopwidth:i:\d+',  "desktopwidth:i:$Width"
    $rdpContent = $rdpContent -replace 'desktopheight:i:\d+', "desktopheight:i:$Height"
}

# ----------------------------------------------------------------------
# Persist password via cmdkey (mstsc reads from Credential Manager)
# ----------------------------------------------------------------------
if ($Password) {
    Write-Step 'Storing credential via cmdkey (Credential Manager)...'
    $cmdkeyArgs = @('/generic:TERMSRV/' + ($Host -replace ':.*',''), '/user:' + $Username, '/pass:' + $Password)
    & "$env:WINDIR\System32\cmdkey.exe" $cmdkeyArgs 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-OK 'Credential stored (will be removed by uninstall-credentials.ps1).'
    } else {
        Write-Warn2 'cmdkey failed to store credential — mstsc will prompt.'
    }
}

# ----------------------------------------------------------------------
# Write temp .rdp file
# ----------------------------------------------------------------------
$tempRdp = Join-Path $env:TEMP "GitHubRDPToolkit-$(Get-Date -Format yyyyMMddHHmmss).rdp"
$rdpContent | Out-File -FilePath $tempRdp -Encoding ASCII -NoNewline
Write-OK "RDP file written: $tempRdp"

# ----------------------------------------------------------------------
# Launch mstsc.exe
# ----------------------------------------------------------------------
Write-Step "Launching mstsc.exe with: $tempRdp"
Write-Host "  Host     : $Host"   -ForegroundColor White
Write-Host "  Username : $Username" -ForegroundColor White
Write-Host "  Size     : ${Width}x${Height}" -ForegroundColor White
Write-Host ''

if ($Wait) {
    $p = Start-Process -FilePath $mstsc -ArgumentList "`"$tempRdp`"" -Wait -PassThru
    Write-OK "mstsc.exe exited with code: $($p.ExitCode)"
} else {
    $null = Start-Process -FilePath $mstsc -ArgumentList "`"$tempRdp`""
    Write-OK 'mstsc.exe launched (non-blocking).'
}

# ----------------------------------------------------------------------
# Clean up temp .rdp after 60 seconds (mstsc loads it into memory)
# ----------------------------------------------------------------------
Start-Job -ScriptBlock {
    param($f)
    Start-Sleep -Seconds 60
    if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
} -ArgumentList $tempRdp | Out-Null
