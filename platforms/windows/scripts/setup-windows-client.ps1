#Requires -Version 5.1
<#
.SYNOPSIS
    Sets up a Windows host as a client for the GitHub RDP Mega Toolkit:
      * Verifies mstsc.exe (always present on Windows)
      * Optionally installs xfreerdp (FreeRDP) via winget / scoop / choco
      * Installs cloudflared.exe (Cloudflare fallback)
      * Installs PowerShell 7+ if missing (optional)
      * Verifies Python 3.x presence (optional, only required if you
        want to use the Python-based client tools — the PowerShell
        scripts work without Python)
.DESCRIPTION
    Idempotent: safe to re-run. Skips items that are already installed
    unless -Force is supplied.
.PARAMETER SkipCloudflared
    Skip cloudflared.exe install.
.PARAMETER SkipXfreerdp
    Skip xfreerdp install (use built-in mstsc.exe only).
.PARAMETER SkipPwsh7
    Skip PowerShell 7 install.
.PARAMETER SkipPython
    Skip Python install (you can still use the pure-PowerShell client tools).
.PARAMETER Force
    Reinstall even if a component appears present.
.EXAMPLE
    .\setup-windows-client.ps1
    Installs all client components with sensible defaults.
#>
[CmdletBinding()]
param(
    [switch]$SkipCloudflared,
    [switch]$SkipXfreerdp,
    [switch]$SkipPwsh7,
    [switch]$SkipPython,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Write-Step  { param([string]$m) Write-Host "[setup]   $m" -ForegroundColor Cyan }
function Write-OK    { param([string]$m) Write-Host "[ok]       $m" -ForegroundColor Green }
function Write-Warn2 { param([string]$m) Write-Host "[warn]     $m" -ForegroundColor Yellow }
function Write-Err2  { param([string]$m) Write-Host "[error]    $m" -ForegroundColor Red }

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------
function Test-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CommandOrNull {
    param([string]$Name)
    return Get-Command $Name -ErrorAction SilentlyContinue
}

# ----------------------------------------------------------------------
# Self-elevate (we need admin for system-wide installs)
# ----------------------------------------------------------------------
if (-not (Test-Administrator)) {
    Write-Warn2 'Administrator rights recommended. Relaunching elevated...'
    $argsList = @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`"")
    foreach ($p in 'SkipCloudflared','SkipXfreerdp','SkipPwsh7','SkipPython','Force') {
        if (Get-Variable -Name $p -Scope Script -ErrorAction SilentlyContinue) {
            $val = (Get-Variable -Name $p -Scope Script).Value
            if ($val -is [switch] -and $val.IsPresent) { $argsList += "-$p" }
        }
    }
    # Simpler: re-pass switch params using $PSBoundParameters
    $argsList = @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`"")
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) { if ($v.IsPresent) { $argsList += "-$k" } }
        else { $argsList += "-$k"; $argsList += "`"$v`"" }
    }
    $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList $argsList
    exit $p.ExitCode
}

Write-Host ''
Write-Host '======================================' -ForegroundColor White
Write-Host '  GitHub RDP Mega Toolkit — Client Setup' -ForegroundColor White
Write-Host '======================================' -ForegroundColor White
Write-Host ''

# ----------------------------------------------------------------------
# 1) Verify mstsc.exe (built-in)
# ----------------------------------------------------------------------
Write-Step 'Verifying mstsc.exe (Windows native RDP client)...'
$mstsc = Join-Path $env:WINDIR 'System32\mstsc.exe'
if (Test-Path $mstsc) {
    $ver = (Get-Item $mstsc).VersionInfo.FileVersion
    Write-OK "mstsc.exe found: $mstsc (version $ver)"
} else {
    Write-Warn2 'mstsc.exe not found. This is unusual; the Windows install may be damaged (N Edition?).'
}

# ----------------------------------------------------------------------
# 2) Optional: xfreerdp (FreeRDP)
# ----------------------------------------------------------------------
if (-not $SkipXfreerdp) {
    Write-Step 'Checking for xfreerdp...'
    $xfreerdp = Get-CommandOrNull 'xfreerdp.exe'
    if (-not $xfreerdp) { $xfreerdp = Get-CommandOrNull 'xfreerdp' }
    if ($xfreerdp -and -not $Force) {
        Write-OK "xfreerdp already installed: $($xfreerdp.Source)"
    } else {
        Write-Step 'Attempting to install xfreerdp (FreeRDP)...'
        $ok = $false
        # FreeRDP doesn't ship on winget directly under that name. Try alternatives.
        $winget = Get-CommandOrNull 'winget'
        if ($winget) {
            # Try a few known package IDs
            foreach ($pkg in @('FreeRDP.FreeRDP','Microsoft.FreeRDP','FreeRDP.xfreerdp')) {
                Write-Step "Trying winget: $pkg"
                & $winget.Source install $pkg --accept-package-agreements --accept-source-agreements -h 2>$null
                if ($LASTEXITCODE -eq 0) { $ok = $true; break }
            }
        }
        if (-not $ok) {
            $scoop = Get-CommandOrNull 'scoop'
            if ($scoop) {
                Write-Step 'Trying scoop install freerdp...'
                & $scoop.Source install freerdp 2>$null
                if ($LASTEXITCODE -eq 0) { $ok = $true }
            }
        }
        if (-not $ok) {
            $choco = Get-CommandOrNull 'choco'
            if ($choco) {
                Write-Step 'Trying choco install freerdp...'
                & $choco.Source install freerdp -y --no-progress 2>$null
                if ($LASTEXITCODE -eq 0) { $ok = $true }
            }
        }
        if (-not $ok) {
            Write-Warn2 'Could not auto-install xfreerdp. Falling back to mstsc.exe.'
            Write-Warn2 'Manual install: https://github.com/FreeRDP/FreeRDP/releases'
            Write-Warn2 'Look for FreeRDP-*.msi or build from source.'
        } else {
            Write-OK 'xfreerdp installed.'
        }
    }
}

# ----------------------------------------------------------------------
# 3) Optional: cloudflared.exe (Cloudflare fallback)
# ----------------------------------------------------------------------
if (-not $SkipCloudflared) {
    Write-Step 'Checking for cloudflared.exe...'
    $cf = Get-CommandOrNull 'cloudflared.exe'
    if (-not $cf) { $cf = Get-CommandOrNull 'cloudflared' }
    if ($cf -and -not $Force) {
        Write-OK "cloudflared already installed: $($cf.Source)"
    } else {
        Write-Step 'Installing cloudflared.exe...'
        $ok = $false
        $winget = Get-CommandOrNull 'winget'
        if ($winget) {
            & $winget.Source install Cloudflare.cloudflared --accept-package-agreements --accept-source-agreements -h 2>$null
            if ($LASTEXITCODE -eq 0) { $ok = $true }
        }
        if (-not $ok) {
            $choco = Get-CommandOrNull 'choco'
            if ($choco) {
                & $choco.Source install cloudflared -y --no-progress 2>$null
                if ($LASTEXITCODE -eq 0) { $ok = $true }
            }
        }
        if (-not $ok) {
            $scoop = Get-CommandOrNull 'scoop'
            if ($scoop) {
                & $scoop.Source install cloudflared 2>$null
                if ($LASTEXITCODE -eq 0) { $ok = $true }
            }
        }
        if (-not $ok) {
            # Direct download fallback
            Write-Step 'Direct download of cloudflared.exe...'
            try {
                $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/cloudflare/cloudflared/releases/latest' -UseBasicParsing
                $asset = $rel.assets | Where-Object { $_.name -eq 'cloudflared-windows-amd64.exe' } | Select-Object -First 1
                if ($asset) {
                    $binDir = Join-Path $env:ProgramFiles 'GitHubRDPToolkit\bin'
                    $null = New-Item -ItemType Directory -Path $binDir -Force
                    $dest = Join-Path $binDir 'cloudflared.exe'
                    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $dest -UseBasicParsing
                    Write-OK "cloudflared.exe downloaded to $dest (not yet on PATH)"
                    $ok = $true
                }
            } catch {
                Write-Warn2 "Direct download failed: $($_.Exception.Message)"
            }
        }
        if (-not $ok) {
            Write-Warn2 'cloudflared install failed. Cloudflare fallback will not be available.'
        }
    }
}

# ----------------------------------------------------------------------
# 4) Optional: PowerShell 7+
# ----------------------------------------------------------------------
if (-not $SkipPwsh7) {
    Write-Step 'Checking for PowerShell 7+...'
    $pwsh = Get-CommandOrNull 'pwsh.exe'
    if (-not $pwsh) { $pwsh = Get-CommandOrNull 'pwsh' }
    if ($pwsh -and -not $Force) {
        $ver = & $pwsh.Source --version
        Write-OK "PowerShell 7+ already installed: $($pwsh.Source) ($($ver.Trim()))"
    } else {
        Write-Step 'Installing PowerShell 7...'
        $ok = $false
        $winget = Get-CommandOrNull 'winget'
        if ($winget) {
            & $winget.Source install Microsoft.PowerShell --accept-package-agreements --accept-source-agreements -h 2>$null
            if ($LASTEXITCODE -eq 0) { $ok = $true }
        }
        if (-not $ok) {
            $choco = Get-CommandOrNull 'choco'
            if ($choco) {
                & $choco.Source install pwsh -y --no-progress 2>$null
                if ($LASTEXITCODE -eq 0) { $ok = $true }
            }
        }
        if ($ok) { Write-OK 'PowerShell 7 installed.' }
        else { Write-Warn2 'PowerShell 7 install skipped/failed. Windows PowerShell 5.1 is sufficient.' }
    }
}

# ----------------------------------------------------------------------
# 5) Optional: Python 3.x (for Python client tools)
# ----------------------------------------------------------------------
if (-not $SkipPython) {
    Write-Step 'Checking for Python 3...'
    $py = Get-CommandOrNull 'python.exe'
    if (-not $py) { $py = Get-CommandOrNull 'python' }
    if (-not $py) { $py = Get-CommandOrNull 'py.exe' }
    if ($py -and -not $Force) {
        $ver = & $py.Source --version 2>$null
        Write-OK "Python already installed: $($py.Source) ($($ver.Trim()))"
    } else {
        Write-Step 'Installing Python 3...'
        $ok = $false
        $winget = Get-CommandOrNull 'winget'
        if ($winget) {
            & $winget.Source install Python.Python.3.12 --accept-package-agreements --accept-source-agreements -h 2>$null
            if ($LASTEXITCODE -eq 0) { $ok = $true }
        }
        if (-not $ok) {
            $choco = Get-CommandOrNull 'choco'
            if ($choco) {
                & $choco.Source install python -y --no-progress 2>$null
                if ($LASTEXITCODE -eq 0) { $ok = $true }
            }
        }
        if ($ok) { Write-OK 'Python installed.' }
        else { Write-Warn2 'Python install skipped/failed. Pure-PowerShell client scripts work without Python.' }
    }
}

Write-Host ''
Write-Host '======================================' -ForegroundColor Green
Write-Host '  Client setup complete!' -ForegroundColor Green
Write-Host '======================================' -ForegroundColor Green
Write-Host ''
Write-Host '  Next steps:' -ForegroundColor White
Write-Host '    1. Run: rdp-toolkit fetch-creds' -ForegroundColor White
Write-Host '    2. Run: rdp-toolkit connect' -ForegroundColor White
Write-Host ''
exit 0
