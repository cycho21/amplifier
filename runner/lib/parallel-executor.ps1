# Parallel Executor
# Implements real concurrent execution for workflow steps using PowerShell Jobs

$ErrorActionPreference = "Stop"

# Load dependencies
. (Join-Path $PSScriptRoot "step-state-machine.ps1")
. (Join-Path $PSScriptRoot "retry-policy.ps1")
. (Join-Path $PSScriptRoot "cancellation-token.ps1")

function Invoke-ParallelExecution {
    <#
    .SYNOPSIS
    Executes workflow steps in parallel using PowerShell Jobs

    .PARAMETER Steps
    Array of step objects with id and depends_on fields

    .PARAMETER RetryPolicy
    Retry policy configuration

    .PARAMETER CostTrackingPolicy
    Cost tracking policy configuration

    .PARAMETER MemoryPolicy
    Memory policy configuration

    .PARAMETER Token
    Cancellation token for graceful shutdown

    .PARAMETER WorkflowName
    Name of the workflow being executed

    .PARAMETER TaskId
    Task ID for logging

    .OUTPUTS
    Array of step logs with execution results and step_statuses
    #>
    param(
        [array]$Steps,
        [hashtable]$RetryPolicy,
        [hashtable]$CostTrackingPolicy,
        [hashtable]$MemoryPolicy,
        [CancellationToken]$Token,
        [string]$WorkflowName,
        [string]$TaskId
    )

    # Initialize step statuses using state machine
    $statuses = Initialize-StepStatuses -Steps $Steps
    $stepLogs = @()
    $runningJobs = @{}  # Maps job ID to step ID

    Write-Verbose "Starting parallel execution for $($Steps.Count) steps"

    try {
        # Main execution loop
        while ($true) {
            # Check for cancellation
            if ($Token.IsCancelled) {
                Write-Warning "Cancellation detected, stopping all jobs"

                # Stop all running jobs
                foreach ($job in $runningJobs.Keys) {
                    $jobObj = Get-Job -Id $job -ErrorAction SilentlyContinue
                    if ($jobObj -and $jobObj.State -eq "Running") {
                        Stop-Job -Id $job -ErrorAction SilentlyContinue
                    }
                    Remove-Job -Id $job -ErrorAction SilentlyContinue
                }

                # Mark remaining steps as Cancelled
                foreach ($stepId in $statuses.Keys) {
                    $status = $statuses[$stepId]
                    if ($status.State -in @([StepState]::Waiting, [StepState]::Ready, [StepState]::Running)) {
                        Set-StepCancelled -Statuses $statuses -StepId $stepId
                    }
                }

                throw "Workflow cancelled: $($Token.Reason)"
            }

            # Get ready steps that aren't already running
            $readySteps = Get-ReadySteps -Statuses $statuses -Steps $Steps
            $readySteps = $readySteps | Where-Object {
                $stepId = $_.id
                $status = $statuses[$stepId]
                $status.State -eq [StepState]::Ready
            }

            # Check for stuck state before starting jobs
            if ($readySteps.Count -eq 0 -and $runningJobs.Count -eq 0) {
                # No ready steps and no running jobs - check if all steps are resolved
                $allResolved = $true
                foreach ($stepId in $statuses.Keys) {
                    $state = $statuses[$stepId].State
                    if ($state -notin @([StepState]::Completed, [StepState]::Failed, [StepState]::Blocked, [StepState]::Cancelled)) {
                        $allResolved = $false
                        break
                    }
                }

                if ($allResolved) {
                    Write-Verbose "All steps resolved, execution complete"
                    break
                } else {
                    Write-Warning "No ready steps and no running jobs, but not all steps resolved - possible DAG issue"
                    break
                }
            }

            # Start jobs for ready steps
            foreach ($step in $readySteps) {
                $stepId = $step.id

                Write-Verbose "Starting job for step: $stepId"
                Set-StepRunning -Statuses $statuses -StepId $stepId

                # Calculate absolute paths for libraries
                $retryPolicyPath = Join-Path $PSScriptRoot "retry-policy.ps1"
                $workflowPath = Join-Path (Split-Path $PSScriptRoot -Parent) "workflow.ps1"

                # Create job scriptblock
                $scriptBlock = {
                    param($Step, $RetryPolicy, $CostPolicy, $MemPolicy, $WorkflowName, $TaskId, $RetryPolicyPath, $WorkflowPath)

                    $ErrorActionPreference = "Stop"

                    # Load libraries in job context
                    . $RetryPolicyPath
                    . $WorkflowPath

                    try {
                        # Execute step with retry wrapper
                        $retryResult = Invoke-WithRetryPolicy -Action {
                            param($Attempt)

                            # Call New-StepLog from workflow.ps1
                            New-StepLog -Step $Step -RetryPolicy $RetryPolicy `
                                -CostTrackingPolicy $CostPolicy `
                                -MemoryPolicy $MemPolicy `
                                -WorkflowName $WorkflowName `
                                -TaskId $TaskId
                        } -RetryPolicy $RetryPolicy -StepId $Step.id

                        return @{
                            success = $true
                            log = $retryResult.result
                            attempts = $retryResult.attempts
                        }
                    } catch {
                        return @{
                            success = $false
                            error = $_.Exception.Message
                            attempts = 1
                        }
                    }
                }

                # Start job
                $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList @(
                    $step,
                    $RetryPolicy,
                    $CostTrackingPolicy,
                    $MemoryPolicy,
                    $WorkflowName,
                    $TaskId,
                    $retryPolicyPath,
                    $workflowPath
                )

                $runningJobs[$job.Id] = $stepId
            }

            # Check for completed jobs
            $completedJobs = @()
            foreach ($jobId in $runningJobs.Keys) {
                $job = Get-Job -Id $jobId -ErrorAction SilentlyContinue

                if (-not $job) {
                    $completedJobs += $jobId
                    continue
                }

                if ($job.State -in @("Completed", "Failed", "Stopped")) {
                    $stepId = $runningJobs[$jobId]

                    try {
                        if ($job.State -eq "Completed") {
                            $result = Receive-Job -Id $jobId -ErrorAction Stop

                            if ($result.success) {
                                # Step succeeded
                                Set-StepCompleted -Statuses $statuses -StepId $stepId
                                $stepLogs += $result.log
                                Write-Verbose "Step $stepId completed successfully"
                            } else {
                                # Step failed
                                Set-StepFailed -Statuses $statuses -StepId $stepId -Error $result.error
                                Write-Warning "Step $stepId failed: $($result.error)"
                            }
                        } else {
                            # Job failed or stopped
                            $error = if ($job.State -eq "Failed") {
                                $jobError = Receive-Job -Id $jobId -ErrorAction SilentlyContinue
                                if ($jobError) { $jobError.ToString() } else { "Job failed" }
                            } else {
                                "Job stopped"
                            }
                            Set-StepFailed -Statuses $statuses -StepId $stepId -Error $error
                            Write-Warning "Step $stepId failed: $error"
                        }
                    } catch {
                        Set-StepFailed -Statuses $statuses -StepId $stepId -Error $_.Exception.Message
                        Write-Warning "Step $stepId failed: $($_.Exception.Message)"
                    }

                    Remove-Job -Id $jobId -ErrorAction SilentlyContinue
                    $completedJobs += $jobId
                }
            }

            # Remove completed jobs from tracking
            foreach ($jobId in $completedJobs) {
                $runningJobs.Remove($jobId)
            }

            # Wait before next poll
            Start-Sleep -Milliseconds 100
        }

        # Build step_statuses for output
        $stepStatuses = @{}
        foreach ($stepId in $statuses.Keys) {
            $status = $statuses[$stepId]
            $stepStatuses[$stepId] = @{
                state = $status.State.ToString()
                attempts = $status.Attempts
                error = $status.Error
                started_at = if ($status.StartedAt) { $status.StartedAt.ToString("o") } else { $null }
                completed_at = if ($status.CompletedAt) { $status.CompletedAt.ToString("o") } else { $null }
            }
        }

        return @{
            step_logs = $stepLogs
            step_statuses = $stepStatuses
        }

    } catch {
        # Cleanup on error
        foreach ($jobId in $runningJobs.Keys) {
            $job = Get-Job -Id $jobId -ErrorAction SilentlyContinue
            if ($job -and $job.State -eq "Running") {
                Stop-Job -Id $jobId -ErrorAction SilentlyContinue
            }
            Remove-Job -Id $jobId -ErrorAction SilentlyContinue
        }
        throw
    }
}

# Functions are available when dot-sourced with:
# . .\runner\lib\parallel-executor.ps1
