# Real Runners Progress

This document records incremental real runner work.

## 2026-05-03: Runner Invocation Contract

Status: completed.

Scope:

- Define `dry-run` and `real` runner invocation modes.
- Require explicit opt-in before any real external runner invocation.
- Preserve deterministic dry-run behavior for local tests.
- Require real runner logs to keep `summary`, `changed_files`,
  `verification_result`, `risks`, and `next_steps`.
- Require runner-specific metadata to be additive only.
- Define malformed real runner output as a run failure.

Verification:

- Passed: `.\test_runner_invocation_contract.ps1`.

## 2026-05-03: Provider/Tool Selection

Status: completed.

Scope:

- Add Codex-only runner selection to every execution spec.
- Keep runner selection separate from role instructions.
- Keep `mode: dry-run` as the deterministic default.
- Defer Claude and other providers until the Codex runner path is complete.
- Document the runner selection fields in the execution contract.

Verification:

- Passed: `.\test_execution_runner_selection.ps1`.

## 2026-05-03: Execution Input Path Validation

Status: completed.

Scope:

- Remove stale `docs/agents` references from product execution specs.
- Keep product role definitions self-contained.
- Require execution spec input paths to resolve to existing product files.
- Preserve the boundary that `agent-governance/` is not product runtime input.

Verification:

- Passed: `.\test_execution_input_paths.ps1`.

## 2026-05-03: Codex Invocation Boundary

Status: completed.

Scope:

- Make `runner/codex.ps1` read `provider`, `tool`, and `mode` from the execution spec.
- Keep dry-run as the default and avoid external calls unless real mode is explicit.
- Require `-AllowReal` before invoking `codex exec`.
- Add invocation metadata for configured mode, effective mode, command, exit code, and raw output path.
- Preserve required output fields in dry-run and real boundary logs.
- Leave structured model output parsing for the next real-runner step.

Verification:

- Passed: `.\test_codex_runner_invocation_boundary.ps1`.
