#Requires -Version 5.1
<#
.SYNOPSIS
    Adds Windows Firewall rules to allow inbound RDP (TCP 3389 + UDP 3389)
    and outbound tunnel traffic (SSH 22, HTTPS 443, cloudflared).
.DESCRIPTION
    Creates the following firewall rules (all reversible via -Remove):
      * "GitHubRDPToolkit-RDP-In-TCP"   — inbound TCP 3389
      * "GitHubRDPToolkit-RDP-In-UDP"   — inbound UDP 3389
      * "GitHubRDPToolkit-Tunnel-SSH"   — outbound TCP 22 (Serveo/localhost.run)
      * "GitHubRDPToolkit-Tunnel-HTTPS" — outbound TCP 443 (Cloudflare API)
      * "GitHubRDPToolkit-Cloudflared"  — outbound UDP 7844 / TCP 7844 (QUIC)
.PARAMETER Remove
    Remove the rules previously created by this script.
.PARAMETER Profile
    Profile(s) to apply rules to: Domain, Private, Public, Any.
    Default: Domain,Private
.PARAMETER LocalRdpPort
    Local RDP port to allow inbound. Default: 3389
.EXAMPLE
    .\rdp-firewall-rules.ps1
    Creates the firewall rules on Domain + Private profiles.
.EXAMPLE
    .\rdp-firewall-rules.ps1 -Profile Any -LocalRdpPort 3390
    Allow RDP on port 3390 across all profiles.
.EXAMPLE
    .\rdp-firewall-rules.ps1 -Remove
    Removes all rules created by this script.
#>
[CmdletBinding()]
param(
    [switch]$Remove,
    [ValidateSet('Domain','Private','Public','Any')]
    [string[]]$Profile = @('Domain','Private'),
    [int]$LocalRdpPort = 3389
)

$ErrorActionPreference = 'Stop'

$RulePrefix = 'GitHubRDPToolkit'

