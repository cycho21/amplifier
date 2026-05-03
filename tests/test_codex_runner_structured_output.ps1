$ErrorActionPreference = "Stop"

$logOut = "logs/test-codex-structured-output-000_template.json"
$promptOut = "logs/prompts/test-codex-structured-output.prompt.txt"
$rawOutputOut = "logs/raw/test-codex-structured-output.txt"

foreach ($path in @($logOut, $promptOut, $rawOutputOut)) {
    if (Test-Path $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

& .\runner\codex.ps1 `
    -TaskId "000_template" `
    -Role "implementer" `
    -ExecutionSpec "execution/implementer.yaml" `
    -AgentRole "agents/implementer.md" `
    -Mode "real" `
    -AllowReal `
    -CodexCommand ".\test-fixtures\fake-codex-structured.ps1" `
    -PromptOut $promptOut `
    -LogOut $logOut `
    -RawOutputOut $rawOutputOut

$log = Get-Content -Encoding utf8 $logOut -Raw | ConvertFrom-Json

if ($log.runner -ne "codex-real") {
    throw "Expected codex-real runner, got $($log.runner)"
}

if ($log.invocation.parsed_output -ne $true) {
    throw "Expected invocation.parsed_output true"
}

if ($log.output.summary -ne "Structured Codex output was captured.") {
    throw "Expected parsed summary, got '$($log.output.summary)'"
}

$changedFiles = @($log.output.changed_files)
if ($changedFiles -notcontains "runner/codex.ps1") {
    throw "Expected parsed changed_files to include runner/codex.ps1"
}

if ($log.output.verification_result -ne "Structured fake Codex response parsed successfully.") {
    throw "Expected parsed verification_result"
}

$risks = @($log.output.risks)
if ($risks -notcontains "Fake response only validates adapter parsing.") {
    throw "Expected parsed risks"
}

$nextSteps = @($log.output.next_steps)
if ($nextSteps -notcontains "Add malformed output fixtures in the next step.") {
    throw "Expected parsed next_steps"
}

foreach ($path in @($logOut, $promptOut, $rawOutputOut)) {
    if (Test-Path $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

Write-Output "Codex runner structured output test passed."
