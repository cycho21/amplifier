# Integration Tests for Memory Policy
# Tests Read-Memory, Write-Memory, and Merge-MemoryData functions

$ErrorActionPreference = "Stop"

# Load the memory manager library
. (Join-Path $PSScriptRoot "..\..\runner\lib\memory-manager.ps1")

$passCount = 0
$failCount = 0

function Test-Case {
    param(
        [string]$Name,
        [scriptblock]$Test
    )

    try {
        & $Test
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:passCount++
    } catch {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        $script:failCount++
    }
}

Write-Host ""
Write-Host "=== Memory Policy Integration Tests ===" -ForegroundColor Cyan
Write-Host ""

# Setup: Clean test memory file
$testMemoryPath = "logs/memory/test-workflow-memory.json"
if (Test-Path $testMemoryPath) {
    Remove-Item $testMemoryPath -Force
}

# Test 1: Dry-run mode never loads or writes
Test-Case "Dry-run mode never loads or writes" {
    $policy = @{
        enabled = $true
        persistence = "dry-run"
        scope = "workflow"
        path = $testMemoryPath
    }

    $result = Read-Memory -MemoryPolicy $policy -WorkflowName "test" -TaskId "000"

    if ($result.loaded -ne $false) {
        throw "Expected loaded=false in dry-run mode, got $($result.loaded)"
    }

    $written = Write-Memory -MemoryPolicy $policy -MemoryData @{ test = "data" } -WorkflowName "test" -TaskId "000"

    if ($written -ne $false) {
        throw "Expected written=false in dry-run mode, got $written"
    }
}

# Test 2: Disabled memory never loads or writes
Test-Case "Disabled memory never loads or writes" {
    $policy = @{
        enabled = $false
        persistence = "file"
        scope = "workflow"
        path = $testMemoryPath
    }

    $result = Read-Memory -MemoryPolicy $policy -WorkflowName "test" -TaskId "000"

    if ($result.loaded -ne $false) {
        throw "Expected loaded=false when disabled, got $($result.loaded)"
    }

    $written = Write-Memory -MemoryPolicy $policy -MemoryData @{ test = "data" } -WorkflowName "test" -TaskId "000"

    if ($written -ne $false) {
        throw "Expected written=false when disabled, got $written"
    }
}

# Test 3: First run creates memory file
Test-Case "First run creates memory file" {
    $policy = @{
        enabled = $true
        persistence = "file"
        scope = "workflow"
        path = $testMemoryPath
    }

    # Read (should return empty, loaded=false)
    $result = Read-Memory -MemoryPolicy $policy -WorkflowName "test-workflow" -TaskId "001"

    if ($result.loaded -ne $false) {
        throw "Expected loaded=false on first run, got $($result.loaded)"
    }

    if ($result.data.Count -ne 0) {
        throw "Expected empty data on first run, got $($result.data.Count) keys"
    }

    # Write
    $testData = @{
        key1 = "value1"
        key2 = "value2"
    }

    $written = Write-Memory -MemoryPolicy $policy -MemoryData $testData -WorkflowName "test-workflow" -TaskId "001"

    if ($written -ne $true) {
        throw "Expected written=true, got $written"
    }

    # Verify file exists
    if (-not (Test-Path $testMemoryPath)) {
        throw "Memory file not created at $testMemoryPath"
    }
}

# Test 4: Second run loads memory file
Test-Case "Second run loads memory file" {
    $policy = @{
        enabled = $true
        persistence = "file"
        scope = "workflow"
        path = $testMemoryPath
    }

    # Read (should load data)
    $result = Read-Memory -MemoryPolicy $policy -WorkflowName "test-workflow" -TaskId "001"

    if ($result.loaded -ne $true) {
        throw "Expected loaded=true on second run, got $($result.loaded)"
    }

    if (-not $result.data.ContainsKey("key1")) {
        throw "Expected key1 in loaded data"
    }

    if ($result.data.key1 -ne "value1") {
        throw "Expected key1='value1', got '$($result.data.key1)'"
    }

    if (-not $result.data.ContainsKey("key2")) {
        throw "Expected key2 in loaded data"
    }
}

