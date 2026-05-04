$ErrorActionPreference = "Stop"

$logOut = "logs/test-workflow-parallel-review-000_template.json"
$repeatLogOut = "logs/test-workflow-parallel-review-repeat-000_template.json"

function Get-ParallelGroupSignature {
    param($Log)

    return (@($Log.output.parallel_groups) | ForEach-Object {
        $stepIds = @($_.steps | ForEach-Object { $_.step_id })
        "$($_.group):$($stepIds -join ',')"
    }) -join "|"
}

foreach ($path in @($logOut, $repeatLogOut)) {
    if (Test-Path $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

& .\runner\workflow.ps1 `
    -TaskId "000_template" `
    -WorkflowSpec "workflows/parallel-review.yaml" `
    -Mode "dry-run" `
    -AllowReal `
    -StepRunnerCommand ".\test-fixtures\fail-if-invoked-codex.ps1" `
    -LogOut $logOut

& .\runner\workflow.ps1 `
    -TaskId "000_template" `
    -WorkflowSpec "workflows/parallel-review.yaml" `
    -Mode "dry-run" `
    -AllowReal `
    -StepRunnerCommand ".\test-fixtures\fail-if-invoked-codex.ps1" `
    -LogOut $repeatLogOut

if (-not (Test-Path $logOut)) {
    throw "Expected parallel workflow log was not created: $logOut"
}

$log = Get-Content -Encoding utf8 $logOut -Raw | ConvertFrom-Json
$repeatLog = Get-Content -Encoding utf8 $repeatLogOut -Raw | ConvertFrom-Json

if ($log.runner -ne "workflow-dry-run") {
    throw "Expected runner workflow-dry-run, got $($log.runner)"
}

if ($log.workflow -ne "parallel-review") {
    throw "Expected workflow parallel-review, got $($log.workflow)"
}

if ($log.output.execution_mode -ne "parallel") {
    throw "Expected execution_mode parallel, got $($log.output.execution_mode)"
}

if (-not ($log.output.PSObject.Properties.Name -contains "parallel_groups")) {
    throw "Missing required parallel_groups field"
}

$groups = @($log.output.parallel_groups)

if ($groups.Count -ne 2) {
    throw "Expected 2 parallel groups, got $($groups.Count)"
}

$firstGroupStepIds = @($groups[0].steps | ForEach-Object { $_.step_id })
$secondGroupStepIds = @($groups[1].steps | ForEach-Object { $_.step_id })

if (($firstGroupStepIds -join ",") -ne "backend-engineer,frontend-engineer") {
    throw "Expected deterministic first group order, got '$($firstGroupStepIds -join ",")'"
}

if (($secondGroupStepIds -join ",") -ne "tester,reviewer") {
    throw "Expected deterministic second group order, got '$($secondGroupStepIds -join ",")'"
}

if ((Get-ParallelGroupSignature $log) -ne (Get-ParallelGroupSignature $repeatLog)) {
    throw "Expected repeated dry-run parallel grouping to be deterministic"
}

$firstGroupRoles = @($groups[0].steps | ForEach-Object { $_.role })
$secondGroupRoles = @($groups[1].steps | ForEach-Object { $_.role })

foreach ($role in @("backend-engineer", "frontend-engineer")) {
    if ($firstGroupRoles -notcontains $role) {
        throw "Expected first parallel group to contain $role"
    }
}

foreach ($role in @("tester", "reviewer")) {
    if ($secondGroupRoles -notcontains $role) {
        throw "Expected second parallel group to contain $role"
    }
}

foreach ($stepLog in $log.output.step_logs) {
    foreach ($field in @("summary", "changed_files", "verification_result", "risks", "next_steps")) {
        if (-not ($stepLog.output.PSObject.Properties.Name -contains $field)) {
            throw "Missing required output field '$field' in step $($stepLog.role)"
        }
    }
}

if ($log.output.final_status -ne "dry-run-complete") {
    throw "Expected final_status dry-run-complete, got $($log.output.final_status)"
}

if (Test-Path $repeatLogOut) {
    Remove-Item -LiteralPath $repeatLogOut -Force
}

Write-Output "Parallel workflow runner test passed."
