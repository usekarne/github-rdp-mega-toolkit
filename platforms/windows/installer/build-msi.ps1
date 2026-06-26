#Requires -Version 5.1
<#
.SYNOPSIS
    Builds a Windows Installer .msi for the GitHub RDP Mega Toolkit using WiX.
.DESCRIPTION
    Looks for candle.exe + light.exe (WiX Toolset v3.x) or wix.exe (WiX v4+)
    on PATH or in $env:WIX, compiles GitHubRDPToolkit.wxs into a .wixobj, and
    links it into the final .msi under .\output\.

    The SOURCE_ROOT environment variable is set so the .wxs $(env.SOURCE_ROOT)
    references resolve. By default SOURCE_ROOT points to the project root
    (three levels above this script).
.PARAMETER SourceRoot
    Override the source root directory used to resolve $(env.SOURCE_ROOT).
.PARAMETER OutputDir
    Output directory for the .msi. Default: .\output
.PARAMETER WxsFile
    Path to the .wxs source. Default: GitHubRDPToolkit.wxs in script dir.
.PARAMETER Version
    Version string baked into the .msi file name.
.PARAMETER SkipVersionStamp
    Skip appending version to output filename (use just 'GitHubRDPToolkit.msi').
.EXAMPLE
    .\build-msi.ps1
    Builds the .msi using defaults.
.NOTES
    WiX Toolset can be installed via:
      winget install WixToolset.WiX
      choco install wixtoolset
      scoop install wixtoolset
#>
[CmdletBinding()]
param(
    [string]$SourceRoot       = '',
    [string]$OutputDir        = '',
    [string]$WxsFile          = '',
    [string]$Version          = '9.0.0',
    [switch]$SkipVersionStamp
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Write-Step { param([string]$m) Write-Host "[build-msi] $m" -ForegroundColor Cyan }
function Write-OK   { param([string]$m) Write-Host "[ok]        $m" -ForegroundColor Green }
function Write-Warn2{ param([string]$m) Write-Host "[warn]      $m" -ForegroundColor Yellow }
function Write-Err2 { param([string]$m) Write-Host "[error]     $m" -ForegroundColor Red }

# ----------------------------------------------------------------------
# Resolve paths
# ----------------------------------------------------------------------
$scriptDir = Split-Path -Parent $PSCommandPath
if (-not $SourceRoot) {
    # scriptDir = .../platforms/windows/installer
    # SourceRoot = .../github-rdp-mega-toolkit
    $SourceRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $scriptDir))
}
if (-not $WxsFile)    { $WxsFile    = Join-Path $scriptDir 'GitHubRDPToolkit.wxs' }
if (-not $OutputDir)  { $OutputDir  = Join-Path $scriptDir 'output' }

if (-not (Test-Path $WxsFile)) {
    Write-Err2 "WiX source not found: $WxsFile"
    exit 1
}
if (-not (Test-Path $SourceRoot)) {
    Write-Err2 "Source root not found: $SourceRoot"
    exit 1
}

$null = New-Item -ItemType Directory -Path $OutputDir -Force
$intermediate = Join-Path $OutputDir 'obj'
$null = New-Item -ItemType Directory -Path $intermediate -Force

# ----------------------------------------------------------------------
# Locate WiX
# ----------------------------------------------------------------------
function Find-WixTool {
    param([string]$tool)
    # 1) PATH
    $cmd = Get-Command $tool -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # 2) $env:WIX (WiX 3.x convention)
    if ($env:WIX) {
        $p = Join-Path $env:WIX $tool
        if (Test-Path $p) { return $p }
    }
    # 3) Program Files (WiX 3.x and 4.x default locations)
    $candidates = @(
        "$env:ProgramFiles\WiX Toolset v3.11\bin\$tool",
        "${env:ProgramFiles(x86)}\WiX Toolset v3.11\bin\$tool",
        "$env:ProgramFiles\WiX Toolset v4.0\bin\$tool",
        "${env:ProgramFiles(x86)}\WiX Toolset v4.0\bin\$tool",
        "$env:ProgramFiles\wix\$tool",
        "${env:ProgramFiles(x86)}\wix\$tool"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

$candle = Find-WixTool 'candle.exe'
$light  = Find-WixTool 'light.exe'
$wix4   = Find-WixTool 'wix.exe'

if ($wix4) {
    # WiX v4 unified CLI
    Write-Step "Using WiX v4: $wix4"
    $wixobj = Join-Path $intermediate 'GitHubRDPToolkit.wixobj'
    $msiName = if ($SkipVersionStamp) { 'GitHubRDPToolkit.msi' } else { "GitHubRDPToolkit-$Version.msi" }
    $msiPath = Join-Path $OutputDir $msiName

    Write-Step "Compiling + linking: $WxsFile"
    & $wix4 build "$WxsFile" -o "$msiPath" -d "SOURCE_ROOT=$SourceRoot" -arch x64
    if ($LASTEXITCODE -ne 0) {
        Write-Err2 "wix.exe build failed (exit $LASTEXITCODE)"
        exit $LASTEXITCODE
    }
    Write-OK "MSI built: $msiPath"
    return
}

if (-not $candle -or -not $light) {
    Write-Err2 'WiX Toolset not found. Install via one of:'
    Write-Err2 '  winget install WixToolset.WiX'
    Write-Err2 '  choco install wixtoolset'
    Write-Err2 '  scoop install wixtoolset'
    Write-Err2 'Then ensure candle.exe and light.exe are on PATH or set $env:WIX.'
    exit 1
}

# ----------------------------------------------------------------------
# WiX v3 path
# ----------------------------------------------------------------------
Write-Step "Using WiX v3:"
Write-Step "  candle: $candle"
Write-Step "  light : $light"

$wixobj = Join-Path $intermediate 'GitHubRDPToolkit.wixobj'
$msiName = if ($SkipVersionStamp) { 'GitHubRDPToolkit.msi' } else { "GitHubRDPToolkit-$Version.msi" }
$msiPath = Join-Path $OutputDir $msiName

# Set SOURCE_ROOT so $(env.SOURCE_ROOT) in .wxs resolves
$env:SOURCE_ROOT = $SourceRoot

Write-Step "Compiling: $WxsFile -> $wixobj"
& $candle -nologo -arch x64 -d "SOURCE_ROOT=$SourceRoot" -out "$wixobj" "$WxsFile"
if ($LASTEXITCODE -ne 0) {
    Write-Err2 "candle.exe failed (exit $LASTEXITCODE)"
    exit $LASTEXITCODE
}
Write-OK 'Compile succeeded.'

Write-Step "Linking: $wixobj -> $msiPath"
& $light -nologo -out "$msiPath" "$wixobj"
if ($LASTEXITCODE -ne 0) {
    Write-Err2 "light.exe failed (exit $LASTEXITCODE)"
    exit $LASTEXITCODE
}
Write-OK "Link succeeded."

if (Test-Path $msiPath) {
    $size = (Get-Item $msiPath).Length
    Write-OK "MSI built: $msiPath ($([math]::Round($size / 1MB, 2)) MB)"
} else {
    Write-Err2 "Expected MSI not found: $msiPath"
    exit 1
}

Write-Host ''
Write-Host 'Done. Install the MSI with:' -ForegroundColor White
Write-Host "  msiexec /i `"$msiPath`" /qb" -ForegroundColor Yellow
Write-Host ''
exit 0
