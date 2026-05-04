# Voting Contract

## Purpose

This document defines the runner-neutral contract boundary for future workflow
result voting.

Voting is separate from structural comparison. Comparison verifies whether step
outputs preserve required fields and can be compared. Voting may later choose or
rank among eligible step results, but it must not replace comparison.

## Stability Rule

Voting must not run until comparison and real execution are stable.

Until voting execution is implemented, workflow logs are not required to include
voting output. Voting output is optional until voting execution is implemented.

The workflow runner may add a voting gate placeholder only when:

- the workflow used real execution
- the workflow completed successfully
- structural comparison completed with `all-required-fields-present`

Dry-run workflows and failed real workflows must not emit voting output.

## Future Voting Output

When voting is implemented, workflow logs that include voting must add a
`voting` object under `output`.

Minimum future voting fields:

```text
- voting_method
- eligible_step_ids
- votes
- selected_step_id
- status
```

## Separation From Comparison

Voting must not replace comparison. A workflow log may include both
`comparison` and `voting`, but `comparison` remains the structural field
presence check.

Voting must not mutate step logs, remove comparison output, or hide missing
required fields.

## Placeholder Status

Until a voting algorithm is implemented, gated voting output must use:

```text
voting_method: not-implemented
status: ready-not-implemented
votes: []
selected_step_id: ""
```

## Out Of Scope

- Voting algorithms.
- Judge prompt design.
- Weighting or scoring rules.
- Automatic winner selection.
