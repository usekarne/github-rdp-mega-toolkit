# core/powershell/cleanup.ps1 - Teardown RDP, kill tunnels, remove user
. "$PSScriptRoot\utils.ps1"

Write-Block "CLEANUP"

Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Stop-Service -Name 'TermService' -Force -ErrorAction SilentlyContinue
Write-Ok 'TermService stopped'

$UserName = if ($env:RDP_USER) { $env:RDP_USER } else { 'runner' }
Remove-LocalUser -Name $UserName -ErrorAction SilentlyContinue
Write-Ok "User '$UserName' removed"

Get-Process -Name 'ngrok','cloudflared','ssh','bore','lt' -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item 'ngrok.exe','cloudflared.exe' -Force -ErrorAction SilentlyContinue
Write-Ok 'Tunnel processes killed'

Remove-NetFirewallRule -DisplayName 'RDP-3389-In-TCP' -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName 'RDP-3389-In-UDP' -ErrorAction SilentlyContinue
Write-Ok 'Firewall rules removed'

Send-Notify -Title 'RDP Session Ended' -Body "Cleanup complete on runner."

Write-Ok 'Cleanup done.'
