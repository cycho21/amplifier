# Test Task: Runner Contract Compliance

## Objective

This is a minimal test task for validating runner contract compliance.

## Requirements

1. Return a valid JSON response
2. Include all required output fields:
   - summary
   - changed_files
   - verification_result
   - risks
   - next_steps

## Expected Output

```json
{
  "summary": "Test task completed successfully",
  "changed_files": [],
  "verification_result": "Contract compliance verified",
  "risks": ["This is a test task"],
  "next_steps": ["Run additional integration tests"]
}
```

## Verification

The test framework will validate that:
- All required fields are present
- Field types match the contract (arrays for changed_files, risks, next_steps)
- provider_metadata is additive (doesn't override output fields)
