$ErrorActionPreference = "Stop"

$logOut = "logs/test-workflow-memory-policy-000_template.json"

& .\runner\workflow.ps1 `
    -TaskId "000_template" `
    -WorkflowSpec "workflows/implementation-review.yaml" `
    -LogOut $logOut

if (-not (Test-Path $logOut)) {
    throw "Expected workflow log was not created: $logOut"
}

$log = Get-Content -Encoding utf8 $logOut -Raw | ConvertFrom-Json

if (-not ($log.output.PSObject.Properties.Name -contains "memory")) {
    throw "Missing workflow memory output"
}

$memory = $log.output.memory

foreach ($field in @("enabled", "scope", "persistence", "path", "loaded", "written")) {
    if (-not ($memory.PSObject.Properties.Name -contains $field)) {
        throw "Missing workflow memory field '$field'"
    }
}

if ($memory.enabled -ne $true) {
    throw "Expected memory enabled true"
}

if ($memory.scope -ne "workflow") {
    throw "Expected memory scope workflow, got $($memory.scope)"
}

if ($memory.persistence -ne "dry-run") {
    throw "Expected memory persistence dry-run, got $($memory.persistence)"
}

if ($memory.path -ne "logs/memory/implementation-review-000_template.json") {
    throw "Unexpected memory path: $($memory.path)"
}

if ($memory.loaded -ne $false) {
    throw "Expected dry-run memory loaded false"
}

if ($memory.written -ne $false) {
    throw "Expected dry-run memory written false"
}

foreach ($stepLog in $log.output.step_logs) {
    if (-not ($stepLog.PSObject.Properties.Name -contains "memory")) {
        throw "Missing step memory field in step $($stepLog.role)"
    }

    if ($stepLog.memory.path -ne "logs/memory/implementation-review-000_template.json") {
        throw "Unexpected step memory path for $($stepLog.role): $($stepLog.memory.path)"
    }
}

Write-Output "Workflow memory policy test passed."
