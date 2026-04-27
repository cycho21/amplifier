# Cancellation Token
# Provides graceful cancellation mechanism for long-running operations

$ErrorActionPreference = "Stop"

class CancellationToken {
    [bool]$IsCancelled = $false
    [string]$Reason = ""

    [void]Cancel([string]$reason) {
        $this.IsCancelled = $true
        $this.Reason = $reason
        Write-Warning "Cancellation requested: $reason"
    }

    [void]ThrowIfCancelled() {
        if ($this.IsCancelled) {
            throw "Operation cancelled: $($this.Reason)"
        }
    }
}

function New-CancellationToken {
    <#
    .SYNOPSIS
    Creates a new cancellation token

    .OUTPUTS
    CancellationToken object
    #>

    return [CancellationToken]::new()
}

function Test-Cancelled {
    <#
    .SYNOPSIS
    Tests if a cancellation token is cancelled

    .PARAMETER Token
    CancellationToken to test

    .OUTPUTS
    Boolean: true if cancelled, false otherwise
    #>
    param([CancellationToken]$Token)

    return $Token.IsCancelled
}

function Invoke-WithCancellation {
    <#
    .SYNOPSIS
    Wraps job execution with periodic cancellation checks

    .PARAMETER Action
    Scriptblock to execute as a background job

    .PARAMETER Token
    CancellationToken to monitor

    .PARAMETER CheckIntervalMs
    How often to check for cancellation (milliseconds)

    .OUTPUTS
    Job result or throws if cancelled
    #>
    param(
        [scriptblock]$Action,
        [CancellationToken]$Token,
        [int]$CheckIntervalMs = 500
    )

    $job = Start-Job -ScriptBlock $Action

    try {
        while ($job.State -eq "Running") {
            # Check for cancellation
            if ($Token.IsCancelled) {
                Write-Verbose "Cancellation detected, stopping job"
                Stop-Job $job
                Remove-Job $job
                throw "Job cancelled: $($Token.Reason)"
            }

            # Wait before next check
            Start-Sleep -Milliseconds $CheckIntervalMs
        }

        # Job completed naturally
        $result = Receive-Job $job -ErrorAction Stop
        Remove-Job $job

        return $result
    } catch {
        # Cleanup on error
        if ($job.State -eq "Running") {
            Stop-Job $job
        }
        Remove-Job $job -ErrorAction SilentlyContinue
        throw
    }
}

# Functions are available when dot-sourced with:
# . .\runner\lib\cancellation-token.ps1
