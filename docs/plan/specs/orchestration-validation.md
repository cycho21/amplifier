# Orchestration: Dependency Graph Validation Specification

## 1. Objective

Implement parse-time validation for workflow dependency graphs to detect errors before execution, providing clear error messages for cycles, invalid dependencies, and structural issues.

**Target Users:**
- Workflow authors creating multi-agent orchestration specs
- Amplifier framework maintainers
- CI/CD pipeline developers

**Success Criteria:**
- Workflows are validated immediately after loading (parse-time)
- Cyclic dependencies detected with clear cycle path in error message
- Invalid dependencies (referencing non-existent steps) cause immediate failure
- Self-dependencies detected with specific error message
- Existing dry-run and real execution behavior preserved
- Validation adds <100ms overhead for typical workflows (<20 steps)

**Out of Scope (for this spec):**
- Real concurrent process execution (separate task)
- Failure propagation (separate task)
- Result voting (separate task)
- Dynamic dependency changes at runtime

---

## 2. Commands

### Existing Commands (Modified)

```powershell
# Execute workflow with validation
.\runner\workflow.ps1 `
    -TaskId "001_implement_auth" `
    -WorkflowSpec "workflows/implementation-review.yaml" `
    -LogOut "logs/workflow-001.json"

# Validation happens automatically after loading YAML
# If validation fails, workflow stops with clear error before any step executes
```

### New Validation Command (Optional)

```powershell
# Validate workflow without executing
.\runner\validate-workflow.ps1 `
    -WorkflowSpec "workflows/implementation-review.yaml"

# Outputs:
# ✓ Workflow 'implementation-review' is valid
# OR
# ✗ Validation failed: Cycle detected: step 'A' depends on 'B', step 'B' depends on 'A'
```

---

## 3. Project Structure

### New/Modified Files

```
amplifier/
├── runner/
│   ├── lib/
│   │   └── workflow-validator.ps1  # [NEW] Dependency graph validation
│   ├── workflow.ps1                # [MODIFIED] Add validation before execution
│   └── validate-workflow.ps1       # [NEW] Standalone validation tool
├── tests/
│   ├── fixtures/
│   │   └── workflows/
│   │       ├── invalid-cycle.yaml         # [NEW] Test fixture: cycle
│   │       ├── invalid-missing-dep.yaml   # [NEW] Test fixture: missing dependency
│   │       └── invalid-self-dep.yaml      # [NEW] Test fixture: self-dependency
│   └── integration/
│       └── test-workflow-validation.ps1   # [NEW] Validation tests
└── docs/
    └── plan/
        └── specs/
            └── orchestration-validation.md  # [NEW] This file
```

---

## 4. Validation Rules

### Rule 1: No Cycles

**Definition:** A workflow contains a cycle if following `depends_on` references forms a closed loop.

**Example (Invalid):**
```yaml
steps:
  - id: A
    depends_on: [B]
  - id: B
    depends_on: [C]
  - id: C
    depends_on: [A]  # Cycle: A → B → C → A
```

**Error Message:**
```
Workflow validation failed: Cycle detected
Cycle path: A → B → C → A
```

**Detection Algorithm:** Depth-First Search (DFS) with visited/on-stack tracking.

---

### Rule 2: No Self-Dependencies

**Definition:** A step cannot depend on itself.

**Example (Invalid):**
```yaml
steps:
  - id: A
    depends_on: [A]  # Self-dependency
```

**Error Message:**
```
Workflow validation failed: Self-dependency detected
Step 'A' cannot depend on itself
```

---

### Rule 3: All Dependencies Must Exist

**Definition:** Every step referenced in `depends_on` must be defined in the workflow.

**Example (Invalid):**
```yaml
steps:
  - id: A
    depends_on: [NONEXISTENT]  # No step with id 'NONEXISTENT'
```

**Error Message:**
```
Workflow validation failed: Invalid dependency
Step 'A' depends on 'NONEXISTENT', which does not exist in the workflow
```

---

### Rule 4: Workflow Must Have At Least One Step

**Definition:** Empty workflows are invalid.

**Example (Invalid):**
```yaml
steps: []
```

**Error Message:**
```
Workflow validation failed: Empty workflow
Workflow must contain at least one step
```

---

## 5. Implementation Design

### Core Validation Function

**Location:** `runner/lib/workflow-validator.ps1`

