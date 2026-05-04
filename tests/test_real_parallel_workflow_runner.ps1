$ErrorActionPreference = "Stop"

function Remove-TestOutput {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        if (Test-Path $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

function Assert-RequiredOutputFields {
    param($Output, [string]$Context)

    foreach ($field in @("summary", "changed_files", "verification_result", "risks", "next_steps")) {
        if (-not ($Output.PSObject.Properties.Name -contains $field)) {
            throw "$Context missing required output field: $field"
        }
    }
}

function Assert-StepsOverlap {
    param(
        [string]$FirstRole,
        [string]$SecondRole,
        [string]$MarkerDir
    )

    $firstStart = [int64](Get-Content -Encoding utf8 (Join-Path $MarkerDir "$FirstRole.start") -Raw)
    $firstEnd = [int64](Get-Content -Encoding utf8 (Join-Path $MarkerDir "$FirstRole.end") -Raw)
    $secondStart = [int64](Get-Content -Encoding utf8 (Join-Path $MarkerDir "$SecondRole.start") -Raw)
    $secondEnd = [int64](Get-Content -Encoding utf8 (Join-Path $MarkerDir "$SecondRole.end") -Raw)

    if (-not ($firstStart -lt $secondEnd -and $secondStart -lt $firstEnd)) {
        throw "Expected $FirstRole and $SecondRole to overlap in real parallel mode"
    }
}

$logOut = "logs/test-workflow-real-parallel-review-000_template.json"
$stepLogDir = "logs/test-real-parallel-step-logs"
$markerDir = "logs/test-real-parallel-markers"

Remove-TestOutput @($logOut, $stepLogDir, $markerDir)

$previousMarkerDir = $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR
$previousSleepMs = $env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS
$env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $markerDir
$env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS = "1000"

try {
    & .\runner\workflow.ps1 `
        -TaskId "000_template" `
        -WorkflowSpec "workflows/parallel-review.yaml" `
        -Mode "real" `
        -AllowReal `
        -StepRunnerCommand ".\test-fixtures\fake-workflow-step-runner.ps1" `
        -StepLogDir $stepLogDir `
        -LogOut $logOut
} finally {
    $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $previousMarkerDir
    $env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS = $previousSleepMs
}

if (-not (Test-Path $logOut)) {
    throw "Expected real parallel workflow log was not created: $logOut"
}

$log = Get-Content -Encoding utf8 $logOut -Raw | ConvertFrom-Json

if ($log.runner -ne "workflow-real") {
    throw "Expected runner workflow-real, got $($log.runner)"
}

if ($log.output.execution_mode -ne "parallel") {
    throw "Expected execution_mode parallel, got $($log.output.execution_mode)"
}

if ($log.output.final_status -ne "real-complete") {
    throw "Expected final_status real-complete, got $($log.output.final_status)"
}

$groups = @($log.output.parallel_groups)
if ($groups.Count -ne 2) {
    throw "Expected 2 parallel groups, got $($groups.Count)"
}

Assert-StepsOverlap "backend-engineer" "frontend-engineer" $markerDir
Assert-StepsOverlap "tester" "reviewer" $markerDir

foreach ($stepLog in $log.output.step_logs) {
    Assert-RequiredOutputFields $stepLog.output "Step $($stepLog.step_id)"

    if ($stepLog.runner -ne "fake-workflow-step-runner") {
        throw "Expected embedded real step runner metadata for $($stepLog.step_id)"
    }

    if (-not ($stepLog.cost_tracking.PSObject.Properties.Name -contains "provider_metadata")) {
        throw "Expected step $($stepLog.step_id) cost_tracking to include provider_metadata"
    }

    if ($stepLog.cost_tracking.provider_metadata.provider -ne "fake-provider") {
        throw "Expected step $($stepLog.step_id) provider metadata source from runner log"
    }

    if ($stepLog.cost_tracking.estimated_cost -ne 0.07) {
        throw "Expected step $($stepLog.step_id) estimated_cost 0.07, got $($stepLog.cost_tracking.estimated_cost)"
    }
}

$backendStepCost = @($log.output.cost_tracking.step_costs | Where-Object { $_.step_id -eq "backend-engineer" })[0]
if (-not ($backendStepCost.PSObject.Properties.Name -contains "provider_metadata")) {
    throw "Expected workflow step cost entry to include provider_metadata"
}

if ($backendStepCost.provider_metadata.provider -ne "fake-provider") {
    throw "Expected workflow step cost provider metadata source from runner log"
}

if ($backendStepCost.estimated_cost -ne 0.07) {
    throw "Expected workflow backend-engineer step cost 0.07, got $($backendStepCost.estimated_cost)"
}

if ($log.output.cost_tracking.estimated_total_cost -ne 0.28) {
    throw "Expected workflow estimated_total_cost 0.28, got $($log.output.cost_tracking.estimated_total_cost)"
}

$stepCostTotal = 0
foreach ($stepCost in $log.output.cost_tracking.step_costs) {
    $stepCostTotal += [decimal]$stepCost.estimated_cost
}

if ([decimal]$log.output.cost_tracking.estimated_total_cost -ne $stepCostTotal) {
    throw "Expected workflow estimated_total_cost to equal step cost sum $stepCostTotal"
}

Remove-TestOutput @($logOut, $stepLogDir, $markerDir)

Write-Output "Real parallel workflow runner test passed."
