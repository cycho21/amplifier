param(
    [string]$TaskId = "000_template",
    [string]$Role = "implementer",
    [string]$ExecutionSpec = "execution/implementer.yaml",
    [string]$AgentRole = "agents/implementer.md",
    [string]$Plan = "docs/plan/PLAN.md",
    [string]$Contract = "docs/plan/CONTRACT.md",
    [string]$PromptOut = "logs/prompts/implementer-000_template.prompt.txt",
    [string]$LogOut = "logs/20260426-implementer-000_template.json",
    [string]$Mode = "",
    [switch]$AllowReal,
    [string]$CodexCommand = "codex.cmd",
    [string]$RawOutputOut = ""
)

$ErrorActionPreference = "Stop"

function Read-Utf8File {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Required input file not found: $Path"
    }

    return Get-Content -Encoding utf8 $Path -Raw
}

function Read-RunnerSelection {
    param([string[]]$Lines)

    $selection = [ordered]@{
        provider = ""
        tool = ""
        mode = ""
    }
    $inRunner = $false

    foreach ($line in $Lines) {
        if ($line -match "^runner:\s*$") {
            $inRunner = $true
            continue
        }

        if (-not $inRunner) {
            continue
        }

        if ($line -match "^\S") {
            break
        }

        if ($line -match "^\s{2}provider:\s*(.+)$") {
            $selection.provider = $Matches[1].Trim().Trim('"')
            continue
        }

        if ($line -match "^\s{2}tool:\s*(.+)$") {
            $selection.tool = $Matches[1].Trim().Trim('"')
            continue
        }

        if ($line -match "^\s{2}mode:\s*(.+)$") {
            $selection.mode = $Matches[1].Trim().Trim('"')
        }
    }

    foreach ($field in @("provider", "tool", "mode")) {
        if ([string]::IsNullOrWhiteSpace($selection[$field])) {
            throw "Required runner selection field not found: $field"
        }
    }

    return $selection
}

function Test-CodexRunnerSelection {
    param($RunnerSelection)

    if ($RunnerSelection.provider -ne "codex") {
        throw "Unsupported Codex runner provider: $($RunnerSelection.provider)"
    }

    if ($RunnerSelection.tool -ne "codex-cli") {
        throw "Unsupported Codex runner tool: $($RunnerSelection.tool)"
    }

    if (@("dry-run", "real") -notcontains $RunnerSelection.mode) {
        throw "Unsupported Codex runner mode: $($RunnerSelection.mode)"
    }
}

function Resolve-InvocationMode {
    param(
        [string]$ConfiguredMode,
        [string]$RequestedMode
    )

    if ([string]::IsNullOrWhiteSpace($RequestedMode)) {
        return $ConfiguredMode
    }

    if (@("dry-run", "real") -notcontains $RequestedMode) {
        throw "Unsupported requested Codex runner mode: $RequestedMode"
    }

    return $RequestedMode
}

function Invoke-RealCodex {
    param(
        [string]$Prompt,
        [string]$CodexCommand,
        [string]$RawOutputOut
    )

    $rawOutputDir = Split-Path -Parent $RawOutputOut
    New-Item -ItemType Directory -Force -Path $rawOutputDir | Out-Null

    $events = @($Prompt | & $CodexCommand exec --skip-git-repo-check --json -o $RawOutputOut - 2>&1)
    $exitCode = $LASTEXITCODE

    return [ordered]@{
        exit_code = $exitCode
        events = $events
    }
}

function ConvertTo-StringArray {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [array]) {
        return @($Value | ForEach-Object { [string]$_ })
    }

    return @([string]$Value)
}

function Read-StructuredCodexOutput {
    param([string]$RawOutputPath)

    if (-not (Test-Path $RawOutputPath)) {
        return $null
    }

    $rawOutput = Get-Content -Encoding utf8 $RawOutputPath -Raw

    try {
        $parsed = $rawOutput | ConvertFrom-Json
    } catch {
        return $null
    }

    foreach ($field in @("summary", "changed_files", "verification_result", "risks", "next_steps")) {
        if (-not ($parsed.PSObject.Properties.Name -contains $field)) {
            return $null
        }
    }

    return [ordered]@{
        summary = [string]$parsed.summary
        changed_files = ConvertTo-StringArray $parsed.changed_files
        verification_result = [string]$parsed.verification_result
        risks = ConvertTo-StringArray $parsed.risks
        next_steps = ConvertTo-StringArray $parsed.next_steps
    }
}

