param(
    [string]$TaskId,
    [string]$Role,
    [string]$ExecutionSpec,
    [string]$AgentRole,
    [string]$PromptOut,
    [string]$LogOut,
    [string]$Mode = "",
    [switch]$AllowReal
)

$ErrorActionPreference = "Stop"

if ($Mode -ne "real") {
    throw "Fake workflow flaky step runner expected real mode, got '$Mode'"
}

if (-not $AllowReal) {
    throw "Fake workflow flaky step runner expected AllowReal"
}

$markerDir = $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR
if ([string]::IsNullOrWhiteSpace($markerDir)) {
    $markerDir = "logs/test-real-retry-markers"
}

New-Item -ItemType Directory -Force -Path $markerDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $PromptOut) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogOut) | Out-Null

$attemptPath = Join-Path $markerDir "$Role.attempts"
$attempt = 1

if (Test-Path $attemptPath) {
    $attempt = [int](Get-Content -Encoding utf8 $attemptPath -Raw) + 1
}

Set-Content -Encoding utf8 -Path $attemptPath -Value $attempt
Set-Content -Encoding utf8 -Path (Join-Path $markerDir "$Role.attempt-$attempt") -Value ([DateTime]::UtcNow.Ticks)
Set-Content -Encoding utf8 -Path $PromptOut -Value "Fake prompt for $Role attempt $attempt"

if ($Role -eq "backend-engineer" -and $attempt -eq 1) {
    throw "Retryable fake runner error for $Role"
}

$log = [ordered]@{
    run_id = "fake-$Role-$TaskId"
    runner = "fake-workflow-flaky-step-runner"
    role = $Role
    task_id = $TaskId
    inputs = @(
        $AgentRole,
        "tasks/$TaskId.md",
        $ExecutionSpec
    )
    output = [ordered]@{
        summary = "Fake flaky workflow step completed for $Role."
        changed_files = @()
        verification_result = "Fake workflow flaky step runner completed on attempt $attempt."
        risks = @("Fake runner only verifies retry orchestration.")
        next_steps = @("Replace fake runner with a real step runner.")
    }
}

$log | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 -Path $LogOut
Write-Output "Fake workflow flaky step log written to $LogOut"
