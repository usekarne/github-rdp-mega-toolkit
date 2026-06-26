# core/powershell/health-check.ps1 - Probe RDP/tunnel health, write status to artifact
. "$PSScriptRoot\utils.ps1"

Write-Block "HEALTH CHECK"

$rdpPort     = Test-Port -Port 3389
$rdpService  = (Get-Service -Name 'TermService' -ErrorAction SilentlyContinue).Status
$publicIp    = Get-PublicIp
$tunnelType  = if ($env:TUNNEL_TYPE) { $env:TUNNEL_TYPE } else { 'unknown' }
$tunnelUrl   = if ($env:TUNNEL_URL)  { $env:TUNNEL_URL }  else { 'unknown' }
$diskFree    = (Get-PSDrive C -ErrorAction SilentlyContinue).Free / 1GB
$memFree     = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).FreePhysicalMemory / 1MB
$uptime      = (Get-Date) - (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime

$status = [ordered]@{
    timestamp     = (Get-Date).ToString('o')
    rdp_port_3389 = $rdpPort
    rdp_service   = $rdpService
    tunnel_type   = $tunnelType
    tunnel_url    = $tunnelUrl
    public_ip     = $publicIp
    disk_free_gb  = [math]::Round($diskFree, 2)
    mem_free_gb   = [math]::Round($memFree, 2)
    uptime_hrs    = [math]::Round($uptime.TotalHours, 2)
}

$status.GetEnumerator() | ForEach-Object { Write-Host "  $($_.Key): $($_.Value)" }

$status | ConvertTo-Json -Depth 3 | Out-File -FilePath 'health-status.json' -Encoding ASCII

Write-Ok 'Health check complete'
