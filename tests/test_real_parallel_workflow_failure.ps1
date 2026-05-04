$ErrorActionPreference = "Stop"

function Remove-TestOutput {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        if (Test-Path $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

$logOut = "logs/test-workflow-real-parallel-failure-000_template.json"
$stepLogDir = "logs/test-real-parallel-failure-step-logs"
$markerDir = "logs/test-real-parallel-failure-markers"

Remove-TestOutput @($logOut, $stepLogDir, $markerDir)

$previousMarkerDir = $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR
$env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $markerDir

try {
    & .\runner\workflow.ps1 `
        -TaskId "000_template" `
        -WorkflowSpec "workflows/parallel-review.yaml" `
        -Mode "real" `
        -AllowReal `
        -StepRunnerCommand ".\test-fixtures\fake-workflow-failing-step-runner.ps1" `
        -StepLogDir $stepLogDir `
        -LogOut $logOut
} finally {
    $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $previousMarkerDir
}

if (-not (Test-Path $logOut)) {
    throw "Expected real parallel failure workflow log was not created: $logOut"
}

$log = Get-Content -Encoding utf8 $logOut -Raw | ConvertFrom-Json

if ($log.runner -ne "workflow-real") {
    throw "Expected runner workflow-real, got $($log.runner)"
}

if ($log.output.final_status -ne "real-failed") {
    throw "Expected final_status real-failed, got $($log.output.final_status)"
}

$failedSteps = @($log.output.failed_steps | ForEach-Object { $_.step_id })
if ($failedSteps -notcontains "backend-engineer") {
    throw "Expected backend-engineer to be recorded as failed"
}

$cancelledSteps = @($log.output.cancelled_steps | ForEach-Object { $_.step_id })
if ($cancelledSteps -notcontains "frontend-engineer") {
    throw "Expected frontend-engineer to be recorded as cancelled"
}

$skippedSteps = @($log.output.skipped_steps | ForEach-Object { $_.step_id })
foreach ($stepId in @("tester", "reviewer")) {
    if ($skippedSteps -notcontains $stepId) {
        throw "Expected dependent step $stepId to be skipped after upstream failure"
    }
}

foreach ($role in @("tester", "reviewer")) {
    if (Test-Path (Join-Path $markerDir "$role.start")) {
        throw "Dependent step $role must not start after upstream failure"
    }
}

$risks = @($log.output.risks)
if ($risks -notcontains "Real parallel workflow stopped after a step failure.") {
    throw "Expected failure risk to explain propagation"
}

Remove-TestOutput @($logOut, $stepLogDir, $markerDir)

Write-Output "Real parallel workflow failure propagation test passed."
