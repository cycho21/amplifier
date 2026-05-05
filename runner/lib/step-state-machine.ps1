# Step State Machine
# Manages step lifecycle states and failure propagation

$ErrorActionPreference = "Stop"

enum StepState {
    Waiting      # Not ready (dependencies incomplete)
    Ready        # All dependencies met, can start
    Running      # Currently executing
    Completed    # Successfully finished
    Failed       # Execution failed
    Blocked      # Dependency failed, cannot run
    Cancelled    # Workflow cancelled
}

class StepStatus {
    [string]$StepId
    [StepState]$State
    [int]$Attempts
    [string]$Error
    [datetime]$StartedAt
    [datetime]$CompletedAt

    StepStatus([string]$stepId) {
        $this.StepId = $stepId
        $this.State = [StepState]::Waiting
        $this.Attempts = 0
        $this.Error = ""
    }
}

function Initialize-StepStatuses {
    <#
    .SYNOPSIS
    Initializes step status objects for all steps

    .PARAMETER Steps
    Array of step objects with id and depends_on fields

    .OUTPUTS
    Hashtable mapping step ID to StepStatus object
    #>
    param([array]$Steps)

    $statuses = @{}

    foreach ($step in $Steps) {
        $statuses[$step.id] = [StepStatus]::new($step.id)
    }

    return $statuses
}

function Update-StepReadiness {
    <#
    .SYNOPSIS
    Updates step states based on dependency completion

    .PARAMETER Statuses
    Hashtable of step statuses

    .PARAMETER Steps
    Array of step objects with dependencies

    .OUTPUTS
    None (modifies statuses in place)
    #>
    param(
        [hashtable]$Statuses,
        [array]$Steps
    )

    foreach ($step in $Steps) {
        $status = $Statuses[$step.id]

        # Only update Waiting steps
        if ($status.State -ne [StepState]::Waiting) {
            continue
        }

        $allDependenciesMet = $true
        $anyDependencyFailed = $false

        # Check each dependency
        foreach ($depId in $step.depends_on) {
            $depStatus = $Statuses[$depId]

            if ($depStatus.State -eq [StepState]::Failed) {
                $anyDependencyFailed = $true
                break
            }

            if ($depStatus.State -ne [StepState]::Completed) {
                $allDependenciesMet = $false
            }
        }

        # Update state based on dependencies
        if ($anyDependencyFailed) {
            $status.State = [StepState]::Blocked
            Write-Verbose "Step $($step.id) blocked due to failed dependency"
        } elseif ($allDependenciesMet) {
            $status.State = [StepState]::Ready
            Write-Verbose "Step $($step.id) ready to run"
        }
    }
}

function Get-ReadySteps {
    <#
    .SYNOPSIS
    Gets all steps that are ready to execute

    .PARAMETER Statuses
    Hashtable of step statuses

    .PARAMETER Steps
    Array of step objects

    .OUTPUTS
    Array of steps in Ready state
    #>
    param(
        [hashtable]$Statuses,
        [array]$Steps
    )

    # Update readiness first
    Update-StepReadiness -Statuses $Statuses -Steps $Steps

    # Filter to Ready steps
    return $Steps | Where-Object {
        $Statuses[$_.id].State -eq [StepState]::Ready
    }
}

function Set-StepRunning {
    <#
    .SYNOPSIS
    Marks a step as running

    .PARAMETER Statuses
    Hashtable of step statuses

    .PARAMETER StepId
    Step ID to mark as running

    .OUTPUTS
    None (modifies statuses in place)
    #>
    param(
        [hashtable]$Statuses,
        [string]$StepId
    )

    $status = $Statuses[$StepId]
    $status.State = [StepState]::Running
    $status.StartedAt = Get-Date

    Write-Verbose "Step $StepId started"
}

function Set-StepCompleted {
    <#
    .SYNOPSIS
    Marks a step as completed

    .PARAMETER Statuses
    Hashtable of step statuses

    .PARAMETER StepId
    Step ID to mark as completed

    .OUTPUTS
    None (modifies statuses in place)
    #>
    param(
        [hashtable]$Statuses,
        [string]$StepId
    )

    $status = $Statuses[$StepId]
    $status.State = [StepState]::Completed
    $status.CompletedAt = Get-Date

    Write-Verbose "Step $StepId completed"
}

function Set-StepFailed {
    <#
    .SYNOPSIS
    Marks a step as failed

    .PARAMETER Statuses
    Hashtable of step statuses

    .PARAMETER StepId
    Step ID to mark as failed

    .PARAMETER Error
    Error message

    .OUTPUTS
    None (modifies statuses in place)
    #>
    param(
        [hashtable]$Statuses,
        [string]$StepId,
        [string]$Error
    )

    $status = $Statuses[$StepId]
    $status.State = [StepState]::Failed
    $status.Error = $Error
    $status.CompletedAt = Get-Date

    Write-Verbose "Step $StepId failed: $Error"
}

function Set-StepCancelled {
    <#
    .SYNOPSIS
    Marks a step as cancelled

    .PARAMETER Statuses
    Hashtable of step statuses

    .PARAMETER StepId
    Step ID to mark as cancelled

    .OUTPUTS
    None (modifies statuses in place)
    #>
    param(
        [hashtable]$Statuses,
        [string]$StepId
    )

    $status = $Statuses[$StepId]
    $status.State = [StepState]::Cancelled
    $status.CompletedAt = Get-Date

    Write-Verbose "Step $StepId cancelled"
}

function Get-StepStatus {
    <#
    .SYNOPSIS
    Gets the status of a step

    .PARAMETER Statuses
    Hashtable of step statuses

    .PARAMETER StepId
    Step ID to query

    .OUTPUTS
    StepStatus object
    #>
    param(
        [hashtable]$Statuses,
        [string]$StepId
    )

    return $Statuses[$StepId]
}

# Functions are available when dot-sourced with:
# . .\runner\lib\step-state-machine.ps1
