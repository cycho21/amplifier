$ErrorActionPreference = "Stop"

function Remove-TestOutput {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        if (Test-Path $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

$logOut = "logs/test-workflow-real-memory-000_template.json"
$stepLogDir = "logs/test-real-memory-step-logs"
$markerDir = "logs/test-real-memory-markers"
$memoryDir = "logs/test-real-memory"
$memoryPath = Join-Path $memoryDir "parallel-review-memory-000_template.json"

Remove-TestOutput @($logOut, $stepLogDir, $markerDir, $memoryDir)
New-Item -ItemType Directory -Force -Path $memoryDir | Out-Null

$seedMemory = [ordered]@{
    seeded = $true
    value = "existing-memory"
}
$seedMemory | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 -Path $memoryPath

$previousMarkerDir = $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR
$previousSleepMs = $env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS
$env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $markerDir
$env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS = "1"

try {
    & .\runner\workflow.ps1 `
        -TaskId "000_template" `
        -WorkflowSpec "test-fixtures/workflows/parallel-review-memory.yaml" `
        -Mode "real" `
        -AllowReal `
        -StepRunnerCommand ".\test-fixtures\fake-workflow-step-runner.ps1" `
        -StepLogDir $stepLogDir `
        -LogOut $logOut
} finally {
    $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $previousMarkerDir
    $env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS = $previousSleepMs
}

if (-not (Test-Path $logOut)) {
    throw "Expected real memory workflow log was not created: $logOut"
}

$log = Get-Content -Encoding utf8 $logOut -Raw | ConvertFrom-Json

if ($log.output.final_status -ne "real-complete") {
    throw "Expected real memory workflow to complete, got $($log.output.final_status)"
}

if ($log.output.memory.path.Replace("\", "/") -ne $memoryPath.Replace("\", "/")) {
    throw "Expected workflow memory path $memoryPath, got $($log.output.memory.path)"
}

if ($log.output.memory.loaded -ne $true) {
    throw "Expected workflow memory loaded true"
}

if ($log.output.memory.written -ne $true) {
    throw "Expected workflow memory written true"
}

foreach ($stepLog in $log.output.step_logs) {
    if ($stepLog.memory.loaded -ne $true) {
        throw "Expected step $($stepLog.step_id) memory loaded true"
    }

    if ($stepLog.memory.written -ne $true) {
        throw "Expected step $($stepLog.step_id) memory written true"
    }
}

if (-not (Test-Path $memoryPath)) {
    throw "Expected real memory file to exist: $memoryPath"
}

$writtenMemory = Get-Content -Encoding utf8 $memoryPath -Raw | ConvertFrom-Json

if ($writtenMemory.workflow -ne "parallel-review-memory") {
    throw "Expected written memory workflow parallel-review-memory, got $($writtenMemory.workflow)"
}

if ($writtenMemory.task_id -ne "000_template") {
    throw "Expected written memory task_id 000_template, got $($writtenMemory.task_id)"
}

if ($writtenMemory.loaded_existing_memory -ne $true) {
    throw "Expected written memory to record loaded_existing_memory true"
}

$stepIds = @($writtenMemory.step_ids)
if ($stepIds.Count -ne 2 -or $stepIds -notcontains "backend-engineer" -or $stepIds -notcontains "frontend-engineer") {
    throw "Expected written memory to record completed step ids"
}

Remove-TestOutput @($logOut, $stepLogDir, $markerDir, $memoryDir)

$env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $markerDir
$env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS = "1"

try {
    & .\runner\workflow.ps1 `
        -TaskId "000_template" `
        -WorkflowSpec "test-fixtures/workflows/parallel-review-memory.yaml" `
        -Mode "real" `
        -AllowReal `
        -StepRunnerCommand ".\test-fixtures\fake-workflow-step-runner.ps1" `
        -StepLogDir $stepLogDir `
        -LogOut $logOut

    & .\runner\workflow.ps1 `
        -TaskId "000_template" `
        -WorkflowSpec "test-fixtures/workflows/parallel-review-memory.yaml" `
        -Mode "real" `
        -AllowReal `
        -StepRunnerCommand ".\test-fixtures\fake-workflow-step-runner.ps1" `
        -StepLogDir $stepLogDir `
        -LogOut $logOut
} finally {
    $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $previousMarkerDir
    $env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS = $previousSleepMs
}

$secondRunLog = Get-Content -Encoding utf8 $logOut -Raw | ConvertFrom-Json
if ($secondRunLog.output.memory.loaded -ne $true) {
    throw "Expected second real memory run to load memory written by first run"
}

$secondRunMemory = Get-Content -Encoding utf8 $memoryPath -Raw | ConvertFrom-Json
if ($secondRunMemory.loaded_existing_memory -ne $true) {
    throw "Expected second real memory write to record loaded_existing_memory true"
}

$unsafeMemory = [ordered]@{
    workflow = "other-workflow"
    task_id = "000_template"
    value = "do-not-overwrite"
}

Remove-TestOutput @($logOut, $stepLogDir, $markerDir, $memoryDir)
New-Item -ItemType Directory -Force -Path $memoryDir | Out-Null
$unsafeMemory | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 -Path $memoryPath

$env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $markerDir
$env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS = "1"
$failedForUnsafeScope = $false

try {
    & .\runner\workflow.ps1 `
        -TaskId "000_template" `
        -WorkflowSpec "test-fixtures/workflows/parallel-review-memory.yaml" `
        -Mode "real" `
        -AllowReal `
        -StepRunnerCommand ".\test-fixtures\fake-workflow-step-runner.ps1" `
        -StepLogDir $stepLogDir `
        -LogOut $logOut
} catch {
    $failedForUnsafeScope = $true

    if ($_.Exception.Message -notlike "*Refusing to overwrite memory outside workflow scope*") {
        throw "Expected unsafe scope memory error, got '$($_.Exception.Message)'"
    }
} finally {
    $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $previousMarkerDir
    $env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS = $previousSleepMs
}

if (-not $failedForUnsafeScope) {
    throw "Expected real workflow memory run to fail for unsafe scope"
}

$preservedUnsafeMemory = Get-Content -Encoding utf8 $memoryPath -Raw | ConvertFrom-Json
if ($preservedUnsafeMemory.workflow -ne "other-workflow" -or $preservedUnsafeMemory.value -ne "do-not-overwrite") {
    throw "Expected unsafe scope memory file to be preserved"
}

$staleMemory = [ordered]@{
    workflow = "parallel-review-memory"
    task_id = "000_template"
    stale = $true
    value = "stale-memory"
}

Remove-TestOutput @($logOut, $stepLogDir, $markerDir, $memoryDir)
New-Item -ItemType Directory -Force -Path $memoryDir | Out-Null
$staleMemory | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 -Path $memoryPath

$env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $markerDir
$env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS = "1"

try {
    & .\runner\workflow.ps1 `
        -TaskId "000_template" `
        -WorkflowSpec "test-fixtures/workflows/parallel-review-memory.yaml" `
        -Mode "real" `
        -AllowReal `
        -StepRunnerCommand ".\test-fixtures\fake-workflow-step-runner.ps1" `
        -StepLogDir $stepLogDir `
        -LogOut $logOut
} finally {
    $env:MINI_AMPLIFIER_FAKE_STEP_MARKER_DIR = $previousMarkerDir
    $env:MINI_AMPLIFIER_FAKE_STEP_SLEEP_MS = $previousSleepMs
}

$staleLog = Get-Content -Encoding utf8 $logOut -Raw | ConvertFrom-Json
if ($staleLog.output.memory.stale -ne $true) {
    throw "Expected workflow memory stale true for stale existing memory"
}

if ($staleLog.output.memory.written -ne $false) {
    throw "Expected stale memory not to be overwritten"
}

$preservedStaleMemory = Get-Content -Encoding utf8 $memoryPath -Raw | ConvertFrom-Json
if ($preservedStaleMemory.value -ne "stale-memory") {
    throw "Expected stale memory file to be preserved"
}

Remove-TestOutput @($logOut, $stepLogDir, $markerDir, $memoryDir)

Write-Output "Real workflow memory test passed."
