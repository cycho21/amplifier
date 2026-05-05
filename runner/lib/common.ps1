# Common utilities for Mini Amplifier runners
# Shared functions extracted from workflow.ps1, codex.ps1, claude.ps1

$ErrorActionPreference = "Stop"

function Read-Utf8File {
    <#
    .SYNOPSIS
    Read a UTF-8 file safely with error handling

    .PARAMETER Path
    File path to read

    .OUTPUTS
    File contents as string
    #>
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Required input file not found: $Path"
    }

    return Get-Content -Encoding utf8 $Path -Raw
}

function Get-ScalarValue {
    <#
    .SYNOPSIS
    Extract scalar value from YAML lines using regex

    .PARAMETER Lines
    Array of YAML file lines

    .PARAMETER Key
    YAML key to extract

    .OUTPUTS
    Trimmed value string
    #>
    param(
        [string[]]$Lines,
        [string]$Key
    )

    foreach ($line in $Lines) {
        if ($line -match "^$Key\s*:\s*(.+)$") {
            return $Matches[1].Trim().Trim('"')
        }
    }

    throw "Required field not found: $Key"
}

function Resolve-TaskToken {
    <#
    .SYNOPSIS
    Replace {task_id} token in string

    .PARAMETER Value
    String with potential {task_id} token

    .PARAMETER TaskId
    Task ID to substitute

    .OUTPUTS
    Resolved string
    #>
    param(
        [string]$Value,
        [string]$TaskId
    )

    return $Value.Replace("{task_id}", $TaskId).Trim('"')
}

function Read-ExecutionSpec {
    <#
    .SYNOPSIS
    Parse execution spec YAML and extract provider configuration

    .PARAMETER Path
    Path to execution spec YAML file

    .OUTPUTS
    Hashtable with role, provider, provider_config, input, instructions, output
    #>
    param([string]$Path)

    $text = Read-Utf8File $Path
    $lines = $text -split "\r?\n"

    $spec = [ordered]@{
        role = ""
        provider = "dry-run"
        provider_config = @{}
        input = @()
        instructions = @()
        output = @()
    }

    $inInput = $false
    $inInstructions = $false
    $inOutput = $false
    $inProviderConfig = $false
    $currentProvider = ""

    foreach ($line in $lines) {
        # Reset section flags on new top-level key
        if ($line -match "^[a-z_]+:") {
            $inInput = $false
            $inInstructions = $false
            $inOutput = $false
            $inProviderConfig = $false
        }

        # Extract role
        if ($line -match "^role:\s*(.+)$") {
            $spec.role = $Matches[1].Trim().Trim('"')
            continue
        }

        # Extract provider (defaults to dry-run)
        if ($line -match "^provider:\s*(.+)$") {
            $spec.provider = $Matches[1].Trim().Trim('"')
            continue
        }

        # provider_config section
        if ($line -match "^provider_config:\s*$") {
            $inProviderConfig = $true
            continue
        }

        if ($inProviderConfig) {
            # Nested provider name (e.g., "  codex:")
            if ($line -match "^\s{2}([a-z]+):\s*$") {
                $currentProvider = $Matches[1]
                $spec.provider_config[$currentProvider] = @{}
                continue
            }

            # Provider settings (e.g., "    model: sonnet-4.5")
            if ($line -match "^\s{4}([a-z_]+):\s*(.+)$") {
                $key = $Matches[1]
                $value = $Matches[2].Trim().Trim('"')

                # Convert numeric values
                if ($value -match "^\d+$") {
                    $value = [int]$value
                }

                $spec.provider_config[$currentProvider][$key] = $value
                continue
            }
        }

        # input section
        if ($line -match "^input:\s*$") {
            $inInput = $true
            continue
        }

        if ($inInput -and $line -match "^\s{2}-\s*(.+)$") {
            $spec.input += $Matches[1].Trim().Trim('"')
            continue
        }

        # instructions section
        if ($line -match "^instructions:\s*$") {
            $inInstructions = $true
            continue
        }

        if ($inInstructions -and $line -match "^\s{2}-\s*(.+)$") {
            $spec.instructions += $Matches[1].Trim().Trim('"')
            continue
        }

        # output section
        if ($line -match "^output:\s*$") {
            $inOutput = $true
            continue
        }

        if ($inOutput -and $line -match "^\s{2}-\s*(.+)$") {
            $spec.output += $Matches[1].Trim().Trim('"')
            continue
        }
    }

    if ([string]::IsNullOrEmpty($spec.role)) {
        throw "Execution spec missing required 'role' field: $Path"
    }

    return $spec
}

function New-StructuredLog {
    <#
    .SYNOPSIS
    Create contract-compliant structured log

    .PARAMETER RunId
    Unique run identifier

    .PARAMETER Runner
    Runner name (dry-run, codex, claude)

    .PARAMETER Role
    Agent role

    .PARAMETER TaskId
    Task identifier

    .PARAMETER Provider
    Provider name

    .PARAMETER Inputs
    Array of input file paths

    .PARAMETER Output
    Output hashtable (must contain: summary, changed_files, verification_result, risks, next_steps)

    .PARAMETER ProviderMetadata
    Optional provider-specific metadata (additive only)

    .OUTPUTS
    Ordered hashtable suitable for JSON serialization
    #>
    param(
        [string]$RunId,
        [string]$Runner,
        [string]$Role,
        [string]$TaskId,
        [string]$Provider,
        [array]$Inputs,
        [hashtable]$Output,
        [hashtable]$ProviderMetadata = @{}
    )

    $log = [ordered]@{
        run_id = $RunId
        runner = $Runner
        role = $Role
        task_id = $TaskId
        provider = $Provider
        inputs = $Inputs
        output = $Output
    }

    if ($ProviderMetadata.Count -gt 0) {
        $log.provider_metadata = $ProviderMetadata
    }

    return $log
}

# Functions are available when dot-sourced with:
# . .\runner\lib\common.ps1
