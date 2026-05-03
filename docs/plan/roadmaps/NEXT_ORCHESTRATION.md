# Next Roadmap: Orchestration

## Goal

Move from dry-run workflow grouping to real orchestration behavior.

## Status

In progress.

## Sequence

1. [x] Define dependency graph validation for workflow specs.
2. [x] Detect cycles before execution.
3. [ ] Execute independent steps concurrently in real parallel mode.
4. [ ] Preserve deterministic dry-run grouping for tests.
5. [ ] Add cancellation and failure propagation rules.
6. [ ] Define result voting separately from structural comparison.
7. [ ] Implement voting only after comparison and real execution are stable.

## Acceptance Criteria

- Sequential workflows still execute in dependency order.
- Parallel workflows execute independent steps concurrently when real mode is enabled.
- Dry-run logs still include `parallel_groups`.
- Voting does not replace structural comparison.

## Out Of Scope

- Provider-specific cost calculation.
- Persistent memory store implementation.
