# Retry Policy Implementation
# Wraps step execution with retry logic based on workflow retry policy

$ErrorActionPreference = "Stop"

function Invoke-WithRetryPolicy {
    <#
    .SYNOPSIS
    Wraps step execution with retry loop

    .PARAMETER Action
    Scriptblock to execute (receives attempt number as parameter)

    .PARAMETER RetryPolicy
    Retry policy hashtable with max_attempts, retry_on, backoff

    .PARAMETER StepId
    Step identifier for logging

    .OUTPUTS
    Hashtable with result, attempts, final_status
    #>
    param(
        [scriptblock]$Action,
        [hashtable]$RetryPolicy,
        [string]$StepId
    )

    $maxAttempts = $RetryPolicy.max_attempts
    $backoff = $RetryPolicy.backoff
    $retryOn = $RetryPolicy.retry_on

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Write-Verbose "[$StepId] Attempt $attempt of $maxAttempts"

            $result = & $Action $attempt

            return @{
                result = $result
                attempts = $attempt
                final_status = "success"
            }
        } catch {
            $errorType = Get-ErrorClassification -Exception $_

            Write-Verbose "[$StepId] Error classified as: $errorType"

            # Check if max attempts reached
            if ($attempt -ge $maxAttempts) {
                Write-Warning "[$StepId] Failed after $attempt attempts: $_"
                throw "Step failed after $attempt attempts: $_"
            }

            # Check if error is retryable
            if (-not (Test-Retryable -ErrorType $errorType -RetryPolicy $RetryPolicy)) {
                Write-Warning "[$StepId] Non-retryable error ($errorType): $_"
                throw "Non-retryable error ($errorType): $_"
            }

            # Calculate backoff delay
            $waitSeconds = Get-BackoffDelay -Attempt $attempt -Strategy $backoff

            if ($waitSeconds -gt 0) {
                Write-Warning "[$StepId] Attempt $attempt failed ($errorType): $_. Retrying in $waitSeconds seconds..."
                Start-Sleep -Seconds $waitSeconds
            } else {
                Write-Warning "[$StepId] Attempt $attempt failed ($errorType): $_. Retrying immediately..."
            }
        }
    }
}

function Get-ErrorClassification {
    <#
    .SYNOPSIS
    Classifies exceptions as transient/permanent/timeout/parse-error

    .PARAMETER Exception
    Exception object to classify

    .OUTPUTS
    String: error type (transient, permanent, timeout, parse-error, runner-error)
    #>
    param($Exception)

    # Handle both string messages and exception objects
    $message = if ($Exception -is [string]) {
        $Exception
    } elseif ($null -ne $Exception.Message) {
        $Exception.Message
    } else {
        $Exception.ToString()
    }

    $messageLower = $message.ToLower()

    # Permanent errors (check first - more specific)
    if ($messageLower -match "permanent error|invalid api key|authentication failed") {
        return "permanent"
    }

    # Transient errors (from HTTP status codes and rate limits)
    if ($messageLower -match "transient error|rate limit|5\d{2}") {
        return "transient"
    }

    # Timeout errors
    if ($messageLower -match "timeout|timed out") {
        return "timeout"
    }

    # JSON parsing errors
    if ($messageLower -match "parse|json|convertfrom-json") {
        return "parse-error"
    }

    # API key missing
    if ($messageLower -match "api_key|environment variable") {
        return "permanent"
    }

    # Default to runner-error for unknown failures
    return "runner-error"
}

function Test-Retryable {
    <#
    .SYNOPSIS
    Checks if error type is in retry_on list

    .PARAMETER ErrorType
    Error type from Get-ErrorClassification

    .PARAMETER RetryPolicy
    Retry policy hashtable

    .OUTPUTS
    Boolean: true if retryable, false otherwise
    #>
    param(
        [string]$ErrorType,
        [hashtable]$RetryPolicy
    )

    return $RetryPolicy.retry_on -contains $ErrorType
}

function Get-BackoffDelay {
    <#
    .SYNOPSIS
    Calculates wait time based on strategy (none/linear/exponential)

    .PARAMETER Attempt
    Current attempt number (1-indexed)

    .PARAMETER Strategy
    Backoff strategy: none, linear, exponential, fixed

    .OUTPUTS
    Integer: seconds to wait before next attempt
    #>
    param(
        [int]$Attempt,
        [string]$Strategy
    )

    switch ($Strategy) {
        "none" {
            return 0
        }
        "linear" {
            # 2s, 4s, 6s, 8s...
            return $Attempt * 2
        }
        "exponential" {
            # 2^1=2s, 2^2=4s, 2^3=8s, 2^4=16s...
            return [Math]::Pow(2, $Attempt)
        }
        "fixed" {
            # Constant 5s delay
            return 5
        }
        default {
            Write-Warning "Unknown backoff strategy: $Strategy. Using 'none'."
            return 0
        }
    }
}

# Functions are available when dot-sourced with:
# . .\runner\lib\retry-policy.ps1
