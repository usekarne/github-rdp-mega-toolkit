# core/powershell/auto-config.ps1 - Auto-generate configs/*.json if missing
. "$PSScriptRoot\utils.ps1"

Write-Block "AUTO-CONFIG - generate missing config files"

$ConfigDir = Join-Path $PSScriptRoot '..\..\configs'
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

# Defaults file (the source of truth for auto-generation)
$defaultsFile = Join-Path $ConfigDir 'auto-generated-defaults.json'
if (-not (Test-Path $defaultsFile)) {
    # Write the defaults file itself if missing
    $defaults = @{
        version = '9.0.0'
        description = 'Default values used by auto-config.ps1 when other config files are missing'
        software_list_default = @(
            @{ id = 'Google.Chrome'; enabled = $true }
            @{ id = 'Mozilla.Firefox'; enabled = $true }
            @{ id = 'Microsoft.VisualStudioCode'; enabled = $true }
        )
        tunnel_providers_default = @('serveo','localhost.run','cloudflare')
        optimization_profile_default = 'productivity'
        session_hours_default = 6
        heartbeat_sec_default = 300
    }
    $defaults | ConvertTo-Json -Depth 5 | Out-File -FilePath $defaultsFile -Encoding utf8
    Write-Ok "Created $defaultsFile"
}

$defaults = Get-Content $defaultsFile -Raw | ConvertFrom-Json

# Check each required config and create if missing
$requiredConfigs = @(
    'software-list.json',
    'tunnel-providers.json',
    'notification-channels.json',
    'optimization-profiles.json',
    'session-profiles.json',
    'virtual-environments.json',
    'security-policies.json',
    'client-tools-config.json',
    'kali-tools.json',
    'android-termux-packages.json',
    'windows-features.json'
)

foreach ($cfgName in $requiredConfigs) {
    $cfgPath = Join-Path $ConfigDir $cfgName
    if (-not (Test-Path $cfgPath)) {
        Write-Warn "$cfgName missing - would auto-generate from defaults"
        # In v9.0, all configs are committed to the repo, so this is just a sanity check
        # If a config is missing, the workflow will fail with a clear error
    } else {
        Write-Ok "$cfgName present"
    }
}

Write-Ok 'Auto-config check complete'
