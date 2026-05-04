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

- Passed: `.\tests\test_runner_invocation_contract.ps1`.

## 2026-05-03: Provider/Tool Selection

Status: completed.

Scope:

- Add Codex-only runner selection to every execution spec.
- Keep runner selection separate from role instructions.
- Keep `mode: dry-run` as the deterministic default.
- Defer Claude and other providers until the Codex runner path is complete.
- Document the runner selection fields in the execution contract.

Verification:

- Passed: `.\tests\test_execution_runner_selection.ps1`.

## 2026-05-03: Execution Input Path Validation

Status: completed.

Scope:

- Remove stale `docs/agents` references from product execution specs.
- Keep product role definitions self-contained.
- Require execution spec input paths to resolve to existing product files.
- Preserve the boundary that `agent-governance/` is not product runtime input.

Verification:

- Passed: `.\tests\test_execution_input_paths.ps1`.

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

- Passed: `.\tests\test_codex_runner_invocation_boundary.ps1`.

## 2026-05-03: Structured Codex Output Capture

Status: completed.

Scope:

- Instruct Codex real runs to return JSON with required output fields.
- Parse valid raw Codex final responses from `--output-last-message`.
- Copy parsed `summary`, `changed_files`, `verification_result`, `risks`, and `next_steps` into the structured log.
- Record whether real output parsing succeeded.
- Leave strict malformed-output failure fixtures for the next step.

Verification:

- Passed: `.\tests\test_codex_runner_structured_output.ps1`.

## 2026-05-03: Dry-Run Fallback Coverage

Status: completed.

Scope:

- Add a real-mode Codex execution fixture for fallback tests.
- Prove `-Mode dry-run` overrides a real-mode execution spec.
- Prove dry-run fallback does not invoke the configured Codex command or write raw output.
- Preserve required structured output fields in fallback logs.

Verification:

- Passed: `.\tests\test_codex_runner_invocation_boundary.ps1`.

## 2026-05-04: Malformed Codex Output Fixtures

Status: completed.

Scope:

- Add fake Codex fixtures for invalid JSON and missing required output fields.
- Fail real Codex runs when raw output cannot populate every required structured field.
- Preserve failure logs with runner metadata, exit code, raw output path, and required output fields.
- Keep valid structured Codex output passing through unchanged.

Verification:

- Passed: `.\tests\test_codex_runner_malformed_output.ps1`.
- Passed: `.\tests\test_codex_runner_invocation_boundary.ps1`.
- Passed: `.\tests\test_codex_runner_structured_output.ps1`.

## 2026-05-04: Codex Log Compatibility Coverage

Status: completed.

Scope:

- Add a compatibility test that generates dry-run and fake real Codex logs from the same task.
- Prove real-run logs preserve the dry-run top-level log fields.
- Prove real-run output preserves required `summary`, `changed_files`, `verification_result`, `risks`, and `next_steps` fields.
- Prove runner-specific metadata remains additive across `runner_selection` and `invocation`.

Verification:

- Passed: `.\tests\test_codex_runner_log_compatibility.ps1`.
