# core/powershell/rotate-password.ps1 - Rotate the runner password mid-session
. "$PSScriptRoot\utils.ps1"

$UserName = if ($env:RDP_USER) { $env:RDP_USER } else { 'runner' }
$NewPwd   = New-RandomPassword -Length 24

Write-Block "ROTATE PASSWORD - user=$UserName"

try {
    $sec = ConvertTo-SecureString $NewPwd -AsPlainText -Force
    Set-LocalUser -Name $UserName -Password $sec -ErrorAction Stop
    Write-Ok 'Password rotated'
} catch {
    Write-Err "Rotate failed: $($_.Exception.Message)"
    exit 1
}

$NewPwd | Out-File -FilePath 'rdp-password.txt' -Encoding ASCII -NoNewline
"RDP_PASSWORD=$NewPwd" | Out-File -FilePath 'RDP_PASSWORD.txt' -Encoding ASCII -NoNewline
Write-Host "[ARTIFACT] RDP_PASSWORD=$NewPwd"

# Rewrite connect-info.txt with new password (BRIDGE_CMD and CONNECT_CMD on separate lines)
$connectPath = 'connect-info.txt'
if (Test-Path $connectPath) {
    $content = Get-Content $connectPath -Raw
    $bridge = ''
    if ($content -match 'BRIDGE_CMD=([^\r\n]*)') { $bridge = $Matches[1] }
    $newConnect = if ($content -match 'CONNECT_CMD=([^\r\n]*)') {
        ($Matches[1] -replace "/p:'[^']*'", "/p:'$NewPwd'")
    } else {
        "xfreerdp /v:localhost:33890 /u:$UserName /p:'$NewPwd' /cert:ignore +clipboard +auto-reconnect /size:1280x720"
    }
    "BRIDGE_CMD=$bridge`r`nCONNECT_CMD=$newConnect" | Out-File -FilePath $connectPath -Encoding ASCII -NoNewline
}

"RDP_PASS=$NewPwd" | Out-File -Append -Encoding utf8 $env:GITHUB_ENV

Send-Notify -Title 'RDP Password Rotated' -Body "User: $UserName`nNew password: $NewPwd"

Write-Block "NEW PASSWORD"
Write-Host "|  $NewPwd"
Write-Host "+============================================================+"
