# core/powershell/notify.ps1 - Standalone notifier (called by workflows for events)
. "$PSScriptRoot\utils.ps1"

$Title = if ($args[0]) { $args[0] } else { 'Notification' }
$Body  = if ($args[1]) { $args[1] } else { '' }

Write-Block "NOTIFY"
Write-Info "Title: $Title"
Write-Info "Body:  $Body"

Send-Notify -Title $Title -Body $Body

Write-Ok 'Notify dispatched'
