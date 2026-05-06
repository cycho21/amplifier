$ErrorActionPreference = "Stop"

$executionSpecs = Get-ChildItem -File "execution" -Filter "*.yaml"
$executionContractPath = "docs/plan/contracts/execution.md"
$roadmapPath = "docs/plan/roadmaps/REAL_RUNNERS.md"
$progressPath = "docs/plan/roadmaps/REAL_RUNNERS_PROGRESS.md"

if ($executionSpecs.Count -eq 0) {
    throw "Expected execution specs under execution/"
}

foreach ($spec in $executionSpecs) {
    $text = Get-Content -Encoding utf8 $spec.FullName -Raw

    foreach ($requiredText in @(
        "runner:",
        "provider: codex",
        "tool: codex-cli",
        "mode: dry-run"
    )) {
        if ($text -notlike "*$requiredText*") {
            throw "$($spec.Name) missing runner selection text: $requiredText"
        }
    }
}

$executionContract = Get-Content -Encoding utf8 $executionContractPath -Raw
$roadmap = Get-Content -Encoding utf8 $roadmapPath -Raw
$progress = Get-Content -Encoding utf8 $progressPath -Raw

foreach ($requiredText in @(
    "runner:",
    "provider: codex",
    "tool: codex-cli",
    "mode: dry-run",
    "Codex is the only supported provider until the Codex runner path is complete"
)) {
    if ($executionContract -notlike "*$requiredText*") {
        throw "Execution contract missing runner selection text: $requiredText"
    }
}

if ($roadmap -notmatch "2\. \[x\] Add provider/tool selection to execution specs without hard-coding role behavior\.") {
    throw "REAL_RUNNERS.md must mark provider/tool selection as complete"
}

if ($progress -notlike "*Provider/Tool Selection*") {
    throw "REAL_RUNNERS_PROGRESS.md must record provider/tool selection progress"
}

Write-Output "Execution runner selection test passed."
