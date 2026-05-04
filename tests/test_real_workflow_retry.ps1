$ErrorActionPreference = "Stop"

function Remove-TestOutput {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        if (Test-Path $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

$logOut = "logs/test-workflow-real-retry-000_template.json"
$stepLogDir = "logs/test-real-retry-step-logs"
$markerDir = "logs/test-real-retry-markers"

Remove-TestOutput @($logOut, $stepLogDir, $markerDir)

$previousMarkerDir = $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR
$env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $markerDir

try {
    & .\runner\workflow.ps1 `
        -TaskId "000_template" `
        -WorkflowSpec "test-fixtures/workflows/parallel-review-retry.yaml" `
        -Mode "real" `
        -AllowReal `
        -StepRunnerCommand ".\test-fixtures\fake-workflow-flaky-step-runner.ps1" `
        -StepLogDir $stepLogDir `
        -LogOut $logOut
} finally {
    $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $previousMarkerDir
}

if (-not (Test-Path $logOut)) {
    throw "Expected real retry workflow log was not created: $logOut"
}

$log = Get-Content -Encoding utf8 $logOut -Raw | ConvertFrom-Json

if ($log.output.final_status -ne "real-complete") {
    throw "Expected retry workflow to complete, got $($log.output.final_status)"
}

if ($log.output.retry_policy.max_attempts -ne 2) {
    throw "Expected workflow retry max_attempts 2"
}

$backendAttempts = [int](Get-Content -Encoding utf8 (Join-Path $markerDir "backend-engineer.attempts") -Raw)
if ($backendAttempts -ne 2) {
    throw "Expected backend-engineer to be retried once, got $backendAttempts attempts"
}

$frontendAttempts = [int](Get-Content -Encoding utf8 (Join-Path $markerDir "frontend-engineer.attempts") -Raw)
if ($frontendAttempts -ne 1) {
    throw "Expected frontend-engineer to run once, got $frontendAttempts attempts"
}

$backendStep = @($log.output.step_logs | Where-Object { $_.step_id -eq "backend-engineer" })[0]
if ($backendStep.attempts -ne 2) {
    throw "Expected backend-engineer step log attempts 2, got $($backendStep.attempts)"
}

if (-not ($log.output.PSObject.Properties.Name -contains "retry_attempts")) {
    throw "Expected workflow log to include retry_attempts"
}

$workflowBackendRetryAttempts = @($log.output.retry_attempts | Where-Object { $_.step_id -eq "backend-engineer" })
if ($workflowBackendRetryAttempts.Count -ne 2) {
    throw "Expected workflow log to record 2 backend-engineer retry attempts, got $($workflowBackendRetryAttempts.Count)"
}

if ($workflowBackendRetryAttempts[0].attempt -ne 1 -or $workflowBackendRetryAttempts[0].status -ne "failed") {
    throw "Expected workflow backend-engineer retry attempt 1 to be failed"
}

if ($workflowBackendRetryAttempts[1].attempt -ne 2 -or $workflowBackendRetryAttempts[1].status -ne "succeeded") {
    throw "Expected workflow backend-engineer retry attempt 2 to be succeeded"
}

if (-not ($backendStep.PSObject.Properties.Name -contains "retry_attempts")) {
    throw "Expected backend-engineer step log to include retry_attempts"
}

if (@($backendStep.retry_attempts).Count -ne 2) {
    throw "Expected backend-engineer step log to record 2 retry attempts, got $(@($backendStep.retry_attempts).Count)"
}

if ($backendStep.retry_attempts[0].attempt -ne 1 -or $backendStep.retry_attempts[0].status -ne "failed") {
    throw "Expected backend-engineer step retry attempt 1 to be failed"
}

if ($backendStep.retry_attempts[1].attempt -ne 2 -or $backendStep.retry_attempts[1].status -ne "succeeded") {
    throw "Expected backend-engineer step retry attempt 2 to be succeeded"
}

$backendRunnerLog = Get-Content -Encoding utf8 $backendStep.runner_log -Raw | ConvertFrom-Json
if (-not ($backendRunnerLog.PSObject.Properties.Name -contains "retry_attempts")) {
    throw "Expected backend-engineer runner step log to include retry_attempts"
}

if (@($backendRunnerLog.retry_attempts).Count -ne 2) {
    throw "Expected backend-engineer runner step log to record 2 retry attempts, got $(@($backendRunnerLog.retry_attempts).Count)"
}

$frontendStep = @($log.output.step_logs | Where-Object { $_.step_id -eq "frontend-engineer" })[0]
if ($frontendStep.attempts -ne 1) {
    throw "Expected frontend-engineer step log attempts 1, got $($frontendStep.attempts)"
}

if ($log.output.attempts -ne 1) {
    throw "Expected workflow attempt count to remain 1 for step-level retry, got $($log.output.attempts)"
}

Remove-TestOutput @($logOut, $stepLogDir, $markerDir)

$exhaustionLogOut = "logs/test-workflow-real-retry-exhaustion-000_template.json"
$exhaustionStepLogDir = "logs/test-real-retry-exhaustion-step-logs"
$exhaustionMarkerDir = "logs/test-real-retry-exhaustion-markers"

Remove-TestOutput @($exhaustionLogOut, $exhaustionStepLogDir, $exhaustionMarkerDir)

$env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $exhaustionMarkerDir

try {
    & .\runner\workflow.ps1 `
        -TaskId "000_template" `
        -WorkflowSpec "test-fixtures/workflows/parallel-review-retry.yaml" `
        -Mode "real" `
        -AllowReal `
        -StepRunnerCommand ".\test-fixtures\fake-workflow-failing-step-runner.ps1" `
        -StepLogDir $exhaustionStepLogDir `
        -LogOut $exhaustionLogOut
} finally {
    $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $previousMarkerDir
}

if (-not (Test-Path $exhaustionLogOut)) {
    throw "Expected retry exhaustion workflow log was not created: $exhaustionLogOut"
}

$exhaustionLog = Get-Content -Encoding utf8 $exhaustionLogOut -Raw | ConvertFrom-Json

if ($exhaustionLog.output.final_status -ne "real-failed") {
    throw "Expected retry exhaustion workflow to fail, got $($exhaustionLog.output.final_status)"
}

$exhaustedBackendAttempts = @($exhaustionLog.output.retry_attempts | Where-Object { $_.step_id -eq "backend-engineer" })
if ($exhaustedBackendAttempts.Count -ne 2) {
    throw "Expected retry exhaustion to record 2 backend-engineer attempts, got $($exhaustedBackendAttempts.Count)"
}

if (@($exhaustedBackendAttempts | Where-Object { $_.status -ne "failed" }).Count -ne 0) {
    throw "Expected every backend-engineer exhaustion attempt to fail"
}

$failedBackendStep = @($exhaustionLog.output.failed_steps | Where-Object { $_.step_id -eq "backend-engineer" })[0]
if ($failedBackendStep.attempts -ne 2) {
    throw "Expected failed backend-engineer attempts 2, got $($failedBackendStep.attempts)"
}

if ($failedBackendStep.retry_exhausted -ne $true) {
    throw "Expected failed backend-engineer retry_exhausted true"
}

Remove-TestOutput @($exhaustionLogOut, $exhaustionStepLogDir, $exhaustionMarkerDir)

Write-Output "Real workflow retry test passed."
