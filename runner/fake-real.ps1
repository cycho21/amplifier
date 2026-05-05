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
    throw "Fake real runner expected real mode, got '$Mode'"
}

if (-not $AllowReal) {
    throw "Fake real runner expected -AllowReal"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $PromptOut) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogOut) | Out-Null

Set-Content -Encoding utf8 -Path $PromptOut -Value "Fake real prompt for $Role"

$log = [ordered]@{
    run_id = "fake-real-$Role-$TaskId"
    runner = "fake-real"
    role = $Role
    task_id = $TaskId
    inputs = @(
        $AgentRole,
        "tasks/$TaskId.md",
        $ExecutionSpec
    )
    cost_tracking = [ordered]@{
        provider_metadata = [ordered]@{
            provider = "fake"
            tool = "fake-real"
            model = "fake-real"
            input_tokens = 0
            output_tokens = 0
            total_tokens = 0
            source = "controlled-fake-real-runner"
        }
    }
    output = [ordered]@{
        summary = "Controlled fake real step completed for $Role."
        changed_files = @()
        verification_result = "Fake real runner completed without invoking Codex."
        risks = @("Fake runner verifies real workflow plumbing only.")
        next_steps = @("Replace fake runner with Codex only after dogfood passes.")
    }
}

$log | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 -Path $LogOut
Write-Output "Fake real step log written to $LogOut"