```powershell
function Test-WorkflowDependencies {
    <#
    .SYNOPSIS
    Validate workflow dependency graph for cycles and invalid references

    .PARAMETER Steps
    Array of workflow step objects

    .OUTPUTS
    Validation result object with errors array
    #>
    param([array]$Steps)

    $errors = @()

    # Rule 4: Check for empty workflow
    if ($Steps.Count -eq 0) {
        $errors += [ordered]@{
            type = "empty_workflow"
            message = "Workflow must contain at least one step"
        }
        return @{ valid = $false; errors = $errors }
    }

    # Build step ID index
    $stepIds = @{}
    foreach ($step in $Steps) {
        $stepIds[$step.id] = $true
    }

    # Rule 2: Check for self-dependencies
    foreach ($step in $Steps) {
        if ($step.depends_on -contains $step.id) {
            $errors += [ordered]@{
                type = "self_dependency"
                step = $step.id
                message = "Step '$($step.id)' cannot depend on itself"
            }
        }
    }

    # Rule 3: Check for invalid dependencies
    foreach ($step in $Steps) {
        foreach ($dep in $step.depends_on) {
            if (-not $stepIds.ContainsKey($dep)) {
                $errors += [ordered]@{
                    type = "invalid_dependency"
                    step = $step.id
                    dependency = $dep
                    message = "Step '$($step.id)' depends on '$dep', which does not exist in the workflow"
                }
            }
        }
    }

    # Rule 1: Check for cycles using DFS
    $cycleErrors = Find-DependencyCycles -Steps $Steps
    $errors += $cycleErrors

    if ($errors.Count -eq 0) {
        return @{ valid = $true; errors = @() }
    }

    return @{ valid = $false; errors = $errors }
}

function Find-DependencyCycles {
    <#
    .SYNOPSIS
    Detect cycles in dependency graph using DFS

    .PARAMETER Steps
    Array of workflow step objects

    .OUTPUTS
    Array of cycle error objects
    #>
    param([array]$Steps)

    $errors = @()
    $visited = @{}
    $onStack = @{}
    $adjacency = @{}

    # Build adjacency list
    foreach ($step in $Steps) {
        $adjacency[$step.id] = $step.depends_on
    }

    # DFS function
    $dfsVisit = {
        param($stepId, $path)

        if ($onStack[$stepId]) {
            # Cycle detected - extract cycle path
            $cycleStart = $path.IndexOf($stepId)
            $cyclePath = $path[$cycleStart..($path.Count - 1)] + @($stepId)
            $cyclePathStr = $cyclePath -join " → "

            $errors += [ordered]@{
                type = "cycle"
                path = $cyclePath
                message = "Cycle detected: $cyclePathStr"
            }
            return
        }

        if ($visited[$stepId]) {
            return
        }

        $visited[$stepId] = $true
        $onStack[$stepId] = $true

        foreach ($dep in $adjacency[$stepId]) {
            & $dfsVisit $dep ($path + @($stepId))
        }

        $onStack[$stepId] = $false
    }

    # Run DFS from each node
    foreach ($step in $Steps) {
        if (-not $visited[$step.id]) {
            & $dfsVisit $step.id @()
        }
    }

    return $errors
}
```

---

### Integration with workflow.ps1

**Modification Point:** After `Read-WorkflowSteps`, before execution

```powershell
# In workflow.ps1, after loading steps:
$steps = Read-WorkflowSteps $workflowLines $TaskId

# NEW: Validate workflow dependencies
. (Join-Path $PSScriptRoot "lib/workflow-validator.ps1")
$validation = Test-WorkflowDependencies -Steps $steps

if (-not $validation.valid) {
    Write-Output "Workflow validation failed:"
    foreach ($error in $validation.errors) {
        Write-Output "  ✗ $($error.message)"
    }
    throw "Workflow validation failed. See errors above."
}

# Continue with existing execution logic...
```

---

## 6. Code Style

### PowerShell Conventions

**Follow existing codebase patterns:**
- Strict error handling: `$ErrorActionPreference = "Stop"`
- Clear function names: `Test-WorkflowDependencies`, `Find-DependencyCycles`
- Ordered hashtables for structured output: `[ordered]@{}`
- Descriptive error messages with step IDs and paths
- DFS implementation using scriptblocks for nested recursion

### Error Message Format

