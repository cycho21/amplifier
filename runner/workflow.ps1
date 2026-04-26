param(
    [string]$TaskId = "000_template",
    [string]$WorkflowSpec = "workflows/implementation-review.yaml",
    [string]$LogOut = "logs/20260426-workflow-implementation-review-000_template.json"
)

$ErrorActionPreference = "Stop"

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
    param($CostTrackingPolicy)

    return [ordered]@{
        enabled = $CostTrackingPolicy.enabled
        currency = $CostTrackingPolicy.currency
        unit = $CostTrackingPolicy.unit
        estimated_cost = 0
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

function New-StepLog {
    param(
        $Step,
        $RetryPolicy,
        $CostTrackingPolicy,
        $MemoryPolicy
    )

    return [ordered]@{
        step_id = $Step.id
        role = $Step.role
        task_id = $Step.task_id
        retry_policy = $RetryPolicy
        attempts = 1
        cost_tracking = New-StepCostTracking $CostTrackingPolicy
        memory = New-StepMemory $MemoryPolicy
        inputs = @(
            $Step.agent_role,
            "tasks/$($Step.task_id).md",
            $Step.execution_spec
        )
        output = [ordered]@{
            summary = "Dry-run workflow step generated without invoking an external LLM."
            changed_files = @()
            verification_result = "Workflow step inputs were loaded locally."
            risks = @("This step does not verify actual LLM execution.")
            next_steps = @("Replace dry-run behavior with a real step invocation when ready.")
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
        $MemoryPolicy
    )

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

    return [ordered]@{
        workflow_summary = "Sequential workflow dry-run completed."
        step_logs = $stepLogs
        retry_policy = $RetryPolicy
        attempts = 1
        final_status = "dry-run-complete"
        risks = @("This run does not invoke external LLM tools.")
        next_steps = @("Wire workflow steps to concrete runners after the dry-run contract is stable.")
    }
}

function Invoke-ParallelDryRun {
    param(
        $Steps,
        $RetryPolicy,
        $CostTrackingPolicy,
        $MemoryPolicy
    )

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

    return [ordered]@{
        workflow_summary = "Parallel workflow dry-run completed."
        step_logs = $stepLogs
        execution_mode = "parallel"
        parallel_groups = $parallelGroups
        retry_policy = $RetryPolicy
        attempts = 1
        final_status = "dry-run-complete"
        risks = @("This run does not invoke external LLM tools or launch concurrent processes.")
        next_steps = @("Replace dry-run grouping with real parallel runner execution when ready.")
    }
}

function New-WorkflowMemory {
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

function New-WorkflowCostTracking {
    param(
        $CostTrackingPolicy,
        $StepLogs
    )

    $stepCosts = @()

    foreach ($stepLog in $StepLogs) {
        $stepCosts += [ordered]@{
            step_id = $stepLog.step_id
            role = $stepLog.role
            estimated_cost = 0
            currency = $CostTrackingPolicy.currency
            unit = $CostTrackingPolicy.unit
        }
    }

    return [ordered]@{
        enabled = $CostTrackingPolicy.enabled
        currency = $CostTrackingPolicy.currency
        unit = $CostTrackingPolicy.unit
        estimated_total_cost = 0
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

$workflowText = Read-Utf8File $WorkflowSpec
$workflowLines = $workflowText -split "\r?\n"
$workflowName = Get-ScalarValue $workflowLines "workflow"
$mode = Get-ScalarValue $workflowLines "mode"
$retryPolicy = Read-RetryPolicy $workflowLines
$costTrackingPolicy = Read-CostTrackingPolicy $workflowLines
$memoryPolicy = Read-MemoryPolicy $workflowLines $workflowName $TaskId

$steps = Read-WorkflowSteps $workflowLines $TaskId

if ($mode -eq "sequential") {
    $output = Invoke-SequentialDryRun $steps $retryPolicy $costTrackingPolicy $memoryPolicy
} elseif ($mode -eq "parallel") {
    $output = Invoke-ParallelDryRun $steps $retryPolicy $costTrackingPolicy $memoryPolicy
} else {
    throw "Unsupported workflow mode: $mode"
}

$output.memory = New-WorkflowMemory $memoryPolicy
$output.cost_tracking = New-WorkflowCostTracking $costTrackingPolicy $output.step_logs
$output.comparison = New-WorkflowComparison $output.step_logs

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
