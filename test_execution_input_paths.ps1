$ErrorActionPreference = "Stop"

$taskId = "000_template"
$executionSpecs = Get-ChildItem -File "execution" -Filter "*.yaml"
$agentRoles = Get-ChildItem -File "agents" -Filter "*.md"

if ($executionSpecs.Count -eq 0) {
    throw "Expected execution specs under execution/"
}

foreach ($spec in $executionSpecs) {
    $lines = Get-Content -Encoding utf8 $spec.FullName
    $inInput = $false

    foreach ($line in $lines) {
        if ($line -match "^input:\s*$") {
            $inInput = $true
            continue
        }

        if ($inInput -and $line -match "^\S") {
            $inInput = $false
        }

        if (-not $inInput) {
            continue
        }

        if ($line -match "^\s{2}-\s*(.+)$") {
            $path = $Matches[1].Trim().Trim('"').Replace("{task_id}", $taskId)

            if ($path -like "docs/agents/*") {
                throw "$($spec.Name) references removed docs/agents path: $path"
            }

            if (-not (Test-Path $path)) {
                throw "$($spec.Name) references missing input path: $path"
            }
        }
    }
}

foreach ($role in $agentRoles) {
    $text = Get-Content -Encoding utf8 $role.FullName -Raw

    if ($text -like "*docs/agents/*") {
        throw "$($role.Name) references removed docs/agents path"
    }
}

Write-Output "Execution input path test passed."
