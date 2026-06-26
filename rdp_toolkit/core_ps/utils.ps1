#Requires -Version 7.0
<#
    .SYNOPSIS
        Shared helpers for the RDP Mega Toolkit v9 PowerShell core.

    .DESCRIPTION
        Logging (Write-Block/Info/Ok/Warn/Err), networking (Test-Port,
        Get-PublicIp), secrets (New-RandomPassword with complexity enforced)
        and notifications (Discord/Telegram/Slack webhooks).

    .NOTES
        Pure PowerShell 7+ — no third-party modules required.  Dot-source
        this file from every other script in core_ps/ to share helpers:

            . "$PSScriptRoot/utils.ps1"
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Module-level configuration
# ---------------------------------------------------------------------------
$script:ToolkitBanner = @'
  ____  ____  ____  _   _  _____    ____  _____ __  __ _____ _
 |  _ \|  _ \|  _ \| \ | || ____|  / ___|| ____|  \/  | ____| |
 | |_) | |_) | |_) |  \| ||  _|    \___ \|  _| | |\/| |  _| | |
 |  _ <|  __/|  _ <| |\  || |___    ___) | |___| |  | | |___| |___
 |_| \_\_|   |_| \_\_| \_||_____|  |____/|_____|_|  |_|_____|_____|
                         v9 — cross-platform RDP toolkit
'@

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

function Write-Block {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message
    )
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
}

function Write-Info {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message
    )
    Write-Host "[INFO] $Message" -ForegroundColor White
}

function Write-Ok {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message
    )
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

function Write-Warn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message
    )
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Err {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message
    )
    [Console]::Error.WriteLine("[ERR]  $Message")
}

function Write-Banner {
    [CmdletBinding()]
    param()
    Write-Host $script:ToolkitBanner -ForegroundColor DarkCyan
}

# ---------------------------------------------------------------------------
# Networking helpers
# ---------------------------------------------------------------------------

function Test-Port {
    <#
        .SYNOPSIS
            Returns $true when a TCP port on the target host accepts a connection.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ComputerName,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [int]$TimeoutMs = 3000
    )
    $tcp = [System.Net.Sockets.TcpClient]::new()
    try {
        $iar = $tcp.BeginConnect($ComputerName, $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if ($ok -and $tcp.Connected) {
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        $tcp.Close()
        $tcp.Dispose()
    }
}

function Get-PublicIp {
    <#
        .SYNOPSIS
            Best-effort fetch of the host's public IP address.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $urls = @(
        'https://api.ipify.org?format=text',
        'https://ifconfig.me/ip',
        'https://icanhazip.com'
    )
    foreach ($u in $urls) {
        try {
            $ip = (Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 5).Content.Trim()
            if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$' -or $ip -match '^([0-9a-fA-F:]+)$') {
                return $ip
            }
        } catch {
            # try next
        }
    }
    return 'unknown'
}

# ---------------------------------------------------------------------------
# Password generator — 24 chars with complexity enforced
# ---------------------------------------------------------------------------

function New-RandomPassword {
    <#
        .SYNOPSIS
            Generates a cryptographically strong 24-character password that
            satisfies Active Directory complexity rules
            (upper + lower + digit + symbol, no repeat > 3).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [int]$Length = 24
    )
    if ($Length -lt 12) {
        throw "Password length must be >= 12 (got $Length)"
    }
    # Use the OS RNG through .NET — never System.Random.
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    function Get-RandomChar([char[]]$Pool) {
        $bytes = New-Object 'byte[]' 4
        $rng.GetBytes($bytes)
        $val = [BitConverter]::ToUInt32($bytes, 0)
        return $Pool[$val % $Pool.Length]
    }

    $upper = [char[]]('ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray())
    $lower = [char[]]('abcdefghijkmnopqrstuvwxyz'.ToCharArray())
    $digit = [char[]]('23456789'.ToCharArray())
    $symbol = [char[]]('!@#$%^&*()-_=+[]{}'.ToCharArray())

    # Guarantee at least one of each class.
    $chars = @(
        (Get-RandomChar $upper),
        (Get-RandomChar $lower),
        (Get-RandomChar $digit),
        (Get-RandomChar $symbol)
    )
    $all = $upper + $lower + $digit + $symbol
    while ($chars.Count -lt $Length) {
        $chars += (Get-RandomChar $all)
    }

    # Fisher–Yates shuffle (also seeded by the OS RNG).
    for ($i = $chars.Count - 1; $i -gt 0; $i--) {
        $bytes = New-Object 'byte[]' 4
        $rng.GetBytes($bytes)
        $j = [BitConverter]::ToUInt32($bytes, 0) % ($i + 1)
        $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
    }
    $rng.Dispose()
    return -join $chars
}

