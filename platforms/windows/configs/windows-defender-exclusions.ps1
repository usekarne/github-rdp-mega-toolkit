#Requires -Version 5.1
<#
.SYNOPSIS
    Adds Microsoft Defender exclusions for the GitHub RDP Mega Toolkit
    install directory + key processes, to prevent real-time scanning
    from interfering with RDP sessions, tunnels, and credential files.
.DESCRIPTION
    Excludes the following from Defender real-time + scheduled scans:
      * Install directory: $env:ProgramFiles\GitHubRDPToolkit
      * Local app data:    $env:LOCALAPPDATA\GitHubRDPToolkit
      * Tunnel binaries:   cloudflared.exe, ssh.exe
      * Credential cache:  *.rdp-creds.json under local app data
.PARAMETER InstallDir
    Override the install directory. Default: $env:ProgramFiles\GitHubRDPToolkit
.PARAMETER Remove
    Remove previously-added exclusions.
.EXAMPLE
    .\windows-defender-exclusions.ps1
.EXAMPLE
    .\windows-defender-exclusions.ps1 -Remove
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles 'GitHubRDPToolkit'),
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

function Write-Step  { param([string]$m) Write-Host "[defender] $m" -ForegroundColor Cyan }
function Write-OK    { param([string]$m) Write-Host "[ok]       $m" -ForegroundColor Green }
function Write-Warn2 { param([string]$m) Write-Host "[warn]     $m" -ForegroundColor Yellow }
function Write-Err2  { param([string]$m) Write-Host "[error]    $m" -ForegroundColor Red }

# ----------------------------------------------------------------------
# Self-elevate
# ----------------------------------------------------------------------
function Test-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Administrator)) {
    Write-Warn2 'Administrator rights required. Relaunching elevated...'
    $argsList = @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`"","-InstallDir","`"$InstallDir`"")
    if ($Remove) { $argsList += '-Remove' }
    $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList $argsList
    exit $p.ExitCode
}

# ----------------------------------------------------------------------
# Detect Defender availability
# ----------------------------------------------------------------------
try {
    $prefs = Get-MpPreference -ErrorAction Stop
} catch {
    Write-Err2 "Microsoft Defender cmdlets not available: $($_.Exception.Message)"
    Write-Err2 'This script requires Windows 10/11 with Defender enabled, OR Server with Defender installed.'
    exit 1
}

# ----------------------------------------------------------------------
# Build exclusion lists
# ----------------------------------------------------------------------
$localApp = Join-Path $env:LOCALAPPDATA 'GitHubRDPToolkit'

$pathsToExclude = @(
    $InstallDir,
    $localApp,
    (Join-Path $InstallDir 'bin'),
    (Join-Path $InstallDir 'scripts'),
    (Join-Path $InstallDir 'configs')
)

$processesToExclude = @(
    'cloudflared.exe',
    'ssh.exe',
    'xfreerdp.exe',
    'mstsc.exe',
    'powershell.exe',
    'pwsh.exe'
)

$extensionsToExclude = @(
    '.rdp',
    '.rdp-creds.json',
    '.creds.json'
)

# ----------------------------------------------------------------------
# Remove mode
# ----------------------------------------------------------------------
if ($Remove) {
    Write-Step 'Removing Defender exclusions...'

    foreach ($p in $pathsToExclude) {
        if ($prefs.ExclusionPath -contains $p) {
            Remove-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue
            Write-OK "Removed path exclusion: $p"
        }
    }
    foreach ($pr in $processesToExclude) {
        if ($prefs.ExclusionProcess -contains $pr) {
            Remove-MpPreference -ExclusionProcess $pr -ErrorAction SilentlyContinue
            Write-OK "Removed process exclusion: $pr"
        }
    }
    foreach ($e in $extensionsToExclude) {
        if ($prefs.ExclusionExtension -contains $e) {
            Remove-MpPreference -ExclusionExtension $e -ErrorAction SilentlyContinue
            Write-OK "Removed extension exclusion: $e"
        }
    }
    Write-OK 'Defender exclusions removed.'
    return
}

# ----------------------------------------------------------------------
# Add mode
# ----------------------------------------------------------------------
Write-Step 'Adding Defender exclusions...'

foreach ($p in $pathsToExclude) {
    if (-not (Test-Path $p)) {
        Write-Warn2 "Path does not exist (will still add exclusion): $p"
    }
    try {
        Add-MpPreference -ExclusionPath $p -ErrorAction Stop
        Write-OK "Added path exclusion: $p"
    } catch {
        Write-Warn2 "Could not add path exclusion for '$p': $($_.Exception.Message)"
    }
}

foreach ($pr in $processesToExclude) {
    try {
        Add-MpPreference -ExclusionProcess $pr -ErrorAction Stop
        Write-OK "Added process exclusion: $pr"
    } catch {
        Write-Warn2 "Could not add process exclusion for '$pr': $($_.Exception.Message)"
    }
}

foreach ($e in $extensionsToExclude) {
    try {
        Add-MpPreference -ExclusionExtension $e -ErrorAction Stop
        Write-OK "Added extension exclusion: $e"
    } catch {
        Write-Warn2 "Could not add extension exclusion for '$e': $($_.Exception.Message)"
    }
}

# ----------------------------------------------------------------------
# Disable cloud-delivered protection sample submission for the toolkit
# (optional — prevents accidental upload of credential files). User
# can re-enable via Security Center UI.
# ----------------------------------------------------------------------
Write-Step 'Optional: disabling automatic sample submission for safety...'
try {
    Set-MpPreference -SubmitSamplesConsent 2   # Never send samples
    Write-OK 'Sample submission set to: never.'
} catch {
    Write-Warn2 "Could not set sample submission consent: $($_.Exception.Message)"
}

Write-Host ''
Write-Host 'Defender exclusions applied.' -ForegroundColor Green
Write-Host "To remove later: .\windows-defender-exclusions.ps1 -Remove" -ForegroundColor Yellow
