# Real Run Smoke Test

## Status

Not started.

## Goal

Execute a real agent run end-to-end through the Operator UI using the simplest
possible task: write a one-paragraph project summary file. This validates that
the real runner path, log capture, and write scope guard all work correctly in
this environment.

## Principles

- Keep the task scope to a single file write so the result is trivially verifiable.
- Use a single-step workflow to isolate the runner from orchestration complexity.
- Treat any runner failure as signal about the environment, not the task.

## Sequence

1. Create task file `tasks/001_smoke_test.md` targeting `docs/plan/SUMMARY.md`.
2. Create workflow `workflows/single-step.yaml` with one implementer step.
3. Run as dry-run first to confirm the command preview is correct.
4. Run as real with write scope limited to `docs/plan/SUMMARY.md`.
5. Verify the log file contains a valid result and `docs/plan/SUMMARY.md` exists.

## Acceptance Criteria

- [ ] Dry-run completes and produces a log file without errors.
- [ ] Real run completes and produces a log file with `status: success`.
- [ ] `docs/plan/SUMMARY.md` is created and contains a readable project summary.
- [ ] Log file includes `runner`, `cost`, and `changed_files` fields.

## Out Of Scope

- Multi-step or parallel workflows.
- Any task that modifies existing source files.
- Retry or voting gate behavior.
