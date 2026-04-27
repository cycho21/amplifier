param(
    [string]$TaskId = "000_template",
    [string]$Role = "implementer",
    [string]$ExecutionSpec = "execution/implementer.yaml",
    [string]$AgentRole = "agents/implementer.md",
    [string]$Plan = "docs/plan/PLAN.md",
    [string]$Contract = "docs/plan/CONTRACT.md",
    [string]$PromptOut = "logs/prompts/codex-$TaskId.prompt.txt",
    [string]$LogOut = "logs/$(Get-Date -Format 'yyyyMMdd')-codex-$TaskId.json"
)

$ErrorActionPreference = "Stop"

# Load shared libraries
. (Join-Path $PSScriptRoot "lib/common.ps1")
. (Join-Path $PSScriptRoot "lib/output-parser.ps1")

function Test-CodexAuthentication {
    <#
    .SYNOPSIS
    Validate that OPENAI_API_KEY environment variable is set
    #>
    if ([string]::IsNullOrEmpty($env:OPENAI_API_KEY)) {
        throw "OPENAI_API_KEY environment variable is required for Codex provider. Please set it before running."
    }
}

function Invoke-OpenAIAPI {
    <#
    .SYNOPSIS
    Invoke OpenAI API with timeout and error handling

    .PARAMETER Prompt
    Full prompt text to send

    .PARAMETER Config
    Provider config hashtable (model, timeout, max_tokens)

    .OUTPUTS
    Hashtable with response and metadata
    #>
    param(
        [string]$Prompt,
        [hashtable]$Config
    )

    $model = if ($Config.ContainsKey("model")) { $Config.model } else { "gpt-4" }
    $timeout = if ($Config.ContainsKey("timeout")) { $Config.timeout } else { 600 }
    $maxTokens = if ($Config.ContainsKey("max_tokens")) { $Config.max_tokens } else { 8000 }

    $headers = @{
        "Authorization" = "Bearer $($env:OPENAI_API_KEY)"
        "Content-Type" = "application/json"
    }

    $body = @{
        model = $model
        max_tokens = $maxTokens
        messages = @(
            @{
                role = "user"
                content = $Prompt
            }
        )
    } | ConvertTo-Json -Depth 10

    $startTime = Get-Date

    # Invoke API with timeout using Start-Job
    $job = Start-Job -ScriptBlock {
        param($Headers, $Body)

        $response = Invoke-RestMethod `
            -Uri "https://api.openai.com/v1/chat/completions" `
            -Method Post `
            -Headers $Headers `
            -Body $Body `
            -ContentType "application/json"

        return $response
    } -ArgumentList @($headers, $body)

    $result = Wait-Job $job -Timeout $timeout

    if ($null -eq $result) {
        # Timeout occurred
        Stop-Job $job
        Remove-Job $job
        throw "OpenAI API request timed out after $timeout seconds"
    }

    try {
        $response = Receive-Job $job -ErrorAction Stop
    } catch {
        $errorDetails = $_.Exception.Message

        # Parse HTTP status code if available
        if ($errorDetails -match "(\d{3})") {
            $statusCode = [int]$Matches[1]

            if ($statusCode -ge 500 -and $statusCode -lt 600) {
                throw "Transient error (HTTP $statusCode): $errorDetails"
            } elseif ($statusCode -eq 429) {
                throw "Transient error (Rate limit): $errorDetails"
            } elseif ($statusCode -ge 400 -and $statusCode -lt 500) {
                throw "Permanent error (HTTP $statusCode): $errorDetails"
            }
        }

        throw "API error: $errorDetails"
    } finally {
        Remove-Job $job
    }

    $endTime = Get-Date
    $latencyMs = [int](($endTime - $startTime).TotalMilliseconds)

    # Extract response text from OpenAI API format
    $responseText = ""
    if ($response.choices -and $response.choices.Count -gt 0) {
        $responseText = $response.choices[0].message.content
    } else {
        throw "OpenAI API response missing choices field"
    }

    # Build metadata
    $metadata = @{
        model = $response.model
        latency_ms = $latencyMs
    }

    if ($response.usage) {
        $metadata.prompt_tokens = $response.usage.prompt_tokens
        $metadata.completion_tokens = $response.usage.completion_tokens
        $metadata.total_tokens = $response.usage.total_tokens
    }

    return @{
        text = $responseText
        metadata = $metadata
    }
}

function Build-Prompt {
    <#
    .SYNOPSIS
    Build structured prompt from inputs

    .OUTPUTS
    Prompt string
    #>
    param(
        [string]$RoleText,
        [string]$PlanText,
        [string]$ContractText,
        [string]$TaskText,
        [string]$ExecutionText,
        [int]$Attempt = 1
    )

    $prompt = @"
[System]
$RoleText

[Context]
## Plan
$PlanText

## Contract
$ContractText

## Task
$TaskText

[Instructions]
$ExecutionText

[Output Format]
You MUST respond with valid JSON only. No markdown code fences, no explanation.
{
  "summary": "Brief description of what was done",
  "changed_files": ["array", "of", "file", "paths"],
  "verification_result": "How the changes were verified",
  "risks": ["array", "of", "identified", "risks"],
  "next_steps": ["array", "of", "next", "actions"]
}
"@

    # Add stricter instructions on retry
    if ($Attempt -gt 1) {
        $prompt += Get-StricterJsonPrompt -Attempt $Attempt
    }

    return $prompt
}

# Main execution
Write-Output "Codex Runner - OpenAI API Invocation"
Write-Output "Task: $TaskId, Role: $Role"

# Validate authentication
Test-CodexAuthentication

# Read execution spec to get provider config
$execSpec = Read-ExecutionSpec -Path $ExecutionSpec

if ($execSpec.provider -ne "codex") {
    Write-Warning "Execution spec provider is '$($execSpec.provider)', expected 'codex'. Proceeding anyway..."
}

$providerConfig = if ($execSpec.provider_config.ContainsKey("codex")) {
    $execSpec.provider_config.codex
} else {
    @{ model = "gpt-4"; timeout = 600; max_tokens = 8000 }
}

Write-Output "  Model: $($providerConfig.model)"

# Stage 1: Reading task & context
Write-Host "[STAGE] Reading task & context" -ForegroundColor Cyan
$taskPath = "tasks/$TaskId.md"
$planText = Read-Utf8File $Plan
$contractText = Read-Utf8File $Contract
$roleText = Read-Utf8File $AgentRole
$taskText = Read-Utf8File $taskPath
Write-Host "[STAGE] Reading complete" -ForegroundColor Green

# Retry logic with stricter prompts
$output = Retry-WithStricterPrompt -MaxAttempts 3 -InvokeFunction {
    param($Attempt)

    Write-Output "  Attempt $Attempt/3"

    # Build prompt
    $prompt = Build-Prompt `
        -RoleText $roleText `
        -PlanText $planText `
        -ContractText $contractText `
        -TaskText $taskText `
        -ExecutionText ($execSpec.instructions -join "`n- ") `
        -Attempt $Attempt

    # Write prompt to file
    $promptDir = Split-Path -Parent $PromptOut
    New-Item -ItemType Directory -Force -Path $promptDir | Out-Null
    Set-Content -Encoding utf8 -Path $PromptOut -Value $prompt

    # Stage 2: Invoking OpenAI API
    Write-Host "[STAGE] Invoking OpenAI API ($($providerConfig.model))" -ForegroundColor Cyan
    $response = Invoke-OpenAIAPI -Prompt $prompt -Config $providerConfig
    Write-Host "[STAGE] API response received" -ForegroundColor Green

    # Store metadata for later use
    $script:apiMetadata = $response.metadata

    # Return raw text for parsing
    return $response.text
}

# Stage 3: Parsing and validating response
Write-Host "[STAGE] Parsing response" -ForegroundColor Cyan
Write-Output "  API call successful"
Write-Host "[STAGE] Response validated" -ForegroundColor Green

# Add provider metadata
$outputWithMetadata = Add-ProviderMetadata -Output $output -Metadata $script:apiMetadata

# Generate structured log
$runId = "$(Get-Date -Format 'yyyyMMdd')-codex-$TaskId"
$log = New-StructuredLog `
    -RunId $runId `
    -Runner "codex" `
    -Role $Role `
    -TaskId $TaskId `
    -Provider "codex" `
    -Inputs @($Plan, $Contract, $AgentRole, $taskPath, $ExecutionSpec) `
    -Output $outputWithMetadata `
    -ProviderMetadata $script:apiMetadata

# Write log
$logDir = Split-Path -Parent $LogOut
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 -Path $LogOut

Write-Output "Prompt written to $PromptOut"
Write-Output "Log written to $LogOut"
Write-Output "Codex runner complete"
