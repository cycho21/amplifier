# Full Orchestration Integration Tests
# End-to-end tests for complete workflow execution with all features

$ErrorActionPreference = "Stop"

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
Write-Host "=== Full Orchestration Integration Tests ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Dry-run mode preserves deterministic grouping
Test-Case "Dry-run mode preserves deterministic grouping" {
    & powershell.exe -NoProfile -File "runner\workflow.ps1" `
        -TaskId "000_template" `
        -WorkflowSpec "workflows/parallel-review.yaml" `
        -LogOut "logs/test-dry-run.json" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Workflow execution failed with exit code $LASTEXITCODE"
    }

    # Read the log file
    $log = Get-Content "logs/test-dry-run.json" -Raw | ConvertFrom-Json

    # Check execution mode
    if ($log.output.execution_mode -ne "parallel") {
        throw "Expected execution_mode='parallel', got '$($log.output.execution_mode)'"
    }

    # Check that parallel_groups exist (dry-run grouping)
    if (-not ($log.output.PSObject.Properties.Name -contains "parallel_groups")) {
        throw "Expected parallel_groups in dry-run output"
    }

    # Clean up
    Remove-Item "logs/test-dry-run.json" -Force
}

# Test 2: Real execution mode with -RealExecution flag
Test-Case "Real execution mode with -RealExecution flag" {
    # Create a simple test workflow
    $testWorkflow = @"
workflow: test-real-execution
mode: parallel

steps:
  - id: step1
    task_id: "{task_id}"
    role: architect
    agent_role: agents/architect.md
    execution_spec: execution/architect.yaml
    depends_on: []

  - id: step2
    task_id: "{task_id}"
    role: architect
    agent_role: agents/architect.md
    execution_spec: execution/architect.yaml
    depends_on: ["step1"]
"@

    $testWorkflowPath = "workflows/test-real-execution.yaml"
    $testWorkflow | Set-Content -Encoding utf8 -Path $testWorkflowPath

    try {
        & powershell.exe -NoProfile -File "runner\workflow.ps1" `
            -TaskId "000_template" `
            -WorkflowSpec $testWorkflowPath `
            -LogOut "logs/test-real-execution.json" `
            -RealExecution | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Workflow execution failed with exit code $LASTEXITCODE"
        }

        # Read the log file
        $log = Get-Content "logs/test-real-execution.json" -Raw | ConvertFrom-Json

        # Check execution mode
        if ($log.output.execution_mode -ne "parallel-real") {
            throw "Expected execution_mode='parallel-real', got '$($log.output.execution_mode)'"
        }

        # Check that step_statuses exist (real execution)
        if (-not ($log.output.PSObject.Properties.Name -contains "step_statuses")) {
            throw "Expected step_statuses in real execution output"
        }

        # Check that both steps completed
        if ($log.output.step_statuses.step1.state -ne "Completed") {
            throw "Expected step1 Completed, got '$($log.output.step_statuses.step1.state)'"
        }

        if ($log.output.step_statuses.step2.state -ne "Completed") {
            throw "Expected step2 Completed, got '$($log.output.step_statuses.step2.state)'"
        }

    } finally {
        # Clean up
        Remove-Item $testWorkflowPath -Force -ErrorAction SilentlyContinue
        Remove-Item "logs/test-real-execution.json" -Force -ErrorAction SilentlyContinue
    }
}

# Test 3: Workflow log includes all required fields
Test-Case "Workflow log includes all required fields" {
    & powershell.exe -NoProfile -File "runner\workflow.ps1" `
        -TaskId "000_template" `
        -WorkflowSpec "workflows/implementation-review.yaml" `
        -LogOut "logs/test-log-fields.json" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Workflow execution failed with exit code $LASTEXITCODE"
    }

    # Read the log file
    $log = Get-Content "logs/test-log-fields.json" -Raw | ConvertFrom-Json

    # Check required top-level fields
    $requiredFields = @("task_id", "workflow_spec", "output")
    foreach ($field in $requiredFields) {
        if (-not ($log.PSObject.Properties.Name -contains $field)) {
            throw "Missing required field: $field"
        }
    }

    # Check required output fields (common to all workflows)
    $requiredOutputFields = @("workflow_summary", "step_logs", "retry_policy", "attempts", "final_status", "memory", "cost_tracking", "comparison")
    foreach ($field in $requiredOutputFields) {
        if (-not ($log.output.PSObject.Properties.Name -contains $field)) {
            throw "Missing required output field: $field"
        }
    }

    # Clean up
    Remove-Item "logs/test-log-fields.json" -Force
}

