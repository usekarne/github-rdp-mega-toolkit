# core/powershell/setup-venv.ps1 - Setup virtual environment based on VENV_TYPE env var
. "$PSScriptRoot\utils.ps1"

$VenvType = if ($env:VENV_TYPE) { $env:VENV_TYPE.ToLower() } else { 'none' }
Write-Block "SETUP VENV - type=$VenvType"

switch ($VenvType) {
    'docker' {
        Write-Info 'Starting Docker Desktop...'
        try {
            $dockerPath = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
            if (Test-Path $dockerPath) {
                Start-Process -FilePath $dockerPath
                Write-Ok 'Docker Desktop started'
            } else {
                Write-Warn 'Docker Desktop not found at standard path'
            }
        } catch { Write-Warn "Docker start failed: $($_.Exception.Message)" }
    }
    'wsl' {
        Write-Info 'Configuring WSL...'
        try {
            $wslList = wsl -l -v 2>&1
            Write-Host "WSL distros: $wslList"
        } catch { Write-Warn 'WSL not available' }
    }
    'hyperv' {
        Write-Info 'Starting Hyper-V VM...'
        try {
            $vms = Get-VM -ErrorAction SilentlyContinue
            Write-Host "Available VMs:"
            $vms | Format-Table Name, State
        } catch { Write-Warn 'Hyper-V not available' }
    }
    'none' {
        Write-Info 'No virtual environment requested (VENV_TYPE=none)'
    }
    default {
        Write-Warn "Unknown VENV_TYPE: $VenvType (valid: docker, wsl, hyperv, none)"
    }
}

Write-Ok 'VENV setup complete'
