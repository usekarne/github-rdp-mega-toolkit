# core/powershell/optimize-windows.ps1 - Windows optimization profiles (v9.0)
. "$PSScriptRoot\utils.ps1"

$Profile = if ($env:OPTIMIZE_PROFILE) { $env:OPTIMIZE_PROFILE.ToLower() } else { 'productivity' }
Write-Block "OPTIMIZE WINDOWS - profile=$Profile"

$Profiles = @{
    gaming = @{
        disable = @('DiagTrack','dmwappushservice','SysMain','WSearch','Fax','XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc')
        enable  = @('Themes','AudioEndpointBuilder','Audiosrv')
        visual  = 'performance'
    }
    productivity = @{
        disable = @('DiagTrack','dmwappushservice','Fax','WSearch')
        enable  = @('Themes','AudioEndpointBuilder','Audiosrv','Winmgmt')
        visual  = 'balanced'
    }
    minimal = @{
        disable = @('DiagTrack','dmwappushservice','SysMain','WSearch','Fax','XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc','MapsBroker','lfsvc','RetailDemo','wisvc','TabletInputService','PhoneSvc','ScardSvr','ScDeviceEnum','SCPolicySvc')
        enable  = @()
        visual  = 'best-performance'
    }
}

$p = $Profiles[$Profile]
if (-not $p) { Write-Warn "Unknown profile '$Profile' - using productivity"; $p = $Profiles['productivity'] }

foreach ($svc in $p.disable) {
    try {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Ok "Disabled service: $svc"
    } catch { Write-Warn "Could not disable $svc" }
}

foreach ($svc in $p.enable) {
    try {
        Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name $svc -ErrorAction SilentlyContinue
        Write-Ok "Enabled service: $svc"
    } catch { }
}

try {
    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    switch ($p.visual) {
        'best-performance' { Set-ItemProperty -Path $path -Name 'VisualFXSetting' -Value 2 -Type DWord -Force }
        'performance'      { Set-ItemProperty -Path $path -Name 'VisualFXSetting' -Value 2 -Type DWord -Force }
        'balanced'         { Set-ItemProperty -Path $path -Name 'VisualFXSetting' -Value 0 -Type DWord -Force }
    }
    Write-Ok "Visual effects: $($p.visual)"
} catch { }

try {
    $hp = (powercfg /list | Select-String 'High performance' | Select-Object -First 1)
    if ($hp -match '([a-fA-F0-9-]{36})') {
        powercfg /setactive $Matches[1] 2>&1 | Out-Null
        Write-Ok 'Power plan: High Performance'
    }
} catch { }

powercfg /change standby-timeout-ac 0 2>&1 | Out-Null
powercfg /change monitor-timeout-ac 15 2>&1 | Out-Null
powercfg /change hibernate-timeout-ac 0 2>&1 | Out-Null
Write-Ok 'Sleep/standby disabled (AC)'

if ($Profile -eq 'gaming' -or $Profile -eq 'minimal') {
    try {
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
        Write-Ok 'Defender real-time disabled'
    } catch { Write-Warn 'Could not disable Defender (may need Tamper Protection off)' }
}

$telemetryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
if (-not (Test-Path $telemetryPath)) { New-Item -Path $telemetryPath -Force | Out-Null }
Set-ItemProperty -Path $telemetryPath -Name 'AllowTelemetry' -Value 0 -Type DWord -Force
Write-Ok 'Telemetry set to 0 (Security-only)'

$advPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-ItemProperty -Path $advPath -Name 'HideFileExt' -Value 0 -Type DWord -Force
Set-ItemProperty -Path $advPath -Name 'Hidden'    -Value 1 -Type DWord -Force
Write-Ok 'File extensions + hidden files visible'

if ($env:TZ) {
    try { Set-TimeZone -Id $env:TZ -ErrorAction SilentlyContinue } catch { }
}

try {
    $uacPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    Set-ItemProperty -Path $uacPath -Name 'ConsentPromptBehaviorAdmin' -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $uacPath -Name 'EnableLUA' -Value 1 -Type DWord -Force
    Write-Ok 'UAC prompt auto-elevate (no prompts)'
} catch { }

Write-Ok "Optimization ($Profile) complete"
