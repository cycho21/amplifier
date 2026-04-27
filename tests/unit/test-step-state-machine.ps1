# Unit Tests for Step State Machine
# Tests StepState enum, StepStatus class, and state transition functions

$ErrorActionPreference = "Stop"

# Load the step state machine library
. (Join-Path $PSScriptRoot "..\..\runner\lib\step-state-machine.ps1")

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
Write-Host "=== Step State Machine Unit Tests ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Initialize step statuses
Test-Case "Initialize step statuses" {
    $steps = @(
        @{ id = "step1"; depends_on = @() }
        @{ id = "step2"; depends_on = @("step1") }
    )

    $statuses = Initialize-StepStatuses -Steps $steps

    if ($statuses.Count -ne 2) {
        throw "Expected 2 statuses, got $($statuses.Count)"
    }

    if ($statuses["step1"].State -ne [StepState]::Waiting) {
        throw "Expected Waiting state for step1, got $($statuses['step1'].State)"
    }

    if ($statuses["step2"].State -ne [StepState]::Waiting) {
        throw "Expected Waiting state for step2, got $($statuses['step2'].State)"
    }
}

# Test 2: Step with no dependencies becomes Ready
Test-Case "Step with no dependencies becomes Ready" {
    $steps = @(
        @{ id = "step1"; depends_on = @() }
    )

    $statuses = Initialize-StepStatuses -Steps $steps

    Update-StepReadiness -Statuses $statuses -Steps $steps

    if ($statuses["step1"].State -ne [StepState]::Ready) {
        throw "Expected Ready state for step1, got $($statuses['step1'].State)"
    }
}

# Test 3: Step with completed dependencies becomes Ready
Test-Case "Step with completed dependencies becomes Ready" {
    $steps = @(
        @{ id = "step1"; depends_on = @() }
        @{ id = "step2"; depends_on = @("step1") }
    )

    $statuses = Initialize-StepStatuses -Steps $steps

    # Mark step1 as completed
    Set-StepCompleted -Statuses $statuses -StepId "step1"

    Update-StepReadiness -Statuses $statuses -Steps $steps

    if ($statuses["step2"].State -ne [StepState]::Ready) {
        throw "Expected Ready state for step2, got $($statuses['step2'].State)"
    }
}

# Test 4: Step with failed dependency becomes Blocked
Test-Case "Step with failed dependency becomes Blocked" {
    $steps = @(
        @{ id = "step1"; depends_on = @() }
        @{ id = "step2"; depends_on = @("step1") }
    )

    $statuses = Initialize-StepStatuses -Steps $steps

    # Mark step1 as failed
    Set-StepFailed -Statuses $statuses -StepId "step1" -Error "Test failure"

    Update-StepReadiness -Statuses $statuses -Steps $steps

    if ($statuses["step2"].State -ne [StepState]::Blocked) {
        throw "Expected Blocked state for step2, got $($statuses['step2'].State)"
    }
}

# Test 5: Blocked steps never become Ready
Test-Case "Blocked steps never become Ready" {
    $steps = @(
        @{ id = "step1"; depends_on = @() }
        @{ id = "step2"; depends_on = @("step1") }
    )

    $statuses = Initialize-StepStatuses -Steps $steps

    # Mark step1 as failed
    Set-StepFailed -Statuses $statuses -StepId "step1" -Error "Test failure"

    Update-StepReadiness -Statuses $statuses -Steps $steps

    # Verify step2 is Blocked
    if ($statuses["step2"].State -ne [StepState]::Blocked) {
        throw "Expected Blocked state for step2"
    }

    # Update readiness again (shouldn't change)
    Update-StepReadiness -Statuses $statuses -Steps $steps

    # Should still be Blocked
    if ($statuses["step2"].State -ne [StepState]::Blocked) {
        throw "Blocked step should remain Blocked"
    }
}

# Test 6: Failed step propagates to multiple dependents
Test-Case "Failed step propagates to multiple dependents" {
    $steps = @(
        @{ id = "step1"; depends_on = @() }
        @{ id = "step2"; depends_on = @("step1") }
        @{ id = "step3"; depends_on = @("step1") }
    )

    $statuses = Initialize-StepStatuses -Steps $steps

    # Mark step1 as failed
    Set-StepFailed -Statuses $statuses -StepId "step1" -Error "Test failure"

    Update-StepReadiness -Statuses $statuses -Steps $steps

    # Both dependents should be Blocked
    if ($statuses["step2"].State -ne [StepState]::Blocked) {
        throw "Expected Blocked state for step2"
    }

    if ($statuses["step3"].State -ne [StepState]::Blocked) {
        throw "Expected Blocked state for step3"
    }
}

