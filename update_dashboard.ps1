param(
    [string]$TaskName = "Claude JSON Cron"
)

$ErrorActionPreference = "Stop"

[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8

$Root = $PSScriptRoot
$ConfigPath = Join-Path $Root "tasks.json"
$StatePath = Join-Path $Root "cron.state.json"
$LogPath = Join-Path $Root "cron.log"
$OutputPath = Join-Path $Root "dashboard.html"

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return $raw | ConvertFrom-Json
}

function HtmlEncode {
    param([AllowNull()][object]$Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Format-Duration {
    param([double]$Minutes)

    if ($Minutes -le 0) {
        return "now"
    }

    $span = [TimeSpan]::FromMinutes([Math]::Ceiling($Minutes))
    if ($span.TotalDays -ge 1) {
        return "{0}d {1}h {2}m" -f [Math]::Floor($span.TotalDays), $span.Hours, $span.Minutes
    }

    if ($span.TotalHours -ge 1) {
        return "{0}h {1}m" -f [Math]::Floor($span.TotalHours), $span.Minutes
    }

    return "{0}m" -f [Math]::Max(1, [int][Math]::Ceiling($span.TotalMinutes))
}

function Get-StateMap {
    $state = @{}
    $saved = Read-JsonFile -Path $StatePath
    if ($null -eq $saved) {
        return $state
    }

    foreach ($property in $saved.PSObject.Properties) {
        $state[$property.Name] = $property.Value
    }

    return $state
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config not found: $ConfigPath"
}

$config = Read-JsonFile -Path $ConfigPath
$state = Get-StateMap
$now = Get-Date
$scheduledTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
$scheduledTaskInfo = if ($scheduledTask) {
    $scheduledTask | Get-ScheduledTaskInfo
} else {
    $null
}

$rows = foreach ($task in $config.tasks) {
    $lastRun = $null
    if ($state.ContainsKey($task.name) -and $state[$task.name].lastRun) {
        $lastRun = [datetime]$state[$task.name].lastRun
    }

    $everyMinutes = [int]$task.everyMinutes
    $nextRun = if ($task.enabled -eq $false) {
        $null
    } elseif ($null -eq $lastRun) {
        $now
    } elseif ($everyMinutes -le 0) {
        $now
    } else {
        $lastRun.AddMinutes($everyMinutes)
    }

    $remainingMinutes = if ($nextRun) { ($nextRun - $now).TotalMinutes } else { $null }
    $status = if ($task.enabled -eq $false) {
        "disabled"
    } elseif ($null -eq $lastRun -or $remainingMinutes -le 0) {
        "due"
    } else {
        "scheduled"
    }

    [pscustomobject]@{
        Name = [string]$task.name
        Enabled = [bool]$task.enabled
        Status = $status
        EveryMinutes = $everyMinutes
        WorkDir = [string]$task.workDir
        LastRun = $lastRun
        NextRun = $nextRun
        Remaining = if ($remainingMinutes -ne $null) { Format-Duration -Minutes $remainingMinutes } else { "-" }
    }
}

$lastLogLines = if (Test-Path -LiteralPath $LogPath) {
    Get-Content -Tail 18 -LiteralPath $LogPath -Encoding UTF8
} else {
    @("No log file yet.")
}

$enabledCount = @($rows | Where-Object { $_.Enabled }).Count
$dueCount = @($rows | Where-Object { $_.Status -eq "due" }).Count
$taskScript = Join-Path $Root "claude_task.ps1"
$cronScript = Join-Path $Root "claude_cron.ps1"
$allReady = $scheduledTask -and (Test-Path -LiteralPath $ConfigPath) -and (Test-Path -LiteralPath $taskScript) -and (Test-Path -LiteralPath $cronScript)

$rowHtml = foreach ($row in $rows) {
    $statusLabel = switch ($row.Status) {
        "due" { "Due now" }
        "scheduled" { "Waiting" }
        "disabled" { "Disabled" }
        default { $row.Status }
    }

    $statusClass = "status-$($row.Status)"
    $lastRunText = if ($row.LastRun) { $row.LastRun.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" }
    $nextRunText = if ($row.NextRun) { $row.NextRun.ToString("yyyy-MM-dd HH:mm:ss") } else { "-" }

@"
<tr>
  <td><strong>$(HtmlEncode $row.Name)</strong></td>
  <td><span class="pill $statusClass">$(HtmlEncode $statusLabel)</span></td>
  <td>$(HtmlEncode $row.Remaining)</td>
  <td>$(HtmlEncode $lastRunText)</td>
  <td>$(HtmlEncode $nextRunText)</td>
  <td>$(HtmlEncode $row.EveryMinutes)m</td>
  <td class="path">$(HtmlEncode $row.WorkDir)</td>
</tr>
"@
}

$schedulerStatus = if ($scheduledTask) { "Registered" } else { "Not registered" }
$schedulerClass = if ($scheduledTask) { "ok" } else { "warn" }
$lastTaskRun = if ($scheduledTaskInfo -and $scheduledTaskInfo.LastRunTime -gt [datetime]"2000-01-01") {
    $scheduledTaskInfo.LastRunTime.ToString("yyyy-MM-dd HH:mm:ss")
} else {
    "Never"
}
$nextTaskRun = if ($scheduledTaskInfo -and $scheduledTaskInfo.NextRunTime -gt [datetime]"2000-01-01") {
    $scheduledTaskInfo.NextRunTime.ToString("yyyy-MM-dd HH:mm:ss")
} else {
    "-"
}
$readyText = if ($allReady) { "All systems ready" } else { "Setup incomplete" }
$readyClass = if ($allReady) { "ok" } else { "warn" }
$logHtml = ($lastLogLines | ForEach-Object { HtmlEncode $_ }) -join "`n"

$html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Claude JSON Cron Dashboard</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f6f7f9;
      --panel: #ffffff;
      --text: #20242a;
      --muted: #67707d;
      --line: #dfe3e8;
      --ok: #137a4b;
      --ok-bg: #dff5ea;
      --warn: #9b5d00;
      --warn-bg: #fff1d6;
      --due: #a53434;
      --due-bg: #fde2e2;
      --wait: #245f9d;
      --wait-bg: #e0eefc;
      --disabled: #666;
      --disabled-bg: #eceff2;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font: 14px/1.5 "Segoe UI", Arial, sans-serif;
    }
    .shell {
      max-width: 1180px;
      margin: 0 auto;
      padding: 28px 24px 40px;
    }
    header {
      display: flex;
      align-items: flex-end;
      justify-content: space-between;
      gap: 18px;
      margin-bottom: 18px;
    }
    h1 {
      margin: 0;
      font-size: 28px;
      font-weight: 650;
    }
    .sub {
      color: var(--muted);
      margin-top: 4px;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;
      margin-bottom: 18px;
    }
    .metric, .panel {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
    }
    .metric {
      padding: 14px 16px;
      min-height: 92px;
    }
    .label {
      color: var(--muted);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: .04em;
    }
    .value {
      margin-top: 8px;
      font-size: 22px;
      font-weight: 650;
    }
    .value.small {
      font-size: 16px;
      line-height: 1.4;
    }
    .ok { color: var(--ok); }
    .warn { color: var(--warn); }
    .panel {
      overflow: hidden;
      margin-top: 14px;
    }
    .panel-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 14px 16px;
      border-bottom: 1px solid var(--line);
    }
    .panel-title {
      font-size: 16px;
      font-weight: 650;
    }
    table {
      width: 100%;
      border-collapse: collapse;
    }
    th, td {
      padding: 12px 16px;
      text-align: left;
      border-bottom: 1px solid var(--line);
      vertical-align: middle;
      white-space: nowrap;
    }
    th {
      color: var(--muted);
      font-size: 12px;
      font-weight: 600;
      text-transform: uppercase;
    }
    td.path {
      white-space: normal;
      color: var(--muted);
      max-width: 320px;
      word-break: break-all;
    }
    tr:last-child td { border-bottom: 0; }
    .pill {
      display: inline-flex;
      align-items: center;
      min-height: 26px;
      padding: 3px 10px;
      border-radius: 999px;
      font-weight: 600;
      font-size: 12px;
    }
    .status-due { color: var(--due); background: var(--due-bg); }
    .status-scheduled { color: var(--wait); background: var(--wait-bg); }
    .status-disabled { color: var(--disabled); background: var(--disabled-bg); }
    pre {
      margin: 0;
      padding: 16px;
      background: #111820;
      color: #d7dee8;
      overflow: auto;
      max-height: 340px;
      font: 12px/1.55 Consolas, "Courier New", monospace;
    }
    .actions {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      justify-content: flex-end;
    }
    .button {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-height: 34px;
      padding: 6px 12px;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--panel);
      color: var(--text);
      text-decoration: none;
      font-weight: 600;
    }
    @media (max-width: 860px) {
      header { align-items: flex-start; flex-direction: column; }
      .grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      table { display: block; overflow-x: auto; }
    }
    @media (max-width: 540px) {
      .shell { padding: 20px 14px 32px; }
      .grid { grid-template-columns: 1fr; }
      h1 { font-size: 24px; }
    }
  </style>
