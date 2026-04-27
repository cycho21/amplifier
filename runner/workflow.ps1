param(
    [string]$TaskId = "000_template",
    [string]$WorkflowSpec = "workflows/implementation-review.yaml",
    [string]$LogOut = "logs/20260426-workflow-implementation-review-000_template.json",
    [switch]$RealExecution = $false
)

$ErrorActionPreference = "Stop"

# Load libraries
. (Join-Path $PSScriptRoot "lib/retry-policy.ps1")
. (Join-Path $PSScriptRoot "lib/cost-calculator.ps1")
. (Join-Path $PSScriptRoot "lib/memory-manager.ps1")
. (Join-Path $PSScriptRoot "lib/parallel-executor.ps1")

function Read-Utf8File {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Required input file not found: $Path"
    }

    return Get-Content -Encoding utf8 $Path -Raw
}

function Get-ScalarValue {
    param(
        [string[]]$Lines,
        [string]$Key
    )

    foreach ($line in $Lines) {
        if ($line -match "^$Key\s*:\s*(.+)$") {
            return $Matches[1].Trim().Trim('"')
        }
    }

    throw "Required workflow field not found: $Key"
}

function Resolve-TaskToken {
    param(
        [string]$Value,
        [string]$TaskId
    )

    return $Value.Replace("{task_id}", $TaskId).Trim('"')
}

function Read-WorkflowSteps {
    param(
        [string[]]$Lines,
        [string]$TaskId
    )

    $steps = @()
    $current = $null
    $dependsOnMode = $false

    foreach ($line in $Lines) {
        if ($line -match "^\s{2}- id:\s*(.+)$") {
            if ($null -ne $current) {
                $steps += $current
            }

            $current = [ordered]@{
                id = $Matches[1].Trim().Trim('"')
                role = ""
                agent_role = ""
                execution_spec = ""
                task_id = $TaskId
                depends_on = @()
            }
            $dependsOnMode = $false
            continue
        }

        if ($null -eq $current) {
            continue
        }

        if ($line -match "^\s{4}role:\s*(.+)$") {
            $current.role = $Matches[1].Trim().Trim('"')
            $dependsOnMode = $false
            continue
        }

        if ($line -match "^\s{4}agent_role:\s*(.+)$") {
            $current.agent_role = Resolve-TaskToken $Matches[1].Trim() $TaskId
            $dependsOnMode = $false
            continue
        }

        if ($line -match "^\s{4}execution_spec:\s*(.+)$") {
            $current.execution_spec = Resolve-TaskToken $Matches[1].Trim() $TaskId
            $dependsOnMode = $false
            continue
        }

        if ($line -match "^\s{4}task_id:\s*(.+)$") {
            $current.task_id = Resolve-TaskToken $Matches[1].Trim() $TaskId
            $dependsOnMode = $false
            continue
        }

        if ($line -match "^\s{4}depends_on:\s*\[\]\s*$") {
            $current.depends_on = @()
            $dependsOnMode = $false
            continue
        }

        if ($line -match "^\s{4}depends_on:\s*$") {
            $current.depends_on = @()
            $dependsOnMode = $true
            continue
        }

        if ($dependsOnMode -and $line -match "^\s{6}-\s*(.+)$") {
            $current.depends_on += $Matches[1].Trim().Trim('"')
            continue
        }

        if ($line -match "^\s{2}-\s+\w") {
            $dependsOnMode = $false
        }
    }

    if ($null -ne $current) {
        $steps += $current
    }

    if ($steps.Count -eq 0) {
        throw "Workflow contains no steps: $WorkflowSpec"
    }

    return $steps
}

