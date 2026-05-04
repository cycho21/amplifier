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
    throw "Fake workflow step runner expected real mode, got '$Mode'"
}

if (-not $AllowReal) {
    throw "Fake workflow step runner expected AllowReal"
}

$markerDir = $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR
if ([string]::IsNullOrWhiteSpace($markerDir)) {
    $markerDir = "logs/test-real-parallel-markers"
}

$sleepMs = 1000
if (-not [string]::IsNullOrWhiteSpace($env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS)) {
    $sleepMs = [int]$env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS
}

New-Item -ItemType Directory -Force -Path $markerDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $PromptOut) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogOut) | Out-Null

$startTicks = [DateTime]::UtcNow.Ticks
Set-Content -Encoding utf8 -Path (Join-Path $markerDir "$Role.start") -Value $startTicks
Set-Content -Encoding utf8 -Path $PromptOut -Value "Fake prompt for $Role"

Start-Sleep -Milliseconds $sleepMs

$endTicks = [DateTime]::UtcNow.Ticks
Set-Content -Encoding utf8 -Path (Join-Path $markerDir "$Role.end") -Value $endTicks

$log = [ordered]@{
    run_id = "fake-$Role-$TaskId"
    runner = "fake-workflow-step-runner"
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
    cost_tracking = [ordered]@{
        provider_metadata = [ordered]@{
            provider = "fake-provider"
            tool = "fake-workflow-step-runner"
            model = "fake-model"
            input_tokens = 3
            output_tokens = 2
            total_tokens = 5
            input_token_rate = 0.01
            output_token_rate = 0.02
            rate_unit_tokens = 1
            source = "fake-step-runner"
        }
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