$taskPath = "tasks/$TaskId.md"

$planText = Read-Utf8File $Plan
$contractText = Read-Utf8File $Contract
$roleText = Read-Utf8File $AgentRole
$taskText = Read-Utf8File $taskPath
$executionText = Read-Utf8File $ExecutionSpec
$executionLines = $executionText -split "\r?\n"
$runnerSelection = Read-RunnerSelection $executionLines
Test-CodexRunnerSelection $runnerSelection

$effectiveMode = Resolve-InvocationMode $runnerSelection.mode $Mode

if ($effectiveMode -eq "real" -and -not $AllowReal) {
    throw "Real Codex invocation requires -AllowReal"
}

if ([string]::IsNullOrWhiteSpace($RawOutputOut)) {
    $RawOutputOut = "logs/raw/codex-$Role-$TaskId-output.txt"
}

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
Return a JSON object with exactly these fields:
{
  "summary": "string",
  "changed_files": ["path"],
  "verification_result": "string",
  "risks": ["string"],
  "next_steps": ["string"]
}
"@

$promptDir = Split-Path -Parent $PromptOut
$logDir = Split-Path -Parent $LogOut

New-Item -ItemType Directory -Force -Path $promptDir | Out-Null
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

Set-Content -Encoding utf8 -Path $PromptOut -Value $prompt

$runnerName = "codex-dry-run"
$invocation = [ordered]@{
    mode = $effectiveMode
    real_enabled = $false
    command = $CodexCommand
    exit_code = $null
    raw_output = ""
    parsed_output = $false
}
$output = [ordered]@{
    summary = "Dry-run prompt generated without invoking an external LLM."
    changed_files = @()
    verification_result = "Prompt and structured log were generated locally."
    risks = @("This run does not verify actual LLM execution.")
    next_steps = @("Replace dry-run behavior with a real runner invocation when ready.")
}

if ($effectiveMode -eq "real") {
    $runnerName = "codex-real"
    $realResult = Invoke-RealCodex $prompt $CodexCommand $RawOutputOut
    $invocation.real_enabled = $true
    $invocation.exit_code = $realResult.exit_code
    $invocation.raw_output = $RawOutputOut

    if ($realResult.exit_code -ne 0) {
        $output.summary = "Real Codex invocation failed."
        $output.verification_result = "Codex CLI exited with code $($realResult.exit_code)."
        $output.risks = @("The real Codex invocation did not complete successfully.")
        $output.next_steps = @("Inspect Codex CLI output and retry after resolving the runner failure.")
    } else {
        $structuredOutput = Read-StructuredCodexOutput $RawOutputOut

        if ($null -ne $structuredOutput) {
            $output = $structuredOutput
            $invocation.parsed_output = $true
        } else {
            $output.summary = "Real Codex invocation completed behind the runner adapter boundary."
            $output.verification_result = "Codex CLI exited with code 0 and wrote raw output to $RawOutputOut."
            $output.risks = @("Raw Codex output was not parseable as the required structured fields.")
            $output.next_steps = @("Add malformed output fixtures and strict failure handling in the next real-runner step.")
        }
    }
}

$log = [ordered]@{
    run_id = "20260426-$Role-000_template"
    runner = $runnerName
    role = $Role
    task_id = $TaskId
    runner_selection = [ordered]@{
        provider = $runnerSelection.provider
        tool = $runnerSelection.tool
        configured_mode = $runnerSelection.mode
        effective_mode = $effectiveMode
    }
    invocation = $invocation
    inputs = @(
        $Plan,
        $Contract,
        $AgentRole,
        $taskPath,
        $ExecutionSpec
    )
    output = $output
}

$log | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 -Path $LogOut

Write-Output "Prompt written to $PromptOut"
Write-Output "Log written to $LogOut"
