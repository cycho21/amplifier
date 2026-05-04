# Memory Contract

## Purpose

This document defines the runner-neutral persistent memory contract.

Persistent memory records how workflow execution may read or write durable
context. Dry-run runners must keep the log shape stable without reading from or
writing to a real memory store.

## Memory Policy Fields

Workflow specs may define a top-level `memory` block:

```yaml
memory:
  enabled: true
  scope: workflow
  persistence: dry-run
  path: logs/memory/{workflow}-{task_id}.json
```

Required fields:

```text
- enabled
- scope
- persistence
- path
```

## Log Fields

Workflow logs that use memory policy must add `memory` under `output`.

Minimum workflow memory fields:

```text
- enabled
- scope
- persistence
- path
- loaded
- written
- stale
- overwrite_allowed
```

Each step log must also include `memory`.

## Dry-Run Rule

Dry-run runners must not read or write persistent memory.

They must set:

```text
loaded: false
written: false
stale: false
overwrite_allowed: true
```

Real runners may later use the same policy to read and write memory while
preserving the same log fields.

## Real-Run Rule

Real workflow runners must use the configured `path` when `enabled` is `true`
and `persistence` is not `dry-run`.

If the memory file exists before the run, real workflow runners must read it and
set `loaded: true`. If no memory file exists, they must set `loaded: false`.

After a successful real workflow run, real workflow runners must write durable
workflow memory to the configured `path` and set `written: true`.

Real step logs must mirror the workflow memory `loaded` and `written` state.

## Safety Rules

Real workflow runners must not overwrite existing memory from a different
workflow or task scope.

For `scope: workflow`, existing memory that declares a different `workflow` or
`task_id` is outside scope. The runner must fail before writing new memory.

If existing memory declares `stale: true`, the runner must mark workflow memory
as:

```text
loaded: true
stale: true
written: false
overwrite_allowed: false
```

Stale memory must not be overwritten by the run.
