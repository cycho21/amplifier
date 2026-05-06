# Orchestration Progress

This document records incremental orchestration work.

## 2026-05-03: Dependency Graph Validation

## Status

Completed.

Scope:

- Validate workflow dependency graphs before execution.
- Reject duplicate step ids.
- Reject dependencies that do not reference an existing step id.
- Reject steps that depend on themselves.
- Reject dependency cycles before execution.
- Preserve existing sequential and parallel dry-run behavior.

Verification plan:

- Passed: `.\tests\test_workflow_graph_validation.ps1`.
- Passed: `.\tests\test_workflow_runner.ps1`.
- Passed: `.\tests\test_parallel_workflow_runner.ps1`.

## 2026-05-04: Real Parallel Step Execution

Status: completed.

Scope:

- Add explicit real workflow execution mode guarded by `-AllowReal`.
- Invoke dependency-ready parallel workflow steps concurrently in each batch.
- Embed real step runner logs into workflow `step_logs`.
- Preserve `parallel_groups` so dry-run and real-run plans remain comparable.
- Keep sequential and parallel dry-run behavior unchanged.

Verification plan:

- Passed: `.\tests\test_real_parallel_workflow_runner.ps1`.
- Passed: `.\tests\test_parallel_workflow_runner.ps1`.
- Passed: `.\tests\test_workflow_runner.ps1`.

## 2026-05-04: Deterministic Dry-Run Parallel Grouping

Status: completed.

Scope:

- Preserve dry-run `parallel_groups` after real parallel execution was added.
- Prove dry-run mode does not invoke a configured real step runner, even with `-AllowReal`.
- Prove repeated dry-run parallel workflow executions produce the same group order.

Verification plan:

- Passed: `.\tests\test_parallel_workflow_runner.ps1`.

## 2026-05-04: Real Parallel Failure Propagation

Status: completed.

Scope:

- Stop real parallel workflow execution when a step in the current batch fails.
- Cancel still-running jobs in the failed batch when possible.
- Skip later dependency batches after an upstream failure.
- Preserve a workflow-level failure log with `failed_steps`, `cancelled_steps`, and `skipped_steps`.

Verification plan:

- Passed: `.\tests\test_real_parallel_workflow_failure.ps1`.
- Passed: `.\tests\test_real_parallel_workflow_runner.ps1`.

## 2026-05-04: Voting Contract Boundary

Status: completed.

Scope:

- Define voting separately from structural comparison.
- Keep comparison responsible only for required field presence and structural comparability.
- Mark voting output as optional until voting execution is implemented.
- Defer voting algorithms and winner selection to a later roadmap step.

Verification plan:

- Passed: `.\tests\test_workflow_voting_contract.ps1`.

## 2026-05-04: Voting Gate Placeholder

Status: completed.

Scope:

- Emit voting placeholder output only for successful real workflow execution with passing structural comparison.
- Keep dry-run and failed real workflow logs free of voting output.
- Preserve comparison output as the structural readiness gate.
- Defer voting algorithms, votes, and winner selection.

Verification plan:

- Passed: `.\tests\test_workflow_voting_gate.ps1`.
- Passed: `.\tests\test_real_parallel_workflow_runner.ps1`.
- Passed: `.\tests\test_real_parallel_workflow_failure.ps1`.
