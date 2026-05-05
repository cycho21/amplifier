# Output parser and validator for Mini Amplifier runners
# Handles JSON parsing, contract validation, and retry logic

$ErrorActionPreference = "Stop"

function Parse-LLMOutput {
    <#
    .SYNOPSIS
    Parse JSON from LLM raw output, stripping markdown fences if present

    .PARAMETER RawOutput
    Raw output from LLM (may contain markdown code fences)

    .OUTPUTS
    Parsed JSON object or throws on parse failure
    #>
    param([string]$RawOutput)

    if ([string]::IsNullOrWhiteSpace($RawOutput)) {
        throw "LLM output is empty"
    }

    $cleaned = $RawOutput.Trim()

    # Strip markdown code fences if present
    # Matches: ```json\n{...}\n``` or ```\n{...}\n```
    if ($cleaned -match '^\s*```(?:json)?\s*\n([\s\S]+)\n\s*```\s*$') {
        $cleaned = $Matches[1].Trim()
    }

    # Also handle single-line fence: ```json {...}```
    if ($cleaned -match '^\s*```(?:json)?\s*(\{[\s\S]+\})\s*```\s*$') {
        $cleaned = $Matches[1].Trim()
    }

    try {
        $parsed = $cleaned | ConvertFrom-Json

        # Convert PSCustomObject to hashtable for consistency
        if ($parsed -is [PSCustomObject]) {
            $hashtable = @{}
            $parsed.PSObject.Properties | ForEach-Object {
                $hashtable[$_.Name] = $_.Value
            }
            return $hashtable
        }

        return $parsed
    } catch {
        Write-Error "Failed to parse JSON from LLM output: $_`nRaw output (first 500 chars): $($RawOutput.Substring(0, [Math]::Min(500, $RawOutput.Length)))"
        throw
    }
}

function Validate-OutputContract {
    <#
    .SYNOPSIS
    Validate that output contains all required contract fields

    .PARAMETER Output
    Parsed output hashtable from LLM

    .OUTPUTS
    Array of validation errors (empty if valid)
    #>
    param([hashtable]$Output)

    $requiredFields = @(
        "summary",
        "changed_files",
        "verification_result",
        "risks",
        "next_steps"
    )

    $errors = @()

    foreach ($field in $requiredFields) {
        if (-not $Output.ContainsKey($field)) {
            $errors += "Missing required field: $field"
        }
    }

    # Type validation
    if ($Output.ContainsKey("changed_files") -and $Output.changed_files -isnot [array]) {
        $errors += "Field 'changed_files' must be an array"
    }

    if ($Output.ContainsKey("risks") -and $Output.risks -isnot [array]) {
        $errors += "Field 'risks' must be an array"
    }

    if ($Output.ContainsKey("next_steps") -and $Output.next_steps -isnot [array]) {
        $errors += "Field 'next_steps' must be an array"
    }

    return $errors
}

function Add-ProviderMetadata {
    <#
    .SYNOPSIS
    Merge provider-specific metadata additively (without overwriting output fields)

    .PARAMETER Output
    Parsed output hashtable

    .PARAMETER Metadata
    Provider-specific metadata to add

    .OUTPUTS
    Output with provider_metadata added
    #>
    param(
        [hashtable]$Output,
        [hashtable]$Metadata
    )

    $result = $Output.Clone()

    if ($Metadata.Count -gt 0) {
        $result.provider_metadata = $Metadata
    }

    return $result
}

function Retry-WithStricterPrompt {
    <#
    .SYNOPSIS
    Retry LLM invocation with stricter JSON instructions on parse failure

    .PARAMETER InvokeFunction
    ScriptBlock that invokes the LLM and returns raw output

    .PARAMETER MaxAttempts
    Maximum retry attempts (default 3)

    .OUTPUTS
    Parsed and validated output hashtable

    .EXAMPLE
    $output = Retry-WithStricterPrompt -InvokeFunction {
        param($Attempt)
        # Your LLM invocation logic here
        # $Attempt = 1, 2, 3
        return $rawLlmOutput
    } -MaxAttempts 3
    #>
    param(
        [scriptblock]$InvokeFunction,
        [int]$MaxAttempts = 3
    )

    $attempt = 0
    $lastError = $null

    while ($attempt -lt $MaxAttempts) {
        $attempt++

        try {
            Write-Verbose "Attempt $attempt of $MaxAttempts"

            # Invoke the LLM (InvokeFunction gets $attempt as parameter)
            $rawOutput = & $InvokeFunction $attempt

            # Parse output
            $parsed = Parse-LLMOutput -RawOutput $rawOutput

            # Validate contract
            $validationErrors = Validate-OutputContract -Output $parsed

            if ($validationErrors.Count -gt 0) {
                $errorMsg = "Contract validation failed:`n" + ($validationErrors -join "`n")
                Write-Warning $errorMsg

                if ($attempt -ge $MaxAttempts) {
                    throw $errorMsg
                }

                # Retry with stricter instructions
                Start-Sleep -Seconds 2
                continue
            }

            # Success
            return $parsed

        } catch {
            $lastError = $_
            Write-Warning "Attempt $attempt failed: $_"

            if ($attempt -ge $MaxAttempts) {
                throw "Failed after $MaxAttempts attempts. Last error: $lastError"
            }

            # Wait before retry
            Start-Sleep -Seconds 2
        }
    }

    throw "Retry logic failed unexpectedly. Last error: $lastError"
}

function Get-StricterJsonPrompt {
    <#
    .SYNOPSIS
    Generate stricter JSON instructions for retry attempts

    .PARAMETER Attempt
    Current attempt number (1-based)

    .OUTPUTS
    Additional instructions to append to prompt
    #>
    param([int]$Attempt)

    $baseInstructions = @"

CRITICAL OUTPUT REQUIREMENTS:
1. Your response MUST be valid JSON only
2. Do NOT include markdown code fences
3. Do NOT include any explanation before or after the JSON
4. The JSON MUST contain these exact fields:
   - summary (string)
   - changed_files (array of strings)
   - verification_result (string)
   - risks (array of strings)
   - next_steps (array of strings)
"@

    if ($Attempt -eq 2) {
        $baseInstructions += @"

RETRY #1 - Previous response was invalid.
Ensure your response starts with '{' and ends with '}'.
No markdown, no commentary, ONLY JSON.
"@
    } elseif ($Attempt -ge 3) {
        $baseInstructions += @"

FINAL RETRY - Previous responses were invalid.
ABSOLUTELY NO markdown code fences (``` characters).
Start IMMEDIATELY with '{' character.
End IMMEDIATELY with '}' character.
Example valid response:
{"summary": "...", "changed_files": [], "verification_result": "...", "risks": [], "next_steps": []}
"@
    }

    return $baseInstructions
}

# Functions are available when dot-sourced with:
# . .\runner\lib\output-parser.ps1
