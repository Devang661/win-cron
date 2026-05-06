param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$WorkDir,

    [Parameter(Mandatory = $true)]
    [string]$Prompt,

    [Parameter(Mandatory = $true)]
    [string]$GitBashPath,

    [string]$AllowedTools = "Read,Write,Edit"
)

$ErrorActionPreference = "Stop"

[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8

if (-not (Test-Path -LiteralPath $GitBashPath)) {
    throw "Git Bash not found: $GitBashPath"
}

if (-not (Test-Path -LiteralPath $WorkDir)) {
    throw "Work directory not found: $WorkDir"
}

$env:CLAUDE_CODE_GIT_BASH_PATH = $GitBashPath
Set-Location -LiteralPath $WorkDir

Write-Output "Running task: $Name"

& claude `
    --print `
    $Prompt `
    --permission-mode auto `
    --allowedTools $AllowedTools

exit $LASTEXITCODE