function Write-Step  { param([string]$m) Write-Host "[fw]      $m" -ForegroundColor Cyan }
function Write-OK    { param([string]$m) Write-Host "[ok]      $m" -ForegroundColor Green }
function Write-Warn2 { param([string]$m) Write-Host "[warn]    $m" -ForegroundColor Yellow }
function Write-Err2  { param([string]$m) Write-Host "[error]   $m" -ForegroundColor Red }

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
    $argsList = @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`"")
    if ($Remove) { $argsList += '-Remove' }
    $argsList += '-Profile'; $argsList += ($Profile -join ',')
    $argsList += '-LocalRdpPort'; $argsList += "$LocalRdpPort"
    $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList $argsList
    exit $p.ExitCode
}

# ----------------------------------------------------------------------
# Build a profile string compatible with netsh / New-NetFirewallRule
# ----------------------------------------------------------------------
$profileStr = ($Profile -join ',')

if ($Remove) {
    Write-Step 'Removing GitHub RDP Mega Toolkit firewall rules...'
    $rules = Get-NetFirewallRule -DisplayName "$RulePrefix*" -ErrorAction SilentlyContinue
    if (-not $rules) {
        Write-Warn2 'No matching rules found to remove.'
        return
    }
    foreach ($r in $rules) {
        try {
            Remove-NetFirewallRule -Name $r.Name
            Write-OK "Removed: $($r.DisplayName)"
        } catch {
            Write-Warn2 "Failed to remove $($r.DisplayName): $($_.Exception.Message)"
        }
    }
    return
}

# ----------------------------------------------------------------------
# Rule definitions
# ----------------------------------------------------------------------
$rulesToCreate = @(
    @{
        Name        = "$RulePrefix-RDP-In-TCP"
        DisplayName = "$RulePrefix — RDP Inbound TCP $LocalRdpPort"
        Description = 'Allow inbound RDP over TCP for GitHub RDP Mega Toolkit.'
        Direction   = 'Inbound'
        Protocol    = 'TCP'
        LocalPort   = $LocalRdpPort
        Action      = 'Allow'
        Program     = 'System'
    },
    @{
        Name        = "$RulePrefix-RDP-In-UDP"
        DisplayName = "$RulePrefix — RDP Inbound UDP $LocalRdpPort"
        Description = 'Allow inbound RDP over UDP for GitHub RDP Mega Toolkit.'
        Direction   = 'Inbound'
        Protocol    = 'UDP'
        LocalPort   = $LocalRdpPort
        Action      = 'Allow'
        Program     = 'System'
    },
    @{
        Name        = "$RulePrefix-Tunnel-SSH"
        DisplayName = "$RulePrefix — Tunnel SSH Outbound 22"
        Description = 'Allow outbound SSH for Serveo/localhost.run tunnels.'
        Direction   = 'Outbound'
        Protocol    = 'TCP'
        RemotePort  = 22
        Action      = 'Allow'
        Program     = 'Any'
    },
    @{
        Name        = "$RulePrefix-Tunnel-HTTPS"
        DisplayName = "$RulePrefix — Tunnel HTTPS Outbound 443"
        Description = 'Allow outbound HTTPS for Cloudflare API + trycloudflare.com.'
        Direction   = 'Outbound'
        Protocol    = 'TCP'
        RemotePort  = 443
        Action      = 'Allow'
        Program     = 'Any'
    },
    @{
        Name        = "$RulePrefix-Cloudflared-QUIC-UDP"
        DisplayName = "$RulePrefix — Cloudflared QUIC Outbound UDP 7844"
        Description = 'Allow outbound QUIC for cloudflared.exe fallback tunnels.'
        Direction   = 'Outbound'
        Protocol    = 'UDP'
        RemotePort  = 7844
        Action      = 'Allow'
        Program     = 'Any'
    },
    @{
        Name        = "$RulePrefix-Cloudflared-QUIC-TCP"
        DisplayName = "$RulePrefix — Cloudflared QUIC Outbound TCP 7844"
        Description = 'Allow outbound QUIC (TCP fallback) for cloudflared.exe.'
        Direction   = 'Outbound'
        Protocol    = 'TCP'
        RemotePort  = 7844
        Action      = 'Allow'
        Program     = 'Any'
    }
)

# ----------------------------------------------------------------------
# Create / update rules
# ----------------------------------------------------------------------
foreach ($r in $rulesToCreate) {
    Write-Step "Creating rule: $($r.DisplayName)"
    $params = @{
        Name        = $r.Name
        DisplayName = $r.DisplayName
        Description = $r.Description
        Direction   = $r.Direction
        Action      = $r.Action
        Profile     = $profileStr
        Enabled     = 'True'
        ErrorAction = 'Stop'
    }
    if ($r.Protocol -eq 'TCP' -or $r.Protocol -eq 'UDP') {
        $params['Protocol'] = $r.Protocol
        if ($r.LocalPort)  { $params['LocalPort']  = $r.LocalPort }
        if ($r.RemotePort) { $params['RemotePort'] = $r.RemotePort }
    }
    if ($r.Program -and $r.Program -ne 'Any') { $params['Program'] = $r.Program }
    if ($r.Program -eq 'Any') { $params['Program'] = 'Any' }

    # Remove any pre-existing rule with the same name (idempotent)
    $existing = Get-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-NetFirewallRule -Name $r.Name
    }
    try {
        New-NetFirewallRule @params | Out-Null
        Write-OK "Created: $($r.DisplayName)"
    } catch {
        Write-Err2 "Failed: $($r.DisplayName) — $($_.Exception.Message)"
    }
}

Write-Host ''
Write-Host 'Firewall rule provisioning complete.' -ForegroundColor Green
Write-Host "To remove later: .\rdp-firewall-rules.ps1 -Remove" -ForegroundColor Yellow