function Read-RetryPolicy {
    param([string[]]$Lines)

    $policy = [ordered]@{
        max_attempts = 1
        retry_on = @()
        backoff = "none"
    }
    $inRetry = $false
    $inRetryOn = $false

    foreach ($line in $Lines) {
        if ($line -match "^retry:\s*$") {
            $inRetry = $true
            $inRetryOn = $false
            continue
        }

        if (-not $inRetry) {
            continue
        }

        if ($line -match "^\S") {
            break
        }

        if ($line -match "^\s{2}max_attempts:\s*(\d+)\s*$") {
            $policy.max_attempts = [int]$Matches[1]
            $inRetryOn = $false
            continue
        }

        if ($line -match "^\s{2}retry_on:\s*$") {
            $policy.retry_on = @()
            $inRetryOn = $true
            continue
        }

        if ($line -match "^\s{2}backoff:\s*(.+)$") {
            $policy.backoff = $Matches[1].Trim().Trim('"')
            $inRetryOn = $false
            continue
        }

        if ($inRetryOn -and $line -match "^\s{4}-\s*(.+)$") {
            $policy.retry_on += $Matches[1].Trim().Trim('"')
        }
    }

    return $policy
}

function Read-CostTrackingPolicy {
    param([string[]]$Lines)

    $policy = [ordered]@{
        enabled = $false
        currency = "USD"
        unit = "dry-run-estimate"
    }
    $inCostTracking = $false

    foreach ($line in $Lines) {
        if ($line -match "^cost_tracking:\s*$") {
            $inCostTracking = $true
            continue
        }

        if (-not $inCostTracking) {
            continue
        }

        if ($line -match "^\S") {
            break
        }

        if ($line -match "^\s{2}enabled:\s*(true|false)\s*$") {
            $policy.enabled = ($Matches[1] -eq "true")
            continue
        }

        if ($line -match "^\s{2}currency:\s*(.+)$") {
            $policy.currency = $Matches[1].Trim().Trim('"')
            continue
        }

        if ($line -match "^\s{2}unit:\s*(.+)$") {
            $policy.unit = $Matches[1].Trim().Trim('"')
        }
    }

    return $policy
}

function Read-MemoryPolicy {
    param(
        [string[]]$Lines,
        [string]$WorkflowName,
        [string]$TaskId
    )

    $policy = [ordered]@{
        enabled = $false
        scope = "workflow"
        persistence = "dry-run"
        path = ""
    }
    $inMemory = $false

    foreach ($line in $Lines) {
        if ($line -match "^memory:\s*$") {
            $inMemory = $true
            continue
        }

        if (-not $inMemory) {
            continue
        }

        if ($line -match "^\S") {
            break
        }

        if ($line -match "^\s{2}enabled:\s*(true|false)\s*$") {
            $policy.enabled = ($Matches[1] -eq "true")
            continue
        }

        if ($line -match "^\s{2}scope:\s*(.+)$") {
            $policy.scope = $Matches[1].Trim().Trim('"')
            continue
        }

        if ($line -match "^\s{2}persistence:\s*(.+)$") {
            $policy.persistence = $Matches[1].Trim().Trim('"')
            continue
        }

        if ($line -match "^\s{2}path:\s*(.+)$") {
            $policy.path = $Matches[1].Trim().Trim('"')
        }
    }

    $policy.path = $policy.path.Replace("{workflow}", $WorkflowName).Replace("{task_id}", $TaskId)

    return $policy
}

function New-StepCostTracking {
    param(
        $CostTrackingPolicy,
        $ProviderMetadata = @{}
    )

    # Calculate cost from provider metadata
    $estimatedCost = Get-StepCost -ProviderMetadata $ProviderMetadata -Currency $CostTrackingPolicy.currency

    return [ordered]@{
        enabled = $CostTrackingPolicy.enabled
        currency = $CostTrackingPolicy.currency
        unit = $CostTrackingPolicy.unit
        estimated_cost = $estimatedCost
    }
}

function New-StepMemory {
    param($MemoryPolicy)

    return [ordered]@{
        enabled = $MemoryPolicy.enabled
        scope = $MemoryPolicy.scope
        persistence = $MemoryPolicy.persistence
        path = $MemoryPolicy.path
        loaded = $false
        written = $false
    }
}

function Read-ProviderFromExecutionSpec {
    param([string]$ExecutionSpecPath)

    $text = Read-Utf8File $ExecutionSpecPath
    $lines = $text -split "\r?\n"

    foreach ($line in $lines) {
        if ($line -match "^provider:\s*(.+)$") {
            return $Matches[1].Trim().Trim('"')
        }
    }

    return "dry-run"  # Default provider
}

