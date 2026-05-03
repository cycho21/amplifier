# Execution Contract

## Purpose

This document defines the runner-neutral contract for a single agent execution.

## Required Inputs

```text
INPUT:
- PLAN.md
- agent role file
- task file
- execution spec
```

## Required Output

```text
OUTPUT:
- summary
- changed_files
- verification_result
- risks
- next_steps
```

The runner may add tool-specific metadata, but it must not remove or rename the
required output fields.

## Execution Spec

All agent execution rules are defined in YAML.

Example: `execution/implementer.yaml`

```yaml
role: implementer

runner:
  provider: codex
  tool: codex-cli
  mode: dry-run

input:
  - PLAN.md
  - agents/implementer.md
  - tasks/{task_id}.md

instructions:
  - Follow task requirements exactly.
  - Modify only files allowed by the task.
  - Keep changes minimal.
  - Run the narrowest relevant verification command when possible.
  - Report risks and incomplete work explicitly.

output:
  - summary
  - changed_files
  - verification_result
  - risks
  - next_steps
```

The execution spec is the source of truth for prompt generation. Runner scripts
must read this file instead of hard-coding role behavior.

## Runner Selection

Execution specs define runner selection separately from role behavior:

```yaml
runner:
  provider: codex
  tool: codex-cli
  mode: dry-run
```

Codex is the only supported provider until the Codex runner path is complete.
Other providers must be added only after the Codex path preserves the required
log shape in both dry-run and real modes.

`mode: dry-run` is the default deterministic local test mode. `mode: real` must
be set explicitly before a runner may invoke an external tool.

## Runner Responsibilities

The runner is an adapter. It should do as little policy work as possible.

A runner is responsible for:

1. Loading the execution spec.
2. Loading the referenced task and agent role files.
3. Building the prompt using the standard prompt structure.
4. Calling the selected LLM tool or API.
5. Capturing the response.
6. Writing a structured log.

The runner is not responsible for inventing task rules, changing role behavior,
or deciding hidden output fields.

## Prompt Generation Standard

Generated prompts must follow this structure:

```text
[System]
- Agent role definition

[Context]
- PLAN.md
- Task file
- Execution constraints

[Instructions]
- Instructions from execution YAML

[Output Format]
- Required structured output fields
```

Prompt control instructions, schemas, and formatting rules should be written in
English by default. Task-specific output language can be defined by the task file
or agent role.
