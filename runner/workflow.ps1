param(
    [string]$TaskId = "000_template",
    [string]$WorkflowSpec = "workflows/implementation-review.yaml",
    [string]$LogOut = "logs/20260426-workflow-implementation-review-000_template.json",
    [string]$Mode = "dry-run",
    [switch]$AllowReal,
    [string]$StepRunnerCommand = ".\runner\codex.ps1",
    [string]$StepLogDir = "logs/workflow-steps",
    [string]$OperatorRoot = "",
    [string]$TargetRoot = "",
    [string]$RunId = ""
)

$ErrorActionPreference = "Stop"

# Write-FileRetry: atomic-safe file write for Windows.
# Set-Content uses FileShare.Read which causes sharing violations when Windows
# Defender, Node.js watchers, or concurrent processes have the file open.
# [System.IO.File]::WriteAllText uses a compatible sharing mode, and retry +
# exponential backoff handles any remaining transient locks (Defender, AV, etc.).
function Write-FileRetry {
    param(
        [string]$Path,
        [string]$Content,
        [int]$MaxRetries = 5
    )
    $enc = [System.Text.UTF8Encoding]::new($false)  # UTF-8 without BOM
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        try {
            [System.IO.File]::WriteAllText($Path, $Content, $enc)
            return
        } catch [System.IO.IOException] {
            if ($i -ge $MaxRetries - 1) { throw }
            Start-Sleep -Milliseconds ([Math]::Pow(2, $i) * 50)  # 50, 100, 200, 400 ms
        }
    }
}

if ([string]::IsNullOrWhiteSpace($OperatorRoot)) {
    $OperatorRoot = (Get-Location).Path
}

if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
    $TargetRoot = (Get-Location).Path
}

function Resolve-RepoPath {
    param(
        [string]$Path,
        [string]$Root
    )

    if ([System.IO.Path]::IsPathRooted($Path) -or [string]::IsNullOrWhiteSpace($Root)) {
        return $Path
    }

    return Join-Path $Root $Path
}

function Read-Utf8File {
    param(
        [string]$Path,
        [string]$Root = ""
    )

    $resolvedPath = Resolve-RepoPath $Path $Root

    if (-not (Test-Path $resolvedPath)) {
        throw "Required input file not found: $Path"
    }

    return Get-Content -Encoding utf8 $resolvedPath -Raw
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
        $ProviderMetadata = $null
    )

    $estimatedCost = Get-EstimatedStepCost $ProviderMetadata

    $costTracking = [ordered]@{
        enabled = $CostTrackingPolicy.enabled
        currency = $CostTrackingPolicy.currency
        unit = $CostTrackingPolicy.unit
        estimated_cost = $estimatedCost
    }

    if ($null -ne $ProviderMetadata) {
        $costTracking.provider_metadata = $ProviderMetadata
    }

    return $costTracking
}

function Get-ProviderMetadataNumber {
    param(
        $ProviderMetadata,
        [string]$Name
    )

    if ($null -eq $ProviderMetadata) {
        return [decimal]0
    }

    if (-not ($ProviderMetadata.PSObject.Properties.Name -contains $Name)) {
        return [decimal]0
    }

    return [decimal]$ProviderMetadata.$Name
}

function Get-EstimatedStepCost {
    param($ProviderMetadata)

    $rateUnitTokens = Get-ProviderMetadataNumber $ProviderMetadata "rate_unit_tokens"

    if ($rateUnitTokens -le 0) {
        return 0
    }

    $inputTokens = Get-ProviderMetadataNumber $ProviderMetadata "input_tokens"
    $outputTokens = Get-ProviderMetadataNumber $ProviderMetadata "output_tokens"
    $inputTokenRate = Get-ProviderMetadataNumber $ProviderMetadata "input_token_rate"
    $outputTokenRate = Get-ProviderMetadataNumber $ProviderMetadata "output_token_rate"

    $estimatedCost = (($inputTokens * $inputTokenRate) + ($outputTokens * $outputTokenRate)) / $rateUnitTokens

    return [Math]::Round($estimatedCost, 6)
}

