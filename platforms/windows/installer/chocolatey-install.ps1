#Requires -Version 5.1
<#
.SYNOPSIS
    Chocolatey install script for github-rdp-mega-toolkit.
.DESCRIPTION
    Called by Chocolatey during `choco install github-rdp-mega-toolkit`.
    Copies the bundled tools/configs/scripts into the Chocolatey package
    install directory and (optionally) downloads cloudflared.exe.
.NOTES
    $toolsDir is provided by Chocolatey at runtime.
    $packageName, $packageVersion are provided by Chocolatey.
#>
$ErrorActionPreference = 'Stop'
$toolsDir   = if ($env:ChocolateyPackageFolder) { $env:ChocolateyPackageFolder } else { Split-Path -Parent $PSCommandPath }
$packageName = 'github-rdp-mega-toolkit'
$version     = '9.0.0'

Write-Host "[choco-install] Installing $packageName v$version to $toolsDir" -ForegroundColor Cyan

# ----------------------------------------------------------------------
# Optional: download cloudflared.exe (only if -InstallCloudflared was
# passed via package parameters)
# ----------------------------------------------------------------------
$pp = Get-PackageParameters
if ($pp.ContainsKey('InstallCloudflared') -or $pp.ContainsKey('Cloudflared')) {
    Write-Host '[choco-install] Downloading cloudflared.exe ...' -ForegroundColor Cyan
    $binDir = Join-Path $toolsDir 'bin'
    $null = New-Item -ItemType Directory -Path $binDir -Force
    $cfDest = Join-Path $binDir 'cloudflared.exe'
    try {
        $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/cloudflare/cloudflared/releases/latest' -UseBasicParsing
        $asset = $rel.assets | Where-Object { $_.name -eq 'cloudflared-windows-amd64.exe' } | Select-Object -First 1
        if ($asset) {
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $cfDest -UseBasicParsing
            Write-Host "[choco-install] cloudflared.exe saved to $cfDest" -ForegroundColor Green
        } else {
            Write-Warning 'cloudflared asset not found in latest release; skipping.'
        }
    } catch {
        Write-Warning "cloudflared download failed: $($_.Exception.Message)"
    }
}

# ----------------------------------------------------------------------
# Register shim for toolkit entry point (if a CLI wrapper is bundled)
# ----------------------------------------------------------------------
$cliWrapper = Join-Path $toolsDir 'bin\rdp-toolkit.cmd'
if (Test-Path $cliWrapper) {
    Install-BinFile -Name 'rdp-toolkit' -Path $cliWrapper
    Write-Host "[choco-install] Shim installed: rdp-toolkit -> $cliWrapper" -ForegroundColor Green
}

# ----------------------------------------------------------------------
# Create Start Menu shortcuts
# ----------------------------------------------------------------------
$startMenuDir = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'GitHubRDPToolkit'
$null = New-Item -ItemType Directory -Path $startMenuDir -Force
$consoleLnk = Join-Path $startMenuDir 'GitHub RDP Toolkit Console.lnk'
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut($consoleLnk)
$sc.TargetPath = 'powershell.exe'
$sc.Arguments  = "-NoExit -Command `"& { Set-Location '$toolsDir'; Write-Host 'GitHub RDP Mega Toolkit — ready.' }`""
$sc.WorkingDirectory = $toolsDir
$sc.Description = 'Open a toolkit console.'
$sc.Save()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($ws) | Out-Null
Write-Host "[choco-install] Start Menu shortcut created: $consoleLnk" -ForegroundColor Green

# ----------------------------------------------------------------------
# Print post-install guidance
# ----------------------------------------------------------------------
Write-Host ''
Write-Host '======================================' -ForegroundColor Green
Write-Host "  $packageName v$version installed." -ForegroundColor Green
Write-Host '======================================' -ForegroundColor Green
Write-Host "  Install dir : $toolsDir" -ForegroundColor White
Write-Host '  Next steps  :' -ForegroundColor White
Write-Host '    1. Open a NEW terminal' -ForegroundColor White
Write-Host '    2. Run: rdp-toolkit doctor' -ForegroundColor White
Write-Host '    3. Run: rdp-toolkit fetch-creds' -ForegroundColor White
Write-Host '    4. Run: rdp-toolkit connect' -ForegroundColor White
Write-Host ''