# Test 5: Scope validation rejects mismatched workflow
Test-Case "Scope validation rejects mismatched workflow" {
    $policy = @{
        enabled = $true
        persistence = "file"
        scope = "workflow"
        path = $testMemoryPath
    }

    # Try to load with different workflow name
    $result = Read-Memory -MemoryPolicy $policy -WorkflowName "different-workflow" -TaskId "001"

    # Should return loaded=false due to scope mismatch
    if ($result.loaded -ne $false) {
        throw "Expected loaded=false for mismatched workflow, got $($result.loaded)"
    }
}

# Test 6: Merge strategy - merge (default)
Test-Case "Merge strategy: merge (adds and overwrites)" {
    $existing = @{
        key1 = "old_value1"
        key2 = "old_value2"
    }

    $new = @{
        key2 = "new_value2"  # Overwrite
        key3 = "new_value3"  # Add
    }

    $merged = Merge-MemoryData -Existing $existing -New $new -OverwritePolicy "merge"

    if ($merged.key1 -ne "old_value1") {
        throw "Expected key1='old_value1', got '$($merged.key1)'"
    }

    if ($merged.key2 -ne "new_value2") {
        throw "Expected key2='new_value2' (overwritten), got '$($merged.key2)'"
    }

    if ($merged.key3 -ne "new_value3") {
        throw "Expected key3='new_value3' (added), got '$($merged.key3)'"
    }
}

# Test 7: Merge strategy - replace
Test-Case "Merge strategy: replace (complete replacement)" {
    $existing = @{
        key1 = "value1"
        key2 = "value2"
    }

    $new = @{
        key3 = "value3"
    }

    $merged = Merge-MemoryData -Existing $existing -New $new -OverwritePolicy "replace"

    # Should be completely replaced
    if ($merged.ContainsKey("key1")) {
        throw "Expected key1 to be removed in replace mode"
    }

    if ($merged.ContainsKey("key2")) {
        throw "Expected key2 to be removed in replace mode"
    }

    if (-not $merged.ContainsKey("key3")) {
        throw "Expected key3 in replace mode"
    }
}

# Test 8: Merge strategy - preserve
Test-Case "Merge strategy: preserve (never overwrites)" {
    $existing = @{
        key1 = "old_value1"
        key2 = "old_value2"
    }

    $new = @{
        key2 = "new_value2"  # Should NOT overwrite
        key3 = "new_value3"  # Should add
    }

    $merged = Merge-MemoryData -Existing $existing -New $new -OverwritePolicy "preserve"

    if ($merged.key1 -ne "old_value1") {
        throw "Expected key1='old_value1', got '$($merged.key1)'"
    }

    if ($merged.key2 -ne "old_value2") {
        throw "Expected key2='old_value2' (preserved), got '$($merged.key2)'"
    }

    if ($merged.key3 -ne "new_value3") {
        throw "Expected key3='new_value3' (added), got '$($merged.key3)'"
    }
}

# Test 9: Memory file contains metadata
Test-Case "Memory file contains metadata" {
    $policy = @{
        enabled = $true
        persistence = "file"
        scope = "workflow"
        path = $testMemoryPath
    }

    $testData = @{
        mykey = "myvalue"
    }

    Write-Memory -MemoryPolicy $policy -MemoryData $testData -WorkflowName "test-workflow" -TaskId "002"

    # Read raw file and check metadata
    $rawContent = Get-Content -Path $testMemoryPath -Raw
    $memoryObj = $rawContent | ConvertFrom-Json

    if ($memoryObj.workflow -ne "test-workflow") {
        throw "Expected workflow='test-workflow', got '$($memoryObj.workflow)'"
    }

    if ($memoryObj.task_id -ne "002") {
        throw "Expected task_id='002', got '$($memoryObj.task_id)'"
    }

    if ($memoryObj.scope -ne "workflow") {
        throw "Expected scope='workflow', got '$($memoryObj.scope)'"
    }

    if (-not $memoryObj.last_updated) {
        throw "Expected last_updated field in memory file"
    }
}

# Cleanup
if (Test-Path $testMemoryPath) {
    Remove-Item $testMemoryPath -Force
}

# Summary
Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "  Passed: $passCount" -ForegroundColor Green
Write-Host "  Failed: $failCount" -ForegroundColor Red
Write-Host ""

if ($failCount -gt 0) {
    exit 1
} else {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
}
