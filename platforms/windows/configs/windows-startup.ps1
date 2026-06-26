#Requires -Version 5.1
<#
.SYNOPSIS
    Auto-start script that registers a Scheduled Task to launch the
    Cloudflare tunnel bridge at Windows boot, ensuring tunnel
    persistence across reboots.
.DESCRIPTION
    Creates / updates a Scheduled Task named "GitHubRDPToolkit-Tunnel"
    that:
      * Runs at system startup (with highest privileges)
      * Launches tunnel-bridge-windows.ps1 (or a user-supplied command)
      * Restarts on failure (every 60s, up to 3 attempts)
      * Records status to the Windows Event Log (source: GitHubRDPToolkit)

    The script is idempotent — running it again updates the task.
.PARAMETER BridgeScript
    Path to the bridge script. Default:
    "$env:ProgramFiles\GitHubRDPToolkit\platforms\windows\scripts\tunnel-bridge-windows.ps1"
.PARAMETER TunnelType
    Which tunnel backend to use: serveo, localhostrun, cloudflare.
    Default: cloudflare (most reliable on Windows; uses cloudflared.exe).
.PARAMETER RdpPort
    Local RDP port to bridge. Default: 3389.
.PARAMETER Remove
    Remove the scheduled task instead of creating it.
.PARAMETER RunNow
    Also start the task immediately after creation.
.EXAMPLE
    .\windows-startup.ps1
    Registers the auto-start task with defaults.
.EXAMPLE
    .\windows-startup.ps1 -TunnelType serveo -RunNow
    Registers with Serveo backend and starts immediately.
.EXAMPLE
    .\windows-startup.ps1 -Remove
    Removes the scheduled task.
#>
[CmdletBinding()]
param(
    [string]$BridgeScript = (Join-Path $env:ProgramFiles 'GitHubRDPToolkit\platforms\windows\scripts\tunnel-bridge-windows.ps1'),
    [ValidateSet('serveo','localhostrun','cloudflare')]
    [string]$TunnelType = 'cloudflare',
    [int]$RdpPort = 3389,
    [switch]$Remove,
    [switch]$RunNow
)

$ErrorActionPreference = 'Stop'

$TaskName = 'GitHubRDPToolkit-Tunnel'
$EventSource = 'GitHubRDPToolkit'

function Write-Step  { param([string]$m) Write-Host "[startup] $m" -ForegroundColor Cyan }
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
    $argsList = @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`"","-TunnelType","$TunnelType","-RdpPort","$RdpPort","-BridgeScript","`"$BridgeScript`"")
    if ($Remove) { $argsList += '-Remove' }
    if ($RunNow) { $argsList += '-RunNow' }
    $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList $argsList
    exit $p.ExitCode
}

# ----------------------------------------------------------------------
# Ensure event log source exists
# ----------------------------------------------------------------------
if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    try {
        New-EventLog -Source $EventSource -LogName 'Application' -ErrorAction Stop
        Write-OK "Event log source '$EventSource' created."
    } catch {
        Write-Warn2 "Could not create event log source: $($_.Exception.Message)"
    }
}

function Write-Event {
    param([string]$Message, [string]$EntryType = 'Information', [int]$EventId = 100)
    try {
        Write-EventLog -LogName 'Application' -Source $EventSource -EventId $EventId -EntryType $EntryType -Message $Message -ErrorAction SilentlyContinue
    } catch { }
}

# ----------------------------------------------------------------------
# Remove mode
# ----------------------------------------------------------------------
if ($Remove) {
    Write-Step "Removing scheduled task: $TaskName"
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Warn2 "Scheduled task not found: $TaskName"
        return
    }
    try {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-OK "Scheduled task removed: $TaskName"
        Write-Event -Message "Auto-start tunnel task '$TaskName' removed by $env:USERNAME" -EntryType Information -EventId 200
    } catch {
        Write-Err2 "Failed to remove task: $($_.Exception.Message)"
        exit 1
    }
    return
}

# ----------------------------------------------------------------------
# Validate bridge script exists
# ----------------------------------------------------------------------
if (-not (Test-Path $BridgeScript)) {
    Write-Err2 "Bridge script not found: $BridgeScript"
    Write-Err2 "Install the toolkit first via install.ps1, or pass -BridgeScript <path>."
    exit 1
}

# ----------------------------------------------------------------------
# Build the action (PowerShell bridge launcher)
# ----------------------------------------------------------------------
$bridgeArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$BridgeScript`" -TunnelType $TunnelType -RdpPort $RdpPort -Persistent"
$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument $bridgeArgs `
    -WorkingDirectory (Split-Path -Parent $BridgeScript)

# ----------------------------------------------------------------------
# Trigger: at system startup
# ----------------------------------------------------------------------
$trigger = New-ScheduledTaskTrigger -AtStartup -RandomDelay (New-TimeSpan -Seconds 30)

# ----------------------------------------------------------------------
# Settings: restart on failure, run as soon as possible after missed,
#           don't stop on idle, allow hard terminate.
# ----------------------------------------------------------------------
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
    -DontStopOnIdleEnd `
    -RunOnlyIfNetworkAvailable

# ----------------------------------------------------------------------
# Principal: SYSTEM, highest privileges
# ----------------------------------------------------------------------
$principal = New-ScheduledTaskPrincipal `
    -UserId 'SYSTEM' `
    -LogonType ServiceAccount `
    -RunLevel Highest

# ----------------------------------------------------------------------
# Register (or update) the task
# ----------------------------------------------------------------------
Write-Step "Registering scheduled task: $TaskName"
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
try {
    if ($existing) {
        Set-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
        Write-OK "Scheduled task updated: $TaskName"
    } else {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Auto-start the GitHub RDP Mega Toolkit tunnel bridge at boot.' -Force | Out-Null
        Write-OK "Scheduled task created: $TaskName"
    }
} catch {
    Write-Err2 "Failed to register scheduled task: $($_.Exception.Message)"
    exit 1
}

# ----------------------------------------------------------------------
# Optional: run now
# ----------------------------------------------------------------------
if ($RunNow) {
    Write-Step 'Starting the task now...'
    try {
        Start-ScheduledTask -TaskName $TaskName
        Start-Sleep -Seconds 2
        $info = Get-ScheduledTaskInfo -TaskName $TaskName
        Write-OK "Task last run result: $($info.LastTaskResult)"
    } catch {
        Write-Warn2 "Could not start task immediately: $($_.Exception.Message)"
    }
}

Write-Event -Message "Auto-start tunnel task '$TaskName' registered by $env:USERNAME. Tunnel: $TunnelType, RDP port: $RdpPort" -EntryType Information -EventId 100

Write-Host ''
Write-Host 'Auto-start tunnel task configured.' -ForegroundColor Green
Write-Host "  Task name   : $TaskName" -ForegroundColor White
Write-Host "  Bridge      : $BridgeScript" -ForegroundColor White
Write-Host "  Tunnel type : $TunnelType" -ForegroundColor White
Write-Host "  RDP port    : $RdpPort" -ForegroundColor White
Write-Host ''
Write-Host "To remove later: .\windows-startup.ps1 -Remove" -ForegroundColor Yellow
Write-Host "To view task  : Get-ScheduledTask -TaskName '$TaskName' | Get-ScheduledTaskInfo" -ForegroundColor Yellow
