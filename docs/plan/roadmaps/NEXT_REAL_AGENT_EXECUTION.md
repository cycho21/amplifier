# Next Roadmap: Real Agent Execution

## Goal

Enable real agent execution from the Operator UI through explicit, auditable
controls while keeping dry-run as the default and preserving target repository
safety boundaries.

## Status

In progress.

## Principles

- Dry-run remains the default path.
- Real execution requires an explicit opt-in signal at every layer.
- Real execution must reuse the existing workflow and runner contracts.
- Target repo task/log ownership remains unchanged.
- Write scope must be visible before real execution starts.
- Failed real executions must preserve command, stdout, stderr, exit code, and
  linked logs for review.
- Do not enable concurrent real runs inside the same target repository.

## Sequence

1. [x] Add a guarded real execution request model that only allows `real` mode
   with explicit opt-in and emits `-AllowReal`.
2. [x] Add server-side real execution confirmation checks separate from dry-run
   confirmation.
3. [x] Add UI controls for real execution that are disabled until a generated
   task, write scope, and explicit real confirmation are present.
4. [ ] Show a real execution risk summary before invoking the runner.
5. [ ] Record real execution metadata in `.operator/runs.json` and execution
   record logs without changing dry-run log shape.
6. [ ] Add UI states for real running, real failed, and real completed records.
7. [ ] Add tests proving real mode remains blocked without explicit opt-in at
   model, server, and UI-adjacent layers.
8. [ ] Dogfood with a controlled fake real runner before allowing Codex real
   invocation from the UI.

## Acceptance Criteria

- `dry-run` behavior and tests remain unchanged.
- `real` mode cannot be created without explicit opt-in.
- Real workflow commands include `-AllowReal`.
- Server rejects real execution unless real confirmation is present.
- The Operator UI clearly separates dry-run and real execution controls.
- Write scope is visible before real execution can be invoked.
- Real execution records are linked to generated workflow logs.
- A fake real runner dogfood path proves the end-to-end flow without invoking
  Codex.

## Out Of Scope

- Autonomous background scheduling.
- Multiple concurrent real runners per target repository.
- Remote execution.
- Authentication.
- Provider account setup.
- Editing target tasks from the UI.
- Invoking Codex real mode from the UI before fake-run dogfood passes.
