#Requires -Version 5.1
<#
.SYNOPSIS
    PowerShell installer for the GitHub RDP Mega Toolkit (Windows client).
.DESCRIPTION
    This script installs the GitHub RDP Mega Toolkit to
    "$env:ProgramFiles\GitHubRDPToolkit", copies all tools/configs/docs,
    adds the install directory to the system PATH, creates Start Menu and
    Desktop shortcuts, registers an uninstaller in the Windows registry,
    creates an uninstall.ps1 at the install location, and verifies that
    either xfreerdp (from FreeRDP builds) or mstsc.exe (built-in) is
    available on the host.

    Optionally downloads and installs cloudflared.exe when the
    -InstallCloudflared switch is supplied (Cloudflare fallback path).

    Works on Windows PowerShell 5.1 (Desktop) AND PowerShell 7+ (Core).
.PARAMETER InstallDir
    Override the install directory. Defaults to "$env:ProgramFiles\GitHubRDPToolkit".
.PARAMETER InstallCloudflared
    If set, downloads cloudflared.exe and installs it alongside the toolkit.
.PARAMeter CloudflaredVersion
    cloudflared release tag to fetch. Defaults to "latest".
.PARAMETER Force
    Overwrite an existing installation without prompting.
.PARAMETER NoShortcuts
    Skip creating Start Menu and Desktop shortcuts.
.PARAMETER NoPath
    Skip adding the install directory to the system PATH.
.EXAMPLE
    .\install.ps1
    Installs with defaults.
.EXAMPLE
    .\install.ps1 -InstallCloudflared -Force
    Installs with Cloudflare fallback client and overwrites existing install.
.NOTES
    File Name    : install.ps1
    Author       : usekarne
    Prerequisite : PowerShell 5.1+ (Desktop or Core), administrator rights.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles 'GitHubRDPToolkit'),
    [switch]$InstallCloudflared,
    [string]$CloudflaredVersion = 'latest',
    [switch]$Force,
    [switch]$NoShortcuts,
    [switch]$NoPath
)

# ----------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # speed up Invoke-WebRequest

$Script:Appname        = 'GitHubRDPToolkit'
$Script:AppVersion     = '9.0.0'
$Script:AppPublisher   = 'usekarne'
$Script:AppURL         = 'https://github.com/usekarne/github-rdp-mega-toolkit'
$Script:UninstallRegKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GitHubRDPToolkit'

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------
function Write-Step   { param([string]$msg) Write-Host "[install] $msg" -ForegroundColor Cyan }
function Write-OK     { param([string]$msg) Write-Host "[ok]     $msg" -ForegroundColor Green }
function Write-Warn2  { param([string]$msg) Write-Host "[warn]   $msg" -ForegroundColor Yellow }
function Write-Err2   { param([string]$msg) Write-Host "[error]  $msg" -ForegroundColor Red }