function New-StepLog {
    param(
        $Step,
        $RetryPolicy,
        $CostTrackingPolicy,
        $MemoryPolicy
    )

    # Read provider from step or execution spec
    $provider = if ($Step.PSObject.Properties.Name -contains "provider") {
        $Step.provider
    } elseif ($Step.PSObject.Properties.Name -contains "execution_spec") {
        Read-ProviderFromExecutionSpec -ExecutionSpecPath $Step.execution_spec
    } else {
        "dry-run"  # Default provider
    }

    # Initialize attempt count
    $actualAttempts = 1

    # Route to appropriate runner based on provider
    $output = switch ($provider) {
        "dry-run" {
            # Preserve existing dry-run behavior (no retry for dry-run)
            [ordered]@{
                summary = "Dry-run workflow step generated without invoking an external LLM."
                changed_files = @()
                verification_result = "Workflow step inputs were loaded locally."
                risks = @("This step does not verify actual LLM execution.")
                next_steps = @("Replace dry-run behavior with a real step invocation when ready.")
            }
        }
        "codex" {
            # Invoke codex.ps1 runner with retry wrapper
            $retryResult = Invoke-WithRetryPolicy -Action {
                param($Attempt)
                Invoke-CodexRunner -Step $Step
            } -RetryPolicy $RetryPolicy -StepId $Step.id

            $actualAttempts = $retryResult.attempts
            $retryResult.result
        }
        "claude" {
            # Invoke claude.ps1 runner with retry wrapper
            $retryResult = Invoke-WithRetryPolicy -Action {
                param($Attempt)
                Invoke-ClaudeRunner -Step $Step
            } -RetryPolicy $RetryPolicy -StepId $Step.id

            $actualAttempts = $retryResult.attempts
            $retryResult.result
        }
        default {
            throw "Unsupported provider: $provider. Expected: dry-run, codex, or claude"
        }
    }

    # Extract provider metadata from output for cost calculation
    $providerMetadata = if ($output.Keys -contains "provider_metadata") {
        $output.provider_metadata
    } else {
        @{}
    }

    return [ordered]@{
        step_id = $Step.id
        role = $Step.role
        task_id = $Step.task_id
        provider = $provider
        retry_policy = $RetryPolicy
        attempts = $actualAttempts
        cost_tracking = New-StepCostTracking -CostTrackingPolicy $CostTrackingPolicy -ProviderMetadata $providerMetadata
        memory = New-StepMemory $MemoryPolicy
        inputs = @(
            $Step.agent_role,
            "tasks/$($Step.task_id).md",
            $Step.execution_spec
        )
        output = $output
    }
}

function Invoke-CodexRunner {
    param($Step)

    Write-Verbose "Invoking Codex runner for step $($Step.id)"

    $runnerScript = Join-Path $PSScriptRoot "codex.ps1"
    $tempLogPath = [System.IO.Path]::GetTempFileName()

    try {
        # Execute codex.ps1
        & $runnerScript `
            -TaskId $Step.task_id `
            -Role $Step.role `
            -ExecutionSpec $Step.execution_spec `
            -AgentRole $Step.agent_role `
            -LogOut $tempLogPath

        # Read runner output log
        $runnerLog = Get-Content -Path $tempLogPath -Raw | ConvertFrom-Json

        # Extract output (with provider_metadata if present)
        return $runnerLog.output
    } finally {
        if (Test-Path $tempLogPath) {
            Remove-Item $tempLogPath -Force
        }
    }
}

function Invoke-ClaudeRunner {
    param($Step)

    Write-Verbose "Invoking Claude CLI runner for step $($Step.id)"

    $runnerScript = Join-Path $PSScriptRoot "claude.ps1"
    $tempLogPath = [System.IO.Path]::GetTempFileName()

    try {
        # Execute claude.ps1
        & $runnerScript `
            -TaskId $Step.task_id `
            -Role $Step.role `
            -ExecutionSpec $Step.execution_spec `
            -AgentRole $Step.agent_role `
            -LogOut $tempLogPath

        # Read runner output log
        $runnerLog = Get-Content -Path $tempLogPath -Raw | ConvertFrom-Json

        # Extract output (with provider_metadata if present)
        return $runnerLog.output
    } finally {
        if (Test-Path $tempLogPath) {
            Remove-Item $tempLogPath -Force
        }
    }
}