</head>
<body>
  <main class="shell">
    <header>
      <div>
        <h1>Claude JSON Cron Dashboard</h1>
        <div class="sub">Generated at $(HtmlEncode $($now.ToString("yyyy-MM-dd HH:mm:ss"))) from tasks.json</div>
      </div>
      <div class="actions">
        <a class="button" href="tasks.json">Open tasks.json</a>
        <a class="button" href="cron.log">Open log</a>
      </div>
    </header>

    <section class="grid">
      <div class="metric">
        <div class="label">Readiness</div>
        <div class="value $readyClass">$(HtmlEncode $readyText)</div>
      </div>
      <div class="metric">
        <div class="label">Windows Task</div>
        <div class="value $schedulerClass">$(HtmlEncode $schedulerStatus)</div>
      </div>
      <div class="metric">
        <div class="label">Enabled Tasks</div>
        <div class="value">$(HtmlEncode $enabledCount)</div>
      </div>
      <div class="metric">
        <div class="label">Due Now</div>
        <div class="value">$(HtmlEncode $dueCount)</div>
      </div>
    </section>

    <section class="panel">
      <div class="panel-head">
        <div class="panel-title">Scheduler</div>
      </div>
      <table>
        <tbody>
          <tr><th>Task Name</th><td>$(HtmlEncode $TaskName)</td></tr>
          <tr><th>Last Scheduler Run</th><td>$(HtmlEncode $lastTaskRun)</td></tr>
          <tr><th>Next Scheduler Run</th><td>$(HtmlEncode $nextTaskRun)</td></tr>
        </tbody>
      </table>
    </section>

    <section class="panel">
      <div class="panel-head">
        <div class="panel-title">Tasks</div>
      </div>
      <table>
        <thead>
          <tr>
            <th>Name</th>
            <th>Status</th>
            <th>Remaining</th>
            <th>Last Run</th>
            <th>Next Run</th>
            <th>Interval</th>
            <th>Work Dir</th>
          </tr>
        </thead>
        <tbody>
          $($rowHtml -join "`n")
        </tbody>
      </table>
    </section>

    <section class="panel">
      <div class="panel-head">
        <div class="panel-title">Recent Log</div>
      </div>
      <pre>$logHtml</pre>
    </section>
  </main>
</body>
</html>
"@

$html | Out-File -FilePath $OutputPath -Encoding UTF8
Write-Host "Dashboard written: $OutputPath"
