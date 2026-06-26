#Requires -Version 7.0
<#
    .SYNOPSIS
        Probes RDP port / TermService status / disk / memory and writes
        a JSON snapshot to health-status.json.

    .DESCRIPTION
        Output schema (health-status.json):

          {
            "timestamp":      ISO 8601,
            "rdp_port_open":  bool,
            "term_service":   "Running" | "Stopped" | ...,
            "disk":           { "free_gb": float, "total_gb": float, "free_pct": float },
            "memory":         { "free_pct": float, "free_gb": float, "total_gb": float },
            "public_ip":      string,
            "host":           string,
            "ok":             bool
          }
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/utils.ps1"

Write-Block 'health-check.ps1 — gathering diagnostics'

$ts = (Get-Date).ToString('o')

# --- RDP port (3389) probe (localhost) -----------------------------------
$rdpOpen = Test-Port -ComputerName '127.0.0.1' -Port 3389 -TimeoutMs 1500
Write-Info "RDP port 3389 on localhost: $(if ($rdpOpen) {'OPEN'} else {'CLOSED'})"

# --- TermService status -------------------------------------------------
$svc = Get-Service -Name 'TermService' -ErrorAction SilentlyContinue
$svcState = if ($svc) { $svc.Status.ToString() } else { 'missing' }
Write-Info "TermService: $svcState"

# --- Disk (system drive) ------------------------------------------------
$drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
if (-not $drive) {
    # Fallback: pick the first fixed local disk.
    $drive = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
        Select-Object -First 1
}
$disk = @{ free_gb = 0.0; total_gb = 0.0; free_pct = 0.0 }
if ($drive) {
    $totalGB = [math]::Round($drive.Size / 1GB, 2)
    $freeGB  = [math]::Round($drive.FreeSpace / 1GB, 2)
    $freePct = if ($drive.Size -gt 0) { [math]::Round(($drive.FreeSpace / $drive.Size) * 100, 1) } else { 0.0 }
    $disk = @{ free_gb = $freeGB; total_gb = $totalGB; free_pct = $freePct }
    Write-Info "Disk: $freeGB GB free of $totalGB GB ($freePct%)"
}

# --- Memory -------------------------------------------------------------
$mem = Get-CimInstance Win32_OperatingSystem
$totalMemGB = [math]::Round($mem.TotalVisibleMemorySize / 1MB, 2)
$freeMemGB  = [math]::Round($mem.FreePhysicalMemory / 1MB, 2)
$freeMemPct = if ($mem.TotalVisibleMemorySize -gt 0) {
    [math]::Round(($mem.FreePhysicalMemory / $mem.TotalVisibleMemorySize) * 100, 1)
} else { 0.0 }
Write-Info "Memory: $freeMemGB GB free of $totalMemGB GB ($freeMemPct%)"

# --- Public IP ----------------------------------------------------------
$pubIp = Get-PublicIp

# --- Tunnel state (best effort read of artifact files) ------------------
$dir = Get-ArtifactDir
$tunnelType = ''
$tunnelHost = ''
$tunnelTypePath = Join-Path $dir 'tunnel-type.txt'
$tunnelHostPath = Join-Path $dir 'tunnel-host.txt'
if (Test-Path $tunnelTypePath) { $tunnelType = (Get-Content $tunnelTypePath -Raw).Trim() }
if (Test-Path $tunnelHostPath) { $tunnelHost = (Get-Content $tunnelHostPath -Raw).Trim() }

# --- Overall health decision --------------------------------------------
$ok = $rdpOpen -and ($svcState -eq 'Running') -and ($disk.free_pct -gt 5) -and ($freeMemPct -gt 5)

$status = [ordered]@{
    timestamp      = $ts
    host           = $env:COMPUTERNAME
    public_ip      = $pubIp
    rdp_port_open  = $rdpOpen
    term_service   = $svcState
    disk           = $disk
    memory         = @{
        free_gb   = $freeMemGB
        total_gb  = $totalMemGB
        free_pct  = $freeMemPct
    }
    tunnel         = @{
        type = $tunnelType
        host = $tunnelHost
    }
    ok             = $ok
}

$outPath = Join-Path $dir 'health-status.json'
$status | ConvertTo-Json -Depth 5 | Set-Content -Path $outPath -Encoding UTF8
Write-Ok "Wrote $outPath"

if (-not $ok) {
    Write-Warn 'Health check FAILED — see JSON for details.'
    exit 2
}
Write-Ok 'Health check passed.'
exit 0
