#Requires -Version 7.0
<#
    .SYNOPSIS
        Enables RDP on Windows, creates the 'runner' user, opens firewall,
        starts TermService, and persists credentials as artifact files.

    .PARAMETER Username
        Local user to create (default: 'runner').

    .PARAMETER Password
        Override the password (defaults to $env:RDP_MASTER_PASSWORD,
        then to a freshly generated one).

    .NOTES
        Must be run as Administrator.  Tested on Windows Server 2019/2022
        and Windows 10/11 Pro.
#>
[CmdletBinding()]
param(
    [string]$Username = 'runner',
    [string]$Password
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/utils.ps1"

function Set-RegistryDWord {
    [CmdletBinding()]
    param([string]$Path, [string]$Name, [int]$Value)
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord
}

function New-LocalAdmin {
    [CmdletBinding()]
    param([string]$User, [string]$Pw)
    # Remove pre-existing user with the same name to keep idempotent.
    $existing = Get-LocalUser -Name $User -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Warn "User '$User' already exists — resetting password."
        Set-LocalUser -Name $User -Password ($Pw | ConvertTo-SecureString -AsPlainText -Force)
    } else {
        $secure = $Pw | ConvertTo-SecureString -AsPlainText -Force
        New-LocalUser -Name $User -Password $secure `
            -FullName 'RDP Runner' -Description 'GitHub Actions RDP runner' `
            -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
    }
    # Add to Administrators
    Add-LocalGroupMember -Group 'Administrators' -Member $User -ErrorAction SilentlyContinue
    # Add to Remote Desktop Users (and fall back to legacy group name).
    $rdpGroup = 'Remote Desktop Users'
    if (-not (Get-LocalGroup -Name $rdpGroup -ErrorAction SilentlyContinue)) {
        $rdpGroup = 'Remote Desktop Users'  # universal
    }
    Add-LocalGroupMember -Group $rdpGroup -Member $User -ErrorAction SilentlyContinue
}

Write-Block 'Enabling Remote Desktop (registry)'

# HKLM:\System\CurrentControlSet\Control\Terminal Server\fDenyTSConnections = 0
$tsKey = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
Set-RegistryDWord -Path $tsKey -Name 'fDenyTSConnections' -Value 0
# Allow connections from computers running any version of RDP (less secure,
# but required by many mobile clients / xfreerdp builds).
$winStations = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
if (Test-Path $winStations) {
    Set-RegistryDWord -Path $winStations -Name 'UserAuthentication' -Value 0
}
Write-Ok 'RDP enabled in registry (fDenyTSConnections=0, UserAuthentication=0)'

Write-Block "Creating local user '$Username'"

if (-not $Password) {
    $Password = $env:RDP_MASTER_PASSWORD
}
if (-not $Password) {
    Write-Warn 'RDP_MASTER_PASSWORD env not set — generating a strong password.'
    $Password = New-RandomPassword
}
New-LocalAdmin -User $Username -Pw $Password
Write-Ok "User '$Username' created and added to Administrators + Remote Desktop Users"

Write-Block 'Configuring Windows Firewall (TCP+UDP 3389)'
$fwRules = @(
    @{ Name = 'RDP-Mega-Toolkit-TCP-In';  Protocol = 'TCP'; LocalPort = 3389 },
    @{ Name = 'RDP-Mega-Toolkit-UDP-In';  Protocol = 'UDP'; LocalPort = 3389 }
)
foreach ($r in $fwRules) {
    if (Get-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue) {
        Remove-NetFirewallRule -Name $r.Name
    }
    New-NetFirewallRule `
        -Name $r.Name `
        -DisplayName $r.Name `
        -Direction Inbound `
        -Action Allow `
        -Protocol $r.Protocol `
        -LocalPort $r.LocalPort `
        -Profile Any | Out-Null
    Write-Ok "Firewall rule $($r.Name) -> $($r.Protocol) $($r.LocalPort)"
}

Write-Block 'Starting TermService'
$svc = Get-Service -Name 'TermService' -ErrorAction SilentlyContinue
if ($null -eq $svc) {
    Write-Err 'TermService not present on this Windows edition (Home?)'
    throw 'TermService missing'
}
if ($svc.StartType -eq 'Disabled') {
    Set-Service -Name 'TermService' -StartupType Automatic
}
if ($svc.Status -ne 'Running') {
    Start-Service -Name 'TermService'
}
$svc = Get-Service -Name 'TermService'
Write-Ok "TermService status: $($svc.Status) (start type: $($svc.StartType))"

Write-Block 'Persisting credentials to artifact dir'
$dir = Get-ArtifactDir

# Plaintext — used by GitHub Actions artifact only. Caller should treat
# the artifact as a secret.
$pwPath     = Join-Path $dir 'rdp-password.txt'
$unPath     = Join-Path $dir 'RDP_USERNAME.txt'
$pwEnvPath  = Join-Path $dir 'RDP_PASSWORD.txt'

Set-Content -Path $pwPath    -Value $Password -NoNewline -Encoding UTF8
Set-Content -Path $unPath    -Value $Username -NoNewline -Encoding UTF8
Set-Content -Path $pwEnvPath -Value $Password -NoNewline -Encoding UTF8

Write-Ok "Wrote $pwPath, $unPath, $pwEnvPath"

# Also surface a small JSON sidecar for tooling that prefers structured data.
$summary = @{
    username   = $Username
    port       = 3389
    public_ip  = Get-PublicIp
    created_at = (Get-Date).ToString('o')
    host       = $env:COMPUTERNAME
}
$summaryPath = Join-Path $dir 'rdp-summary.json'
$summary | ConvertTo-Json -Depth 4 | Set-Content -Path $summaryPath -Encoding UTF8
Write-Ok "Wrote $summaryPath"

# Push notification (best effort)
Send-Notify -Message "RDP setup complete on $env:COMPUTERNAME — user '$Username', port 3389" -Title 'RDP setup complete' | Out-Null

Write-Block 'setup-rdp.ps1 complete'
exit 0
