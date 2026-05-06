# Next Roadmap: Real Runners

## Goal

Turn the dry-run runner contract into real runner execution while preserving the
existing log shape.

## Status

Completed.

## Sequence

1. [x] Define real runner invocation contract.
2. [x] Add provider/tool selection to execution specs without hard-coding role behavior.
3. [x] Implement real Codex runner invocation behind the existing runner adapter boundary.
4. [x] Capture real model output into the required structured fields.
5. [x] Preserve dry-run mode as a testable fallback.
6. [x] Add failure fixtures for malformed model output.
7. [x] Add tests that prove real-run logs remain compatible with dry-run logs.

## Acceptance Criteria

- Real runner logs keep `summary`, `changed_files`, `verification_result`, `risks`, and `next_steps`.
- Runner-specific metadata is additive only.
- Dry-run tests continue to pass.
- Real invocation can be disabled for deterministic local tests.

## Out Of Scope

- Real parallel execution.
- Cost calculation.
- Persistent memory read/write.
