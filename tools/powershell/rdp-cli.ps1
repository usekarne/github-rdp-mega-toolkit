# tools/powershell/rdp-cli.ps1 - PowerShell CLI for GitHub RDP Mega Toolkit v9.0 (Windows client)
#Requires -Version 5.1
param(
    [string]$Repo = $(if ($env:GH_REPO) { $env:GH_REPO } else { 'usekarne/github-rdp-mega-toolkit' }),
    [string]$Pat  = $(if ($env:GH_PAT)  { $env:GH_PAT }  else { (Read-Host 'Enter GH_PAT') }),
    [Parameter(Position=0)][string]$Command = 'help',
    [Parameter(Position=1)][string]$Arg1,
    [Parameter(Position=2)][string]$Arg2
)

$H = @{ Authorization = "bearer $Pat"; Accept = 'application/vnd.github+json' }

function Invoke-GH([string]$Method, [string]$Path, [object]$Body = $null) {
    $uri = "https://api.github.com/repos/$Repo/$Path"
    if ($Body) {
        Invoke-RestMethod -Uri $uri -Method $Method -Headers $H -ContentType 'application/json' -Body ($Body | ConvertTo-Json) -TimeoutSec 30
    } else {
        Invoke-RestMethod -Uri $uri -Method $Method -Headers $H -TimeoutSec 30
    }
}

switch ($Command.ToLower()) {
    'trigger' {
        $wf = if ($Arg1) { $Arg1 } else { 'lite-rdp.yml' }
        Write-Host "Triggering $wf on $Repo..."
        try {
            Invoke-GH -Method POST -Path "actions/workflows/$wf/dispatches" -Body @{ ref = 'main' } | Out-Null
            Write-Host "OK - dispatched"
        } catch { Write-Host "ERR: $($_.Exception.Message)" }
    }
    'status' {
        Write-Host "=== Active runs ==="
        foreach ($s in @('in_progress','queued','waiting')) {
            $r = Invoke-GH -Method GET -Path "actions/runs?status=$s&per_page=20"
            foreach ($run in $r.workflow_runs) {
                "{0}  {1,-35}  {2,-15}  {3}" -f $run.id, $run.name, $run.status, ($run.conclusion ?? '-')
            }
        }
    }
    'runs' {
        $n = if ($Arg1) { [int]$Arg1 } else { 10 }
        $r = Invoke-GH -Method GET -Path "actions/runs?per_page=$n"
        foreach ($run in $r.workflow_runs) {
            "{0}  {1,-35}  {2,-15}  {3}  {4}" -f $run.id, $run.name, $run.status, ($run.conclusion ?? '-'), $run.created_at
        }
    }
    'fetch' {
        $scriptPath = Join-Path $PSScriptRoot '..\python\fetch-creds.py'
        $pyArgs = @()
        if ($Arg1) { $pyArgs += @('--run-id', $Arg1) }
        $pyArgs += @('--connect')
        & python $scriptPath @pyArgs
    }
    'kill' {
        Write-Host "Cancelling all in-progress runs..."
        foreach ($s in @('in_progress','queued','waiting')) {
            $r = Invoke-GH -Method GET -Path "actions/runs?status=$s&per_page=100"
            foreach ($run in $r.workflow_runs) {
                try {
                    Invoke-GH -Method POST -Path "actions/runs/$($run.id)/cancel" | Out-Null
                    Write-Host "  cancelled $($run.id)"
                } catch { Write-Host "  failed $($run.id): $($_.Exception.Message)" }
            }
        }
    }
    'watch' {
        $scriptPath = Join-Path $PSScriptRoot '..\python\fetch-creds.py'
        & python $scriptPath --watch --connect
    }
    default {
        Write-Host "GitHub RDP Mega Toolkit v9.0 - PowerShell CLI"
        Write-Host ""
        Write-Host "Usage:  .\rdp-cli.ps1 <command> [arg1] [arg2]"
        Write-Host ""
        Write-Host "Commands:"
        Write-Host "  trigger [workflow]   Trigger a workflow (default: lite-rdp.yml)"
        Write-Host "  status               Show active runs"
        Write-Host "  runs [N]             Show last N runs (default 10)"
        Write-Host "  fetch [run-id]       Print credentials + connect command"
        Write-Host "  kill                 Cancel all in-progress runs"
        Write-Host "  watch                Poll until artifact appears, then print connect cmd"
        Write-Host "  help                 This message"
        Write-Host ""
        Write-Host "Env vars:"
        Write-Host "  GH_PAT (required)    GitHub PAT with actions:read + actions:write"
        Write-Host "  GH_REPO (optional)   Override repo (default: $Repo)"
    }
}
