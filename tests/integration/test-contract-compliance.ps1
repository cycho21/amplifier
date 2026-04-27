# Contract Compliance Test Suite
# Validates that runner outputs conform to the contract

$ErrorActionPreference = "Stop"

Write-Output "=== Contract Compliance Test Suite ==="
Write-Output ""

# Load output parser for validation
. (Join-Path $PSScriptRoot "../../runner/lib/output-parser.ps1")

$testsPassed = 0
$testsFailed = 0

function Test-RequiredFields {
    param(
        [string]$TestName,
        [hashtable]$Output
    )

    Write-Output "Test: $TestName"

    $requiredFields = @(
        "summary",
        "changed_files",
        "verification_result",
        "risks",
        "next_steps"
    )

    $missing = @()

    foreach ($field in $requiredFields) {
        if (-not $Output.ContainsKey($field)) {
            $missing += $field
        }
    }

    if ($missing.Count -eq 0) {
        Write-Output "  ✓ PASS - All required fields present"
        $script:testsPassed++
        return $true
    } else {
        Write-Output "  ✗ FAIL - Missing fields: $($missing -join ', ')"
        $script:testsFailed++
        return $false
    }
}

function Test-NoRenamedFields {
    param(
        [string]$TestName,
        [hashtable]$Output
    )

    Write-Output "Test: $TestName"

    # Check that output only contains expected keys
    $allowedKeys = @(
        "summary",
        "changed_files",
        "verification_result",
        "risks",
        "next_steps",
        "provider_metadata"  # Allowed as additive field
    )

    $unexpectedKeys = @()

    foreach ($key in $Output.Keys) {
        if ($allowedKeys -notcontains $key) {
            $unexpectedKeys += $key
        }
    }

    if ($unexpectedKeys.Count -eq 0) {
        Write-Output "  ✓ PASS - No unexpected/renamed fields"
        $script:testsPassed++
        return $true
    } else {
        Write-Output "  ✗ FAIL - Unexpected fields: $($unexpectedKeys -join ', ')"
        $script:testsFailed++
        return $false
    }
}

function Test-ProviderMetadataAdditive {
    param(
        [string]$TestName,
        [hashtable]$Output
    )

    Write-Output "Test: $TestName"

    if (-not $Output.ContainsKey("provider_metadata")) {
        Write-Output "  ⚠ WARNING - No provider_metadata (OK for dry-run)"
        $script:testsPassed++
        return $true
    }

    $metadata = $Output.provider_metadata

    # Ensure provider_metadata doesn't override required fields
    $overrides = @()

    foreach ($field in @("summary", "changed_files", "verification_result", "risks", "next_steps")) {
        if ($metadata -is [hashtable] -and $metadata.ContainsKey($field)) {
            $overrides += $field
        }
    }

    if ($overrides.Count -eq 0) {
        Write-Output "  ✓ PASS - provider_metadata is additive only"
        $script:testsPassed++
        return $true
    } else {
        Write-Output "  ✗ FAIL - provider_metadata overrides fields: $($overrides -join ', ')"
        $script:testsFailed++
        return $false
    }
}

function Test-ArrayFieldTypes {
    param(
        [string]$TestName,
        [hashtable]$Output
    )

    Write-Output "Test: $TestName"

    $arrayFields = @("changed_files", "risks", "next_steps")
    $nonArrays = @()

    foreach ($field in $arrayFields) {
        if ($Output.ContainsKey($field) -and $Output[$field] -isnot [array]) {
            $nonArrays += $field
        }
    }

    if ($nonArrays.Count -eq 0) {
        Write-Output "  ✓ PASS - Array fields have correct types"
        $script:testsPassed++
        return $true
    } else {
        Write-Output "  ✗ FAIL - Non-array fields: $($nonArrays -join ', ')"
        $script:testsFailed++
        return $false
    }
}

# Test 1: Dry-run output
Write-Output "--- Testing Dry-Run Output ---"
$dryRunOutput = @{
    summary = "Dry-run test"
    changed_files = @()
    verification_result = "Verified"
    risks = @()
    next_steps = @()
}

Test-RequiredFields -TestName "Dry-run: Required fields" -Output $dryRunOutput
Test-NoRenamedFields -TestName "Dry-run: No renamed fields" -Output $dryRunOutput
Test-ProviderMetadataAdditive -TestName "Dry-run: Metadata additive" -Output $dryRunOutput
Test-ArrayFieldTypes -TestName "Dry-run: Array types" -Output $dryRunOutput

Write-Output ""

# Test 2: Simulated real runner output with provider_metadata
Write-Output "--- Testing Real Runner Output (Simulated) ---"
$realRunnerOutput = @{
    summary = "Real runner test"
    changed_files = @("file1.ps1")
    verification_result = "Verified via API"
    risks = @("API dependency")
    next_steps = @("Monitor latency")
    provider_metadata = @{
        model = "gpt-4"
        total_tokens = 1234
        latency_ms = 3400
    }
}

Test-RequiredFields -TestName "Real runner: Required fields" -Output $realRunnerOutput
Test-NoRenamedFields -TestName "Real runner: No renamed fields" -Output $realRunnerOutput
Test-ProviderMetadataAdditive -TestName "Real runner: Metadata additive" -Output $realRunnerOutput
Test-ArrayFieldTypes -TestName "Real runner: Array types" -Output $realRunnerOutput

Write-Output ""

# Test 3: Invalid output (missing fields)
Write-Output "--- Testing Invalid Output (Should Fail) ---"
$invalidOutput = @{
    summary = "Incomplete"
}

Test-RequiredFields -TestName "Invalid: Missing fields detection" -Output $invalidOutput

Write-Output ""

# Summary
Write-Output "=== Test Summary ==="
Write-Output "Passed: $testsPassed"
Write-Output "Failed: $testsFailed"

if ($testsFailed -eq 0) {
    Write-Output ""
    Write-Output "✓ All contract compliance tests passed!"
    exit 0
} else {
    Write-Output ""
    Write-Output "✗ Some tests failed. See output above."
    exit 1
}
