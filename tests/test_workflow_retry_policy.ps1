$ErrorActionPreference = "Stop"

$logOut = "logs/test-workflow-retry-policy-000_template.json"

& .\runner\workflow.ps1 `
    -TaskId "000_template" `
    -WorkflowSpec "workflows/implementation-review.yaml" `
    -LogOut $logOut

if (-not (Test-Path $logOut)) {
    throw "Expected workflow log was not created: $logOut"
}

$log = Get-Content -Encoding utf8 $logOut -Raw | ConvertFrom-Json

foreach ($field in @("retry_policy", "attempts")) {
    if (-not ($log.output.PSObject.Properties.Name -contains $field)) {
        throw "Missing workflow retry field '$field'"
    }
}

if ($log.output.retry_policy.max_attempts -ne 2) {
    throw "Expected max_attempts 2, got $($log.output.retry_policy.max_attempts)"
}

if ($log.output.retry_policy.backoff -ne "none") {
    throw "Expected backoff none, got $($log.output.retry_policy.backoff)"
}

if (@($log.output.retry_policy.retry_on) -notcontains "runner-error") {
    throw "Expected retry_on to include runner-error"
}

if ($log.output.attempts -ne 1) {
    throw "Expected dry-run workflow attempts 1, got $($log.output.attempts)"
}

foreach ($stepLog in $log.output.step_logs) {
    foreach ($field in @("retry_policy", "attempts")) {
        if (-not ($stepLog.PSObject.Properties.Name -contains $field)) {
            throw "Missing step retry field '$field' in step $($stepLog.role)"
        }
    }

    if ($stepLog.retry_policy.max_attempts -ne 2) {
        throw "Expected step max_attempts 2 for $($stepLog.role)"
    }

    if ($stepLog.attempts -ne 1) {
        throw "Expected dry-run step attempts 1 for $($stepLog.role)"
    }
}

Write-Output "Workflow retry policy test passed."