function Get-StepProviderMetadata {
    param($ParsedStepLog)

    if ($null -eq $ParsedStepLog) {
        return $null
    }

    if (-not ($ParsedStepLog.PSObject.Properties.Name -contains "cost_tracking")) {
        return $null
    }

    if (-not ($ParsedStepLog.cost_tracking.PSObject.Properties.Name -contains "provider_metadata")) {
        return $null
    }

    return $ParsedStepLog.cost_tracking.provider_metadata
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

function ConvertTo-StringArray {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [array]) {
        return @($Value | ForEach-Object { [string]$_ })
    }

    return @([string]$Value)
}

function Read-RetryAttemptLog {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return @()
    }

    $maxRetries = 10
    $retryDelayMs = 200

    for ($i = 0; $i -lt $maxRetries; $i++) {
        try {
            Start-Sleep -Milliseconds ($retryDelayMs * $i)
            $attemptText = Get-Content -Encoding utf8 $Path -Raw -ErrorAction Stop

            if ([string]::IsNullOrWhiteSpace($attemptText)) {
                return @()
            }

            return @($attemptText | ConvertFrom-Json -ErrorAction Stop | ForEach-Object {
                [ordered]@{
                    step_id = [string]$_.step_id
                    role = [string]$_.role
                    attempt = [int]$_.attempt
                    status = [string]$_.status
                    reason = [string]$_.reason
                }
            })
        } catch {
            if ($i -eq ($maxRetries - 1)) {
                Write-Warning "Failed to read retry attempt log '$Path' after $maxRetries attempts: $_"
                return @()
            }
        }
    }

    return @()
}

