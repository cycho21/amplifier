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
```

Each step log must also include `memory`.

## Dry-Run Rule

Dry-run runners must not read or write persistent memory.

They must set:

```text
loaded: false
written: false
```

Real runners may later use the same policy to read and write memory while
preserving the same log fields.
