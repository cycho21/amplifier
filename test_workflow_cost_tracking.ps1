$ErrorActionPreference = "Stop"

$logOut = "logs/test-workflow-cost-tracking-000_template.json"

& .\runner\workflow.ps1 `
    -TaskId "000_template" `
    -WorkflowSpec "workflows/implementation-review.yaml" `
    -LogOut $logOut

if (-not (Test-Path $logOut)) {
    throw "Expected workflow log was not created: $logOut"
}

$log = Get-Content -Encoding utf8 $logOut -Raw | ConvertFrom-Json

if (-not ($log.output.PSObject.Properties.Name -contains "cost_tracking")) {
    throw "Missing workflow cost_tracking output"
}

$cost = $log.output.cost_tracking

foreach ($field in @("enabled", "currency", "unit", "estimated_total_cost", "step_costs")) {
    if (-not ($cost.PSObject.Properties.Name -contains $field)) {
        throw "Missing workflow cost tracking field '$field'"
    }
}

if ($cost.enabled -ne $true) {
    throw "Expected cost tracking enabled true"
}

if ($cost.currency -ne "USD") {
    throw "Expected currency USD, got $($cost.currency)"
}

if ($cost.unit -ne "dry-run-estimate") {
    throw "Expected unit dry-run-estimate, got $($cost.unit)"
}

if ($cost.estimated_total_cost -ne 0) {
    throw "Expected dry-run estimated_total_cost 0, got $($cost.estimated_total_cost)"
}

$stepCosts = @($cost.step_costs)

if ($stepCosts.Count -ne $log.output.step_logs.Count) {
    throw "Expected one step cost entry per step log"
}

foreach ($stepLog in $log.output.step_logs) {
    if (-not ($stepLog.PSObject.Properties.Name -contains "cost_tracking")) {
        throw "Missing step cost_tracking field in step $($stepLog.role)"
    }

    if ($stepLog.cost_tracking.estimated_cost -ne 0) {
        throw "Expected dry-run step estimated_cost 0 for $($stepLog.role)"
    }
}

Write-Output "Workflow cost tracking test passed."
