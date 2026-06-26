#Requires -Version 7.0
<#
    .SYNOPSIS
        Installs the software catalogue declared in configs/software-list.json
        using winget (preferred) or chocolatey as fallback.

    .PARAMETER ConfigPath
        Path to the JSON catalogue.  Defaults to
        ../configs/software-list.json relative to this script.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/utils.ps1"

if (-not $ConfigPath) {
    $ConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) '..' 'configs' 'software-list.json'
    $ConfigPath = (Resolve-Path $ConfigPath -ErrorAction SilentlyContinue).Path
    if (-not $ConfigPath) {
        # Fall back to a relative path inside the runner workspace.
        $ConfigPath = Join-Path (Get-Location) 'configs' 'software-list.json'
    }
}
if (-not (Test-Path $ConfigPath)) {
    Write-Err "Software catalogue not found: $ConfigPath"
    exit 1
}

Write-Block "Installing software from $ConfigPath"
$catalog = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Detect available installers.
$winget = Get-Command winget -ErrorAction SilentlyContinue
$choco  = Get-Command choco  -ErrorAction SilentlyContinue
if (-not $winget -and -not $choco) {
    Write-Warn 'Neither winget nor choco detected — nothing to install.'
    exit 0
}

$installed = 0
$skipped   = 0
$failed    = 0

foreach ($pkg in $catalog.packages) {
    if (-not $pkg.enabled) {
        Write-Info "SKIP  $($pkg.name) (enabled=false)"
        $skipped++
        continue
    }
    $name = $pkg.name
    Write-Info "INSTALL $name"

    $ok = $false
    if ($winget -and $pkg.winget) {
        try {
            & winget install --id $pkg.winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 |
                Tee-Object -Variable wingetOut | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "winget: $name ($($pkg.winget))"
                $ok = $true
            } else {
                Write-Warn "winget install of $($pkg.winget) failed (exit $LASTEXITCODE)"
            }
        } catch {
            Write-Warn "winget exception for $name : $($_.Exception.Message)"
        }
    }
    if (-not $ok -and $choco -and $pkg.choco) {
        try {
            & choco install $pkg.choco -y --no-progress 2>&1 |
                Tee-Object -Variable chocoOut | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "choco:  $name ($($pkg.choco))"
                $ok = $true
            } else {
                Write-Warn "choco install of $($pkg.choco) failed (exit $LASTEXITCODE)"
            }
        } catch {
            Write-Warn "choco exception for $name : $($_.Exception.Message)"
        }
    }
    if ($ok) {
        $installed++
    } else {
        $failed++
        if (-not $pkg.optional) {
            Write-Err "REQUIRED package failed: $name"
        } else {
            Write-Warn "Optional package failed: $name"
        }
    }
}

Write-Block 'install-software.ps1 summary'
Write-Info "Installed: $installed  Skipped: $skipped  Failed: $failed"

if ($failed -gt 0) {
    Write-Warn 'Some packages failed — see log above for details. Continuing anyway (non-fatal).'
    # Don't exit non-zero — we want the workflow to continue to tunnel setup.
    # Failed packages just won't be available; user can install manually later.
}
exit 0
