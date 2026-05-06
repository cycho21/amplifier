$ErrorActionPreference = "Stop"

$contractIndexPath = "docs/plan/CONTRACT.md"
$runnerContractPath = "docs/plan/contracts/runner-invocation.md"
$roadmapPath = "docs/plan/roadmaps/REAL_RUNNERS.md"

if (-not (Test-Path $runnerContractPath)) {
    throw "Missing runner invocation contract: $runnerContractPath"
}

$contractIndex = Get-Content -Encoding utf8 $contractIndexPath -Raw
$runnerContract = Get-Content -Encoding utf8 $runnerContractPath -Raw
$roadmap = Get-Content -Encoding utf8 $roadmapPath -Raw

if ($contractIndex -notmatch "\[Runner Invocation Contract\]\(contracts/runner-invocation\.md\)") {
    throw "Contract index must reference runner invocation contract"
}

foreach ($requiredText in @(
    "mode: dry-run",
    "mode: real",
    "Real invocation must be explicitly enabled",
    "Dry-run mode must remain deterministic",
    "Runner-specific metadata is additive only",
    "Malformed real runner output must fail the run"
)) {
    if ($runnerContract -notlike "*$requiredText*") {
        throw "Runner invocation contract missing required text: $requiredText"
    }
}

foreach ($field in @("summary", "changed_files", "verification_result", "risks", "next_steps")) {
    if ($runnerContract -notlike "*$field*") {
        throw "Runner invocation contract missing required output field: $field"
    }
}

if ($roadmap -notmatch "1\. \[x\] Define real runner invocation contract\.") {
    throw "REAL_RUNNERS.md must mark runner invocation contract as complete"
}

Write-Output "Runner invocation contract test passed."
