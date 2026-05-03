$ErrorActionPreference = "Stop"

$logOut = "logs/test-workflow-implementation-review-000_template.json"

& .\runner\workflow.ps1 `
    -TaskId "000_template" `
    -WorkflowSpec "workflows/implementation-review.yaml" `
    -LogOut $logOut

if (-not (Test-Path $logOut)) {
    throw "Expected workflow log was not created: $logOut"
}

$log = Get-Content -Encoding utf8 $logOut -Raw | ConvertFrom-Json
$workflowSpec = Get-Content -Encoding utf8 "workflows/implementation-review.yaml" -Raw

if ($log.runner -ne "workflow-dry-run") {
    throw "Expected runner workflow-dry-run, got $($log.runner)"
}

if ($log.workflow -ne "implementation-review") {
    throw "Expected workflow implementation-review, got $($log.workflow)"
}

$expectedSteps = @("architect", "implementer", "tester", "reviewer")
$actualSteps = @($log.output.step_logs | ForEach-Object { $_.role })

if ($actualSteps.Count -ne $expectedSteps.Count) {
    throw "Expected $($expectedSteps.Count) steps, got $($actualSteps.Count)"
}

for ($i = 0; $i -lt $expectedSteps.Count; $i++) {
    if ($actualSteps[$i] -ne $expectedSteps[$i]) {
        throw "Expected step $i to be $($expectedSteps[$i]), got $($actualSteps[$i])"
    }
}

foreach ($stepLog in $log.output.step_logs) {
    foreach ($field in @("summary", "changed_files", "verification_result", "risks", "next_steps")) {
        if (-not ($stepLog.output.PSObject.Properties.Name -contains $field)) {
            throw "Missing required output field '$field' in step $($stepLog.role)"
        }
    }
}

foreach ($field in @("workflow_summary", "step_logs", "final_status", "risks", "next_steps")) {
    if (-not ($log.output.PSObject.Properties.Name -contains $field)) {
        throw "Missing required workflow output field '$field'"
    }
}

$completedSteps = @{}
foreach ($step in $log.output.step_logs) {
    $stepBlockPattern = "(?ms)  - id:\s*$($step.step_id)\s*.*?(?=^  - id:|\z)"
    $stepBlockMatch = [regex]::Match($workflowSpec, $stepBlockPattern)

    if (-not $stepBlockMatch.Success) {
        throw "Could not find workflow spec block for step $($step.step_id)"
    }

    $dependencyMatches = [regex]::Matches($stepBlockMatch.Value, "(?m)^\s{6}-\s*(\S+)\s*$")

    foreach ($dependencyMatch in $dependencyMatches) {
        $dependency = $dependencyMatch.Groups[1].Value

        if (-not $completedSteps.ContainsKey($dependency)) {
            throw "Step $($step.step_id) depends on $dependency before it is complete"
        }
    }

    $completedSteps[$step.step_id] = $true
}

if ($log.output.final_status -ne "dry-run-complete") {
    throw "Expected final_status dry-run-complete, got $($log.output.final_status)"
}

Write-Output "Workflow runner test passed."
