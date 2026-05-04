# Next Roadmap: Operator UI

## Goal

Build a local operator UI for inspecting Mini Amplifier workflows, logs, and
verification status without changing runner behavior.

## Status

In progress.

## Principles

- Start read-only.
- Use local files as the source of truth.
- Do not add authentication, remote execution, or database persistence.
- Do not run real workflows from the UI until log inspection is stable.
- Keep PowerShell runners and contracts as the operational boundary.

## Sequence

1. [x] Add a small local web app scaffold under `frontend/`.
2. [x] Add a read-only log index that lists workflow logs from `logs/`.
3. [x] Add a workflow run inspector for `output.step_logs`, status, risks, and next steps.
4. [x] Render retry attempts, retry exhaustion, cancelled steps, and skipped steps.
5. [x] Render cost tracking totals and per-step provider metadata.
6. [x] Render memory loaded/written/stale/overwrite state.
7. [x] Add a read-only roadmap dashboard from `docs/plan/roadmaps/`.
8. [x] Add a local verification panel that can display test command results from a captured log file.
9. [x] Add tests for log parsing, empty states, malformed logs, and roadmap parsing.

## Acceptance Criteria

- The first UI release can run locally without external services.
- The UI can inspect existing workflow logs without modifying them.
- Failed, cancelled, skipped, retry-exhausted, stale-memory, and cost-total states are visible.
- Missing or malformed logs produce clear UI states instead of crashes.
- The UI does not invoke real runners or mutate memory in this roadmap.

## Out Of Scope

- Remote server deployment.
- Multi-user access.
- Authentication.
- Database-backed persistence.
- Real workflow execution buttons.
- Editing workflow specs, tasks, contracts, or memory from the UI.
