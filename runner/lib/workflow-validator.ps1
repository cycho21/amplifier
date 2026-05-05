# Workflow Dependency Graph Validator
# Validates workflow dependency graphs for cycles, invalid references, and structural issues

$ErrorActionPreference = "Stop"

function Test-WorkflowDependencies {
    <#
    .SYNOPSIS
    Validate workflow dependency graph for cycles and invalid references

    .PARAMETER Steps
    Array of workflow step objects (each with id and depends_on fields)

    .OUTPUTS
    Hashtable with valid (boolean) and errors (array) fields
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

    # Build step ID index for quick lookup
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

    # Rule 3: Check for invalid dependencies (references to non-existent steps)
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
    foreach ($cycleError in $cycleErrors) {
        $errors += $cycleError
    }

    if ($errors.Count -eq 0) {
        return @{ valid = $true; errors = @() }
    }

    return @{ valid = $false; errors = $errors }
}

function Find-DependencyCycles {
    <#
    .SYNOPSIS
    Detect cycles in dependency graph using Depth-First Search

    .PARAMETER Steps
    Array of workflow step objects

    .OUTPUTS
    Array of cycle error objects with type, path, and message fields
    #>
    param([array]$Steps)

    $cycleErrors = @()
    $visited = @{}
    $onStack = @{}
    $adjacency = @{}
    $reportedCycles = @{}

    # Build adjacency list (step -> list of dependencies)
    foreach ($step in $Steps) {
        $adjacency[$step.id] = $step.depends_on
    }

    # Recursive DFS to detect cycles
    function Visit-DFSNode {
        param(
            [string]$NodeId,
            [array]$Path,
            [hashtable]$Visited,
            [hashtable]$OnStack,
            [hashtable]$Adjacency,
            [hashtable]$Reported
        )

        # Cycle detected if node is on current recursion stack
        if ($OnStack[$NodeId]) {
            # Find where cycle starts
            $cycleStart = -1
            for ($i = 0; $i -lt $Path.Count; $i++) {
                if ($Path[$i] -eq $NodeId) {
                    $cycleStart = $i
                    break
                }
            }

            if ($cycleStart -ge 0) {
                $cyclePath = $Path[$cycleStart..($Path.Count - 1)] + @($NodeId)

                # Normalize cycle for deduplication (sorted unique nodes)
                $cycleKey = (($cyclePath | Select-Object -Unique | Sort-Object) -join "-")

                if (-not $Reported.ContainsKey($cycleKey)) {
                    $Reported[$cycleKey] = $true
                    $cyclePathStr = $cyclePath -join " → "

                    return [ordered]@{
                        type = "cycle"
                        path = $cyclePath
                        message = "Cycle detected: $cyclePathStr"
                    }
                }
            }
            return $null
        }

        # Skip if already fully processed
        if ($Visited[$NodeId]) {
            return $null
        }

        # Mark node as visited and on stack
        $Visited[$NodeId] = $true
        $OnStack[$NodeId] = $true

        $foundCycles = @()

        # Visit dependencies
        if ($Adjacency.ContainsKey($NodeId)) {
            foreach ($dep in $Adjacency[$NodeId]) {
                $newPath = $Path + @($NodeId)
                $cycleFound = Visit-DFSNode `
                    -NodeId $dep `
                    -Path $newPath `
                    -Visited $Visited `
                    -OnStack $OnStack `
                    -Adjacency $Adjacency `
                    -Reported $Reported

                if ($null -ne $cycleFound) {
                    $foundCycles += $cycleFound
                }
            }
        }

        # Remove from stack (backtrack)
        $OnStack[$NodeId] = $false

        return $foundCycles
    }

    # Run DFS from each unvisited node
    foreach ($step in $Steps) {
        if (-not $visited[$step.id]) {
            $cycles = Visit-DFSNode `
                -NodeId $step.id `
                -Path @() `
                -Visited $visited `
                -OnStack $onStack `
                -Adjacency $adjacency `
                -Reported $reportedCycles

            if ($null -ne $cycles) {
                foreach ($cycle in $cycles) {
                    $cycleErrors += $cycle
                }
            }
        }
    }

    return $cycleErrors
}

# Functions are available when dot-sourced with:
# . .\runner\lib\workflow-validator.ps1
