$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$TaskConfig = Join-Path $Root "tasks.json"

Write-Host "Checking win-cron package in: $Root"

$requiredFiles = @(
  "tasks.json",
  "claude_cron.ps1",
  "claude_task.ps1",
  "update_dashboard.ps1",
  "register_claude_cron_task.ps1",
  "run_hidden.vbs"
)

foreach ($file in $requiredFiles) {
  $path = Join-Path $Root $file
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing required file: $file"
  }
}

$config = Get-Content -Raw -LiteralPath $TaskConfig | ConvertFrom-Json
Write-Host "tasks.json parses ok."

$claude = Get-Command claude -ErrorAction SilentlyContinue
if ($claude) {
  Write-Host "claude found: $($claude.Source)"
} else {
  Write-Host "WARNING: claude command was not found on PATH."
}

if ($config.gitBashPath -and (Test-Path -LiteralPath $config.gitBashPath)) {
  Write-Host "Git Bash found: $($config.gitBashPath)"
} else {
  Write-Host "WARNING: gitBashPath does not exist: $($config.gitBashPath)"
}

foreach ($task in $config.tasks) {
  if ($task.workDir -and -not (Test-Path -LiteralPath $task.workDir)) {
    Write-Host "WARNING: workDir does not exist for task '$($task.name)': $($task.workDir)"
  }
}

powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "update_dashboard.ps1")
Write-Host "Dashboard refreshed."

Write-Host ""
Write-Host "If the warnings are expected, edit tasks.json first. Then register with:"
Write-Host "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\\register_claude_cron_task.ps1"