function Test-StepInputs {
    param($Step)

    foreach ($path in @($Step.agent_role, $Step.execution_spec, "tasks/$($Step.task_id).md")) {
        Read-Utf8File $path | Out-Null
    }
}

function Invoke-SequentialDryRun {
    param(
        $Steps,
        $RetryPolicy,
        $CostTrackingPolicy,
        $MemoryPolicy,
        $WorkflowName,
        $TaskId
    )

    # Load memory if enabled
    $memoryState = Read-Memory -MemoryPolicy $MemoryPolicy -WorkflowName $WorkflowName -TaskId $TaskId
    $memoryLoaded = $memoryState.loaded

    $completed = @{}
    $stepLogs = @()

    foreach ($step in $Steps) {
        foreach ($dependency in $step.depends_on) {
            if (-not $completed.ContainsKey($dependency)) {
                throw "Step '$($step.id)' depends on incomplete step '$dependency'"
            }
        }

        Test-StepInputs $step
        $stepLogs += New-StepLog $step $RetryPolicy $CostTrackingPolicy $MemoryPolicy
        $completed[$step.id] = $true
    }

    # Write memory if enabled
    $memoryWritten = Write-Memory -MemoryPolicy $MemoryPolicy -MemoryData $memoryState.data -WorkflowName $WorkflowName -TaskId $TaskId

    return [ordered]@{
        workflow_summary = "Sequential workflow dry-run completed."
        step_logs = $stepLogs
        retry_policy = $RetryPolicy
        attempts = 1
        final_status = "dry-run-complete"
        memory_loaded = $memoryLoaded
        memory_written = $memoryWritten
        risks = @("This run does not invoke external LLM tools.")
        next_steps = @("Wire workflow steps to concrete runners after the dry-run contract is stable.")
    }
}

