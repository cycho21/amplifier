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
