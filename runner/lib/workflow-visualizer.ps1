# Workflow Visualization
# ASCII art display for dependency graphs and execution progress

$ErrorActionPreference = "Stop"

function Show-DependencyGraph {
    <#
    .SYNOPSIS
    Display workflow dependency graph as ASCII art

    .PARAMETER Steps
    Array of workflow step objects (each with id and depends_on fields)

    .OUTPUTS
    None (displays to console)
    #>
    param([array]$Steps)

    Write-Host ""
    Write-Host "Dependency Graph:" -ForegroundColor Cyan
    Write-Host ""

    # Build reverse adjacency list (who depends on me)
    $dependents = @{}
    foreach ($step in $Steps) {
        if (-not $dependents.ContainsKey($step.id)) {
            $dependents[$step.id] = @()
        }

        foreach ($dep in $step.depends_on) {
            if (-not $dependents.ContainsKey($dep)) {
                $dependents[$dep] = @()
            }
            $dependents[$dep] += $step.id
        }
    }

    # Display each step with its dependencies and dependents
    foreach ($step in $Steps) {
        $isRoot = ($step.depends_on.Count -eq 0)

        if ($isRoot) {
            Write-Host "  " -NoNewline
            Write-Host "$($step.id)" -ForegroundColor Green -NoNewline
            Write-Host " (no dependencies)" -ForegroundColor DarkGray
        } else {
            Write-Host "  " -NoNewline
            Write-Host "$($step.id)" -ForegroundColor Yellow -NoNewline
            Write-Host " (depends on: " -ForegroundColor DarkGray -NoNewline
            Write-Host ($step.depends_on -join ", ") -ForegroundColor Cyan -NoNewline
            Write-Host ")" -ForegroundColor DarkGray
        }

        # Show arrows to dependents
        if ($dependents[$step.id].Count -gt 0) {
            foreach ($dependent in $dependents[$step.id]) {
                Write-Host "      └──> " -ForegroundColor DarkGray -NoNewline
                Write-Host $dependent -ForegroundColor Magenta
            }
        }
    }

    Write-Host ""
}

function Show-ValidationResult {
    <#
    .SYNOPSIS
    Display workflow validation summary with checkmarks/X marks

    .PARAMETER Validation
    Validation result from Test-WorkflowDependencies

    .OUTPUTS
    None (displays to console)
    #>
    param([hashtable]$Validation)

    Write-Host "Validation:" -ForegroundColor Cyan
    Write-Host ""

    $rules = @(
        @{ name = "No cycles"; type = "cycle" }
        @{ name = "No self-dependencies"; type = "self_dependency" }
        @{ name = "All dependencies exist"; type = "invalid_dependency" }
        @{ name = "Non-empty workflow"; type = "empty_workflow" }
    )

    foreach ($rule in $rules) {
        $hasError = $Validation.errors | Where-Object { $_.type -eq $rule.type }

        if ($hasError) {
            Write-Host "  ✗ " -ForegroundColor Red -NoNewline
            Write-Host $rule.name -ForegroundColor Red
        } else {
            Write-Host "  ✓ " -ForegroundColor Green -NoNewline
            Write-Host $rule.name -ForegroundColor Green
        }
    }

    Write-Host ""

    if ($Validation.valid) {
        Write-Host "Workflow ready to execute" -ForegroundColor Green
    } else {
        Write-Host "Workflow has validation errors" -ForegroundColor Red
    }

    Write-Host ""
}

function Get-ProgressSymbol {
    <#
    .SYNOPSIS
    Get progress symbol for step status

    .PARAMETER Status
    Step status: waiting, running, completed, failed, retrying

    .OUTPUTS
    String symbol for the status
    #>
    param([string]$Status)

    switch ($Status) {
        "waiting"   { return "[ ]" }
        "running"   { return "[►]" }
        "completed" { return "[✓]" }
        "failed"    { return "[✗]" }
        "retrying"  { return "[⟳]" }
        default     { return "[ ]" }
    }
}

function Show-StepProgress {
    <#
    .SYNOPSIS
    Display individual step progress

    .PARAMETER Step
    Step object with id, status, elapsed, and optional stages

    .PARAMETER Mode
    Display mode: "compact" or "detailed"

    .OUTPUTS
    None (displays to console)
    #>
    param(
        [hashtable]$Step,
        [string]$Mode = "compact"
    )

    $symbol = Get-ProgressSymbol -Status $Step.status
    $color = switch ($Step.status) {
        "completed" { "Green" }
        "running"   { "Yellow" }
        "failed"    { "Red" }
        "retrying"  { "Cyan" }
        default     { "DarkGray" }
    }

    # Display symbol and step ID
    Write-Host "  " -NoNewline
    Write-Host $symbol -ForegroundColor $color -NoNewline
    Write-Host " $($Step.id)" -NoNewline

    # Display elapsed time if available
    if ($Step.elapsed) {
        $elapsedStr = "{0:F1}s" -f $Step.elapsed
        if ($Step.status -eq "waiting") {
            Write-Host " (waiting)" -ForegroundColor DarkGray
        } else {
            Write-Host " ($elapsedStr)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host ""
    }

    # Display stages in detailed mode
    if ($Mode -eq "detailed" -and $Step.stages) {
        Show-StepStages -Stages $Step.stages
    }
}

function Show-StepStages {
    <#
    .SYNOPSIS
    Display sub-stages of a step

    .PARAMETER Stages
    Array of stage objects with name, status, elapsed

    .OUTPUTS
    None (displays to console)
    #>
    param([array]$Stages)

    $stageCount = $Stages.Count
    for ($i = 0; $i -lt $stageCount; $i++) {
        $stage = $Stages[$i]
        $isLast = ($i -eq $stageCount - 1)
        $symbol = Get-ProgressSymbol -Status $stage.status

        # Draw tree structure
        if ($isLast) {
            Write-Host "      └─ " -ForegroundColor DarkGray -NoNewline
        } else {
            Write-Host "      ├─ " -ForegroundColor DarkGray -NoNewline
        }

        # Symbol and stage name
        $color = switch ($stage.status) {
            "completed" { "Green" }
            "running"   { "Yellow" }
            default     { "DarkGray" }
        }

        Write-Host $symbol -ForegroundColor $color -NoNewline
        Write-Host " $($stage.name)" -NoNewline

        # Elapsed time
        if ($stage.elapsed) {
            $elapsedStr = "{0:F1}s" -f $stage.elapsed
            Write-Host " ($elapsedStr)" -ForegroundColor DarkGray
        } elseif ($stage.status -eq "running") {
            Write-Host "..." -ForegroundColor Yellow
        } else {
            Write-Host ""
        }
    }
}

function Show-WorkflowProgress {
    <#
    .SYNOPSIS
    Display overall workflow progress

    .PARAMETER Workflow
    Workflow object with name, mode, steps

    .PARAMETER Mode
    Display mode: "compact" or "detailed"

    .OUTPUTS
    None (displays to console)
    #>
    param(
        [hashtable]$Workflow,
        [string]$Mode = "compact"
    )

    Write-Host ""
    Write-Host "Workflow: " -NoNewline -ForegroundColor Cyan
    Write-Host "$($Workflow.name) " -NoNewline
    Write-Host "($($Workflow.mode))" -ForegroundColor DarkGray
    Write-Host ""

    foreach ($step in $Workflow.steps) {
        Show-StepProgress -Step $step -Mode $Mode
    }

    Write-Host ""
}

# Functions are available when dot-sourced with:
# . .\runner\lib\workflow-visualizer.ps1
