param(
    [int]$IntervalSeconds = 300,
    [switch]$Once,
    [switch]$RunAll,
    [string]$Only
)

$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$ConfigPath = Join-Path $Root "tasks.json"
$StatePath = Join-Path $Root "cron.state.json"
$Log = Join-Path $Root "cron.log"
$TaskOutputDir = Join-Path $Root "task-output"
$PidFile = Join-Path $Root "cron.pid"
$TaskScript = Join-Path $Root "claude_task.ps1"
$DashboardScript = Join-Path $Root "update_dashboard.ps1"
$LockName = "ClaudeCron-$([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Root)).TrimEnd('=').Replace('+','-').Replace('/','_'))"
$Mutex = [Threading.Mutex]::new($false, $LockName)

[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $Message" | Out-File -FilePath $Log -Append -Encoding UTF8
}

function Get-SafeFileName {
    param([string]$Name)
    $safe = $Name -replace '[^A-Za-z0-9_.-]', '_'
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "task"
    }
    return $safe
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $raw = Get-Content -Raw -LiteralPath $Path
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return $raw | ConvertFrom-Json
}

function Save-State {
    param([hashtable]$State)
    $State | ConvertTo-Json -Depth 10 | Out-File -FilePath $StatePath -Encoding UTF8
}

function Get-State {
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

function Expand-Prompt {
    param(
        [object]$Task,
        [datetime]$Now
    )

    $date = $Now.ToString("yyyy-MM-dd")
    $datetime = $Now.ToString("yyyy-MM-dd HH:mm:ss")

    $text = if ($Task.prompt -is [array]) {
        ($Task.prompt -join [Environment]::NewLine)
    }
    else {
        [string]$Task.prompt
    }

    return $text.Replace("{date}", $date).Replace("{datetime}", $datetime)
}

function Test-TaskDue {
    param(
        [object]$Task,
        [hashtable]$State,
        [datetime]$Now
    )

    if ($RunAll) {
        return $true
    }

    if ($Only -and $Task.name -eq $Only) {
        return $true
    }

    $everyMinutes = [int]$Task.everyMinutes
    if ($everyMinutes -le 0) {
        return $true
    }

    if (-not $State.ContainsKey($Task.name)) {
        return $true
    }

    $lastRun = [datetime]$State[$Task.name].lastRun
    return ($Now - $lastRun).TotalMinutes -ge $everyMinutes
}

function Invoke-DueTasks {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config not found: $ConfigPath"
    }

    if (-not (Test-Path -LiteralPath $TaskScript)) {
        throw "Task script not found: $TaskScript"
    }

    $config = Read-JsonFile -Path $ConfigPath
    $state = Get-State
    $now = Get-Date
    $exitCode = 0
    $ranAny = $false

    foreach ($task in $config.tasks) {
        if ($Only -and $task.name -ne $Only) {
            continue
        }

        if ($task.enabled -eq $false) {
            Write-Log "Task skipped: $($task.name) disabled."
            continue
        }

        if (-not (Test-TaskDue -Task $task -State $state -Now $now)) {
            Write-Log "Task skipped: $($task.name) not due."
            continue
        }

        $ranAny = $true
        $prompt = Expand-Prompt -Task $task -Now $now
        $gitBashPath = if ($task.gitBashPath) { [string]$task.gitBashPath } else { [string]$config.gitBashPath }
        $allowedTools = if ($task.allowedTools) { [string]$task.allowedTools } else { [string]$config.defaultAllowedTools }
        $safeName = Get-SafeFileName -Name ([string]$task.name)
        $taskOutputPath = Join-Path $TaskOutputDir "$safeName-latest.log"

        Write-Log "Task started: $($task.name)"

        try {
            if (-not (Test-Path -LiteralPath $TaskOutputDir)) {
                New-Item -ItemType Directory -Path $TaskOutputDir | Out-Null
            }

            "Task: $($task.name)" | Out-File -FilePath $taskOutputPath -Encoding UTF8
            "Started: $($now.ToString("yyyy-MM-dd HH:mm:ss"))" | Out-File -FilePath $taskOutputPath -Append -Encoding UTF8

            & powershell.exe `
                -NoProfile `
                -ExecutionPolicy Bypass `
                -File $TaskScript `
                -Name ([string]$task.name) `
                -WorkDir ([string]$task.workDir) `
                -Prompt $prompt `
                -GitBashPath $gitBashPath `
                -AllowedTools $allowedTools 2>&1 |
                Out-File -FilePath $taskOutputPath -Append -Encoding UTF8

            $taskExitCode = $LASTEXITCODE
            Write-Log "Task finished: $($task.name) exit=$taskExitCode"
            Write-Log "Task output saved: task-output/$safeName-latest.log"

            if ($taskExitCode -eq 0) {
                $state[$task.name] = @{
                    lastRun = $now.ToString("o")
                }
                Save-State -State $state
            }
            else {
                $exitCode = $taskExitCode
            }
        }
        catch {
            Write-Log "Task failed: $($task.name) $($_.Exception.Message)"
            Write-Log "Task output saved: task-output/$safeName-latest.log"
            $exitCode = 1
        }
    }

    if (-not $ranAny) {
        Write-Log "No due tasks."
    }

    return $exitCode
}

function Update-Dashboard {
    if (-not (Test-Path -LiteralPath $DashboardScript)) {
        return
    }

    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DashboardScript 2>&1 |
            Out-File -FilePath $Log -Append -Encoding UTF8
    }
    catch {
        Write-Log "Dashboard update failed. $($_.Exception.Message)"
    }
}

$hasLock = $Mutex.WaitOne(0)
if (-not $hasLock) {
    Write-Log "Another claude_cron.ps1 instance is already running. Exit."
    exit 2
}

try {
    $PID | Out-File -FilePath $PidFile -Encoding ASCII

    do {
        $exitCode = Invoke-DueTasks
        Update-Dashboard

        if ($Once) {
            exit $exitCode
        }

        Write-Log "Sleeping ${IntervalSeconds}s."
        Start-Sleep -Seconds $IntervalSeconds
    } while ($true)
}
finally {
    if (Test-Path -LiteralPath $PidFile) {
        Remove-Item -LiteralPath $PidFile -Force
    }

    if ($hasLock) {
        [void]$Mutex.ReleaseMutex()
    }

    $Mutex.Dispose()
}
