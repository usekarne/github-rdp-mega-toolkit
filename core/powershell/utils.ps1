# core/powershell/utils.ps1 - Shared helpers for GitHub RDP Mega Toolkit v9.0
# Dot-sourced by all other PowerShell scripts in this directory.
# NOTE: Do NOT use Export-ModuleMember here - it only works in .psm1 modules,
# not in dot-sourced .ps1 scripts (causes "can only be called from inside a module" error).

function Write-Block {
    param([string]$Title)
    $line = '+' + ('=' * 60) + '+'
    Write-Host ''
    Write-Host $line
    Write-Host "|  $Title"
    Write-Host $line
}

function Write-Info  { param([string]$Msg) Write-Host "[INFO] $Msg" }
function Write-Ok    { param([string]$Msg) Write-Host "[OK]   $Msg" }
function Write-Warn  { param([string]$Msg) Write-Host "[WARN] $Msg" }
function Write-Err   { param([string]$Msg) Write-Host "[ERR]  $Msg" }

function Test-Port {
    param([string]$Computer = 'localhost', [int]$Port = 3389, [int]$Timeout = 2000)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect($Computer, $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($Timeout, $false)
        if ($ok) { $tcp.EndConnect($iar); $tcp.Close(); return $true }
        return $false
    } catch { return $false }
}

function Get-PublicIp {
    try { return (Invoke-RestMethod -Uri 'https://api.ipify.org' -UseBasicParsing -TimeoutSec 10).Trim() }
    catch { try { return (Invoke-RestMethod -Uri 'https://ifconfig.me' -UseBasicParsing -TimeoutSec 10).Trim() } catch { return 'unknown' } }
}

function Invoke-EnsureComplexity {
    param([Parameter(Mandatory)][string]$Password)
    if ($Password -notmatch '[A-Z]') { $Password = 'A' + $Password }
    if ($Password -notmatch '[a-z]') { $Password = $Password + 'a' }
    if ($Password -notmatch '[0-9]') { $Password = '1' + $Password }
    if ($Password -notmatch '[^A-Za-z0-9]') { $Password = $Password + '!' }
    return $Password
}

function New-RandomPassword {
    param([int]$Length = 24)
    $chars = (48..57) + (65..90) + (97..122) + (33..33) + (35..38) + (42..43) + (45..46) + (63..64) + (95)
    $pwd = -join ($chars | Get-Random -Count $Length | ForEach-Object { [char]$_ })
    return Invoke-EnsureComplexity -Password $pwd
}

function Write-ArtifactFile {
    param([string]$Name, [string]$Value)
    "$Name=$Value" | Out-File -FilePath "$Name.txt" -Encoding ASCII -NoNewline
    Write-Host "[ARTIFACT] $Name=$Value"
}

function Send-Notify {
    param([string]$Title, [string]$Body)
    $channelsFile = Join-Path $PSScriptRoot '..\..\configs\notification-channels.json'
    if (-not (Test-Path $channelsFile)) { return }
    try {
        $cfg = Get-Content $channelsFile -Raw | ConvertFrom-Json
        if ($cfg.discord.enabled -and $cfg.discord.webhook_url) {
            $payload = @{ username = $cfg.discord.username; content = "**$Title**`n$Body" } | ConvertTo-Json -Depth 5
            Invoke-RestMethod -Uri $cfg.discord.webhook_url -Method Post -Body $payload -ContentType 'application/json' -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null
        }
        if ($cfg.telegram.enabled -and $cfg.telegram.bot_token -and $cfg.telegram.chat_id) {
            $uri = "https://api.telegram.org/bot$($cfg.telegram.bot_token)/sendMessage"
            $body = @{ chat_id = $cfg.telegram.chat_id; text = "*$Title*`n$Body"; parse_mode = 'Markdown' }
            Invoke-RestMethod -Uri $uri -Method Post -Body $body -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null
        }
        if ($cfg.slack.enabled -and $cfg.slack.webhook_url) {
            $payload = @{ text = "*$Title*`n$Body" } | ConvertTo-Json -Depth 5
            Invoke-RestMethod -Uri $cfg.slack.webhook_url -Method Post -Body $payload -ContentType 'application/json' -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {
        Write-Warn "Notify failed: $($_.Exception.Message)"
    }
}

function Get-SystemInfo {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    return [ordered]@{
        os_caption    = $os.Caption
        os_version    = $os.Version
        last_boot     = $os.LastBootUpTime
        total_mem_gb  = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
        free_mem_gb   = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        disk_free_gb  = [math]::Round((Get-PSDrive C -ErrorAction SilentlyContinue).Free / 1GB, 2)
        public_ip     = Get-PublicIp
    }
}

# Self-test when run directly (not dot-sourced)
if ($MyInvocation.InvocationName -eq '.') { return }
# If invoked directly, just print version info
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "utils.ps1 loaded - $(Get-Date)"
}
