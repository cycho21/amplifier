# Integration Tests for Real Parallel Execution
# Tests concurrent execution with PowerShell Jobs

$ErrorActionPreference = "Stop"

# Load the parallel executor library
. (Join-Path $PSScriptRoot "..\..\runner\lib\parallel-executor.ps1")
. (Join-Path $PSScriptRoot "..\..\runner\workflow.ps1")

$passCount = 0
$failCount = 0

function Test-Case {
    param(
        [string]$Name,
        [scriptblock]$Test
    )

    try {
        & $Test
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:passCount++
    } catch {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        $script:failCount++
    }
}

Write-Host ""
Write-Host "=== Real Parallel Execution Integration Tests ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Independent steps run concurrently
Test-Case "Independent steps run concurrently" {
    $steps = @(
        @{
            id = "step1"
            role = "tester"
            depends_on = @()
            provider = "dry-run"
            instructions = "Test step 1"
        }
        @{
            id = "step2"
            role = "tester"
            depends_on = @()
            provider = "dry-run"
            instructions = "Test step 2"
        }
    )

    $retryPolicy = @{
        enabled = $false
        max_attempts = 1
        backoff_strategy = "none"
        retry_on = @()
    }

    $costPolicy = @{
        enabled = $false
        currency = "USD"
    }

    $memoryPolicy = @{
        enabled = $false
        persistence = "dry-run"
        scope = "workflow"
        path = ""
        overwrite = "merge"
    }

    $token = New-CancellationToken

    $result = Invoke-ParallelExecution -Steps $steps `
        -RetryPolicy $retryPolicy `
        -CostTrackingPolicy $costPolicy `
        -MemoryPolicy $memoryPolicy `
        -Token $token `
        -WorkflowName "test-workflow" `
        -TaskId "001"

    # Both steps should complete
    if ($result.step_statuses["step1"].state -ne "Completed") {
        throw "Expected step1 Completed, got $($result.step_statuses['step1'].state)"
    }

    if ($result.step_statuses["step2"].state -ne "Completed") {
        throw "Expected step2 Completed, got $($result.step_statuses['step2'].state)"
    }

    # Should have 2 step logs
    if ($result.step_logs.Count -ne 2) {
        throw "Expected 2 step logs, got $($result.step_logs.Count)"
    }
}

# Test 2: Dependent step waits for prerequisite
Test-Case "Dependent step waits for prerequisite" {
    $steps = @(
        @{
            id = "step1"
            role = "tester"
            depends_on = @()
            provider = "dry-run"
            instructions = "First step"
        }
        @{
            id = "step2"
            role = "tester"
            depends_on = @("step1")
            provider = "dry-run"
            instructions = "Second step"
        }
    )

    $retryPolicy = @{
        enabled = $false
        max_attempts = 1
        backoff_strategy = "none"
        retry_on = @()
    }

    $costPolicy = @{
        enabled = $false
        currency = "USD"
    }

    $memoryPolicy = @{
        enabled = $false
        persistence = "dry-run"
        scope = "workflow"
        path = ""
        overwrite = "merge"
    }

    $token = New-CancellationToken

    $result = Invoke-ParallelExecution -Steps $steps `
        -RetryPolicy $retryPolicy `
        -CostTrackingPolicy $costPolicy `
        -MemoryPolicy $memoryPolicy `
        -Token $token `
        -WorkflowName "test-workflow" `
        -TaskId "002"

    # Both steps should complete
    if ($result.step_statuses["step1"].state -ne "Completed") {
        throw "Expected step1 Completed, got $($result.step_statuses['step1'].state)"
    }

    if ($result.step_statuses["step2"].state -ne "Completed") {
        throw "Expected step2 Completed, got $($result.step_statuses['step2'].state)"
    }

    # step2 should start after step1
    $step1Start = [datetime]$result.step_statuses["step1"].started_at
    $step2Start = [datetime]$result.step_statuses["step2"].started_at

    if ($step2Start -lt $step1Start) {
        throw "Step2 should not start before step1"
    }
}

