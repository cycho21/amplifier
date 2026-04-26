# Mini Amplifier MVP

## Purpose

The first working version should prove one complete path:

```text
task file -> execution spec -> prompt -> runner -> structured output -> log file
```

The MVP is successful when the same task contract can be executed by at least
one runner and leaves a valid log.

## Deliverables

- one task template
- one implementer role file
- one implementer execution YAML
- one runner
- one generated prompt path
- one structured log output
- one documented verification command

## Minimum Build Order

1. Define `tasks/000_template.md`.
2. Define `agents/implementer.md`.
3. Define `execution/implementer.yaml`.
4. Implement the first runner adapter.
5. Generate a prompt from the task, role, and execution spec.
6. Execute the prompt through the runner.
7. Save the result to `logs/`.
8. Validate that the log contains all required fields.

Each step should be small and independently reviewable.

## Validation Strategy

The MVP should be validated with narrow checks first.

Required checks:

- execution YAML can be parsed
- referenced input files exist
- generated prompt contains the required sections from [CONTRACT.md](CONTRACT.md)
- runner returns the required output fields from [CONTRACT.md](CONTRACT.md)
- log file is valid JSON

Later checks can compare two runners executing the same task and verify that
their output structures match.

## Definition of Done

The project reaches its first useful milestone when:

- a task can be executed from a task file and execution YAML
- the runner does not hard-code role policy
- the result contains the required output fields
- a structured log is written
- at least one verification command confirms the log shape
- the same contract can be reused by another runner without changing the task

The longer-term goal is met when the same task can be executed through both
Codex and Claude with equivalent input contracts and compatible output logs.
