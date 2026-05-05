# Integration Tests for Retry Policy
# Tests Invoke-WithRetryPolicy and error classification

$ErrorActionPreference = "Stop"

# Load the retry policy library
. (Join-Path $PSScriptRoot "..\..\runner\lib\retry-policy.ps1")

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
Write-Host "=== Retry Policy Integration Tests ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Successful execution on first attempt
Test-Case "Successful execution on first attempt" {
    $policy = @{
        max_attempts = 3
        retry_on = @("runner-error")
        backoff = "none"
    }

    $result = Invoke-WithRetryPolicy -Action {
        param($Attempt)
        return @{ data = "success" }
    } -RetryPolicy $policy -StepId "test-step"

    if ($result.attempts -ne 1) {
        throw "Expected 1 attempt, got $($result.attempts)"
    }

    if ($result.final_status -ne "success") {
        throw "Expected success status, got $($result.final_status)"
    }
}

# Test 2: Retry on transient error and succeed on second attempt
Test-Case "Retry on transient error, succeed on second attempt" {
    $policy = @{
        max_attempts = 3
        retry_on = @("transient")
        backoff = "none"
    }

    $result = Invoke-WithRetryPolicy -Action {
        param($Attempt)

        if ($Attempt -eq 1) {
            throw "Transient error: rate limit"
        }

        return @{ data = "success on attempt 2" }
    } -RetryPolicy $policy -StepId "test-step"

    if ($result.attempts -ne 2) {
        throw "Expected 2 attempts, got $($result.attempts)"
    }

    if ($result.final_status -ne "success") {
        throw "Expected success status, got $($result.final_status)"
    }
}

# Test 3: Retry exhaustion after max_attempts
Test-Case "Retry exhaustion after max_attempts" {
    $policy = @{
        max_attempts = 2
        retry_on = @("runner-error")
        backoff = "none"
    }

    $errorThrown = $false
    $errorMessage = ""

    try {
        Invoke-WithRetryPolicy -Action {
            param($Attempt)
            throw "Persistent failure"
        } -RetryPolicy $policy -StepId "test-step"
    } catch {
        $errorThrown = $true
        $errorMessage = $_.Exception.Message

        if ($errorMessage -notmatch "failed after 2 attempts") {
            throw "Expected 'failed after 2 attempts' in error message, got: $errorMessage"
        }
    }

    if (-not $errorThrown) {
        throw "Expected exception after max_attempts"
    }

    # Extract attempt count from error message
    if ($errorMessage -match "failed after (\d+) attempts") {
        $attemptCount = [int]$Matches[1]
        if ($attemptCount -ne 2) {
            throw "Expected 2 attempts in error message, got $attemptCount"
        }
    } else {
        throw "Could not parse attempt count from error message: $errorMessage"
    }
}

# Test 4: Non-retryable error fails immediately
Test-Case "Non-retryable error fails immediately" {
    $policy = @{
        max_attempts = 3
        retry_on = @("transient")  # Only retry transient errors
        backoff = "none"
    }

    $errorThrown = $false
    $errorMessage = ""

    try {
        Invoke-WithRetryPolicy -Action {
            param($Attempt)
            throw "Permanent error: invalid API key"
        } -RetryPolicy $policy -StepId "test-step"
    } catch {
        $errorThrown = $true
        $errorMessage = $_.Exception.Message

        if ($errorMessage -notmatch "Non-retryable error") {
            throw "Expected 'Non-retryable error' in message, got: $errorMessage"
        }
    }

    if (-not $errorThrown) {
        throw "Expected exception for non-retryable error"
    }

    # For non-retryable errors, should fail immediately without retry
    # Error message doesn't include attempt count, so we verify it says "Non-retryable"
    if ($errorMessage -notmatch "permanent") {
        throw "Expected 'permanent' error type in message: $errorMessage"
    }
}

# Test 5: Backoff strategy - linear
Test-Case "Backoff strategy: linear" {
    $delay = Get-BackoffDelay -Attempt 1 -Strategy "linear"
    if ($delay -ne 2) {
        throw "Expected 2s delay, got ${delay}s"
    }

    $delay = Get-BackoffDelay -Attempt 2 -Strategy "linear"
    if ($delay -ne 4) {
        throw "Expected 4s delay, got ${delay}s"
    }

    $delay = Get-BackoffDelay -Attempt 3 -Strategy "linear"
    if ($delay -ne 6) {
        throw "Expected 6s delay, got ${delay}s"
    }
}

# Test 6: Backoff strategy - exponential
Test-Case "Backoff strategy: exponential" {
    $delay = Get-BackoffDelay -Attempt 1 -Strategy "exponential"
    if ($delay -ne 2) {
        throw "Expected 2s delay (2^1), got ${delay}s"
    }

    $delay = Get-BackoffDelay -Attempt 2 -Strategy "exponential"
    if ($delay -ne 4) {
        throw "Expected 4s delay (2^2), got ${delay}s"
    }

    $delay = Get-BackoffDelay -Attempt 3 -Strategy "exponential"
    if ($delay -ne 8) {
        throw "Expected 8s delay (2^3), got ${delay}s"
    }
}

# Test 7: Backoff strategy - none
Test-Case "Backoff strategy: none" {
    $delay = Get-BackoffDelay -Attempt 1 -Strategy "none"
    if ($delay -ne 0) {
        throw "Expected 0s delay, got ${delay}s"
    }

    $delay = Get-BackoffDelay -Attempt 5 -Strategy "none"
    if ($delay -ne 0) {
        throw "Expected 0s delay, got ${delay}s"
    }
}

# Test 8: Error classification - transient
Test-Case "Error classification: transient" {
    $error = [Exception]::new("Transient error: rate limit exceeded")
    $errorType = Get-ErrorClassification -Exception $error

    if ($errorType -ne "transient") {
        throw "Expected 'transient', got '$errorType'"
    }
}

# Test 9: Error classification - timeout
Test-Case "Error classification: timeout" {
    $error = [Exception]::new("Request timed out after 600 seconds")
    $errorType = Get-ErrorClassification -Exception $error

    if ($errorType -ne "timeout") {
        throw "Expected 'timeout', got '$errorType'"
    }
}

# Test 10: Error classification - permanent
Test-Case "Error classification: permanent" {
    $error = [Exception]::new("Permanent error: invalid API key")
    $errorType = Get-ErrorClassification -Exception $error

    if ($errorType -ne "permanent") {
        throw "Expected 'permanent', got '$errorType'"
    }
}

# Test 11: Test-Retryable function
Test-Case "Test-Retryable: retryable error type" {
    $policy = @{ retry_on = @("transient", "timeout") }

    if (-not (Test-Retryable -ErrorType "transient" -RetryPolicy $policy)) {
        throw "Expected 'transient' to be retryable"
    }

    if (-not (Test-Retryable -ErrorType "timeout" -RetryPolicy $policy)) {
        throw "Expected 'timeout' to be retryable"
    }

    if (Test-Retryable -ErrorType "permanent" -RetryPolicy $policy) {
        throw "Expected 'permanent' to not be retryable"
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
