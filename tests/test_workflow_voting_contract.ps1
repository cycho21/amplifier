$ErrorActionPreference = "Stop"

$contractIndexPath = "docs/plan/CONTRACT.md"
$comparisonContractPath = "docs/plan/contracts/comparison.md"
$votingContractPath = "docs/plan/contracts/voting.md"
$roadmapPath = "docs/plan/roadmaps/ORCHESTRATION.md"

if (-not (Test-Path $votingContractPath)) {
    throw "Missing voting contract: $votingContractPath"
}

$contractIndex = Get-Content -Encoding utf8 $contractIndexPath -Raw
$comparisonContract = Get-Content -Encoding utf8 $comparisonContractPath -Raw
$votingContract = Get-Content -Encoding utf8 $votingContractPath -Raw
$roadmap = Get-Content -Encoding utf8 $roadmapPath -Raw

if ($contractIndex -notmatch "\[Voting Contract\]\(contracts/voting\.md\)") {
    throw "Contract index must reference voting contract"
}

foreach ($requiredText in @(
    "Voting is separate from structural comparison",
    "Voting must not replace comparison",
    "Voting must not run until comparison and real execution are stable",
    "Voting output is optional until voting execution is implemented"
)) {
    if ($votingContract -notlike "*$requiredText*") {
        throw "Voting contract missing required text: $requiredText"
    }
}

foreach ($field in @("voting_method", "eligible_step_ids", "votes", "selected_step_id", "status")) {
    if ($votingContract -notlike "*$field*") {
        throw "Voting contract missing future voting field: $field"
    }
}

if ($comparisonContract -notlike "*does not choose a winner, score quality, or vote*") {
    throw "Comparison contract must remain structural and non-voting"
}

if ($roadmap -notmatch "6\. \[x\] Define result voting separately from structural comparison\.") {
    throw "ORCHESTRATION.md must mark voting definition as complete"
}

Write-Output "Workflow voting contract test passed."