function Test-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevate {
    Write-Warn2 'Administrator rights required. Relaunching elevated...'
    $psi = New-Object System.Diagnostics.ProcessStartInfo 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $($PSBoundParameters.GetEnumerator() | ForEach-Object { if ($_.Value -is [switch]) { if ($_.Value) { "-$($_.Key)" } } else { "-$($_.Key) `"$($_.Value)`"" } })"
    $psi.Verb = 'runas'
    $psi.UseShellExecute = $true
    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
        exit $p.ExitCode
    } catch {
        Write-Err2 "Elevation declined or failed: $($_.Exception.Message)"
        exit 1
    }
}

function Get-PathEntries {
    $machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    if (-not $machinePath) { return @() }
    return $machinePath.Split(';', [StringSplitOptions]::RemoveEmptyEntries)
}

function Add-ToSystemPath {
    param([string]$dir)
    $current = Get-PathEntries
    if ($current -contains $dir) {
        Write-OK "PATH already contains '$dir'."
        return
    }
    $newPath = ($current + $dir) -join ';'
    [Environment]::SetEnvironmentVariable('PATH', $newPath, 'Machine')
    Write-OK "Added '$dir' to system PATH."
}

function Remove-FromSystemPath {
    param([string]$dir)
    $current = Get-PathEntries
    if ($current -notcontains $dir) { return }
    $newPath = ($current | Where-Object { $_ -ne $dir }) -join ';'
    [Environment]::SetEnvironmentVariable('PATH', $newPath, 'Machine')
    Write-OK "Removed '$dir' from system PATH."
}

function New-Shortcut {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [string]$Arguments      = '',
        [string]$WorkingDir     = '',
        [string]$IconLocation   = '',
        [string]$Description    = ''
    )
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($ShortcutPath)
    $sc.TargetPath   = $TargetPath
    if ($Arguments)    { $sc.Arguments     = $Arguments }
    if ($WorkingDir)   { $sc.WorkingDirectory = $WorkingDir }
    if ($IconLocation) { $sc.IconLocation = $IconLocation }
    if ($Description)  { $sc.Description  = $Description }
    $sc.Save()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ws) | Out-Null
}

function Get-InstalledSize {
    param([string]$path)
    if (-not (Test-Path $path)) { return 0 }
    $sum = 0
    Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object { $sum += $_.Length }
    return [int]([math]::Round($sum / 1KB))
}

# ----------------------------------------------------------------------
# Pre-flight checks
# ----------------------------------------------------------------------
if (-not (Test-Administrator)) {
    Invoke-SelfElevate
    return
}

Write-Host ''
Write-Host '======================================' -ForegroundColor White
Write-Host "  GitHub RDP Mega Toolkit $Script:AppVersion Installer" -ForegroundColor White
Write-Host '======================================' -ForegroundColor White
Write-Host ''

# ----------------------------------------------------------------------
# Determine source directory (script location)
# ----------------------------------------------------------------------
$sourceRoot = Split-Path -Parent $PSCommandPath
$toolkitRoot = Split-Path -Parent (Split-Path -Parent $sourceRoot)   # .../platforms/windows -> .../github-rdp-mega-toolkit
if (-not (Test-Path (Join-Path $toolkitRoot 'version.txt'))) {
    # Fall back: use current script root as source
    $toolkitRoot = $sourceRoot
}
Write-Step "Source root: $toolkitRoot"
Write-Step "Install dir: $InstallDir"

# ----------------------------------------------------------------------
# Handle existing installation
# ----------------------------------------------------------------------
if (Test-Path $InstallDir) {
    if (-not $Force) {
        $msg = "Install directory '$InstallDir' already exists. Overwrite? (y/N)"
        $reply = Read-Host $msg
        if ($reply -notmatch '^[Yy]') {
            Write-Warn2 'Installation cancelled by user.'
            exit 2
        }
    }
    Write-Step "Removing existing install at '$InstallDir'..."
    Remove-Item -Recurse -Force $InstallDir
}

# ----------------------------------------------------------------------
# Create install directory tree
# ----------------------------------------------------------------------
Write-Step 'Creating install directory tree...'
$null = New-Item -ItemType Directory -Path $InstallDir -Force
$null = New-Item -ItemType Directory -Path (Join-Path $InstallDir 'bin')       -Force
$null = New-Item -ItemType Directory -Path (Join-Path $InstallDir 'configs')   -Force
$null = New-Item -ItemType Directory -Path (Join-Path $InstallDir 'scripts')   -Force
$null = New-Item -ItemType Directory -Path (Join-Path $InstallDir 'docs')      -Force
$null = New-Item -ItemType Directory -Path (Join-Path $InstallDir 'platforms\windows') -Force
Write-OK 'Install directory tree created.'

# ----------------------------------------------------------------------
# Copy files
# ----------------------------------------------------------------------
Write-Step 'Copying toolkit files...'

# Top-level files
$topFiles = @('version.txt', 'README.md', 'LICENSE')
foreach ($f in $topFiles) {
    $src = Join-Path $toolkitRoot $f
    if (Test-Path $src) {
        Copy-Item $src -Destination $InstallDir -Force
    }
}

# configs/
$cfgSrc = Join-Path $toolkitRoot 'configs'
if (Test-Path $cfgSrc) {
    Copy-Item -Path $cfgSrc -Destination (Join-Path $InstallDir 'configs') -Recurse -Force
}

# docs/
$docsSrc = Join-Path $toolkitRoot 'docs'
if (Test-Path $docsSrc) {
    Copy-Item -Path $docsSrc -Destination (Join-Path $InstallDir 'docs') -Recurse -Force
}

# tools/
$toolsSrc = Join-Path $toolkitRoot 'tools'
if (Test-Path $toolsSrc) {
    Copy-Item -Path $toolsSrc -Destination (Join-Path $InstallDir 'tools') -Recurse -Force
}

# platforms/windows (recursive)
$winSrc = Join-Path $toolkitRoot 'platforms\windows'
if (Test-Path $winSrc) {
    Copy-Item -Path $winSrc -Destination (Join-Path $InstallDir 'platforms\windows') -Recurse -Force
}
Write-OK 'Files copied.'

# ----------------------------------------------------------------------
# Optionally install cloudflared.exe
# ----------------------------------------------------------------------
if ($InstallCloudflared) {
    Write-Step 'Downloading cloudflared.exe...'
    try {
        if ($CloudflaredVersion -eq 'latest') {
            $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/cloudflare/cloudflared/releases/latest' -UseBasicParsing
            $asset = $rel.assets | Where-Object { $_.name -eq 'cloudflared-windows-amd64.exe' } | Select-Object -First 1
            if (-not $asset) { throw 'cloudflared-windows-amd64.exe asset not found in latest release' }
            $dlUrl = $asset.browser_download_url
        } else {
            $dlUrl = "https://github.com/cloudflare/cloudflared/releases/download/$CloudflaredVersion/cloudflared-windows-amd64.exe"
        }
        $cfDest = Join-Path $InstallDir 'bin\cloudflared.exe'
        Invoke-WebRequest -Uri $dlUrl -OutFile $cfDest -UseBasicParsing
        Write-OK "cloudflared.exe installed to $cfDest"
    } catch {
        Write-Warn2 "cloudflared install failed: $($_.Exception.Message)"
        Write-Warn2 'You can download it manually from https://github.com/cloudflare/cloudflared/releases'
    }
}

# ----------------------------------------------------------------------
# Generate uninstall.ps1 at install location
# ----------------------------------------------------------------------
Write-Step 'Generating uninstall.ps1 at install location...'
$uninstallPs1 = @'
#Requires -Version 5.1
<#
.SYNOPSIS
    Uninstaller for GitHub RDP Mega Toolkit.
.DESCRIPTION
    Reverses all actions performed by install.ps1: removes the install
    directory, removes the PATH entry, removes Start Menu and Desktop
    shortcuts, removes the registry uninstaller entry, and optionally
    cleans up local app data.
.PARAMETER RemoveAppData
    Also remove cached data under "$env:LOCALAPPDATA\GitHubRDPToolkit".
#>
[CmdletBinding()]
param(
    [switch]$RemoveAppData
)
$ErrorActionPreference = 'Stop'
$InstallDir   = Split-Path -Parent $PSCommandPath
$AppName      = 'GitHubRDPToolkit'
$StartMenuDir = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) $AppName
$DesktopLnk   = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) "$AppName.lnk"
$UninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GitHubRDPToolkit'

function W-S { param($m) Write-Host "[uninstall] $m" -ForegroundColor Cyan }
function W-O { param($m) Write-Host "[ok]        $m" -ForegroundColor Green }
function W-W { param($m) Write-Host "[warn]      $m" -ForegroundColor Yellow }

# Self-elevate
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    W-W 'Administrator rights required. Relaunching elevated...'
    $a = if ($RemoveAppData) { '-RemoveAppData' } else { '' }
    Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $a"
    exit $LASTEXITCODE
}

# Remove PATH entry
W-S 'Removing PATH entry...'
$mp = [Environment]::GetEnvironmentVariable('PATH','Machine')
if ($mp) {
    $entries = $mp.Split(';',[StringSplitOptions]::RemoveEmptyEntries) | Where-Object { $_ -ne $InstallDir }
    [Environment]::SetEnvironmentVariable('PATH', ($entries -join ';'), 'Machine')
    W-O 'PATH entry removed.'
}

# Remove shortcuts
W-S 'Removing shortcuts...'
if (Test-Path $StartMenuDir) { Remove-Item -Recurse -Force $StartMenuDir; W-O "Removed $StartMenuDir" }
if (Test-Path $DesktopLnk)   { Remove-Item -Force $DesktopLnk; W-O "Removed $DesktopLnk" }

# Remove registry uninstaller entry
W-S 'Removing registry uninstaller entry...'
if (Test-Path $UninstallKey) { Remove-Item -Recurse -Force $UninstallKey; W-O "Removed $UninstallKey" }

# Remove install directory
W-S "Removing install directory: $InstallDir"
if (Test-Path $InstallDir) {
    Remove-Item -Recurse -Force $InstallDir
    W-O 'Install directory removed.'
} else {
    W-W 'Install directory not found.'
}

# Optionally remove app data
if ($RemoveAppData) {
    $appData = Join-Path $env:LOCALAPPDATA 'GitHubRDPToolkit'
    W-S "Removing app data: $appData"
    if (Test-Path $appData) { Remove-Item -Recurse -Force $appData; W-O 'App data removed.' }
    else { W-W 'No app data found.' }
}

W-O 'Uninstall complete.'
'@
$uninstallPs1Path = Join-Path $InstallDir 'uninstall.ps1'
$uninstallPs1 | Out-File -FilePath $uninstallPs1Path -Encoding ASCII -NoNewline
Write-OK "uninstall.ps1 created at $uninstallPs1Path"

# ----------------------------------------------------------------------
# Add to system PATH
# ----------------------------------------------------------------------
if (-not $NoPath) {
    Write-Step 'Adding install directory to system PATH...'
    Add-ToSystemPath -dir $InstallDir
} else {
    Write-Warn2 'Skipping PATH update (-NoPath).'
}

# ----------------------------------------------------------------------
# Create shortcuts
# ----------------------------------------------------------------------
if (-not $NoShortcuts) {
    Write-Step 'Creating Start Menu shortcuts...'
    $startMenuDir = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) $Script:Appname
    $null = New-Item -ItemType Directory -Path $startMenuDir -Force

    $consoleLnk = Join-Path $startMenuDir "$Script:Appname Console.lnk"
    New-Shortcut -ShortcutPath $consoleLnk `
                 -TargetPath 'powershell.exe' `
                 -Arguments "-NoExit -Command `"& { Set-Location '$InstallDir'; Write-Host 'GitHub RDP Mega Toolkit — ready.' }`"" `
                 -WorkingDir $InstallDir `
                 -IconLocation 'powershell.exe,0' `
                 -Description 'Open a toolkit console.'

    $uninstallLnk = Join-Path $startMenuDir "Uninstall $Script:Appname.lnk"
    New-Shortcut -ShortcutPath $uninstallLnk `
                 -TargetPath 'powershell.exe' `
                 -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$uninstallPs1Path`"" `
                 -WorkingDir $InstallDir `
                 -IconLocation 'powershell.exe,0' `
                 -Description 'Uninstall GitHub RDP Mega Toolkit.'
    Write-OK "Start Menu shortcuts created at: $startMenuDir"

    Write-Step 'Creating Desktop shortcut...'
    $desktopLnk = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) "$Script:Appname.lnk"
    New-Shortcut -ShortcutPath $desktopLnk `
                 -TargetPath 'powershell.exe' `
                 -Arguments "-NoExit -Command `"& { Set-Location '$InstallDir'; Write-Host 'GitHub RDP Mega Toolkit — ready.' }`"" `
                 -WorkingDir $InstallDir `
                 -IconLocation 'powershell.exe,0' `
                 -Description 'Open a toolkit console.'
    Write-OK "Desktop shortcut created at: $desktopLnk"
} else {
    Write-Warn2 'Skipping shortcut creation (-NoShortcuts).'
}

# ----------------------------------------------------------------------
# Register uninstaller in registry
# ----------------------------------------------------------------------
Write-Step 'Registering uninstaller in registry...'
$regPath = Split-Path $Script:UninstallRegKey -Parent
if (-not (Test-Path $regPath)) { $null = New-Item -Path $regPath -Force }
if (-not (Test-Path $Script:UninstallRegKey)) { $null = New-Item -Path $Script:UninstallRegKey -Force }

$sizeKB = Get-InstalledSize -path $InstallDir
Set-ItemProperty -Path $Script:UninstallRegKey -Name 'DisplayName'      -Value "GitHub RDP Mega Toolkit"
Set-ItemProperty -Path $Script:UninstallRegKey -Name 'DisplayVersion'   -Value $Script:AppVersion
Set-ItemProperty -Path $Script:UninstallRegKey -Name 'Publisher'        -Value $Script:AppPublisher
Set-ItemProperty -Path $Script:UninstallRegKey -Name 'URLInfoAbout'     -Value $Script:AppURL
Set-ItemProperty -Path $Script:UninstallRegKey -Name 'HelpLink'         -Value $Script:AppURL
Set-ItemProperty -Path $Script:UninstallRegKey -Name 'InstallLocation'  -Value $InstallDir
Set-ItemProperty -Path $Script:UninstallRegKey -Name 'InstallDate'      -Value (Get-Date -Format 'yyyyMMdd')
Set-ItemProperty -Path $Script:UninstallRegKey -Name 'UninstallString'  -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$uninstallPs1Path`""
Set-ItemProperty -Path $Script:UninstallRegKey -Name 'QuietUninstallString' -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$uninstallPs1Path`""
Set-ItemProperty -Path $Script:UninstallRegKey -Name 'DisplayIcon'      -Value "powershell.exe,0"
Set-ItemProperty -Path $Script:UninstallRegKey -Name 'EstimatedSize'    -Value $sizeKB -Type DWord
Set-ItemProperty -Path $Script:UninstallRegKey -Name 'NoModify'         -Value 1 -Type DWord
Set-ItemProperty -Path $Script:UninstallRegKey -Name 'NoRepair'         -Value 1 -Type DWord
Set-ItemProperty -Path $Script:UninstallRegKey -Name 'VersionMajor'     -Value 9  -Type DWord
Set-ItemProperty -Path $Script:UninstallRegKey -Name 'VersionMinor'     -Value 0  -Type DWord
Write-OK 'Uninstaller registered in registry.'

# ----------------------------------------------------------------------
# Verify RDP client availability
# ----------------------------------------------------------------------
Write-Step 'Verifying RDP client availability...'
$rdpClient = $null
$mstsc = Join-Path $env:WINDIR 'System32\mstsc.exe'
if (Test-Path $mstsc) {
    $rdpClient = "mstsc ($mstsc)"
    Write-OK "Native Windows RDP client (mstsc) found at $mstsc"
}
$xfreerdp = Get-Command xfreerdp -ErrorAction SilentlyContinue
if (-not $xfreerdp) {
    $xfreerdp = Get-Command xfreerdp.exe -ErrorAction SilentlyContinue
}
if ($xfreerdp) {
    Write-OK "xfreerdp found at $($xfreerdp.Source)"
    if (-not $rdpClient) { $rdpClient = "xfreerdp ($($xfreerdp.Source))" }
}
if (-not $rdpClient) {
    Write-Warn2 'Neither xfreerdp nor mstsc.exe was found on this system.'
    Write-Warn2 'mstsc.exe is built into all Windows editions; if missing, the OS install may be damaged.'
    Write-Warn2 'For a richer RDP experience, install FreeRDP: https://github.com/FreeRDP/FreeRDP/releases'
}

# ----------------------------------------------------------------------
# Done
# ----------------------------------------------------------------------
Write-Host ''
Write-Host '======================================' -ForegroundColor Green
Write-Host '  Installation complete!' -ForegroundColor Green
Write-Host '======================================' -ForegroundColor Green
Write-Host ''
Write-Host "  Install dir : $InstallDir" -ForegroundColor White
Write-Host "  Version     : $Script:AppVersion" -ForegroundColor White
Write-Host "  Uninstaller : $uninstallPs1Path" -ForegroundColor White
if ($rdpClient) {
    Write-Host "  RDP client  : $rdpClient" -ForegroundColor White
}
Write-Host ''
Write-Host '  Open a NEW terminal for PATH changes to take effect.' -ForegroundColor Yellow
Write-Host ''
exit 0
