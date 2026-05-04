$ErrorActionPreference = "Stop"

function Remove-TestOutput {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        if (Test-Path $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

function Assert-NoVoting {
    param($Log, [string]$Context)

    if ($Log.output.PSObject.Properties.Name -contains "voting") {
        throw "$Context must not include voting output"
    }
}

$dryRunLogOut = "logs/test-workflow-voting-gate-dry-run-000_template.json"
$realLogOut = "logs/test-workflow-voting-gate-real-000_template.json"
$failureLogOut = "logs/test-workflow-voting-gate-failure-000_template.json"
$realStepLogDir = "logs/test-voting-gate-real-step-logs"
$failureStepLogDir = "logs/test-voting-gate-failure-step-logs"
$realMarkerDir = "logs/test-voting-gate-real-markers"
$failureMarkerDir = "logs/test-voting-gate-failure-markers"

Remove-TestOutput @(
    $dryRunLogOut,
    $realLogOut,
    $failureLogOut,
    $realStepLogDir,
    $failureStepLogDir,
    $realMarkerDir,
    $failureMarkerDir
)

& .\runner\workflow.ps1 `
    -TaskId "000_template" `
    -WorkflowSpec "workflows/parallel-review.yaml" `
    -LogOut $dryRunLogOut

$previousMarkerDir = $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR
$previousSleepMs = $env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS
$env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $realMarkerDir
$env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS = "100"

try {
    & .\runner\workflow.ps1 `
        -TaskId "000_template" `
        -WorkflowSpec "workflows/parallel-review.yaml" `
        -Mode "real" `
        -AllowReal `
        -StepRunnerCommand ".\test-fixtures\fake-workflow-step-runner.ps1" `
        -StepLogDir $realStepLogDir `
        -LogOut $realLogOut
} finally {
    $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $previousMarkerDir
    $env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS = $previousSleepMs
}

$env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $failureMarkerDir

try {
    & .\runner\workflow.ps1 `
        -TaskId "000_template" `
        -WorkflowSpec "workflows/parallel-review.yaml" `
        -Mode "real" `
        -AllowReal `
        -StepRunnerCommand ".\test-fixtures\fake-workflow-failing-step-runner.ps1" `
        -StepLogDir $failureStepLogDir `
        -LogOut $failureLogOut
} finally {
    $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $previousMarkerDir
}

$dryRunLog = Get-Content -Encoding utf8 $dryRunLogOut -Raw | ConvertFrom-Json
$realLog = Get-Content -Encoding utf8 $realLogOut -Raw | ConvertFrom-Json
$failureLog = Get-Content -Encoding utf8 $failureLogOut -Raw | ConvertFrom-Json

Assert-NoVoting $dryRunLog "Dry-run workflow"
Assert-NoVoting $failureLog "Failed real workflow"

if (-not ($realLog.output.PSObject.Properties.Name -contains "voting")) {
    throw "Successful real workflow must include voting gate output"
}

$voting = $realLog.output.voting

foreach ($field in @("voting_method", "eligible_step_ids", "votes", "selected_step_id", "status")) {
    if (-not ($voting.PSObject.Properties.Name -contains $field)) {
        throw "Voting output missing field: $field"
    }
}

if ($voting.status -ne "ready-not-implemented") {
    throw "Expected voting status ready-not-implemented, got $($voting.status)"
}

if ($voting.voting_method -ne "not-implemented") {
    throw "Expected voting_method not-implemented"
}

if (@($voting.votes).Count -ne 0) {
    throw "Expected no votes before voting execution is implemented"
}

if ($voting.selected_step_id -ne "") {
    throw "Expected no selected_step_id before voting execution is implemented"
}

$eligibleStepIds = @($voting.eligible_step_ids)
foreach ($stepId in @("backend-engineer", "frontend-engineer", "tester", "reviewer")) {
    if ($eligibleStepIds -notcontains $stepId) {
        throw "Expected eligible voting step id: $stepId"
    }
}

Remove-TestOutput @(
    $dryRunLogOut,
    $realLogOut,
    $failureLogOut,
    $realStepLogDir,
    $failureStepLogDir,
    $realMarkerDir,
    $failureMarkerDir
)

Write-Output "Workflow voting gate test passed."
