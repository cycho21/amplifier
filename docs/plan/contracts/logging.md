# Logging Contract

## Purpose

This document defines the runner-neutral structured logging contract.

Logs make runner behavior comparable. They are also the first debugging surface
when two runners behave differently.

## Logging Standard

Each single-agent run should produce one structured log file.

Minimum log fields:

```json
{
  "run_id": "20260426-070000-implementer-000",
  "runner": "codex",
  "role": "implementer",
  "task_id": "000",
  "inputs": [
    "PLAN.md",
    "agents/implementer.md",
    "tasks/000_template.md",
    "execution/implementer.yaml"
  ],
  "output": {
    "summary": "",
    "changed_files": [],
    "verification_result": "",
    "risks": [],
    "next_steps": []
  }
}
```

Runner-specific metadata may be added, but required fields must remain stable.

Workflow-level logs may include orchestration fields such as `workflow`,
`workflow_spec`, and `step_logs`. Step logs must preserve the required
single-agent output fields.