```
Workflow validation failed: <Error Type>
<Detailed message with step IDs>
```

Example:
```
Workflow validation failed: Cycle detected
Cycle path: backend → tester → reviewer → backend
```

---

## 7. Testing Strategy

### Test Levels

**1. Unit Tests (Validation Logic)**
- Test cycle detection with various graph structures
- Test invalid dependency detection
- Test self-dependency detection
- Test empty workflow detection
- Test valid workflows pass without errors

**2. Integration Tests (End-to-End)**
- Test workflow.ps1 rejects invalid workflows before execution
- Test validation adds minimal overhead (<100ms for 20 steps)
- Test error messages are clear and actionable

### Test Fixtures

**Invalid Workflows:**

`tests/fixtures/workflows/invalid-cycle.yaml`:
```yaml
workflow: invalid-cycle
mode: parallel

steps:
  - id: A
    depends_on: [B]
  - id: B
    depends_on: [C]
  - id: C
    depends_on: [A]
```

`tests/fixtures/workflows/invalid-missing-dep.yaml`:
```yaml
workflow: invalid-missing-dep
mode: sequential

steps:
  - id: A
    depends_on: [NONEXISTENT]
```

`tests/fixtures/workflows/invalid-self-dep.yaml`:
```yaml
workflow: invalid-self-dep
mode: sequential

steps:
  - id: A
    depends_on: [A]
```

**Valid Workflows:**

Existing workflows should continue to pass validation:
- `workflows/implementation-review.yaml`
- `workflows/parallel-review.yaml`

---

## 8. Boundaries

### What This Spec DOES Include

✅ Parse-time dependency graph validation
✅ Cycle detection with clear path in error message
✅ Invalid dependency detection
✅ Self-dependency detection
✅ Empty workflow detection
✅ Standalone validation tool (`validate-workflow.ps1`)
✅ Integration tests for all validation rules

### What This Spec DOES NOT Include

❌ Real concurrent execution (next task)
❌ Failure propagation rules (next task)
❌ Cancellation logic (next task)
❌ Result voting (next task)
❌ Dynamic dependency changes at runtime
❌ Performance optimization for very large graphs (>1000 steps)

### Always Do

- Validate before any step execution
- Provide clear, actionable error messages
- Include step IDs and paths in error messages
- Preserve existing dry-run and real execution behavior
- Keep validation fast (<100ms for typical workflows)

### Ask First About

- Adding new validation rules beyond the 4 core rules
- Changing error message format
- Adding warnings vs errors (currently all errors)
- Validation performance threshold for large workflows

### Never Do

- Skip validation if workflow "looks simple"
- Silently fix invalid workflows (always fail with error)
- Execute any steps before validation passes
- Change existing workflow YAML schema

---

## 9. Acceptance Criteria

**This spec is complete when:**

1. ✅ `runner/lib/workflow-validator.ps1` implements all 4 validation rules
2. ✅ `runner/workflow.ps1` validates workflows before execution
3. ✅ Cycle detection uses DFS algorithm and reports full cycle path
4. ✅ Invalid dependencies cause immediate failure with clear error
5. ✅ Self-dependencies detected with specific error message
6. ✅ Empty workflows rejected with clear error
7. ✅ Validation adds <100ms overhead for workflows with <20 steps
8. ✅ All existing valid workflows continue to pass
9. ✅ Integration tests cover all validation rules
10. ✅ Standalone `validate-workflow.ps1` tool available

---

## 10. Implementation Order

**Recommended sequence:**

1. Create `runner/lib/workflow-validator.ps1` with core validation functions
2. Add test fixtures for invalid workflows
3. Add integration tests
4. Integrate validation into `runner/workflow.ps1` (after step loading)
5. Create standalone `validate-workflow.ps1` tool
6. Update documentation with examples
7. Run full test suite to ensure no regressions

---

## 11. Error Examples

### Example 1: Cycle Detection

**Input:** `workflows/invalid-cycle.yaml`
```yaml
steps:
  - id: A
    depends_on: [B]
  - id: B
    depends_on: [A]
```

**Output:**
```
Workflow validation failed:
  ✗ Cycle detected: A → B → A

Error: Workflow validation failed. See errors above.
```

### Example 2: Invalid Dependency

**Input:** `workflows/invalid-missing-dep.yaml`
```yaml
steps:
  - id: implementer
    depends_on: [architect]
  # No step with id 'architect'
```