function New-WorkflowRetryAttempts {
    param($StepLogs)

    $retryAttempts = @()

    foreach ($stepLog in $StepLogs) {
        if ($stepLog.Contains("retry_attempts")) {
            $retryAttempts += @($stepLog.retry_attempts)
        }
    }

    return $retryAttempts
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
        retry_attempts = @()
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

function New-RealStepLog {
    param(
        $Step,
        $ParsedStepLog,
        [string]$StepLogPath,
        [int]$Attempts,
        $RetryAttempts,
        $RetryPolicy,
        $CostTrackingPolicy,
        $MemoryPolicy
    )

    $stepLog = [ordered]@{
        step_id = $Step.id
        role = $Step.role
        task_id = $Step.task_id
        runner = [string]$ParsedStepLog.runner
        runner_log = $StepLogPath
        retry_policy = $RetryPolicy
        attempts = $Attempts
        retry_attempts = $RetryAttempts
        cost_tracking = New-StepCostTracking $CostTrackingPolicy (Get-StepProviderMetadata $ParsedStepLog)
        memory = New-StepMemory $MemoryPolicy
        inputs = ConvertTo-StringArray $ParsedStepLog.inputs
        output = [ordered]@{
            summary = [string]$ParsedStepLog.output.summary
            changed_files = ConvertTo-StringArray $ParsedStepLog.output.changed_files
            verification_result = [string]$ParsedStepLog.output.verification_result
            risks = ConvertTo-StringArray $ParsedStepLog.output.risks
            next_steps = ConvertTo-StringArray $ParsedStepLog.output.next_steps
        }
    }

    if ($ParsedStepLog.PSObject.Properties.Name -contains "timing") {
        $stepLog.timing = $ParsedStepLog.timing
    }

    if ($ParsedStepLog.PSObject.Properties.Name -contains "invocation") {
        $stepLog.invocation = $ParsedStepLog.invocation
    }

    return $stepLog
}

function Test-StepInputs {
    param($Step)

    foreach ($path in @($Step.agent_role, $Step.execution_spec, "tasks/$($Step.task_id).md")) {
        $root = if ($path -match "^tasks[\\/]") { $TargetRoot } else { $OperatorRoot }
        Read-Utf8File $path $root | Out-Null
    }
}

function Invoke-WorkflowGraphVisit {
    param(
        [string]$StepId,
        [hashtable]$StepById,
        [hashtable]$VisitState,
        [string[]]$Path
    )

    if ($VisitState.ContainsKey($StepId)) {
        if ($VisitState[$StepId] -eq "visiting") {
            $cyclePath = @($Path + $StepId) -join " -> "
            throw "Workflow dependency graph contains a cycle: $cyclePath"
        }

        return
    }

    $VisitState[$StepId] = "visiting"
    $step = $StepById[$StepId]

    foreach ($dependency in $step.depends_on) {
        Invoke-WorkflowGraphVisit $dependency $StepById $VisitState @($Path + $StepId)
    }

    $VisitState[$StepId] = "visited"
}

function Test-WorkflowGraph {
    param($Steps)

    $stepById = @{}

    foreach ($step in $Steps) {
        if ($stepById.ContainsKey($step.id)) {
            throw "Duplicate workflow step id: $($step.id)"
        }

        $stepById[$step.id] = $step
    }

    foreach ($step in $Steps) {
        foreach ($dependency in $step.depends_on) {
            if ($dependency -eq $step.id) {
                throw "Step '$($step.id)' depends on itself"
            }

            if (-not $stepById.ContainsKey($dependency)) {
                throw "Step '$($step.id)' depends on unknown step '$dependency'"
            }
        }
    }

    $visitState = @{}

    foreach ($step in $Steps) {
        Invoke-WorkflowGraphVisit $step.id $stepById $visitState @()
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

function Invoke-RealStepRunnerJob {
    param(
        $Step,
        [string]$WorkflowName,
        [string]$WorkingDirectory,
        [string]$StepRunnerCommand,
        [string]$StepLogDir,
        $RetryPolicy
    )

    $stepPromptOut = "logs/prompts/workflow-$WorkflowName-$($Step.id)-$($Step.task_id).prompt.txt"
    $stepLogOut = Join-Path $StepLogDir "$WorkflowName-$($Step.id)-$($Step.task_id).json"
    $stepAttemptOut = "$stepLogOut.attempts"
    $stepRetryAttemptsOut = "$stepLogOut.retry-attempts.json"
    $resolvedCommand = $StepRunnerCommand

    if (Test-Path $StepRunnerCommand) {
        $resolvedCommand = (Resolve-Path $StepRunnerCommand).Path
    }

    return Start-Job -ArgumentList @(
        $WorkingDirectory,
        $resolvedCommand,
        $Step.id,
        $Step.task_id,
        $Step.role,
        $Step.execution_spec,
        $Step.agent_role,
        $stepPromptOut,
        $stepLogOut,
        $stepAttemptOut,
        $stepRetryAttemptsOut,
        $RetryPolicy.max_attempts,
        @($RetryPolicy.retry_on)
    ) -ScriptBlock {
        param(
            [string]$WorkingDirectory,
            [string]$Command,
            [string]$StepId,
            [string]$TaskId,
            [string]$Role,
            [string]$ExecutionSpec,
            [string]$AgentRole,
            [string]$PromptOut,
            [string]$LogOut,
            [string]$AttemptOut,
            [string]$RetryAttemptsOut,
            [int]$MaxAttempts,
            [string[]]$RetryOn
        )

        Set-Location $WorkingDirectory

        if ($MaxAttempts -lt 1) {
            $MaxAttempts = 1
        }

        function Write-FileRetry {
            param([string]$Path, [string]$Content, [int]$MaxRetries = 5)
            $enc = [System.Text.UTF8Encoding]::new($false)
            for ($i = 0; $i -lt $MaxRetries; $i++) {
                try {
                    [System.IO.File]::WriteAllText($Path, $Content, $enc)
                    return
                } catch [System.IO.IOException] {
                    if ($i -ge $MaxRetries - 1) { throw }
                    Start-Sleep -Milliseconds ([Math]::Pow(2, $i) * 50)
                }
            }
        }

        $retryRunnerErrors = @($RetryOn) -contains "runner-error"
        $lastError = ""
        $attemptRecords = @()

        function Write-AttemptRecords {
            param($Records, [string]$Path)

            try {
                $json = ConvertTo-Json -InputObject @($Records) -Depth 6
                Write-FileRetry -Path $Path -Content $json
            } catch {
                Write-Warning "Failed to write retry attempt records to '$Path': $_"
            }
        }

        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            Write-FileRetry -Path $AttemptOut -Content "$attempt"

            try {
                & $Command `
                    -TaskId $TaskId `
                    -Role $Role `
                    -ExecutionSpec $ExecutionSpec `
                    -AgentRole $AgentRole `
                    -Mode "real" `
                    -AllowReal `
                    -PromptOut $PromptOut `
                    -LogOut $LogOut

                if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
                    throw "Step runner exited with code $LASTEXITCODE for step '$Role'"
                }

                $attemptRecords += [ordered]@{
                    step_id = $StepId
                    role = $Role
                    attempt = $attempt
                    status = "succeeded"
                    reason = ""
                }
                Write-AttemptRecords $attemptRecords $RetryAttemptsOut
                Start-Sleep -Milliseconds 300
                return
            } catch {
                $lastError = $_.Exception.Message
                $attemptRecords += [ordered]@{
                    step_id = $StepId
                    role = $Role
                    attempt = $attempt
                    status = "failed"
                    reason = $lastError
                }
                Write-AttemptRecords $attemptRecords $RetryAttemptsOut

                if (-not $retryRunnerErrors -or $attempt -ge $MaxAttempts) {
                    Start-Sleep -Milliseconds 300
                    throw $lastError
                }
            }
        }
    } | Add-Member -NotePropertyName StepId -NotePropertyValue $Step.id -PassThru |
        Add-Member -NotePropertyName StepLogOut -NotePropertyValue $stepLogOut -PassThru |
        Add-Member -NotePropertyName StepAttemptOut -NotePropertyValue $stepAttemptOut -PassThru |
        Add-Member -NotePropertyName StepRetryAttemptsOut -NotePropertyValue $stepRetryAttemptsOut -PassThru
}

function Invoke-ParallelRealRun {
    param(
        $Steps,
        $RetryPolicy,
        $CostTrackingPolicy,
        $MemoryPolicy,
        [string]$WorkflowName,
        [string]$StepRunnerCommand,
        [string]$StepLogDir
    )

    $remaining = @($Steps)
    $completed = @{}
    $stepLogs = @()
    $parallelGroups = @()
    $groupIndex = 1
    $workingDirectory = (Get-Location).Path
    $stepById = @{}

    foreach ($step in $Steps) {
        $stepById[$step.id] = $step
    }

    New-Item -ItemType Directory -Force -Path $StepLogDir | Out-Null

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
        $jobs = @()

        foreach ($step in $ready) {
            Test-StepInputs $step
            $jobs += Invoke-RealStepRunnerJob $step $WorkflowName $workingDirectory $StepRunnerCommand $StepLogDir $RetryPolicy
            $groupSteps += [ordered]@{
                step_id = $step.id
                role = $step.role
            }
        }

        $readyIds = @($ready | ForEach-Object { $_.id })
        $failure = $null

        while ($true) {
            $pendingJobs = @($jobs | Where-Object { $_.State -eq "Running" -or $_.State -eq "NotStarted" })

            if ($pendingJobs.Count -eq 0) {
                break
            }

            $finishedJobs = @(Wait-Job -Job $pendingJobs -Any)

            foreach ($job in $finishedJobs) {
                $receiveError = ""

                try {
                    Receive-Job -Job $job -ErrorAction Stop | Out-Null
                } catch {
                    $receiveError = $_.Exception.Message
                }

                Start-Sleep -Milliseconds 500

                if ($job.State -ne "Completed" -or -not [string]::IsNullOrWhiteSpace($receiveError)) {
                    $failedStep = $stepById[$job.StepId]
                    $failure = [ordered]@{
                        step_id = $failedStep.id
                        role = $failedStep.role
                        reason = if ([string]::IsNullOrWhiteSpace($receiveError)) { "Step runner failed." } else { $receiveError }
                    }
                    break
                }
            }

            if ($null -ne $failure) {
                break
            }
        }

        if ($null -ne $failure) {
            $cancelledSteps = @()
            $retryAttempts = @()

            foreach ($job in @($jobs | Where-Object { $_.State -eq "Running" -or $_.State -eq "NotStarted" })) {
                Stop-Job -Job $job | Out-Null
                $cancelledStep = $stepById[$job.StepId]
                $cancelledSteps += [ordered]@{
                    step_id = $cancelledStep.id
                    role = $cancelledStep.role
                    reason = "Cancelled after another step in the parallel batch failed."
                }
            }

            $skippedSteps = @($remaining | Where-Object { $readyIds -notcontains $_.id } | ForEach-Object {
                [ordered]@{
                    step_id = $_.id
                    role = $_.role
                    reason = "Skipped because an upstream parallel batch failed."
                }
            })

            Start-Sleep -Milliseconds 300

            foreach ($job in $jobs) {
                $jobRetryAttempts = Read-RetryAttemptLog $job.StepRetryAttemptsOut
                $retryAttempts += $jobRetryAttempts

                if ($job.StepId -eq $failure.step_id) {
                    $attemptCount = @($jobRetryAttempts).Count
                    if ($attemptCount -eq 0 -and (Test-Path $job.StepAttemptOut)) {
                        $attemptCount = [int](Get-Content -Encoding utf8 $job.StepAttemptOut -Raw)
                    }
                    if ($attemptCount -eq 0) {
                        $attemptCount = 1
                    }
                    $failure.attempts = $attemptCount
                    $failure.retry_exhausted = (
                        @($RetryPolicy.retry_on) -contains "runner-error" -and
                        $failure.attempts -ge $RetryPolicy.max_attempts
                    )
                }

                Remove-Job -Job $job -Force
            }

            $parallelGroups += [ordered]@{
                group = $groupIndex
                steps = $groupSteps
            }

            return [ordered]@{
                workflow_summary = "Parallel workflow real run failed."
                step_logs = $stepLogs
                execution_mode = "parallel"
                parallel_groups = $parallelGroups
                retry_policy = $RetryPolicy
                attempts = 1
                retry_attempts = $retryAttempts
                final_status = "real-failed"
                failed_steps = @($failure)
                cancelled_steps = $cancelledSteps
                skipped_steps = $skippedSteps
                risks = @("Real parallel workflow stopped after a step failure.")
                next_steps = @("Inspect failed step logs and retry after resolving the runner failure.")
            }
        }

        Start-Sleep -Milliseconds 300

        foreach ($step in $ready) {
            $job = @($jobs | Where-Object { $_.StepId -eq $step.id })[0]
            $parsedStepLog = Get-Content -Encoding utf8 $job.StepLogOut -Raw | ConvertFrom-Json
            $attempts = 1

            if (Test-Path $job.StepAttemptOut) {
                $attempts = [int](Get-Content -Encoding utf8 $job.StepAttemptOut -Raw)
            }

            $retryAttempts = Read-RetryAttemptLog $job.StepRetryAttemptsOut
            $parsedStepLog | Add-Member -NotePropertyName retry_policy -NotePropertyValue $RetryPolicy -Force
            $parsedStepLog | Add-Member -NotePropertyName attempts -NotePropertyValue $attempts -Force
            $parsedStepLog | Add-Member -NotePropertyName retry_attempts -NotePropertyValue $retryAttempts -Force
            try {
                $enrichedJson = $parsedStepLog | ConvertTo-Json -Depth 8
                Write-FileRetry -Path $job.StepLogOut -Content $enrichedJson
            } catch {
                Write-Warning "Failed to enrich step log '$($job.StepLogOut)': $_"
            }

            $stepLogs += New-RealStepLog $step $parsedStepLog $job.StepLogOut $attempts $retryAttempts $RetryPolicy $CostTrackingPolicy $MemoryPolicy
            $completed[$step.id] = $true
            Remove-Job -Job $job -Force
        }

        $parallelGroups += [ordered]@{
            group = $groupIndex
            steps = $groupSteps
        }

        $remaining = @($remaining | Where-Object { $readyIds -notcontains $_.id })
        $groupIndex++
    }

    return [ordered]@{
        workflow_summary = "Parallel workflow real run completed."
        step_logs = $stepLogs
        execution_mode = "parallel"
        parallel_groups = $parallelGroups
        retry_policy = $RetryPolicy
        attempts = 1
        retry_attempts = New-WorkflowRetryAttempts $stepLogs
        final_status = "real-complete"
        risks = @("This run invoked step runners concurrently within dependency-ready groups.")
        next_steps = @("Add cancellation and failure propagation rules when real execution behavior is stable.")
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
        stale = $false
        overwrite_allowed = $true
    }
}