function Invoke-ParallelDryRun {
    param(
        $Steps,
        $RetryPolicy,
        $CostTrackingPolicy,
        $MemoryPolicy,
        $WorkflowName,
        $TaskId,
        [switch]$RealExecution = $false
    )

    # If real execution requested, use parallel executor
    if ($RealExecution) {
        Write-Verbose "Real parallel execution mode enabled"

        # Load memory if enabled
        $memoryState = Read-Memory -MemoryPolicy $MemoryPolicy -WorkflowName $WorkflowName -TaskId $TaskId
        $memoryLoaded = $memoryState.loaded

        # Create cancellation token
        $token = New-CancellationToken

        # Execute in parallel
        $result = Invoke-ParallelExecution -Steps $Steps `
            -RetryPolicy $RetryPolicy `
            -CostTrackingPolicy $CostTrackingPolicy `
            -MemoryPolicy $MemoryPolicy `
            -Token $token `
            -WorkflowName $WorkflowName `
            -TaskId $TaskId

        # Write memory if enabled
        $memoryWritten = Write-Memory -MemoryPolicy $MemoryPolicy -MemoryData $memoryState.data -WorkflowName $WorkflowName -TaskId $TaskId

        # Determine final status
        $finalStatus = "completed"
        foreach ($stepId in $result.step_statuses.Keys) {
            $state = $result.step_statuses[$stepId].state
            if ($state -eq "Failed") {
                $finalStatus = "failed"
                break
            } elseif ($state -eq "Cancelled") {
                $finalStatus = "cancelled"
                break
            }
        }

        return [ordered]@{
            workflow_summary = "Parallel workflow execution completed."
            step_logs = $result.step_logs
            step_statuses = $result.step_statuses
            execution_mode = "parallel-real"
            retry_policy = $RetryPolicy
            attempts = 1
            final_status = $finalStatus
            memory_loaded = $memoryLoaded
            memory_written = $memoryWritten
        }
    }

    # Otherwise, do dry-run (original behavior)
    Write-Verbose "Dry-run parallel execution mode"

    # Load memory if enabled
    $memoryState = Read-Memory -MemoryPolicy $MemoryPolicy -WorkflowName $WorkflowName -TaskId $TaskId
    $memoryLoaded = $memoryState.loaded

    $remaining = @($Steps)
    $completed = @{}
    $stepLogs = @()
    $parallelGroups = @()
    $groupIndex = 1

    while ($remaining.Count -gt 0) {
        $ready = @($remaining | Where-Object {
            $isReady = $true

            foreach ($dependency in $_.depends_on) {
                if (-not $completed.ContainsKey($dependency)) {
                    $isReady = $false
                    break
                }
            }

            $isReady
        })

        if ($ready.Count -eq 0) {
            throw "Parallel workflow contains unresolved or cyclic dependencies."
        }

        $groupSteps = @()

        foreach ($step in $ready) {
            Test-StepInputs $step
            $stepLog = New-StepLog $step $RetryPolicy $CostTrackingPolicy $MemoryPolicy
            $stepLogs += $stepLog
            $groupSteps += [ordered]@{
                step_id = $step.id
                role = $step.role
            }
        }

        $parallelGroups += [ordered]@{
            group = $groupIndex
            steps = $groupSteps
        }

        foreach ($step in $ready) {
            $completed[$step.id] = $true
        }

        $readyIds = @($ready | ForEach-Object { $_.id })
        $remaining = @($remaining | Where-Object { $readyIds -notcontains $_.id })
        $groupIndex++
    }

    # Write memory if enabled
    $memoryWritten = Write-Memory -MemoryPolicy $MemoryPolicy -MemoryData $memoryState.data -WorkflowName $WorkflowName -TaskId $TaskId

    return [ordered]@{
        workflow_summary = "Parallel workflow dry-run completed."
        step_logs = $stepLogs
        execution_mode = "parallel"
        parallel_groups = $parallelGroups
        retry_policy = $RetryPolicy
        attempts = 1
        final_status = "dry-run-complete"
        memory_loaded = $memoryLoaded
        memory_written = $memoryWritten
        risks = @("This run does not invoke external LLM tools or launch concurrent processes.")
        next_steps = @("Replace dry-run grouping with real parallel runner execution when ready.")
    }
}

function New-WorkflowMemory {
    param(
        $MemoryPolicy,
        [bool]$Loaded = $false,
        [bool]$Written = $false
    )

    return [ordered]@{
        enabled = $MemoryPolicy.enabled
        scope = $MemoryPolicy.scope
        persistence = $MemoryPolicy.persistence
        path = $MemoryPolicy.path
        loaded = $Loaded
        written = $Written
    }
}

function New-WorkflowCostTracking {
    param(
        $CostTrackingPolicy,
        $StepLogs
    )

    $stepCosts = @()

    foreach ($stepLog in $StepLogs) {
        # Extract cost from step log cost_tracking field
        $stepCost = if ($stepLog.cost_tracking.Keys -contains "estimated_cost") {
            $stepLog.cost_tracking.estimated_cost
        } else {
            0
        }

        $stepCosts += [ordered]@{
            step_id = $stepLog.step_id
            role = $stepLog.role
            estimated_cost = $stepCost
            currency = $CostTrackingPolicy.currency
            unit = $CostTrackingPolicy.unit
        }
    }

    # Calculate total cost
    $totalCost = Get-WorkflowTotalCost -StepCosts $stepCosts

    return [ordered]@{
        enabled = $CostTrackingPolicy.enabled
        currency = $CostTrackingPolicy.currency
        unit = $CostTrackingPolicy.unit
        estimated_total_cost = $totalCost
        step_costs = $stepCosts
    }
}