**Output:**
```
Workflow validation failed:
  ✗ Step 'implementer' depends on 'architect', which does not exist in the workflow

Error: Workflow validation failed. See errors above.
```

### Example 3: Self-Dependency

**Input:** `workflows/invalid-self-dep.yaml`
```yaml
steps:
  - id: tester
    depends_on: [tester]
```

**Output:**
```
Workflow validation failed:
  ✗ Step 'tester' cannot depend on itself

Error: Workflow validation failed. See errors above.
```

### Example 4: Multiple Errors

**Input:** Workflow with multiple issues

**Output:**
```
Workflow validation failed:
  ✗ Step 'A' cannot depend on itself
  ✗ Step 'B' depends on 'NONEXISTENT', which does not exist in the workflow
  ✗ Cycle detected: C → D → C

Error: Workflow validation failed. See errors above.
```

---

## 12. Performance Considerations

**Validation Complexity:**
- Cycle detection: O(V + E) where V = steps, E = dependencies
- Invalid dependency check: O(V * D) where D = avg dependencies per step
- Expected overhead: <100ms for V=20, D=3

**Optimization Opportunities (future):**
- Cache validation results for unchanged workflows
- Parallel validation for independent checks
- Early termination on first error (if fast-fail mode desired)

**Current Threshold:**
- Target: <100ms for workflows with <20 steps
- Warning: >1000ms for workflows with >100 steps
- No hard limit, but validation time logged for monitoring

---

## 13. Visualization and Progress Reporting

### Overview

Display real-time workflow execution status with ASCII art visualization showing:
- Current execution state (completed, running, waiting)
- Dependency graph structure
- Step-by-step progress within each agent
- Execution time tracking

### Dependency Graph Visualization

**Before Execution (Validation):**
```
Validating workflow: parallel-review

Dependency Graph:
  backend-engineer ──┐
                     ├──> tester ────┐
  frontend-engineer ─┤                ├──> deployer
                     └──> reviewer ───┘

✓ No cycles detected
✓ All dependencies valid
✓ Workflow ready to execute
```

**Algorithm:** Use topological ordering to determine visual layout.

### Execution Progress Visualization

**During Execution:**
```
Workflow: parallel-review (parallel mode) - Group 2/3

Group 1: Completed (5.1s)
  [✓] backend-engineer (3.2s)
  [✓] frontend-engineer (2.8s)

Group 2: Running (2.3s elapsed)
  [►] tester
      ├─ [✓] Reading task & context (0.1s)
      ├─ [►] Invoking OpenAI API... (2.1s)
      └─ [ ] Parsing response

  [►] reviewer
      ├─ [✓] Reading task & context (0.1s)
      ├─ [►] Invoking Claude CLI... (2.0s)
      └─ [ ] Parsing response

Group 3: Waiting
  [ ] deployer (depends on: tester, reviewer)
```

### Step-by-Step Agent Progress

**Execution Stages per Agent:**

1. **Reading task & context** (fast, <1s)
   - Load task file
   - Load agent role
   - Load execution spec
   - Build prompt

2. **Invoking LLM** (slow, variable)
   - Call API/CLI
   - Wait for response
   - Track elapsed time

3. **Parsing response** (fast, <1s)
   - Parse JSON
   - Validate contract
   - Retry if needed (show retry count)

4. **Completed** (final state)
   - Show total time
   - Show provider metadata (model, tokens)

### Progress Symbols

```
[ ] - Waiting (not started)
[►] - Running (in progress)
[✓] - Completed (success)
[✗] - Failed (error)
[⟳] - Retrying (after parse failure)
```

### Implementation Design

**Location:** `runner/lib/workflow-visualizer.ps1`

