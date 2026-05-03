# Runner Invocation Contract

## Purpose

This document defines how runner adapters switch from deterministic dry-run
behavior to real tool invocation while preserving comparable logs.

## Invocation Modes

Runners must support these modes:

```text
mode: dry-run
mode: real
```

`mode: dry-run` generates prompts and structured logs without invoking external
LLM tools.

`mode: real` invokes the selected external runner tool behind the same adapter
boundary.

Real invocation must be explicitly enabled. A runner must not call an external
tool because of a default value, missing field, or ambiguous configuration.

Dry-run mode must remain deterministic so local tests can run without network,
credentials, model access, or external CLI state.

## Required Output Fields

Real runner logs must keep the same required output fields as dry-run logs:

```text
- summary
- changed_files
- verification_result
- risks
- next_steps
```

Runner-specific metadata is additive only. A real runner may add fields such as
tool name, command, exit code, raw output path, or parsed output status, but it
must not remove or rename required fields.

## Failure Behavior

Malformed real runner output must fail the run. A real runner output is
malformed when the adapter cannot populate every required output field from the
tool response.

Failure logs must preserve enough metadata to diagnose the adapter failure
without pretending the task succeeded. The exact malformed-output fixtures and
parser behavior are defined in a later implementation step.

## Out Of Scope

- Provider-specific cost calculation.
- Persistent memory read or write.
- Real parallel execution.
- Provider/tool selection in execution specs.
