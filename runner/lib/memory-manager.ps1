# Memory Manager
# Handles persistent memory read/write for workflows

$ErrorActionPreference = "Stop"

function Read-Memory {
    <#
    .SYNOPSIS
    Loads memory from JSON file if enabled

    .PARAMETER MemoryPolicy
    Memory policy hashtable with enabled, persistence, path, scope

    .PARAMETER WorkflowName
    Workflow name for scope validation

    .PARAMETER TaskId
    Task ID for scope validation

    .OUTPUTS
    Hashtable with data and loaded flag
    #>
    param(
        [hashtable]$MemoryPolicy,
        [string]$WorkflowName,
        [string]$TaskId
    )

    # Return empty memory if disabled or dry-run
    if (-not $MemoryPolicy.enabled -or $MemoryPolicy.persistence -eq "dry-run") {
        return @{
            data = @{}
            loaded = $false
        }
    }

    $path = $MemoryPolicy.path

    # Return empty memory if file doesn't exist
    if (-not (Test-Path $path)) {
        Write-Verbose "Memory file not found: $path. Starting fresh."
        return @{
            data = @{}
            loaded = $false
        }
    }

    try {
        $memoryText = Get-Content -Encoding utf8 -Path $path -Raw
        $memoryData = $memoryText | ConvertFrom-Json

        # Convert PSCustomObject to hashtable
        $memoryHash = @{}
        $memoryData.PSObject.Properties | ForEach-Object {
            $memoryHash[$_.Name] = $_.Value
        }

        # Validate scope
        if ($MemoryPolicy.scope -eq "workflow" -and $memoryHash.ContainsKey("workflow")) {
            if ($memoryHash.workflow -ne $WorkflowName) {
                Write-Warning "Memory scope mismatch. Expected workflow: $WorkflowName, found: $($memoryHash.workflow)"
                return @{
                    data = @{}
                    loaded = $false
                }
            }
        }

        # Extract data field
        $data = if ($memoryHash.ContainsKey("data")) {
            # Convert PSCustomObject to hashtable recursively
            $dataHash = @{}
            if ($null -ne $memoryHash.data) {
                $memoryHash.data.PSObject.Properties | ForEach-Object {
                    $dataHash[$_.Name] = $_.Value
                }
            }
            $dataHash
        } else {
            @{}
        }

        Write-Verbose "Memory loaded from $path"

        return @{
            data = $data
            loaded = $true
        }
    } catch {
        Write-Warning "Failed to load memory from ${path}: $_"
        return @{
            data = @{}
            loaded = $false
        }
    }
}

function Write-Memory {
    <#
    .SYNOPSIS
    Saves memory to JSON file if enabled

    .PARAMETER MemoryPolicy
    Memory policy hashtable

    .PARAMETER MemoryData
    Data to save (hashtable)

    .PARAMETER WorkflowName
    Workflow name for metadata

    .PARAMETER TaskId
    Task ID for metadata

    .OUTPUTS
    Boolean: true if written, false otherwise
    #>
    param(
        [hashtable]$MemoryPolicy,
        [hashtable]$MemoryData,
        [string]$WorkflowName,
        [string]$TaskId
    )

    # Skip if disabled or dry-run
    if (-not $MemoryPolicy.enabled -or $MemoryPolicy.persistence -eq "dry-run") {
        return $false
    }

    $path = $MemoryPolicy.path
    $dir = Split-Path -Parent $path

    # Create directory if needed
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $memoryObject = [ordered]@{
        workflow = $WorkflowName
        task_id = $TaskId
        scope = $MemoryPolicy.scope
        last_updated = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        data = $MemoryData
    }

    try {
        $memoryObject | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 -Path $path
        Write-Verbose "Memory written to $path"
        return $true
    } catch {
        Write-Warning "Failed to write memory to ${path}: $_"
        return $false
    }
}

function Merge-MemoryData {
    <#
    .SYNOPSIS
    Merges new data into existing based on overwrite policy

    .PARAMETER Existing
    Existing memory data hashtable

    .PARAMETER New
    New memory data to merge

    .PARAMETER OverwritePolicy
    Merge strategy: merge (default), replace, preserve

    .OUTPUTS
    Merged data hashtable
    #>
    param(
        [hashtable]$Existing,
        [hashtable]$New,
        [string]$OverwritePolicy = "merge"
    )

    switch ($OverwritePolicy) {
        "merge" {
            # Shallow merge: new keys added, existing keys overwritten
            foreach ($key in $New.Keys) {
                $Existing[$key] = $New[$key]
            }
            return $Existing
        }
        "replace" {
            # Complete replacement
            return $New
        }
        "preserve" {
            # Only add new keys, never overwrite existing
            foreach ($key in $New.Keys) {
                if (-not $Existing.ContainsKey($key)) {
                    $Existing[$key] = $New[$key]
                }
            }
            return $Existing
        }
        default {
            throw "Unknown memory overwrite policy: $OverwritePolicy"
        }
    }
}

# Functions are available when dot-sourced with:
# . .\runner\lib\memory-manager.ps1