```powershell
function Show-WorkflowProgress {
    <#
    .SYNOPSIS
    Display real-time workflow execution progress with ASCII art

    .PARAMETER Workflow
    Workflow object with current state

    .PARAMETER Mode
    Display mode: 'compact' or 'detailed'
    #>
    param(
        [object]$Workflow,
        [string]$Mode = "detailed"
    )

    Clear-Host  # Clear console for refresh

    # Header
    Write-Host "Workflow: $($Workflow.name) ($($Workflow.mode) mode)" -ForegroundColor Cyan
    Write-Host ""

    # Progress by group (for parallel workflows)
    $groupIndex = 1
    foreach ($group in $Workflow.groups) {
        $groupStatus = Get-GroupStatus $group
        $groupTime = Get-GroupElapsedTime $group

        Write-Host "Group $groupIndex/$($Workflow.groups.Count): $groupStatus ($groupTime)" -ForegroundColor Yellow

        foreach ($step in $group.steps) {
            Show-StepProgress -Step $step -Mode $Mode
        }

        Write-Host ""
        $groupIndex++
    }
}

function Show-StepProgress {
    param(
        [object]$Step,
        [string]$Mode
    )

    $symbol = Get-ProgressSymbol -Status $Step.status
    $elapsed = Get-ElapsedTime -Step $Step

    Write-Host "  $symbol $($Step.id)" -NoNewline
    
    if ($Step.status -eq "running" -or $Step.status -eq "completed") {
        Write-Host " ($elapsed)" -ForegroundColor Gray
    } else {
        Write-Host ""
    }

    # Show sub-stages (detailed mode only)
    if ($Mode -eq "detailed" -and $Step.status -eq "running") {
        foreach ($stage in $Step.stages) {
            $stageSymbol = Get-ProgressSymbol -Status $stage.status
            $stageName = $stage.name
            $stageTime = if ($stage.elapsed) { " ($($stage.elapsed)s)" } else { "" }

            Write-Host "      ├─ $stageSymbol $stageName$stageTime" -ForegroundColor DarkGray
        }
        Write-Host "      └─ [ ] " -ForegroundColor DarkGray -NoNewline
        Write-Host "Waiting..." -ForegroundColor DarkGray
    }

    # Show retry count if applicable
    if ($Step.retries -gt 0) {
        Write-Host "      [⟳] Retry $($Step.retries)/3" -ForegroundColor Yellow
    }

    # Show waiting dependencies
    if ($Step.status -eq "waiting" -and $Step.depends_on.Count -gt 0) {
        $deps = $Step.depends_on -join ", "
        Write-Host "      (depends on: $deps)" -ForegroundColor DarkGray
    }
}

function Get-ProgressSymbol {
    param([string]$Status)

    switch ($Status) {
        "waiting"   { return "[ ]" }
        "running"   { return "[►]" }
        "completed" { return "[✓]" }
        "failed"    { return "[✗]" }
        "retrying"  { return "[⟳]" }
        default     { return "[?]" }
    }
}

function Show-DependencyGraph {
    <#
    .SYNOPSIS
    Display workflow dependency graph as ASCII art

    .PARAMETER Steps
    Array of workflow steps
    #>
    param([array]$Steps)

    Write-Host "Dependency Graph:" -ForegroundColor Cyan
    Write-Host ""

    # Build adjacency list for reverse dependencies (who depends on me)
    $dependents = @{}
    foreach ($step in $Steps) {
        foreach ($dep in $step.depends_on) {
            if (-not $dependents.ContainsKey($dep)) {
                $dependents[$dep] = @()
            }
            $dependents[$dep] += $step.id
        }
    }

    # Display each step and its dependencies
    foreach ($step in $Steps) {
        if ($step.depends_on.Count -eq 0) {
            # Root node (no dependencies)
            Write-Host "  $($step.id)" -ForegroundColor Green
        } else {
            # Has dependencies
            $deps = $step.depends_on -join ", "
            Write-Host "  $($step.id) " -NoNewline -ForegroundColor Yellow
            Write-Host "(depends on: $deps)" -ForegroundColor DarkGray
        }

        # Show arrows to dependents
        if ($dependents.ContainsKey($step.id)) {
            foreach ($dependent in $dependents[$step.id]) {
                Write-Host "      └──> $dependent" -ForegroundColor DarkGray
            }
        }
    }

    Write-Host ""
}
```

### Stage Tracking

**Step Stages (tracked in step state):**

```powershell
$step.stages = @(
    @{ name = "Reading task & context"; status = "completed"; elapsed = 0.1 }
    @{ name = "Invoking OpenAI API"; status = "running"; elapsed = 2.3 }
    @{ name = "Parsing response"; status = "waiting"; elapsed = 0 }
)
```

**Update Strategy:**
- Use callbacks or state updates in runner scripts
- Update display every 0.5s during execution
- Final refresh on completion

### Integration Points

**In workflow.ps1:**

