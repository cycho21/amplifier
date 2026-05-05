param(
    [string]$TaskId = "000_template",
    [string]$Role = "implementer",
    [string]$ExecutionSpec = "execution/implementer.yaml",
    [string]$AgentRole = "agents/implementer.md",
    [string]$Plan = "docs/plan/PLAN.md",
    [string]$Contract = "docs/plan/CONTRACT.md",
    [string]$PromptOut = "logs/prompts/claude-$TaskId.prompt.txt",
    [string]$LogOut = "logs/$(Get-Date -Format 'yyyyMMdd')-claude-$TaskId.json"
)

$ErrorActionPreference = "Stop"

# Load shared libraries
. (Join-Path $PSScriptRoot "lib/common.ps1")
. (Join-Path $PSScriptRoot "lib/output-parser.ps1")

function Test-ClaudeCliInstalled {
    <#
    .SYNOPSIS
    Validate that 'claude' CLI command is available in PATH
    #>
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($null -eq $claudeCmd) {
        throw "Claude CLI is not installed or not in PATH. Please install Claude CLI before running."
    }
}

function Invoke-ClaudeCLI {
    <#
    .SYNOPSIS
    Invoke Claude CLI with timeout and stdout parsing

    .PARAMETER PromptFile
    Path to prompt file

    .PARAMETER Config
    Provider config hashtable (model, timeout, max_tokens)

    .OUTPUTS
    Hashtable with response text and metadata
    #>
    param(
        [string]$PromptFile,
        [hashtable]$Config
    )

    $model = if ($Config.ContainsKey("model")) { $Config.model } else { "claude-sonnet-4-5" }
    $timeout = if ($Config.ContainsKey("timeout")) { $Config.timeout } else { 600 }

    $startTime = Get-Date

    # Invoke Claude CLI with timeout using Start-Job
    $job = Start-Job -ScriptBlock {
        param($PromptFile, $Model)

        # Execute Claude CLI
        # Note: Adjust command based on actual Claude CLI syntax
        # Assuming: claude --file <promptFile> or similar
        $output = & claude --file $PromptFile 2>&1 | Out-String

        return $output
    } -ArgumentList @($PromptFile, $model)

    $result = Wait-Job $job -Timeout $timeout

    if ($null -eq $result) {
        # Timeout occurred
        Stop-Job $job
        Remove-Job $job
        throw "Claude CLI execution timed out after $timeout seconds"
    }

    try {
        $rawOutput = Receive-Job $job -ErrorAction Stop
    } catch {
        $errorDetails = $_.Exception.Message
        throw "Claude CLI error: $errorDetails"
    } finally {
        Remove-Job $job
    }

    $endTime = Get-Date
    $latencyMs = [int](($endTime - $startTime).TotalMilliseconds)

    # Build metadata
    $metadata = @{
        model = $model
        latency_ms = $latencyMs
        cli_version = "unknown"  # Could parse from `claude --version`
    }

    return @{
        text = $rawOutput
        metadata = $metadata
    }
}

function Build-Prompt {
    <#
    .SYNOPSIS
    Build structured prompt from inputs with JSON enforcement

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
Do NOT wrap your response in \`\`\`json blocks.
Start your response with '{' and end with '}'.

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
Write-Output "Claude CLI Runner"
Write-Output "Task: $TaskId, Role: $Role"

# Validate Claude CLI is installed
Test-ClaudeCliInstalled

# Read execution spec to get provider config
$execSpec = Read-ExecutionSpec -Path $ExecutionSpec

if ($execSpec.provider -ne "claude") {
    Write-Warning "Execution spec provider is '$($execSpec.provider)', expected 'claude'. Proceeding anyway..."
}

$providerConfig = if ($execSpec.provider_config.ContainsKey("claude")) {
    $execSpec.provider_config.claude
} else {
    @{ model = "claude-sonnet-4-5"; timeout = 600; max_tokens = 8000 }
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

    # Stage 2: Invoking Claude CLI
    Write-Host "[STAGE] Invoking Claude CLI ($($providerConfig.model))" -ForegroundColor Cyan
    $response = Invoke-ClaudeCLI -PromptFile $PromptOut -Config $providerConfig
    Write-Host "[STAGE] CLI response received" -ForegroundColor Green

    # Store metadata for later use
    $script:cliMetadata = $response.metadata

    # Return raw text for parsing
    return $response.text
}

# Stage 3: Parsing and validating response
Write-Host "[STAGE] Parsing response" -ForegroundColor Cyan
Write-Output "  Claude CLI execution successful"
Write-Host "[STAGE] Response validated" -ForegroundColor Green

# Add provider metadata
$outputWithMetadata = Add-ProviderMetadata -Output $output -Metadata $script:cliMetadata

# Generate structured log
$runId = "$(Get-Date -Format 'yyyyMMdd')-claude-$TaskId"
$log = New-StructuredLog `
    -RunId $runId `
    -Runner "claude" `
    -Role $Role `
    -TaskId $TaskId `
    -Provider "claude" `
    -Inputs @($Plan, $Contract, $AgentRole, $taskPath, $ExecutionSpec) `
    -Output $outputWithMetadata `
    -ProviderMetadata $script:cliMetadata

# Write log
$logDir = Split-Path -Parent $LogOut
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 -Path $LogOut

Write-Output "Prompt written to $PromptOut"
Write-Output "Log written to $LogOut"
Write-Output "Claude CLI runner complete"
