# Integration Tests for Cost Tracking
# Tests Get-StepCost and Get-WorkflowTotalCost functions

$ErrorActionPreference = "Stop"

# Load the cost calculator library
. (Join-Path $PSScriptRoot "..\..\runner\lib\cost-calculator.ps1")

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
Write-Host "=== Cost Tracking Integration Tests ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: No metadata returns 0 cost
Test-Case "No metadata returns 0 cost" {
    $cost = Get-StepCost -ProviderMetadata @{} -Currency "USD"

    if ($cost -ne 0) {
        throw "Expected 0 cost for empty metadata, got $cost"
    }
}

# Test 2: GPT-4 cost calculation
Test-Case "GPT-4 cost calculation" {
    $metadata = @{
        model = "gpt-4"
        prompt_tokens = 1000
        completion_tokens = 500
    }

    $cost = Get-StepCost -ProviderMetadata $metadata -Currency "USD"

    # Expected: (1000/33333) + (500/16667) = 0.03 + 0.03 = 0.06
    $expected = 0.06
    $tolerance = 0.001

    if ([Math]::Abs($cost - $expected) -gt $tolerance) {
        throw "Expected cost ~$expected, got $cost"
    }
}

# Test 3: GPT-3.5-turbo cost calculation (cheaper model)
Test-Case "GPT-3.5-turbo cost calculation" {
    $metadata = @{
        model = "gpt-3.5-turbo"
        prompt_tokens = 1000
        completion_tokens = 500
    }

    $cost = Get-StepCost -ProviderMetadata $metadata -Currency "USD"

    # Expected: (1000/200000) + (500/100000) = 0.005 + 0.005 = 0.01
    $expected = 0.01
    $tolerance = 0.001

    if ([Math]::Abs($cost - $expected) -gt $tolerance) {
        throw "Expected cost ~$expected, got $cost"
    }
}

# Test 4: Unknown model returns 0 with warning
Test-Case "Unknown model returns 0 cost" {
    $metadata = @{
        model = "gpt-unknown"
        prompt_tokens = 1000
        completion_tokens = 500
    }

    $cost = Get-StepCost -ProviderMetadata $metadata -Currency "USD"

    if ($cost -ne 0) {
        throw "Expected 0 cost for unknown model, got $cost"
    }
}

# Test 5: Missing tokens returns 0 cost
Test-Case "Missing token counts returns 0 cost" {
    $metadata = @{
        model = "gpt-4"
        # No token counts
    }

    $cost = Get-StepCost -ProviderMetadata $metadata -Currency "USD"

    if ($cost -ne 0) {
        throw "Expected 0 cost when tokens missing, got $cost"
    }
}

# Test 6: Partial token counts (only prompt_tokens)
Test-Case "Partial token counts (only prompt_tokens)" {
    $metadata = @{
        model = "gpt-4"
        prompt_tokens = 1000
        # No completion_tokens
    }

    $cost = Get-StepCost -ProviderMetadata $metadata -Currency "USD"

    # Expected: (1000/33333) + 0 = 0.03
    $expected = 0.03
    $tolerance = 0.001

    if ([Math]::Abs($cost - $expected) -gt $tolerance) {
        throw "Expected cost ~$expected, got $cost"
    }
}

# Test 7: Workflow total cost aggregation
Test-Case "Workflow total cost aggregation" {
    $stepCosts = @(
        @{ step_id = "step1"; estimated_cost = 0.05 }
        @{ step_id = "step2"; estimated_cost = 0.03 }
        @{ step_id = "step3"; estimated_cost = 0.02 }
    )

    $total = Get-WorkflowTotalCost -StepCosts $stepCosts

    # Expected: 0.05 + 0.03 + 0.02 = 0.10
    $expected = 0.10
    $tolerance = 0.001

    if ([Math]::Abs($total - $expected) -gt $tolerance) {
        throw "Expected total cost ~$expected, got $total"
    }
}

# Test 8: Empty step costs returns 0
Test-Case "Empty step costs returns 0" {
    $stepCosts = @()

    $total = Get-WorkflowTotalCost -StepCosts $stepCosts

    if ($total -ne 0) {
        throw "Expected 0 total for empty steps, got $total"
    }
}

# Test 9: Large token counts (realistic scenario)
Test-Case "Large token counts (realistic scenario)" {
    $metadata = @{
        model = "gpt-4"
        prompt_tokens = 8000   # Large context
        completion_tokens = 2000  # Long response
    }

    $cost = Get-StepCost -ProviderMetadata $metadata -Currency "USD"

    # Expected: (8000/33333) + (2000/16667) = 0.24 + 0.12 = 0.36
    $expected = 0.36
    $tolerance = 0.01

    if ([Math]::Abs($cost - $expected) -gt $tolerance) {
        throw "Expected cost ~$expected, got $cost"
    }
}

# Test 10: Cost precision (6 decimal places)
Test-Case "Cost precision (6 decimal places)" {
    $metadata = @{
        model = "gpt-4"
        prompt_tokens = 1
        completion_tokens = 1
    }

    $cost = Get-StepCost -ProviderMetadata $metadata -Currency "USD"

    # Check that result has at most 6 decimal places
    $costStr = $cost.ToString("F6")
    $roundTrip = [double]$costStr

    if ($roundTrip -ne $cost) {
        throw "Cost not properly rounded to 6 decimal places: $cost"
    }
}

# Test 11: Claude Sonnet pricing
Test-Case "Claude Sonnet cost calculation" {
    $metadata = @{
        model = "claude-sonnet-4-5"
        prompt_tokens = 1000
        completion_tokens = 500
    }

    $cost = Get-StepCost -ProviderMetadata $metadata -Currency "USD"

    # Should calculate cost even though Claude CLI doesn't expose tokens
    # (this tests the pricing table entry exists)
    if ($cost -le 0) {
        throw "Expected positive cost for Claude Sonnet, got $cost"
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