function New-WorkflowComparison {
    param($StepLogs)

    $requiredFields = @(
        "summary",
        "changed_files",
        "verification_result",
        "risks",
        "next_steps"
    )

    $requiredFieldsByStep = @()
    $missingRequiredFields = @()

    foreach ($stepLog in $StepLogs) {
        $presentFields = @($stepLog.output.Keys)
        $missingFields = @()

        foreach ($field in $requiredFields) {
            if ($presentFields -notcontains $field) {
                $missingFields += $field
                $missingRequiredFields += [ordered]@{
                    step_id = $stepLog.step_id
                    role = $stepLog.role
                    field = $field
                }
            }
        }

        $requiredFieldsByStep += [ordered]@{
            step_id = $stepLog.step_id
            role = $stepLog.role
            present_fields = $presentFields
            missing_fields = $missingFields
        }
    }

    $status = "all-required-fields-present"

    if ($missingRequiredFields.Count -gt 0) {
        $status = "missing-required-fields"
    }

    return [ordered]@{
        required_fields = $requiredFields
        required_fields_by_step = $requiredFieldsByStep
        missing_required_fields = $missingRequiredFields
        status = $status
    }
}

# Only run main execution if script is executed directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
$workflowText = Read-Utf8File $WorkflowSpec
$workflowLines = $workflowText -split "\r?\n"
$workflowName = Get-ScalarValue $workflowLines "workflow"
$mode = Get-ScalarValue $workflowLines "mode"
$retryPolicy = Read-RetryPolicy $workflowLines
$costTrackingPolicy = Read-CostTrackingPolicy $workflowLines
$memoryPolicy = Read-MemoryPolicy $workflowLines $workflowName $TaskId

$steps = Read-WorkflowSteps $workflowLines $TaskId

# Validate workflow dependencies before execution
. (Join-Path $PSScriptRoot "lib/workflow-validator.ps1")
. (Join-Path $PSScriptRoot "lib/workflow-visualizer.ps1")

Write-Host ""
Write-Host "Validating workflow: " -NoNewline -ForegroundColor Cyan
Write-Host $workflowName -ForegroundColor White
$validation = Test-WorkflowDependencies -Steps $steps

if (-not $validation.valid) {
    Write-Host ""
    Write-Host "Workflow validation failed:" -ForegroundColor Red
    Write-Host ""
    foreach ($error in $validation.errors) {
        Write-Host "  ✗ $($error.message)" -ForegroundColor Red
    }
    Write-Host ""
    throw "Workflow validation failed. See errors above."
}

# Display dependency graph and validation result
Show-DependencyGraph -Steps $steps
Show-ValidationResult -Validation $validation

if ($mode -eq "sequential") {
    $output = Invoke-SequentialDryRun $steps $retryPolicy $costTrackingPolicy $memoryPolicy $workflowName $TaskId
} elseif ($mode -eq "parallel") {
    $output = Invoke-ParallelDryRun $steps $retryPolicy $costTrackingPolicy $memoryPolicy $workflowName $TaskId -RealExecution:$RealExecution
} else {
    throw "Unsupported workflow mode: $mode"
}

# Extract memory loaded/written flags from execution output
$memoryLoaded = if ($output.Keys -contains "memory_loaded") { $output.memory_loaded } else { $false }
$memoryWritten = if ($output.Keys -contains "memory_written") { $output.memory_written } else { $false }

$output.memory = New-WorkflowMemory -MemoryPolicy $memoryPolicy -Loaded $memoryLoaded -Written $memoryWritten
$output.cost_tracking = New-WorkflowCostTracking $costTrackingPolicy $output.step_logs
$output.comparison = New-WorkflowComparison $output.step_logs

# Display completion summary
Write-Host ""
Write-Host "Workflow completed successfully" -ForegroundColor Green
Write-Host "  Steps: $($steps.Count)" -ForegroundColor DarkGray
Write-Host "  Mode: $mode" -ForegroundColor DarkGray
Write-Host ""

$logDir = Split-Path -Parent $LogOut
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$log = [ordered]@{
    run_id = "20260426-workflow-$workflowName-$TaskId"
    runner = "workflow-dry-run"
    workflow = $workflowName
    task_id = $TaskId
    workflow_spec = $WorkflowSpec
    output = $output
}

$log | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 -Path $LogOut

Write-Output "Workflow log written to $LogOut"

} # End of main execution block
