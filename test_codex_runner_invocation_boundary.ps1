$ErrorActionPreference = "Stop"

function Assert-RequiredOutputFields {
    param($Output)

    foreach ($field in @("summary", "changed_files", "verification_result", "risks", "next_steps")) {
        if (-not ($Output.PSObject.Properties.Name -contains $field)) {
            throw "Missing required output field: $field"
        }
    }
}

$dryRunLogOut = "logs/test-codex-boundary-dry-run-000_template.json"
$dryRunPromptOut = "logs/prompts/test-codex-boundary-dry-run.prompt.txt"

& .\runner\codex.ps1 `
    -TaskId "000_template" `
    -Role "implementer" `
    -ExecutionSpec "execution/implementer.yaml" `
    -AgentRole "agents/implementer.md" `
    -PromptOut $dryRunPromptOut `
    -LogOut $dryRunLogOut

$dryRunLog = Get-Content -Encoding utf8 $dryRunLogOut -Raw | ConvertFrom-Json

if ($dryRunLog.runner -ne "codex-dry-run") {
    throw "Expected codex-dry-run runner, got $($dryRunLog.runner)"
}

if ($dryRunLog.runner_selection.provider -ne "codex") {
    throw "Expected runner_selection.provider codex"
}

if ($dryRunLog.invocation.mode -ne "dry-run") {
    throw "Expected dry-run invocation mode"
}

if ($dryRunLog.invocation.real_enabled -ne $false) {
    throw "Dry-run invocation must not enable real execution"
}

Assert-RequiredOutputFields $dryRunLog.output

$unsupportedFailed = $false

try {
    & .\runner\codex.ps1 `
        -TaskId "000_template" `
        -Role "implementer" `
        -ExecutionSpec "test-fixtures/execution/invalid-runner-provider.yaml" `
        -AgentRole "agents/implementer.md" `
        -PromptOut "logs/prompts/test-codex-boundary-invalid.prompt.txt" `
        -LogOut "logs/test-codex-boundary-invalid-000_template.json"
} catch {
    $unsupportedFailed = $true

    if ($_.Exception.Message -notlike "*Unsupported Codex runner provider*") {
        throw "Expected unsupported provider error, got '$($_.Exception.Message)'"
    }
}

if (-not $unsupportedFailed) {
    throw "Expected unsupported provider to fail"
}

$blockedFailed = $false

try {
    & .\runner\codex.ps1 `
        -TaskId "000_template" `
        -Role "implementer" `
        -ExecutionSpec "execution/implementer.yaml" `
        -AgentRole "agents/implementer.md" `
        -Mode "real" `
        -PromptOut "logs/prompts/test-codex-boundary-blocked.prompt.txt" `
        -LogOut "logs/test-codex-boundary-blocked-000_template.json"
} catch {
    $blockedFailed = $true

    if ($_.Exception.Message -notlike "*Real Codex invocation requires -AllowReal*") {
        throw "Expected AllowReal error, got '$($_.Exception.Message)'"
    }
}

if (-not $blockedFailed) {
    throw "Expected real mode without AllowReal to fail"
}

$realLogOut = "logs/test-codex-boundary-real-000_template.json"
$realPromptOut = "logs/prompts/test-codex-boundary-real.prompt.txt"
$rawOutputOut = "logs/raw/test-codex-boundary-real-output.txt"

& .\runner\codex.ps1 `
    -TaskId "000_template" `
    -Role "implementer" `
    -ExecutionSpec "execution/implementer.yaml" `
    -AgentRole "agents/implementer.md" `
    -Mode "real" `
    -AllowReal `
    -CodexCommand ".\test-fixtures\fake-codex.ps1" `
    -PromptOut $realPromptOut `
    -LogOut $realLogOut `
    -RawOutputOut $rawOutputOut

$realLog = Get-Content -Encoding utf8 $realLogOut -Raw | ConvertFrom-Json

if ($realLog.runner -ne "codex-real") {
    throw "Expected codex-real runner, got $($realLog.runner)"
}

if ($realLog.invocation.mode -ne "real") {
    throw "Expected real invocation mode"
}

if ($realLog.invocation.real_enabled -ne $true) {
    throw "Expected real invocation to be explicitly enabled"
}

if ($realLog.invocation.exit_code -ne 0) {
    throw "Expected fake Codex exit code 0, got $($realLog.invocation.exit_code)"
}

if (-not (Test-Path $rawOutputOut)) {
    throw "Expected raw Codex output file: $rawOutputOut"
}

Assert-RequiredOutputFields $realLog.output

Write-Output "Codex runner invocation boundary test passed."
