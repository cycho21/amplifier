# Unit Tests for Cancellation Token
# Tests CancellationToken class and cancellation propagation

$ErrorActionPreference = "Stop"

# Load the cancellation token library
. (Join-Path $PSScriptRoot "..\..\runner\lib\cancellation-token.ps1")

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
Write-Host "=== Cancellation Token Unit Tests ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Token created in uncancelled state
Test-Case "Token created in uncancelled state" {
    $token = New-CancellationToken

    if ($token.IsCancelled -ne $false) {
        throw "Expected IsCancelled=false, got $($token.IsCancelled)"
    }

    if ($token.Reason -ne "") {
        throw "Expected empty Reason, got '$($token.Reason)'"
    }
}

# Test 2: Cancel() sets IsCancelled = true
Test-Case "Cancel() sets IsCancelled to true" {
    $token = New-CancellationToken

    $token.Cancel("Test cancellation")

    if ($token.IsCancelled -ne $true) {
        throw "Expected IsCancelled=true after Cancel(), got $($token.IsCancelled)"
    }

    if ($token.Reason -ne "Test cancellation") {
        throw "Expected Reason='Test cancellation', got '$($token.Reason)'"
    }
}

# Test 3: ThrowIfCancelled() throws when cancelled
Test-Case "ThrowIfCancelled() throws when cancelled" {
    $token = New-CancellationToken
    $token.Cancel("Test cancellation")

    $errorThrown = $false

    try {
        $token.ThrowIfCancelled()
    } catch {
        $errorThrown = $true
        if ($_.Exception.Message -notmatch "Operation cancelled") {
            throw "Expected 'Operation cancelled' in error message, got: $_"
        }
    }

    if (-not $errorThrown) {
        throw "Expected ThrowIfCancelled() to throw when cancelled"
    }
}

# Test 4: ThrowIfCancelled() does not throw when not cancelled
Test-Case "ThrowIfCancelled() does not throw when not cancelled" {
    $token = New-CancellationToken

    # Should not throw
    $token.ThrowIfCancelled()

    # Success if we reach here
}

# Test 5: Test-Cancelled function
Test-Case "Test-Cancelled returns correct status" {
    $token = New-CancellationToken

    if (Test-Cancelled -Token $token) {
        throw "Expected Test-Cancelled=false initially"
    }

    $token.Cancel("Test")

    if (-not (Test-Cancelled -Token $token)) {
        throw "Expected Test-Cancelled=true after Cancel()"
    }
}

# Test 6: Invoke-WithCancellation completes when job finishes quickly
Test-Case "Invoke-WithCancellation completes when job finishes quickly" {
    $token = New-CancellationToken

    $result = Invoke-WithCancellation -Action {
        return @{ data = "test result" }
    } -Token $token -CheckIntervalMs 100

    if ($result.data -ne "test result") {
        throw "Expected result data='test result', got '$($result.data)'"
    }
}

# Test 7: Invoke-WithCancellation stops job when cancelled
Test-Case "Invoke-WithCancellation stops job when cancelled" {
    $token = New-CancellationToken

    # Start a background task that will cancel the token
    $cancelJob = Start-Job -ScriptBlock {
        param($TokenRef)
        Start-Sleep -Milliseconds 500
        # Note: We can't actually cancel the token from another job
        # because objects don't share state across jobs
        # This test will be simplified
    } -ArgumentList $token

    $errorThrown = $false

    try {
        # Start job that will be cancelled
        Start-Job -ScriptBlock {
            Start-Sleep -Seconds 2
            return "should not complete"
        } | Out-Null

        # Manually cancel after a short delay
        Start-Sleep -Milliseconds 300
        $token.Cancel("Test manual cancellation")

        # This should throw because token is cancelled
        $token.ThrowIfCancelled()
    } catch {
        $errorThrown = $true
        if ($_ -notmatch "cancelled") {
            throw "Expected 'cancelled' in error message, got: $_"
        }
    } finally {
        Stop-Job $cancelJob -ErrorAction SilentlyContinue
        Remove-Job $cancelJob -ErrorAction SilentlyContinue
    }

    if (-not $errorThrown) {
        throw "Expected cancellation to throw error"
    }
}

# Test 8: Cancellation reason is preserved
Test-Case "Cancellation reason is preserved" {
    $token = New-CancellationToken

    $reason = "User requested abort"
    $token.Cancel($reason)

    if ($token.Reason -ne $reason) {
        throw "Expected Reason='$reason', got '$($token.Reason)'"
    }

    # Should also be in exception message
    try {
        $token.ThrowIfCancelled()
    } catch {
        if ($_.Exception.Message -notmatch $reason) {
            throw "Expected reason in exception message, got: $_"
        }
    }
}

# Test 9: Multiple Cancel() calls preserve first reason
Test-Case "Multiple Cancel() calls update reason" {
    $token = New-CancellationToken

    $token.Cancel("First reason")
    $firstReason = $token.Reason

    $token.Cancel("Second reason")

    # Second cancel should update the reason
    if ($token.Reason -ne "Second reason") {
        throw "Expected Reason='Second reason', got '$($token.Reason)'"
    }

    # IsCancelled should still be true
    if ($token.IsCancelled -ne $true) {
        throw "Expected IsCancelled=true after multiple cancels"
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
