# Operations Progress

This document records incremental operations work.

## 2026-05-04: Real Retry For Runner Failures

Status: completed.

Scope:

- Add a real parallel workflow fixture with retry policy.
- Retry real step runner failures only when `retry_on` includes `runner-error`.
- Bound retries by `max_attempts`.
- Preserve workflow execution when a retryable step succeeds on a later attempt.
- Keep non-retryable real runner failures on the existing failure propagation path.

Verification plan:

- Passed: `.\tests\test_real_workflow_retry.ps1`.

## 2026-05-04: Provider Cost Metadata Sources

Status: completed.

Scope:

- Add provider cost metadata to real Codex runner logs from structured raw output.
- Preserve provider metadata from real step runner logs in workflow step logs.
- Include provider metadata in workflow `cost_tracking.step_costs` entries.
- Keep estimated costs at `0`; real calculation remains a later Operations item.

Verification plan:

- Passed: `.\tests\test_codex_runner_structured_output.ps1`.
- Passed: `.\tests\test_real_parallel_workflow_runner.ps1`.

## 2026-05-04: Estimated Cost Calculation

Status: completed.

Scope:

- Calculate real workflow step `estimated_cost` from usage metadata and token rates.
- Calculate workflow `estimated_total_cost` as the sum of step estimated costs.
- Keep dry-run costs at `0`.
- Keep real steps without token rates at `0`.

Verification plan:

- Passed: `.\tests\test_real_parallel_workflow_runner.ps1`.
- Passed: `.\tests\test_workflow_cost_tracking.ps1`.

## 2026-05-04: Persistent Memory Read/Write

Status: completed.

Scope:

- Read real workflow memory from the configured policy path when it exists.
- Write durable workflow memory to the configured policy path after successful real runs.
- Record workflow and step memory `loaded` and `written` state.
- Preserve dry-run behavior with no real memory read/write.

Verification plan:

- Passed: `.\tests\test_real_workflow_memory.ps1`.
- Passed: `.\tests\test_workflow_memory_policy.ps1`.

## 2026-05-04: Operations Coverage Closure

Status: completed.

Scope:

- Add retry exhaustion assertions for bounded retry failure logs.
- Add explicit cost total sum assertions.
- Add memory persistence assertions for a second real run loading memory written by the first run.

Verification plan:

- Passed: `.\tests\test_real_workflow_retry.ps1`.
- Passed: `.\tests\test_real_parallel_workflow_runner.ps1`.
- Passed: `.\tests\test_real_workflow_memory.ps1`.

## 2026-05-04: Memory Safety Rules

Status: completed.

Scope:

- Refuse to overwrite existing memory from a different workflow or task scope.
- Preserve stale memory and report `stale: true`.
- Record `overwrite_allowed: false` when stale memory prevents writes.
- Mirror memory safety state into step logs.

Verification plan:

- Passed: `.\tests\test_real_workflow_memory.ps1`.
- Passed: `.\tests\test_workflow_memory_policy.ps1`.
- Passed: `.\tests\test_real_parallel_workflow_failure.ps1`.
- Passed: `.\tests\test_real_parallel_workflow_runner.ps1`.

## 2026-05-04: Retry Attempt Logs

Status: completed.

Scope:

- Record each real step runner invocation in `retry_attempts`.
- Aggregate retry attempts into real workflow logs.
- Add retry metadata to individual real step runner logs.
- Keep dry-run retry attempt logs empty.

Verification plan:

- Passed: `.\tests\test_real_workflow_retry.ps1`.
