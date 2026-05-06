param(
    [string]$TaskName = "Claude JSON Cron",
    [int]$EveryMinutes = 5
)

$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$CronScript = Join-Path $Root "claude_cron.ps1"
$HiddenRunner = Join-Path $Root "run_hidden.vbs"

if (-not (Test-Path -LiteralPath $CronScript)) {
    throw "Cron script not found: $CronScript"
}

if (-not (Test-Path -LiteralPath $HiddenRunner)) {
    throw "Hidden runner not found: $HiddenRunner"
}

$Action = New-ScheduledTaskAction `
    -Execute "wscript.exe" `
    -Argument "`"$HiddenRunner`" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$CronScript`" -Once" `
    -WorkingDirectory $Root

$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes $EveryMinutes)

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Description "Runs due Claude Code tasks from tasks.json." `
    -Force

Write-Host "Registered task '$TaskName' to check tasks.json every $EveryMinutes minutes."
