$ErrorActionPreference = "Stop"

function Remove-TestOutput {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        if (Test-Path $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

function Assert-HasProperties {
    param(
        $Object,
        [string[]]$Properties,
        [string]$Context
    )

    foreach ($property in $Properties) {
        if (-not ($Object.PSObject.Properties.Name -contains $property)) {
            throw "$Context missing required property: $property"
        }
    }
}

function Assert-PropertySubset {
    param(
        $Baseline,
        $Candidate,
        [string]$Context
    )

    foreach ($property in $Baseline.PSObject.Properties.Name) {
        if (-not ($Candidate.PSObject.Properties.Name -contains $property)) {
            throw "$Context removed baseline property: $property"
        }
    }
}

$dryRunLogOut = "logs/test-codex-compatibility-dry-run-000_template.json"
$dryRunPromptOut = "logs/prompts/test-codex-compatibility-dry-run.prompt.txt"
$realLogOut = "logs/test-codex-compatibility-real-000_template.json"
$realPromptOut = "logs/prompts/test-codex-compatibility-real.prompt.txt"
$rawOutputOut = "logs/raw/test-codex-compatibility-real-output.txt"

Remove-TestOutput @(
    $dryRunLogOut,
    $dryRunPromptOut,
    $realLogOut,
    $realPromptOut,
    $rawOutputOut
)

& .\runner\codex.ps1 `
    -TaskId "000_template" `
    -Role "implementer" `
    -ExecutionSpec "execution/implementer.yaml" `
    -AgentRole "agents/implementer.md" `
    -PromptOut $dryRunPromptOut `
    -LogOut $dryRunLogOut

& .\runner\codex.ps1 `
    -TaskId "000_template" `
    -Role "implementer" `
    -ExecutionSpec "execution/implementer.yaml" `
    -AgentRole "agents/implementer.md" `
    -Mode "real" `
    -AllowReal `
    -CodexCommand ".\test-fixtures\fake-codex-structured.ps1" `
    -PromptOut $realPromptOut `
    -LogOut $realLogOut `
    -RawOutputOut $rawOutputOut

$dryRunLog = Get-Content -Encoding utf8 $dryRunLogOut -Raw | ConvertFrom-Json
$realLog = Get-Content -Encoding utf8 $realLogOut -Raw | ConvertFrom-Json

$requiredTopLevelFields = @("run_id", "runner", "role", "task_id", "inputs", "output")
$requiredOutputFields = @("summary", "changed_files", "verification_result", "risks", "next_steps")

Assert-HasProperties $dryRunLog $requiredTopLevelFields "Dry-run log"
Assert-HasProperties $realLog $requiredTopLevelFields "Real-run log"
Assert-HasProperties $dryRunLog.output $requiredOutputFields "Dry-run output"
Assert-HasProperties $realLog.output $requiredOutputFields "Real-run output"

Assert-PropertySubset $dryRunLog $realLog "Real-run log"
Assert-PropertySubset $dryRunLog.runner_selection $realLog.runner_selection "Real-run runner_selection"
Assert-PropertySubset $dryRunLog.invocation $realLog.invocation "Real-run invocation"
Assert-PropertySubset $dryRunLog.output $realLog.output "Real-run output"

if ($dryRunLog.role -ne $realLog.role) {
    throw "Expected compatible role values"
}

if ($dryRunLog.task_id -ne $realLog.task_id) {
    throw "Expected compatible task_id values"
}

if (@($dryRunLog.inputs).Count -ne @($realLog.inputs).Count) {
    throw "Expected compatible input path counts"
}

if ($realLog.runner_selection.configured_mode -ne $dryRunLog.runner_selection.configured_mode) {
    throw "Real run must preserve configured runner mode from the execution spec"
}

if ($realLog.runner_selection.effective_mode -ne "real") {
    throw "Expected real run effective mode"
}

if ($realLog.invocation.real_enabled -ne $true) {
    throw "Expected real run invocation metadata to record explicit enablement"
}

if ($realLog.invocation.parsed_output -ne $true) {
    throw "Expected real run to parse structured output"
}

Remove-TestOutput @(
    $dryRunLogOut,
    $dryRunPromptOut,
    $realLogOut,
    $realPromptOut,
    $rawOutputOut
)

Write-Output "Codex runner log compatibility test passed."
