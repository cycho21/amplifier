# Integration Tests for Workflow Validation
# Tests Test-WorkflowDependencies and Find-DependencyCycles functions

$ErrorActionPreference = "Stop"

# Load the validator
. (Join-Path $PSScriptRoot "..\..\runner\lib\workflow-validator.ps1")

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
Write-Host "=== Workflow Validation Integration Tests ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Valid workflow passes
Test-Case "Valid workflow passes all checks" {
    $steps = @(
        @{ id = "A"; depends_on = @() }
        @{ id = "B"; depends_on = @("A") }
        @{ id = "C"; depends_on = @("A", "B") }
    )

    $result = Test-WorkflowDependencies -Steps $steps

    if (-not $result.valid) {
        throw "Expected valid workflow, but validation failed"
    }

    if ($result.errors.Count -ne 0) {
        throw "Expected no errors, but got $($result.errors.Count)"
    }
}

# Test 2: Simple cycle detection (A → B → A)
Test-Case "Detects simple cycle A → B → A" {
    $steps = @(
        @{ id = "A"; depends_on = @("B") }
        @{ id = "B"; depends_on = @("A") }
    )

    $result = Test-WorkflowDependencies -Steps $steps

    if ($result.valid) {
        throw "Expected invalid workflow, but validation passed"
    }

    $cycleError = $result.errors | Where-Object { $_.type -eq "cycle" }
    if (-not $cycleError) {
        throw "Expected cycle error, but none found"
    }

    if ($cycleError.path -notcontains "A" -or $cycleError.path -notcontains "B") {
        throw "Cycle path missing expected steps"
    }
}

# Test 3: Three-node cycle (A → B → C → A)
Test-Case "Detects three-node cycle A → B → C → A" {
    $steps = @(
        @{ id = "A"; depends_on = @("C") }
        @{ id = "B"; depends_on = @("A") }
        @{ id = "C"; depends_on = @("B") }
    )

    $result = Test-WorkflowDependencies -Steps $steps

    if ($result.valid) {
        throw "Expected invalid workflow, but validation passed"
    }

    $cycleError = $result.errors | Where-Object { $_.type -eq "cycle" }
    if (-not $cycleError) {
        throw "Expected cycle error, but none found"
    }
}

# Test 4: Self-dependency detection
Test-Case "Detects self-dependency" {
    $steps = @(
        @{ id = "A"; depends_on = @("A") }
    )

    $result = Test-WorkflowDependencies -Steps $steps

    if ($result.valid) {
        throw "Expected invalid workflow, but validation passed"
    }

    $selfDepError = $result.errors | Where-Object { $_.type -eq "self_dependency" }
    if (-not $selfDepError) {
        throw "Expected self-dependency error, but none found"
    }

    if ($selfDepError.step -ne "A") {
        throw "Self-dependency error has wrong step ID"
    }
}

# Test 5: Invalid dependency detection
Test-Case "Detects invalid dependency (missing step)" {
    $steps = @(
        @{ id = "A"; depends_on = @("NONEXISTENT") }
    )

    $result = Test-WorkflowDependencies -Steps $steps

    if ($result.valid) {
        throw "Expected invalid workflow, but validation passed"
    }

    $invalidDepError = $result.errors | Where-Object { $_.type -eq "invalid_dependency" }
    if (-not $invalidDepError) {
        throw "Expected invalid dependency error, but none found"
    }

    if ($invalidDepError.step -ne "A") {
        throw "Invalid dependency error has wrong step ID"
    }

    if ($invalidDepError.dependency -ne "NONEXISTENT") {
        throw "Invalid dependency error has wrong dependency ID"
    }
}

# Test 6: Empty workflow detection
Test-Case "Detects empty workflow" {
    $steps = @()

    $result = Test-WorkflowDependencies -Steps $steps

    if ($result.valid) {
        throw "Expected invalid workflow, but validation passed"
    }

    $emptyError = $result.errors | Where-Object { $_.type -eq "empty_workflow" }
    if (-not $emptyError) {
        throw "Expected empty workflow error, but none found"
    }
}

# Test 7: Multiple errors reported
Test-Case "Reports multiple errors (self-dep + cycle)" {
    $steps = @(
        @{ id = "A"; depends_on = @("A", "B") }
        @{ id = "B"; depends_on = @("A") }
    )

    $result = Test-WorkflowDependencies -Steps $steps

    if ($result.valid) {
        throw "Expected invalid workflow, but validation passed"
    }

    # Should have at least self-dependency error
    $selfDepError = $result.errors | Where-Object { $_.type -eq "self_dependency" }
    if (-not $selfDepError) {
        throw "Expected self-dependency error, but none found"
    }

    # Should also detect cycle
    $cycleError = $result.errors | Where-Object { $_.type -eq "cycle" }
    if (-not $cycleError) {
        throw "Expected cycle error, but none found"
    }
}

# Test 8: Complex valid graph (diamond shape)
Test-Case "Validates complex diamond-shaped graph" {
    $steps = @(
        @{ id = "start"; depends_on = @() }
        @{ id = "left"; depends_on = @("start") }
        @{ id = "right"; depends_on = @("start") }
        @{ id = "end"; depends_on = @("left", "right") }
    )

    $result = Test-WorkflowDependencies -Steps $steps

    if (-not $result.valid) {
        throw "Expected valid workflow, but validation failed: $($result.errors | ConvertTo-Json)"
    }
}

# Test 9: Error message format
Test-Case "Error messages contain required fields" {
    $steps = @(
        @{ id = "A"; depends_on = @("B") }
        @{ id = "B"; depends_on = @("A") }
    )

    $result = Test-WorkflowDependencies -Steps $steps

    foreach ($error in $result.errors) {
        if (-not $error["type"]) {
            throw "Error missing 'type' field"
        }

        if (-not $error["message"]) {
            throw "Error missing 'message' field"
        }

        if ($error.type -eq "cycle" -and -not $error["path"]) {
            throw "Cycle error missing 'path' field"
        }
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
