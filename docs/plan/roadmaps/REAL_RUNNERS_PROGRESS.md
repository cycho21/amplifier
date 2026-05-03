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
