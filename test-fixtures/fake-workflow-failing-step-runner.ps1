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
    throw "Fake workflow failing step runner expected real mode, got '$Mode'"
}

if (-not $AllowReal) {
    throw "Fake workflow failing step runner expected AllowReal"
}

$markerDir = $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR
if ([string]::IsNullOrWhiteSpace($markerDir)) {
    $markerDir = "logs/test-real-parallel-failure-markers"
}

New-Item -ItemType Directory -Force -Path $markerDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $PromptOut) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogOut) | Out-Null

$startTicks = [DateTime]::UtcNow.Ticks
Set-Content -Encoding utf8 -Path (Join-Path $markerDir "$Role.start") -Value $startTicks
Set-Content -Encoding utf8 -Path $PromptOut -Value "Fake prompt for $Role"

if ($Role -eq "backend-engineer") {
    throw "Intentional fake failure for $Role"
}

Start-Sleep -Milliseconds 2000

$endTicks = [DateTime]::UtcNow.Ticks
Set-Content -Encoding utf8 -Path (Join-Path $markerDir "$Role.end") -Value $endTicks

$log = [ordered]@{
    run_id = "fake-$Role-$TaskId"
    runner = "fake-workflow-failing-step-runner"
    role = $Role
    task_id = $TaskId
    inputs = @(
        $AgentRole,
        "tasks/$TaskId.md",
        $ExecutionSpec
    )
    timing = [ordered]@{
        start_utc_ticks = $startTicks
        end_utc_ticks = $endTicks
    }
    output = [ordered]@{
        summary = "Fake real workflow step completed for $Role."
        changed_files = @()
        verification_result = "Fake workflow step runner completed."
        risks = @("Fake runner only verifies orchestration.")
        next_steps = @("Replace fake runner with a real step runner.")
    }
}

$log | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 -Path $LogOut
Write-Output "Fake workflow step log written to $LogOut"
