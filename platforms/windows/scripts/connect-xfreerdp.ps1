#Requires -Version 5.1
<#
.SYNOPSIS
    Connect to an RDP session using xfreerdp (FreeRDP) for a richer
    experience than mstsc.exe on Windows.
.DESCRIPTION
    Reads cached credentials from "$env:LOCALAPPDATA\GitHubRDPToolkit"
    and launches xfreerdp against the tunnel endpoint with sensible
    flags: /cert:ignore, +clipboard, +auto-reconnect, /size, /u, /p.

    Falls back to mstsc.exe if xfreerdp is not installed (with a
    warning).
.PARAMETER Host
    Override the RDP host:port. Default: from cached tunnel-info.txt.
.PARAMETER Username
    Override the RDP username. Default: from cached RDP_USERNAME.txt or 'runner'.
.PARAMETER Password
    Override the RDP password. Default: from cached RDP_PASSWORD.txt.
.PARAMETER Width
    Desktop width. Default: 1280.
.PARAMETER Height
    Desktop height. Default: 720.
.PARAMETER ColorDepth
    Color depth (8/15/16/24/32). Default: 32.
.PARAMETER ExtraArgs
    Pass-through arguments appended to the xfreerdp command line.
.PARAMETER FallbackToMstsc
    If xfreerdp is missing, fall back to mstsc.exe (default: on).
.PARAMETER NoFallback
    Do not fall back to mstsc.exe if xfreerdp is missing.
.EXAMPLE
    .\connect-xfreerdp.ps1
    Connects using cached credentials.
.EXAMPLE
    .\connect-xfreerdp.ps1 -Width 1920 -Height 1080
    Connects at 1920x1080.
#>
[CmdletBinding()]
param(
    [string]$Host,
    [string]$Username,
    [string]$Password,
    [int]$Width  = 1280,
    [int]$Height = 720,
    [ValidateSet(8,15,16,24,32)]
    [int]$ColorDepth = 32,
    [string[]]$ExtraArgs = @(),
    [switch]$NoFallback
)

$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$m) Write-Host "[xfreerdp] $m" -ForegroundColor Cyan }
function Write-OK    { param([string]$m) Write-Host "[ok]        $m" -ForegroundColor Green }
function Write-Warn2 { param([string]$m) Write-Host "[warn]      $m" -ForegroundColor Yellow }
function Write-Err2  { param([string]$m) Write-Host "[error]     $m" -ForegroundColor Red }

# ----------------------------------------------------------------------
# Locate xfreerdp
# ----------------------------------------------------------------------
$xfreerdp = Get-Command xfreerdp.exe -ErrorAction SilentlyContinue
if (-not $xfreerdp) { $xfreerdp = Get-Command xfreerdp -ErrorAction SilentlyContinue }
if (-not $xfreerdp) {
    if ($NoFallback) {
        Write-Err2 'xfreerdp not found on PATH and -NoFallback was specified.'
        Write-Err2 'Install FreeRDP: https://github.com/FreeRDP/FreeRDP/releases'
        exit 1
    }
    Write-Warn2 'xfreerdp not found — falling back to mstsc.exe via connect-mstsc.ps1'
    $mstscScript = Join-Path $PSScriptRoot 'connect-mstsc.ps1'
    if (-not (Test-Path $mstscScript)) {
        Write-Err2 "Fallback script not found: $mstscScript"
        exit 1
    }
    $mstscArgs = @()
    if ($Host)     { $mstscArgs += '-Host';     $mstscArgs += $Host }
    if ($Username) { $mstscArgs += '-Username'; $mstscArgs += $Username }
    if ($Password) { $mstscArgs += '-Password'; $mstscArgs += $Password }
    $mstscArgs += '-Width';  $mstscArgs += "$Width"
    $mstscArgs += '-Height'; $mstscArgs += "$Height"
    & $mstscScript @mstscArgs
    exit $LASTEXITCODE
}

Write-OK "xfreerdp found: $($xfreerdp.Source)"

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
    Write-Err2 'No password provided. xfreerdp requires /p.'
    Write-Err2 'Run fetch-creds-windows.ps1 first, or pass -Password <pw>.'
    exit 1
}

# ----------------------------------------------------------------------
# Build xfreerdp arguments
# ----------------------------------------------------------------------
$size = "${Width}x${Height}"
$xfreerdpArgs = @(
    "/v:$Host",
    "/u:$Username",
    "/p:$Password",
    "/cert:ignore",
    "+clipboard",
    "+auto-reconnect",
    "/size:$size",
    "/color-depth:$ColorDepth",
    "+fonts",
    "+aero",
    "+window-drag",
    "+menu-anims",
    "+themes",
    "/gfx:AVC444",
    "/network:auto",
    "/bpp:$ColorDepth"
)
if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
    $xfreerdpArgs += $ExtraArgs
}

# ----------------------------------------------------------------------
# Launch
# ----------------------------------------------------------------------
Write-Step "Launching xfreerdp with: $($xfreerdpArgs -join ' ')"
Write-Host "  Host     : $Host" -ForegroundColor White
Write-Host "  Username : $Username" -ForegroundColor White
Write-Host "  Size     : $size" -ForegroundColor White
Write-Host '  Press Ctrl+Alt+Enter to toggle fullscreen.' -ForegroundColor DarkGray
Write-Host ''

# Mask the password in the visible args
$masked = ($xfreerdpArgs | ForEach-Object { if ($_ -like '/p:*') { '/p:***' } else { $_ } }) -join ' '
Write-Host "[cmd] $($xfreerdp.Source) $masked" -ForegroundColor DarkGray

& $xfreerdp.Source @xfreerdpArgs
$rc = $LASTEXITCODE
Write-OK "xfreerdp exited with code: $rc"
exit $rc
