$ErrorActionPreference = "Stop"

function Remove-TestOutput {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        if (Test-Path $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

function Assert-MalformedOutputFailure {
    param(
        [string]$CaseName,
        [string]$CodexCommand
    )

    $logOut = "logs/test-codex-malformed-$CaseName-000_template.json"
    $promptOut = "logs/prompts/test-codex-malformed-$CaseName.prompt.txt"
    $rawOutputOut = "logs/raw/test-codex-malformed-$CaseName-output.txt"

    Remove-TestOutput @($logOut, $promptOut, $rawOutputOut)

    $failed = $false

    try {
        & .\runner\codex.ps1 `
            -TaskId "000_template" `
            -Role "implementer" `
            -ExecutionSpec "execution/implementer.yaml" `
            -AgentRole "agents/implementer.md" `
            -Mode "real" `
            -AllowReal `
            -CodexCommand $CodexCommand `
            -PromptOut $promptOut `
            -LogOut $logOut `
            -RawOutputOut $rawOutputOut
    } catch {
        $failed = $true

        if ($_.Exception.Message -notlike "*Malformed Codex output*") {
            throw "Expected malformed output error, got '$($_.Exception.Message)'"
        }
    }

    if (-not $failed) {
        throw "Expected malformed output case '$CaseName' to fail"
    }

    if (-not (Test-Path $logOut)) {
        throw "Expected failure log for malformed output case '$CaseName'"
    }

    $log = Get-Content -Encoding utf8 $logOut -Raw | ConvertFrom-Json

    if ($log.runner -ne "codex-real") {
        throw "Expected codex-real runner for malformed output case '$CaseName'"
    }

    if ($log.invocation.exit_code -ne 0) {
        throw "Expected fake Codex exit code 0 for malformed output case '$CaseName'"
    }

    if ($log.invocation.parsed_output -ne $false) {
        throw "Malformed output case '$CaseName' must not be marked parsed"
    }

    if ($log.output.summary -ne "Malformed Codex output.") {
        throw "Expected malformed output summary for case '$CaseName', got '$($log.output.summary)'"
    }

    $risks = @($log.output.risks)
    if ($risks -notcontains "The real Codex response did not contain every required structured output field.") {
        throw "Expected malformed output risk for case '$CaseName'"
    }

    Remove-TestOutput @($logOut, $promptOut, $rawOutputOut)
}

Assert-MalformedOutputFailure "invalid-json" ".\test-fixtures\fake-codex-malformed-json.ps1"
Assert-MalformedOutputFailure "missing-field" ".\test-fixtures\fake-codex-missing-field.ps1"

Write-Output "Codex runner malformed output test passed."