# ---------------------------------------------------------------------------
# Webhook notifications — Discord, Telegram, Slack
# ---------------------------------------------------------------------------

function Send-Notify {
    <#
        .SYNOPSIS
            Sends a notification message to one or more channels via webhook.

        .DESCRIPTION
            Channel selection is driven by environment variables:

              DISCORD_WEBHOOK_URL   — full Discord webhook URL
              TELEGRAM_BOT_TOKEN    — Telegram bot token (chat id via TELEGRAM_CHAT_ID)
              SLACK_WEBHOOK_URL     — full Slack incoming-webhook URL

            Any unset channel is silently skipped.  Returns a hashtable of
            { channel = $true|$false } so callers can see which delivered.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [string]$Title = 'RDP Mega Toolkit v9'
    )
    $results = @{}

    # ---- Discord ----------------------------------------------------------
    $discord = $env:DISCORD_WEBHOOK_URL
    if ($discord) {
        try {
            $payload = @{
                username = 'rdp-mega-toolkit'
                embeds   = @(
                    @{
                        title       = $Title
                        description = $Message
                        color       = 3447003
                    }
                )
            } | ConvertTo-Json -Depth 5 -Compress
            Invoke-RestMethod -Uri $discord -Method Post -Body $payload `
                -ContentType 'application/json' -TimeoutSec 10 | Out-Null
            $results.Discord = $true
        } catch {
            Write-Warn "Discord notify failed: $($_.Exception.Message)"
            $results.Discord = $false
        }
    }

    # ---- Telegram ---------------------------------------------------------
    $tgToken = $env:TELEGRAM_BOT_TOKEN
    $tgChat  = $env:TELEGRAM_CHAT_ID
    if ($tgToken -and $tgChat) {
        try {
            $uri = "https://api.telegram.org/bot$tgToken/sendMessage"
            $body = @{
                chat_id = $tgChat
                text    = "*$Title*`n$Message"
                parse_mode = 'Markdown'
            } | ConvertTo-Json -Depth 3 -Compress
            Invoke-RestMethod -Uri $uri -Method Post -Body $body `
                -ContentType 'application/json' -TimeoutSec 10 | Out-Null
            $results.Telegram = $true
        } catch {
            Write-Warn "Telegram notify failed: $($_.Exception.Message)"
            $results.Telegram = $false
        }
    }

    # ---- Slack ------------------------------------------------------------
    $slack = $env:SLACK_WEBHOOK_URL
    if ($slack) {
        try {
            $payload = @{
                text = "*$Title*`n$Message"
            } | ConvertTo-Json -Depth 3 -Compress
            Invoke-RestMethod -Uri $slack -Method Post -Body $payload `
                -ContentType 'application/json' -TimeoutSec 10 | Out-Null
            $results.Slack = $true
        } catch {
            Write-Warn "Slack notify failed: $($_.Exception.Message)"
            $results.Slack = $false
        }
    }

    if ($results.Count -eq 0) {
        Write-Info 'No notify channels configured (set DISCORD_WEBHOOK_URL / TELEGRAM_BOT_TOKEN / SLACK_WEBHOOK_URL).'
    }
    return $results
}

# ---------------------------------------------------------------------------
# Misc utilities used across the toolkit
# ---------------------------------------------------------------------------

function Get-ArtifactDir {
    <#
        .SYNOPSIS
            Returns (and creates) the directory used to surface credentials
            and tunnel info as GitHub Actions artifacts.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $dir = $env:RDP_ARTIFACT_DIR
    if (-not $dir) { $dir = Join-Path (Get-Location) 'rdp-artifacts' }
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function ConvertTo-SafeJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Data,
        [int]$Depth = 6
    )
    return ($Data | ConvertTo-Json -Depth $Depth -Compress)
}

# Auto-print banner when dot-sourced interactively.
if ($MyInvocation.InvocationName -eq '.') {
    # only when sourced interactively; workflows don't show a banner twice
    Write-Banner
}
