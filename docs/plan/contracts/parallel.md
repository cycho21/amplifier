# Parallel Contract

## Purpose

This document defines the runner-neutral contract for parallel workflow
execution.

Parallel execution is allowed only after the sequential workflow contract is
stable and covered by tests.

## Parallel Workflow Mode

Parallel workflows use the same workflow schema as sequential workflows, with
`mode: parallel`.

Steps with no incomplete dependencies may be grouped into the same parallel
batch. Steps with dependencies may start only after every dependency has
completed in an earlier batch.

Real parallel execution must invoke the step runner for every ready step in the
same batch concurrently. The next batch may start only after every step in the
current batch completes.

## Required Workflow Output

Parallel workflow logs must include the common workflow output fields:

```text
- workflow_summary
- step_logs
- final_status
- risks
- next_steps
```

Parallel workflow logs must also include:

```text
- execution_mode
- parallel_groups
```

`execution_mode` must be `parallel`.

`parallel_groups` must preserve the dry-run execution plan as ordered batches.
Each group lists the steps that are eligible to run together.

## Dry-Run Rule

The dry-run runner does not need to launch real concurrent processes.

It must prove the parallel plan by grouping steps according to `depends_on` and
recording the group structure in the workflow log.

Dry-run grouping must be deterministic for tests. Repeated dry-runs of the same
workflow spec and task must produce the same `parallel_groups` order, and
dry-run mode must not invoke a configured real step runner.

## Real-Run Rule

Real parallel workflow execution must be explicitly enabled. The workflow runner
must not invoke real step runners unless real mode and explicit real-run
permission are both present.

Real parallel workflow logs must preserve `parallel_groups` so dry-run and
real-run execution plans remain comparable.

If any step in a real parallel batch fails, the workflow must stop before
starting later dependency batches. Running or not-yet-started jobs in the same
batch must be cancelled when possible, and the workflow log must record
`failed_steps`, `cancelled_steps`, and `skipped_steps` with `final_status:
real-failed`.
