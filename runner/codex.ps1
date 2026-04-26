param(
    [string]$TaskId = "000_template",
    [string]$Role = "implementer",
    [string]$ExecutionSpec = "execution/implementer.yaml",
    [string]$AgentRole = "agents/implementer.md",
    [string]$Plan = "docs/plan/PLAN.md",
    [string]$Contract = "docs/plan/CONTRACT.md",
    [string]$PromptOut = "logs/prompts/implementer-000_template.prompt.txt",
    [string]$LogOut = "logs/20260426-implementer-000_template.json"
)

$ErrorActionPreference = "Stop"

function Read-Utf8File {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Required input file not found: $Path"
    }

    return Get-Content -Encoding utf8 $Path -Raw
}

$taskPath = "tasks/$TaskId.md"

$planText = Read-Utf8File $Plan
$contractText = Read-Utf8File $Contract
$roleText = Read-Utf8File $AgentRole
$taskText = Read-Utf8File $taskPath
$executionText = Read-Utf8File $ExecutionSpec

$prompt = @"
[System]
$roleText

[Context]
## Plan
$planText

## Contract
$contractText

## Task
$taskText

[Instructions]
$executionText

[Output Format]
- summary
- changed_files
- verification_result
- risks
- next_steps
"@

$promptDir = Split-Path -Parent $PromptOut
$logDir = Split-Path -Parent $LogOut

New-Item -ItemType Directory -Force -Path $promptDir | Out-Null
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

Set-Content -Encoding utf8 -Path $PromptOut -Value $prompt

$log = [ordered]@{
    run_id = "20260426-$Role-000_template"
    runner = "codex-dry-run"
    role = $Role
    task_id = $TaskId
    inputs = @(
        $Plan,
        $Contract,
        $AgentRole,
        $taskPath,
        $ExecutionSpec
    )
    output = [ordered]@{
        summary = "Dry-run prompt generated without invoking an external LLM."
        changed_files = @()
        verification_result = "Prompt and structured log were generated locally."
        risks = @("This run does not verify actual LLM execution.")
        next_steps = @("Replace dry-run behavior with a real runner invocation when ready.")
    }
}

$log | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 -Path $LogOut

Write-Output "Prompt written to $PromptOut"
Write-Output "Log written to $LogOut"
