# core/powershell/setup-rdp.ps1 - Configure Windows RDP server (port 3389, user 'runner', firewall)
. "$PSScriptRoot\utils.ps1"

$UserName = if ($env:RDP_USER) { $env:RDP_USER } else { 'runner' }
$Password = if ($env:RDP_MASTER_PASSWORD) { $env:RDP_MASTER_PASSWORD } else { New-RandomPassword -Length 24 }
$Password = Invoke-EnsureComplexity -Password $Password

Write-Block "SETUP RDP - user=$UserName"

# 1. Enable RDP in registry
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Type DWord -Force
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 0 -Type DWord -Force
Write-Ok 'RDP enabled in registry'

# 2. Create or update local user
$existing = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
if (-not $existing) {
    $sec = ConvertTo-SecureString $Password -AsPlainText -Force
    New-LocalUser -Name $UserName -Password $sec -PasswordNeverExpires -FullName 'RDP Runner' -Description 'Auto-created by GitHub RDP Mega Toolkit v9.0' | Out-Null
    Write-Ok "User '$UserName' created"
} else {
    $sec = ConvertTo-SecureString $Password -AsPlainText -Force
    Set-LocalUser -Name $UserName -Password $sec
    Write-Ok "User '$UserName' password updated"
}

# 3. Add to Administrators + Remote Desktop Users groups
Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $UserName -ErrorAction SilentlyContinue
Add-LocalGroupMember -SID 'S-1-5-32-555' -Member $UserName -ErrorAction SilentlyContinue
Write-Ok "User '$UserName' added to Admins + RDP groups"

# 4. Firewall rules
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName 'RDP-3389-In-TCP' -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName 'RDP-3389-In-UDP' -Direction Inbound -Protocol UDP -LocalPort 3389 -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
Write-Ok 'Firewall rules added'

# 5. Start Terminal Services
Set-Service -Name 'TermService' -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name 'TermService' -ErrorAction SilentlyContinue
Write-Ok 'TermService started'

# 6. Wait for port 3389
$ready = $false
for ($i = 0; $i -lt 15; $i++) {
    if (Test-Port -Port 3389) { $ready = $true; break }
    Start-Sleep -Seconds 2
}
if ($ready) { Write-Ok 'Port 3389 listening' }
else        { Write-Warn 'Port 3389 not listening after 30s (continuing anyway)' }

# 7. Save credentials to artifact files (all -Encoding ASCII -NoNewline)
$Password | Out-File -FilePath 'rdp-password.txt' -Encoding ASCII -NoNewline
"RDP_USERNAME=$UserName" | Out-File -FilePath 'RDP_USERNAME.txt' -Encoding ASCII -NoNewline
"RDP_PASSWORD=$Password" | Out-File -FilePath 'RDP_PASSWORD.txt' -Encoding ASCII -NoNewline
Write-Host "[ARTIFACT] RDP_USERNAME=$UserName"
Write-Host "[ARTIFACT] RDP_PASSWORD=$Password"

# 8. Expose to env
"RDP_USER=$UserName" | Out-File -Append -Encoding utf8 $env:GITHUB_ENV
"RDP_PASS=$Password" | Out-File -Append -Encoding utf8 $env:GITHUB_ENV

Write-Ok 'RDP setup complete'
