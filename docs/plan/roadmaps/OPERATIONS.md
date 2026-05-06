# Next Roadmap: Operations

## Goal

Turn operational log shapes into real operational behavior.

## Status

Completed.

## Sequence

1. [x] Implement real retry behavior for retryable runner failures.
2. [x] Record every retry attempt in workflow and step logs.
3. [x] Add provider cost metadata sources.
4. [x] Calculate estimated cost from usage metadata.
5. [x] Implement persistent memory read/write using the existing memory policy shape.
6. [x] Add memory safety rules for scope, overwrite behavior, and stale data.
7. [x] Add tests for retry exhaustion, cost totals, and memory persistence.

## Acceptance Criteria

- Retry attempts are observable and bounded by `max_attempts`.
- Cost totals equal the sum of step costs.
- Memory dry-run mode never reads or writes real memory.
- Real memory mode uses the configured policy path.

## Out Of Scope

- New UI.
- Database persistence beyond the configured memory path.
