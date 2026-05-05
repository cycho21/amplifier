# Test script for output-parser.ps1
. .\runner\lib\output-parser.ps1

Write-Output "Testing output-parser.ps1..."

# Test 1: Valid JSON
Write-Output "`n=== Test 1: Valid JSON ==="
$valid = @{
    summary = "test"
    changed_files = @()
    verification_result = "pass"
    risks = @()
    next_steps = @()
} | ConvertTo-Json

$parsed = Parse-LLMOutput -RawOutput $valid
$errors = Validate-OutputContract -Output $parsed
if ($errors.Count -eq 0) {
    Write-Output "✓ PASS - Valid JSON parsed correctly"
} else {
    Write-Output "✗ FAIL - Unexpected errors: $($errors -join ', ')"
}

# Test 2: Markdown fences
Write-Output "`n=== Test 2: Markdown fence stripping ==="
$malformed = @"
``````json
{"summary": "test", "changed_files": [], "verification_result": "pass", "risks": [], "next_steps": []}
``````
"@
try {
    $parsed2 = Parse-LLMOutput -RawOutput $malformed
    if ($parsed2.summary -eq "test") {
        Write-Output "✓ PASS - Markdown fences stripped correctly"
    } else {
        Write-Output "✗ FAIL - Unexpected parsed value"
    }
} catch {
    Write-Output "✗ FAIL - Parse error: $_"
}

# Test 3: Missing field detection
Write-Output "`n=== Test 3: Missing field detection ==="
$invalid = @{ summary = "test" } | ConvertTo-Json
$parsed3 = Parse-LLMOutput -RawOutput $invalid
$errors3 = Validate-OutputContract -Output $parsed3
if ($errors3.Count -gt 0) {
    Write-Output "✓ PASS - Missing fields detected: $($errors3.Count) errors"
    Write-Output "  Errors: $($errors3 -join ', ')"
} else {
    Write-Output "✗ FAIL - Should have detected missing fields"
}

# Test 4: Provider metadata addition
Write-Output "`n=== Test 4: Provider metadata addition ==="
$output = @{
    summary = "test"
    changed_files = @()
    verification_result = "pass"
    risks = @()
    next_steps = @()
}
$metadata = @{
    model = "sonnet-4.5"
    tokens = 1234
}
$result = Add-ProviderMetadata -Output $output -Metadata $metadata
if ($result.ContainsKey("provider_metadata") -and $result.provider_metadata.model -eq "sonnet-4.5") {
    Write-Output "✓ PASS - Provider metadata added correctly"
} else {
    Write-Output "✗ FAIL - Provider metadata not added"
}

Write-Output "`n=== All tests complete ==="