# Test 7: Get-ReadySteps returns only Ready steps
Test-Case "Get-ReadySteps returns only Ready steps" {
    $steps = @(
        @{ id = "step1"; depends_on = @() }
        @{ id = "step2"; depends_on = @() }
        @{ id = "step3"; depends_on = @("step1") }
    )

    $statuses = Initialize-StepStatuses -Steps $steps

    # Mark step1 as completed
    Set-StepCompleted -Statuses $statuses -StepId "step1"

    $readySteps = Get-ReadySteps -Statuses $statuses -Steps $steps

    # Should return step2 and step3 (both are ready)
    if ($readySteps.Count -ne 2) {
        throw "Expected 2 ready steps, got $($readySteps.Count)"
    }

    $readyIds = $readySteps | ForEach-Object { $_.id }

    if ($readyIds -notcontains "step2") {
        throw "Expected step2 in ready steps"
    }

    if ($readyIds -notcontains "step3") {
        throw "Expected step3 in ready steps"
    }
}

# Test 8: Set-StepRunning updates state and timestamp
Test-Case "Set-StepRunning updates state and timestamp" {
    $steps = @(
        @{ id = "step1"; depends_on = @() }
    )

    $statuses = Initialize-StepStatuses -Steps $steps

    $beforeTime = Get-Date

    Set-StepRunning -Statuses $statuses -StepId "step1"

    if ($statuses["step1"].State -ne [StepState]::Running) {
        throw "Expected Running state, got $($statuses['step1'].State)"
    }

    if ($statuses["step1"].StartedAt -lt $beforeTime) {
        throw "StartedAt timestamp not set correctly"
    }
}

# Test 9: Set-StepCompleted updates state and timestamp
Test-Case "Set-StepCompleted updates state and timestamp" {
    $steps = @(
        @{ id = "step1"; depends_on = @() }
    )

    $statuses = Initialize-StepStatuses -Steps $steps

    Set-StepRunning -Statuses $statuses -StepId "step1"

    $beforeTime = Get-Date

    Set-StepCompleted -Statuses $statuses -StepId "step1"

    if ($statuses["step1"].State -ne [StepState]::Completed) {
        throw "Expected Completed state, got $($statuses['step1'].State)"
    }

    if ($statuses["step1"].CompletedAt -lt $beforeTime) {
        throw "CompletedAt timestamp not set correctly"
    }
}

# Test 10: Set-StepFailed captures error message
Test-Case "Set-StepFailed captures error message" {
    $steps = @(
        @{ id = "step1"; depends_on = @() }
    )

    $statuses = Initialize-StepStatuses -Steps $steps

    $errorMsg = "Test error message"

    Set-StepFailed -Statuses $statuses -StepId "step1" -Error $errorMsg

    if ($statuses["step1"].State -ne [StepState]::Failed) {
        throw "Expected Failed state, got $($statuses['step1'].State)"
    }

    if ($statuses["step1"].Error -ne $errorMsg) {
        throw "Expected error='$errorMsg', got '$($statuses['step1'].Error)'"
    }
}

# Test 11: Complex dependency graph (diamond shape)
Test-Case "Complex dependency graph (diamond shape)" {
    $steps = @(
        @{ id = "start"; depends_on = @() }
        @{ id = "left"; depends_on = @("start") }
        @{ id = "right"; depends_on = @("start") }
        @{ id = "end"; depends_on = @("left", "right") }
    )

    $statuses = Initialize-StepStatuses -Steps $steps

    # Initially, only 'start' should be Ready (after Update-StepReadiness)
    $ready1 = @(Get-ReadySteps -Statuses $statuses -Steps $steps)

    if ($ready1.Count -ne 1) {
        $readyIds = ($ready1 | ForEach-Object { $_.id }) -join ", "
        throw "Expected 1 ready step initially, got $($ready1.Count) ready steps: $readyIds"
    }

    if ($ready1[0].id -ne "start") {
        throw "Expected 'start' to be ready initially, got '$($ready1[0].id)'"
    }

    # Complete 'start'
    Set-StepCompleted -Statuses $statuses -StepId "start"

    # Now 'left' and 'right' should be Ready
    $ready2 = Get-ReadySteps -Statuses $statuses -Steps $steps
    $readyIds2 = $ready2 | ForEach-Object { $_.id }

    if ($ready2.Count -ne 2) {
        throw "Expected 2 ready steps after completing 'start', got $($ready2.Count)"
    }

    if ($readyIds2 -notcontains "left") {
        throw "Expected 'left' to be ready"
    }

    if ($readyIds2 -notcontains "right") {
        throw "Expected 'right' to be ready"
    }

    # Complete 'left' but not 'right'
    Set-StepCompleted -Statuses $statuses -StepId "left"

    # 'end' should still be Waiting (needs both dependencies)
    $ready3 = @(Get-ReadySteps -Statuses $statuses -Steps $steps)

    if ($ready3 | Where-Object { $_.id -eq "end" }) {
        throw "'end' should not be ready until both dependencies complete"
    }

    # Complete 'right'
    Set-StepCompleted -Statuses $statuses -StepId "right"

    # Now 'end' should be Ready
    $ready4 = @(Get-ReadySteps -Statuses $statuses -Steps $steps)

    if ($ready4.Count -ne 1) {
        $ready4Ids = ($ready4 | ForEach-Object { $_.id }) -join ", "
        throw "Expected 1 ready step after all dependencies complete, got $($ready4.Count): $ready4Ids"
    }

    if ($ready4[0].id -ne "end") {
        throw "Expected 'end' to be ready after both dependencies complete, got '$($ready4[0].id)'"
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