function Set-StepMemoryState {
    param(
        $StepLogs,
        $MemoryState
    )

    foreach ($stepLog in $StepLogs) {
        if ($stepLog.Contains("memory")) {
            $stepLog.memory.loaded = $MemoryState.loaded
            $stepLog.memory.written = $MemoryState.written
            $stepLog.memory.stale = $MemoryState.stale
            $stepLog.memory.overwrite_allowed = $MemoryState.overwrite_allowed
        }
    }
}

function Test-ObjectProperty {
    param(
        $Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $false
    }

    return $Object.PSObject.Properties.Name -contains $Name
}

function Invoke-RealWorkflowMemory {
    param(
        $MemoryPolicy,
        [string]$WorkflowName,
        [string]$TaskId,
        $StepLogs
    )

    $memoryState = New-WorkflowMemory $MemoryPolicy

    if (-not $MemoryPolicy.enabled -or $MemoryPolicy.persistence -eq "dry-run") {
        return $memoryState
    }

    $loaded = Test-Path $MemoryPolicy.path
    $existingMemory = $null

    if ($loaded) {
        $existingMemoryText = Get-Content -Encoding utf8 $MemoryPolicy.path -Raw

        if (-not [string]::IsNullOrWhiteSpace($existingMemoryText)) {
            $existingMemory = $existingMemoryText | ConvertFrom-Json
        }
    }

    if ($null -ne $existingMemory) {
        if (
            (Test-ObjectProperty $existingMemory "workflow") -and
            -not [string]::IsNullOrWhiteSpace($existingMemory.workflow) -and
            $existingMemory.workflow -ne $WorkflowName
        ) {
            throw "Refusing to overwrite memory outside workflow scope: $($MemoryPolicy.path)"
        }

        if (
            (Test-ObjectProperty $existingMemory "task_id") -and
            -not [string]::IsNullOrWhiteSpace($existingMemory.task_id) -and
            $existingMemory.task_id -ne $TaskId
        ) {
            throw "Refusing to overwrite memory outside workflow scope: $($MemoryPolicy.path)"
        }

        if ((Test-ObjectProperty $existingMemory "stale") -and $existingMemory.stale -eq $true) {
            $memoryState.loaded = $true
            $memoryState.stale = $true
            $memoryState.overwrite_allowed = $false
            return $memoryState
        }
    }

    $memoryDir = Split-Path -Parent $MemoryPolicy.path
    if (-not [string]::IsNullOrWhiteSpace($memoryDir)) {
        New-Item -ItemType Directory -Force -Path $memoryDir | Out-Null
    }

    $memoryPayload = [ordered]@{
        workflow = $WorkflowName
        task_id = $TaskId
        scope = $MemoryPolicy.scope
        updated_by = "workflow-real"
        loaded_existing_memory = $loaded
        stale = $false
        step_ids = @($StepLogs | ForEach-Object { $_.step_id })
    }

    Write-FileRetry -Path $MemoryPolicy.path -Content ($memoryPayload | ConvertTo-Json -Depth 6)

    $memoryState.loaded = $loaded
    $memoryState.written = $true

    return $memoryState
}

