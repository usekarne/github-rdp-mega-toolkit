#Requires -Version 7.0
<#
    .SYNOPSIS
        Rotates the local RDP user's password and updates the artifact
        files so the Python runner can pick up the new credential.

    .DESCRIPTION
        Generates a new 24-char complex password, updates the local user,
        rewrites rdp-password.txt / RDP_PASSWORD.txt, and pushes a notify
        ping.  Designed to be callable from a workflow_dispatch called
        'credential-rotate.yml' (the runner.py rotates via this script).
#>
[CmdletBinding()]
param(
    [string]$Username = 'runner'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/utils.ps1"

Write-Block "Rotating password for user '$Username'"

$user = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
if (-not $user) {
    Write-Err "User '$Username' does not exist."
    exit 1
}

$newPw = New-RandomPassword
$secure = $newPw | ConvertTo-SecureString -AsPlainText -Force
Set-LocalUser -Name $Username -Password $secure
Write-Ok 'Local user password updated.'

$dir = Get-ArtifactDir
$pwPath    = Join-Path $dir 'rdp-password.txt'
$pwEnvPath = Join-Path $dir 'RDP_PASSWORD.txt'
$ts        = (Get-Date).ToString('o')

Set-Content -Path $pwPath    -Value $newPw -NoNewline -Encoding UTF8
Set-Content -Path $pwEnvPath -Value $newPw -NoNewline -Encoding UTF8

# Append to a rotation history (so operator can audit changes).
$histPath = Join-Path $dir 'password-rotations.log'
"[$ts] password rotated for $Username" | Out-File -FilePath $histPath -Append -Encoding UTF8

# Update rdp-summary.json if it exists
$sumPath = Join-Path $dir 'rdp-summary.json'
if (Test-Path $sumPath) {
    try {
        $sum = Get-Content $sumPath -Raw | ConvertFrom-Json
        $sum | Add-Member -NotePropertyName password_rotated_at -NotePropertyValue $ts -Force
        $sum | ConvertTo-Json -Depth 4 | Set-Content -Path $sumPath -Encoding UTF8
    } catch {
        Write-Warn "Could not update rdp-summary.json: $($_.Exception.Message)"
    }
}

Write-Ok "Wrote $pwPath and $pwEnvPath"
Write-Info 'New password (will be visible in artifact):'
Write-Host $newPw -ForegroundColor Cyan

Send-Notify -Message "RDP password rotated for user '$Username'." -Title 'Password rotation' | Out-Null

Write-Block 'rotate-password.ps1 complete'
exit 0