# Test 4: Memory persistence works across runs
Test-Case "Memory persistence works across runs" {
    # Create a workflow with memory enabled
    $testWorkflow = @"
workflow: test-memory-persistence
mode: sequential

memory:
  enabled: true
  persistence: file
  scope: workflow
  path: logs/memory/test-memory-{workflow}-{task_id}.json
  overwrite: merge

steps:
  - id: step1
    task_id: "{task_id}"
    role: architect
    agent_role: agents/architect.md
    execution_spec: execution/architect.yaml
    depends_on: []
"@

    $testWorkflowPath = "workflows/test-memory-persistence.yaml"
    $testWorkflow | Set-Content -Encoding utf8 -Path $testWorkflowPath

    try {
        # First run
        & powershell.exe -NoProfile -File "runner\workflow.ps1" `
            -TaskId "000_template" `
            -WorkflowSpec $testWorkflowPath `
            -LogOut "logs/test-memory-1.json" | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "First workflow execution failed with exit code $LASTEXITCODE"
        }

        $log1 = Get-Content "logs/test-memory-1.json" -Raw | ConvertFrom-Json

        # First run should NOT load memory (file doesn't exist yet)
        if ($log1.output.memory.loaded -ne $false) {
            throw "Expected memory.loaded=false on first run, got $($log1.output.memory.loaded)"
        }

        # First run SHOULD write memory
        if ($log1.output.memory.written -ne $true) {
            throw "Expected memory.written=true on first run, got $($log1.output.memory.written)"
        }

        # Second run with same task_id
        & powershell.exe -NoProfile -File "runner\workflow.ps1" `
            -TaskId "000_template" `
            -WorkflowSpec $testWorkflowPath `
            -LogOut "logs/test-memory-2.json" | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Second workflow execution failed with exit code $LASTEXITCODE"
        }

        $log2 = Get-Content "logs/test-memory-2.json" -Raw | ConvertFrom-Json

        # Second run SHOULD load memory
        if ($log2.output.memory.loaded -ne $true) {
            throw "Expected memory.loaded=true on second run, got $($log2.output.memory.loaded)"
        }

        # Second run SHOULD write memory
        if ($log2.output.memory.written -ne $true) {
            throw "Expected memory.written=true on second run, got $($log2.output.memory.written)"
        }

    } finally {
        # Clean up
        Remove-Item $testWorkflowPath -Force -ErrorAction SilentlyContinue
        Remove-Item "logs/test-memory-1.json" -Force -ErrorAction SilentlyContinue
        Remove-Item "logs/test-memory-2.json" -Force -ErrorAction SilentlyContinue
        Remove-Item "logs/memory/test-memory-test-memory-persistence-000_template.json" -Force -ErrorAction SilentlyContinue
    }
}

# Test 5: Cost tracking aggregates across steps
Test-Case "Cost tracking aggregates across steps" {
    & powershell.exe -NoProfile -File "runner\workflow.ps1" `
        -TaskId "000_template" `
        -WorkflowSpec "workflows/implementation-review.yaml" `
        -LogOut "logs/test-cost.json" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Workflow execution failed with exit code $LASTEXITCODE"
    }

    $log = Get-Content "logs/test-cost.json" -Raw | ConvertFrom-Json

    # Check cost_tracking exists
    if (-not ($log.output.PSObject.Properties.Name -contains "cost_tracking")) {
        throw "Missing cost_tracking in output"
    }

    # Check required cost_tracking fields
    if (-not ($log.output.cost_tracking.PSObject.Properties.Name -contains "estimated_total_cost")) {
        throw "Missing estimated_total_cost in cost_tracking"
    }

    if (-not ($log.output.cost_tracking.PSObject.Properties.Name -contains "currency")) {
        throw "Missing currency in cost_tracking"
    }

    # Clean up
    Remove-Item "logs/test-cost.json" -Force
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
