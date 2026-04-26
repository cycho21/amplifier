# Next Roadmap: Operations

## Goal

Turn operational log shapes into real operational behavior.

## Status

Not started.

## Sequence

1. [ ] Implement real retry behavior for retryable runner failures.
2. [ ] Record every retry attempt in workflow and step logs.
3. [ ] Add provider cost metadata sources.
4. [ ] Calculate estimated cost from usage metadata.
5. [ ] Implement persistent memory read/write using the existing memory policy shape.
6. [ ] Add memory safety rules for scope, overwrite behavior, and stale data.
7. [ ] Add tests for retry exhaustion, cost totals, and memory persistence.

## Acceptance Criteria

- Retry attempts are observable and bounded by `max_attempts`.
- Cost totals equal the sum of step costs.
- Memory dry-run mode never reads or writes real memory.
- Real memory mode uses the configured policy path.

## Out Of Scope

- New UI.
- Database persistence beyond the configured memory path.
