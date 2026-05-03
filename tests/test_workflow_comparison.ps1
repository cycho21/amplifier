$ErrorActionPreference = "Stop"

$logOut = "logs/test-workflow-comparison-000_template.json"

& .\runner\workflow.ps1 `
    -TaskId "000_template" `
    -WorkflowSpec "workflows/parallel-review.yaml" `
    -LogOut $logOut

if (-not (Test-Path $logOut)) {
    throw "Expected workflow log was not created: $logOut"
}

$log = Get-Content -Encoding utf8 $logOut -Raw | ConvertFrom-Json

if (-not ($log.output.PSObject.Properties.Name -contains "comparison")) {
    throw "Missing workflow comparison output"
}

$comparison = $log.output.comparison

foreach ($field in @("required_fields", "required_fields_by_step", "missing_required_fields", "status")) {
    if (-not ($comparison.PSObject.Properties.Name -contains $field)) {
        throw "Missing comparison field '$field'"
    }
}

$expectedFields = @("summary", "changed_files", "verification_result", "risks", "next_steps")
$actualFields = @($comparison.required_fields)

foreach ($field in $expectedFields) {
    if ($actualFields -notcontains $field) {
        throw "Comparison required_fields does not include '$field'"
    }
}

$stepComparisons = @($comparison.required_fields_by_step)

if ($stepComparisons.Count -ne $log.output.step_logs.Count) {
    throw "Expected comparison entry per step log"
}

foreach ($stepComparison in $stepComparisons) {
    foreach ($field in @("step_id", "role", "present_fields", "missing_fields")) {
        if (-not ($stepComparison.PSObject.Properties.Name -contains $field)) {
            throw "Missing step comparison field '$field'"
        }
    }

    if (@($stepComparison.missing_fields).Count -ne 0) {
        throw "Expected no missing fields for step $($stepComparison.step_id)"
    }
}

if (@($comparison.missing_required_fields).Count -ne 0) {
    throw "Expected no missing required fields"
}

if ($comparison.status -ne "all-required-fields-present") {
    throw "Expected comparison status all-required-fields-present, got $($comparison.status)"
}

Write-Output "Workflow comparison test passed."