```powershell
# After validation, before execution
. (Join-Path $PSScriptRoot "lib/workflow-visualizer.ps1")

# Show initial dependency graph
Show-DependencyGraph -Steps $steps

# During execution (in execution loops)
while ($executing) {
    Show-WorkflowProgress -Workflow $workflowState -Mode "detailed"
    Start-Sleep -Milliseconds 500
}
```

**In runner scripts (codex.ps1, claude.ps1):**

```powershell
# Update stage: Reading task
Update-StepStage -StepId $StepId -Stage "Reading task & context" -Status "running"
# ... read files ...
Update-StepStage -StepId $StepId -Stage "Reading task & context" -Status "completed" -Elapsed 0.1

# Update stage: Invoking LLM
Update-StepStage -StepId $StepId -Stage "Invoking OpenAI API" -Status "running"
# ... API call ...
Update-StepStage -StepId $StepId -Stage "Invoking OpenAI API" -Status "completed" -Elapsed 3.2

# Update stage: Parsing
Update-StepStage -StepId $StepId -Stage "Parsing response" -Status "running"
# ... parse ...
Update-StepStage -StepId $StepId -Stage "Parsing response" -Status "completed" -Elapsed 0.3
```

### Display Modes

**Compact Mode:**
```
Workflow: parallel-review - Group 2/3

[✓] backend-engineer (3.2s)
[✓] frontend-engineer (2.8s)
[►] tester (2.1s)
[►] reviewer (2.0s)
[ ] deployer (waiting)
```

**Detailed Mode (Default):**
```
Workflow: parallel-review - Group 2/3

[►] tester (2.1s)
    ├─ [✓] Reading task & context (0.1s)
    ├─ [►] Invoking OpenAI API... (2.1s)
    └─ [ ] Parsing response
```

### Visual Examples

**Example 1: Sequential Workflow**
```
Workflow: implementation-review (sequential mode)

[✓] architect (4.5s)
[✓] implementer (12.3s)
    ├─ [✓] Reading task & context (0.2s)
    ├─ [✓] Invoking OpenAI API (11.8s)
    └─ [✓] Parsing response (0.3s)
[►] tester (3.2s)
    ├─ [✓] Reading task & context (0.1s)
    ├─ [►] Invoking Claude CLI... (3.1s)
    └─ [ ] Parsing response
[ ] reviewer (waiting on: tester)
```

**Example 2: Parallel Workflow with Retry**
```
Workflow: parallel-review (parallel mode) - Group 2/3

Group 1: Completed (5.1s)
  [✓] backend-engineer (3.2s)
  [✓] frontend-engineer (2.8s)

Group 2: Running (5.5s elapsed)
  [⟳] tester (5.5s)
      ├─ [✓] Reading task & context (0.1s)
      ├─ [✓] Invoking OpenAI API (4.2s)
      ├─ [✗] Parsing response (failed - invalid JSON)
      ├─ [✓] Invoking OpenAI API (1.0s) [retry 1/3]
      └─ [►] Parsing response...
      [⟳] Retry 1/3

  [►] reviewer (2.3s)
      ├─ [✓] Reading task & context (0.1s)
      ├─ [►] Invoking Claude CLI... (2.1s)
      └─ [ ] Parsing response
```

### Color Coding

- **Cyan**: Workflow name, section headers
- **Green**: Completed steps/stages
- **Yellow**: Running steps, group status
- **Red**: Failed steps/stages
- **DarkGray**: Sub-stages, dependencies, metadata
- **White**: Default text

### Refresh Strategy

**Option A: Continuous Refresh (Recommended)**
- Clear screen every 0.5s
- Redraw entire display
- Smooth visual updates

**Option B: Incremental Updates**
- Only update changed lines
- More complex, less flicker
- Better for very large workflows

**Implementation: Option A** (simpler, sufficient for most workflows)

### Acceptance Criteria

1. ✅ Dependency graph displayed before execution
2. ✅ Real-time progress updates during execution
3. ✅ Step-by-step stage tracking (reading, invoking, parsing)
4. ✅ Retry attempts shown with count
5. ✅ Elapsed time displayed per step and stage
6. ✅ Color-coded status symbols
7. ✅ Compact and detailed display modes
8. ✅ Works with both sequential and parallel workflows
9. ✅ Minimal performance overhead (<10ms per refresh)
10. ✅ Display clears/refreshes without flickering
