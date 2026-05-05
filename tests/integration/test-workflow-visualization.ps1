# Integration Tests for Workflow Visualization
# Tests visualization functions for dependency graphs and progress display

$ErrorActionPreference = "Stop"

# Load the libraries
. (Join-Path $PSScriptRoot "..\..\runner\lib\workflow-validator.ps1")
. (Join-Path $PSScriptRoot "..\..\runner\lib\workflow-visualizer.ps1")

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
Write-Host "=== Workflow Visualization Integration Tests ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Get-ProgressSymbol returns correct symbols
Test-Case "Get-ProgressSymbol returns correct symbols" {
    $symbols = @{
        "waiting" = "[ ]"
        "running" = "[►]"
        "completed" = "[✓]"
        "failed" = "[✗]"
        "retrying" = "[⟳]"
    }

    foreach ($status in $symbols.Keys) {
        $symbol = Get-ProgressSymbol -Status $status
        if ($symbol -ne $symbols[$status]) {
            throw "Expected symbol '$($symbols[$status])' for status '$status', got '$symbol'"
        }
    }
}

# Test 2: Show-DependencyGraph displays without errors
Test-Case "Show-DependencyGraph displays simple graph" {
    $steps = @(
        @{ id = "backend"; depends_on = @() }
        @{ id = "frontend"; depends_on = @() }
        @{ id = "tester"; depends_on = @("backend", "frontend") }
    )

    # Capture output to verify function runs
    $output = Show-DependencyGraph -Steps $steps *>&1

    # If we get here without throwing, test passes
}

# Test 3: Show-DependencyGraph handles single step
Test-Case "Show-DependencyGraph handles single-step workflow" {
    $steps = @(
        @{ id = "solo"; depends_on = @() }
    )

    $output = Show-DependencyGraph -Steps $steps *>&1
    # Success if no exception thrown
}

# Test 4: Show-ValidationResult displays valid workflow
Test-Case "Show-ValidationResult displays valid workflow" {
    $validation = @{
        valid = $true
        errors = @()
    }

    $output = Show-ValidationResult -Validation $validation *>&1
    # Success if no exception thrown
}

# Test 5: Show-ValidationResult displays invalid workflow
Test-Case "Show-ValidationResult displays invalid workflow with errors" {
    $validation = @{
        valid = $false
        errors = @(
            [ordered]@{
                type = "cycle"
                path = @("A", "B", "A")
                message = "Cycle detected: A → B → A"
            }
        )
    }

    $output = Show-ValidationResult -Validation $validation *>&1
    # Success if no exception thrown
}

# Test 6: Show-StepProgress displays step in compact mode
Test-Case "Show-StepProgress displays step in compact mode" {
    $step = @{
        id = "test-step"
        status = "completed"
        elapsed = 3.5
    }

    $output = Show-StepProgress -Step $step -Mode "compact" *>&1
    # Success if no exception thrown
}

# Test 7: Show-StepProgress displays step in detailed mode with stages
Test-Case "Show-StepProgress displays step in detailed mode" {
    $step = @{
        id = "test-step"
        status = "running"
        elapsed = 1.5
        stages = @(
            @{ name = "Reading task"; status = "completed"; elapsed = 0.1 }
            @{ name = "Invoking LLM"; status = "running"; elapsed = 1.4 }
            @{ name = "Parsing response"; status = "waiting" }
        )
    }

    $output = Show-StepProgress -Step $step -Mode "detailed" *>&1
    # Success if no exception thrown
}

# Test 8: Show-StepStages displays stages correctly
Test-Case "Show-StepStages displays stage list" {
    $stages = @(
        @{ name = "Stage 1"; status = "completed"; elapsed = 0.5 }
        @{ name = "Stage 2"; status = "running"; elapsed = 1.0 }
        @{ name = "Stage 3"; status = "waiting" }
    )

    $output = Show-StepStages -Stages $stages *>&1
    # Success if no exception thrown
}

# Test 9: Show-WorkflowProgress displays workflow in compact mode
Test-Case "Show-WorkflowProgress displays workflow in compact mode" {
    $workflow = @{
        name = "test-workflow"
        mode = "sequential"
        steps = @(
            @{ id = "step1"; status = "completed"; elapsed = 2.0 }
            @{ id = "step2"; status = "running"; elapsed = 1.0 }
            @{ id = "step3"; status = "waiting" }
        )
    }

    $output = Show-WorkflowProgress -Workflow $workflow -Mode "compact" *>&1
    # Success if no exception thrown
}

# Test 10: Show-WorkflowProgress displays workflow in detailed mode
Test-Case "Show-WorkflowProgress displays workflow in detailed mode" {
    $workflow = @{
        name = "test-workflow"
        mode = "parallel"
        steps = @(
            @{
                id = "step1"
                status = "running"
                elapsed = 1.5
                stages = @(
                    @{ name = "Reading"; status = "completed"; elapsed = 0.2 }
                    @{ name = "Processing"; status = "running"; elapsed = 1.3 }
                )
            }
        )
    }

    $output = Show-WorkflowProgress -Workflow $workflow -Mode "detailed" *>&1
    # Success if no exception thrown
}

# Test 11: Integration test - Full validation and visualization flow
Test-Case "Full validation and visualization flow" {
    $steps = @(
        @{ id = "architect"; depends_on = @() }
        @{ id = "implementer"; depends_on = @("architect") }
        @{ id = "tester"; depends_on = @("implementer") }
    )

    # Validate
    $validation = Test-WorkflowDependencies -Steps $steps

    if (-not $validation.valid) {
        throw "Expected valid workflow"
    }

    # Visualize dependency graph
    $output1 = Show-DependencyGraph -Steps $steps *>&1

    # Visualize validation result
    $output2 = Show-ValidationResult -Validation $validation *>&1

    # Success if we get here
}

# Test 12: Progress symbols for all statuses
Test-Case "Progress symbols for all known statuses" {
    $statuses = @("waiting", "running", "completed", "failed", "retrying")

    foreach ($status in $statuses) {
        $symbol = Get-ProgressSymbol -Status $status
        if ([string]::IsNullOrEmpty($symbol)) {
            throw "Symbol for status '$status' is null or empty"
        }
    }

    # Unknown status should return default
    $unknownSymbol = Get-ProgressSymbol -Status "unknown"
    if ($unknownSymbol -ne "[ ]") {
        throw "Unknown status should return '[ ]', got '$unknownSymbol'"
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
