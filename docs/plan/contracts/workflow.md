# Workflow Contract

## Purpose

This document defines the runner-neutral contract for multi-agent workflows.

Workflow specs compose existing task files, agent role files, and execution
specs without replacing the single-agent execution contract.

## Workflow Spec

Multi-agent workflows are defined in YAML under `workflows/`.

Example: `workflows/implementation-review.yaml`

```yaml
workflow: implementation-review
mode: sequential

input:
  - docs/plan/PLAN.md
  - docs/plan/CONTRACT.md
  - tasks/{task_id}.md

steps:
  - id: architect
    role: architect
    agent_role: agents/architect.md
    execution_spec: execution/architect.yaml
    task_id: "{task_id}"
    depends_on: []

  - id: implementer
    role: implementer
    agent_role: agents/implementer.md
    execution_spec: execution/implementer.yaml
    task_id: "{task_id}"
    depends_on:
      - architect

output:
  - workflow_summary
  - step_logs
  - final_status
  - risks
  - next_steps
```

## Sequential Execution

Sequential runners must execute steps in dependency order. A step may start only
after every step listed in `depends_on` has completed.

Each workflow step must still produce a normal single-agent log that follows the
required output fields:

```text
- summary
- changed_files
- verification_result
- risks
- next_steps
```

Workflow-level logs may add orchestration metadata, but they must keep step logs
referenced explicitly so each role result remains comparable across runners.
