# core/powershell/install-software.ps1 - Install software from configs/software-list.json via winget/choco
. "$PSScriptRoot\utils.ps1"

$ListFile = Join-Path $PSScriptRoot '..\..\configs\software-list.json'
if (-not (Test-Path $ListFile)) { Write-Warn "software-list.json not found at $ListFile"; exit 0 }

$cfg = Get-Content $ListFile -Raw | ConvertFrom-Json
$software = $cfg.software
$enabled  = $software | Where-Object { $_.enabled }

if (-not $enabled -or $enabled.Count -eq 0) {
    Write-Info 'No software marked enabled in config - skipping'
    exit 0
}

Write-Block "INSTALL SOFTWARE - $($enabled.Count) packages"

$useWinget = $false
try { $null = Get-Command winget -ErrorAction Stop; $useWinget = $true } catch { }
$useChoco = $false
try { $null = Get-Command choco -ErrorAction Stop; $useChoco = $true } catch { }

if (-not $useWinget -and -not $useChoco) {
    Write-Warn 'Neither winget nor choco available - installing choco...'
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        $useChoco = $true
    } catch { Write-Err 'Could not install choco'; exit 1 }
}

foreach ($pkg in $enabled) {
    $id       = $pkg.id
    $provider = if ($pkg.provider) { $pkg.provider.ToLower() } else { if ($useWinget) { 'winget' } else { 'choco' } }
    Write-Info "Installing $id via $provider..."

    try {
        if ($provider -eq 'winget' -and $useWinget) {
            # CRITICAL: use $wingetArgs, NOT $args (which is reserved in PowerShell)
            $wingetArgs = @('install','--id',$id,'--accept-source-agreements','--accept-package-agreements','--silent','--disable-interactivity')
            if ($pkg.scope -eq 'machine') { $wingetArgs += '--scope'; $wingetArgs += 'machine' }
            & winget @wingetArgs 2>&1 | Out-Host
            if ($LASTEXITCODE -eq 0) { Write-Ok "winget: $id installed" } else { Write-Warn "winget: $id exit $LASTEXITCODE" }
        } elseif ($provider -eq 'choco' -and $useChoco) {
            & choco install $id -y --no-progress --limit-output 2>&1 | Out-Host
            if ($LASTEXITCODE -eq 0) { Write-Ok "choco: $id installed" } else { Write-Warn "choco: $id exit $LASTEXITCODE" }
        } else {
            Write-Warn "Provider '$provider' not available for $id"
        }
    } catch {
        Write-Err "Failed to install $id : $($_.Exception.Message)"
    }
}

Write-Ok 'Software install pass complete'
