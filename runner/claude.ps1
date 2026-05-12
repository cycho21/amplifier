param(
    [string]$TaskId = "000_template",
    [string]$Role = "implementer",
    [string]$ExecutionSpec = "execution/implementer.yaml",
    [string]$AgentRole = "agents/implementer.md",
    [string]$Plan = "docs/plan/PLAN.md",
    [string]$Contract = "docs/plan/CONTRACT.md",
    [string]$PromptOut = "logs/prompts/claude-$TaskId.prompt.txt",
    [string]$LogOut = "logs/$(Get-Date -Format 'yyyyMMdd')-claude-$TaskId.json",
    [string]$Mode = "dry-run",
    [switch]$AllowReal
)

$ErrorActionPreference = "Stop"

# Korean Windows defaults to CP949 which cannot encode emojis or many Unicode
# characters. Set UTF-8 so piping prompt text to the Claude CLI stdin works
# correctly regardless of what characters appear in agent/task files.
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false)

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

function Find-ClaudeExe {
    # Prefer the .exe directly to avoid npm wrapper path issues in PowerShell
    $npmPrefix = & npm prefix -g 2>$null
    if ($npmPrefix) {
        $exePath = Join-Path $npmPrefix "node_modules\@anthropic-ai\claude-code\bin\claude.exe"
        if (Test-Path $exePath) { return $exePath }
    }
    return "claude"
}

function Invoke-ClaudeCLI {
    param(
        [string]$PromptFile,
        [hashtable]$Config
    )

    $model = if ($Config.ContainsKey("model")) { $Config.model } else { "claude-sonnet-4-5" }
    $claudeExe = Find-ClaudeExe
    $promptText = Get-Content -Encoding utf8 -Raw $PromptFile
    $startTime = Get-Date

    $rawOutput = $promptText | & $claudeExe --print --model $model --dangerously-skip-permissions 2>&1 | Out-String

    if ($LASTEXITCODE -ne 0) {
        throw "Claude CLI exited with code $LASTEXITCODE. Output: $rawOutput"
    }

    $endTime = Get-Date
    $latencyMs = [int](($endTime - $startTime).TotalMilliseconds)

    return @{
        text = $rawOutput
        metadata = @{
            model = $model
            latency_ms = $latencyMs
            cli_version = "unknown"
        }
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
당신은 한국어로 응답하는 AI 엔지니어입니다. 모든 텍스트 출력은 반드시 한국어로 작성해야 합니다.

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
중요: summary, verification_result, risks, next_steps의 모든 내용을 반드시 한국어로 작성하세요.
영어로 작성하지 마세요. 오직 한국어만 사용하세요.

JSON 형식으로만 응답하세요. 마크다운 코드 펜스나 설명을 추가하지 마세요.
\`\`\`json 블록으로 감싸지 마세요.
응답은 '{'로 시작하고 '}'로 끝나야 합니다.

{
  "summary": "수행한 작업에 대한 설명을 한국어로 작성",
  "changed_files": ["변경된", "파일", "경로"],
  "verification_result": "검증 방법과 결과를 한국어로 작성",
  "risks": ["발견된 위험 요소를 한국어로 작성"],
  "next_steps": ["다음 단계를 한국어로 작성"]
}

예시 (한국어로만 작성):
{
  "summary": "PATCH /api/roadmaps/toggle 엔드포인트 구현 완료 및 검증",
  "changed_files": ["frontend/server.mjs"],
  "verification_result": "12개 테스트 케이스 모두 통과 확인",
  "risks": ["동시성 문제 가능성"],
  "next_steps": ["UI 체크박스 렌더링 구현"]
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

    Write-Host "  Attempt $Attempt/3"

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
Write-Host "  Claude CLI execution successful"
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