# Test 3: Diamond dependency graph
Test-Case "Diamond dependency graph executes correctly" {
    $steps = @(
        @{
            id = "start"
            role = "tester"
            depends_on = @()
            provider = "dry-run"
            instructions = "Start"
        }
        @{
            id = "left"
            role = "tester"
            depends_on = @("start")
            provider = "dry-run"
            instructions = "Left branch"
        }
        @{
            id = "right"
            role = "tester"
            depends_on = @("start")
            provider = "dry-run"
            instructions = "Right branch"
        }
        @{
            id = "end"
            role = "tester"
            depends_on = @("left", "right")
            provider = "dry-run"
            instructions = "End"
        }
    )

    $retryPolicy = @{
        enabled = $false
        max_attempts = 1
        backoff_strategy = "none"
        retry_on = @()
    }

    $costPolicy = @{
        enabled = $false
        currency = "USD"
    }

    $memoryPolicy = @{
        enabled = $false
        persistence = "dry-run"
        scope = "workflow"
        path = ""
        overwrite = "merge"
    }

    $token = New-CancellationToken

    $result = Invoke-ParallelExecution -Steps $steps `
        -RetryPolicy $retryPolicy `
        -CostTrackingPolicy $costPolicy `
        -MemoryPolicy $memoryPolicy `
        -Token $token `
        -WorkflowName "test-workflow" `
        -TaskId "003"

    # All steps should complete
    foreach ($stepId in @("start", "left", "right", "end")) {
        if ($result.step_statuses[$stepId].state -ne "Completed") {
            throw "Expected $stepId Completed, got $($result.step_statuses[$stepId].state)"
        }
    }

    # Verify execution order
    $startTime = [datetime]$result.step_statuses["start"].started_at
    $leftTime = [datetime]$result.step_statuses["left"].started_at
    $rightTime = [datetime]$result.step_statuses["right"].started_at
    $endTime = [datetime]$result.step_statuses["end"].started_at

    # Left and right should start after start
    if ($leftTime -lt $startTime) {
        throw "Left should not start before start"
    }
    if ($rightTime -lt $startTime) {
        throw "Right should not start before start"
    }

    # End should start after both left and right complete
    $leftComplete = [datetime]$result.step_statuses["left"].completed_at
    $rightComplete = [datetime]$result.step_statuses["right"].completed_at

    if ($endTime -lt $leftComplete -or $endTime -lt $rightComplete) {
        throw "End should not start before left and right complete"
    }
}

# Test 4: Step statuses include timestamps and attempts
Test-Case "Step statuses include timestamps and attempts" {
    $steps = @(
        @{
            id = "step1"
            role = "tester"
            depends_on = @()
            provider = "dry-run"
            instructions = "Test"
        }
    )

    $retryPolicy = @{
        enabled = $false
        max_attempts = 1
        backoff_strategy = "none"
        retry_on = @()
    }

    $costPolicy = @{
        enabled = $false
        currency = "USD"
    }

    $memoryPolicy = @{
        enabled = $false
        persistence = "dry-run"
        scope = "workflow"
        path = ""
        overwrite = "merge"
    }

    $token = New-CancellationToken

    $result = Invoke-ParallelExecution -Steps $steps `
        -RetryPolicy $retryPolicy `
        -CostTrackingPolicy $costPolicy `
        -MemoryPolicy $memoryPolicy `
        -Token $token `
        -WorkflowName "test-workflow" `
        -TaskId "004"

    $status = $result.step_statuses["step1"]

    # Check required fields
    if (-not $status.started_at) {
        throw "Missing started_at timestamp"
    }

    if (-not $status.completed_at) {
        throw "Missing completed_at timestamp"
    }

    if (-not $status.ContainsKey("attempts")) {
        throw "Missing attempts field"
    }

    if (-not $status.ContainsKey("state")) {
        throw "Missing state field"
    }
}

# Test 5: Result includes step_logs and step_statuses
Test-Case "Result includes step_logs and step_statuses" {
    $steps = @(
        @{
            id = "step1"
            role = "tester"
            depends_on = @()
            provider = "dry-run"
            instructions = "Test"
        }
    )

    $retryPolicy = @{
        enabled = $false
        max_attempts = 1
        backoff_strategy = "none"
        retry_on = @()
    }

    $costPolicy = @{
        enabled = $false
        currency = "USD"
    }

    $memoryPolicy = @{
        enabled = $false
        persistence = "dry-run"
        scope = "workflow"
        path = ""
        overwrite = "merge"
    }

    $token = New-CancellationToken

    $result = Invoke-ParallelExecution -Steps $steps `
        -RetryPolicy $retryPolicy `
        -CostTrackingPolicy $costPolicy `
        -MemoryPolicy $memoryPolicy `
        -Token $token `
        -WorkflowName "test-workflow" `
        -TaskId "005"

    # Check required fields in result
    if (-not $result.ContainsKey("step_logs")) {
        throw "Result missing step_logs"
    }

    if (-not $result.ContainsKey("step_statuses")) {
        throw "Result missing step_statuses"
    }

    if ($result.step_logs.Count -ne 1) {
        throw "Expected 1 step log, got $($result.step_logs.Count)"
    }

    if ($result.step_statuses.Count -ne 1) {
        throw "Expected 1 step status, got $($result.step_statuses.Count)"
    }
}

# Summary
Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "  Passed: $passCount" -ForegroundColor Green
Write-Host "  Failed: $failCount" -ForegroundColor Red
Write-Host ""

if ($failCount -gt 0) {
    exit 1
} else {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
}