function New-WorkflowCostTracking {
    param(
        $CostTrackingPolicy,
        $StepLogs
    )

    $stepCosts = @()

    foreach ($stepLog in $StepLogs) {
        $stepCost = [ordered]@{
            step_id = $stepLog.step_id
            role = $stepLog.role
            estimated_cost = $stepLog.cost_tracking.estimated_cost
            currency = $CostTrackingPolicy.currency
            unit = $CostTrackingPolicy.unit
        }

        if ($stepLog.cost_tracking.Contains("provider_metadata")) {
            $stepCost.provider_metadata = $stepLog.cost_tracking.provider_metadata
        }

        $stepCosts += $stepCost
    }

    $estimatedTotalCost = 0

    foreach ($stepCost in $stepCosts) {
        $estimatedTotalCost += [decimal]$stepCost.estimated_cost
    }

    return [ordered]@{
        enabled = $CostTrackingPolicy.enabled
        currency = $CostTrackingPolicy.currency
        unit = $CostTrackingPolicy.unit
        estimated_total_cost = [Math]::Round($estimatedTotalCost, 6)
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

function New-WorkflowVotingGate {
    param($StepLogs)

    return [ordered]@{
        voting_method = "not-implemented"
        eligible_step_ids = @($StepLogs | ForEach-Object { $_.step_id })
        votes = @()
        selected_step_id = ""
        status = "ready-not-implemented"
    }
}

$workflowText = Read-Utf8File $WorkflowSpec $OperatorRoot
$workflowLines = $workflowText -split "\r?\n"
$workflowName = Get-ScalarValue $workflowLines "workflow"
$workflowMode = Get-ScalarValue $workflowLines "mode"
$retryPolicy = Read-RetryPolicy $workflowLines
$costTrackingPolicy = Read-CostTrackingPolicy $workflowLines
$memoryPolicy = Read-MemoryPolicy $workflowLines $workflowName $TaskId

$steps = Read-WorkflowSteps $workflowLines $TaskId
Test-WorkflowGraph $steps

if (@("dry-run", "real") -notcontains $Mode) {
    throw "Unsupported workflow invocation mode: $Mode"
}

if ($Mode -eq "real" -and -not $AllowReal) {
    throw "Real workflow execution requires -AllowReal"
}

if ($Mode -eq "real" -and $workflowMode -ne "parallel") {
    throw "Real workflow execution currently supports parallel workflows only"
}

$effectiveStepLogDir = if (-not [string]::IsNullOrWhiteSpace($RunId)) {
    Join-Path $StepLogDir $RunId
} else {
    $StepLogDir
}

if ($Mode -eq "dry-run" -and $workflowMode -eq "sequential") {
    $output = Invoke-SequentialDryRun $steps $retryPolicy $costTrackingPolicy $memoryPolicy
} elseif ($Mode -eq "dry-run" -and $workflowMode -eq "parallel") {
    $output = Invoke-ParallelDryRun $steps $retryPolicy $costTrackingPolicy $memoryPolicy
} elseif ($Mode -eq "real" -and $workflowMode -eq "parallel") {
    $output = Invoke-ParallelRealRun $steps $retryPolicy $costTrackingPolicy $memoryPolicy $workflowName $StepRunnerCommand $effectiveStepLogDir
} else {
    throw "Unsupported workflow mode: $workflowMode"
}

if ($Mode -eq "real" -and $output.final_status -eq "real-complete") {
    $output.memory = Invoke-RealWorkflowMemory $memoryPolicy $workflowName $TaskId $output.step_logs
    Set-StepMemoryState $output.step_logs $output.memory
} else {
    $output.memory = New-WorkflowMemory $memoryPolicy
}

$output.cost_tracking = New-WorkflowCostTracking $costTrackingPolicy $output.step_logs
$output.comparison = New-WorkflowComparison $output.step_logs

if (
    $Mode -eq "real" -and
    $output.final_status -eq "real-complete" -and
    $output.comparison.status -eq "all-required-fields-present"
) {
    $output.voting = New-WorkflowVotingGate $output.step_logs
}

$resolvedLogOut = Resolve-RepoPath $LogOut $TargetRoot
$logDir = Split-Path -Parent $resolvedLogOut
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$effectiveRunId = if (-not [string]::IsNullOrWhiteSpace($RunId)) { $RunId } else { "workflow-$workflowName-$TaskId" }

$log = [ordered]@{
    run_id = $effectiveRunId
    runner = if ($Mode -eq "real") { "workflow-real" } else { "workflow-dry-run" }
    workflow = $workflowName
    task_id = $TaskId
    workflow_spec = $WorkflowSpec
    invocation = [ordered]@{
        mode = $Mode
        real_enabled = ($Mode -eq "real")
        step_runner_command = $StepRunnerCommand
    }
    output = $output
}

Write-FileRetry -Path $resolvedLogOut -Content ($log | ConvertTo-Json -Depth 8)

Write-Output "Workflow log written to $LogOut"
