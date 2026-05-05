# Next Roadmap: Multi-Repo Operator

## Goal

Turn Mini Amplifier into a local operator console that can register multiple
target repositories, initialize them with minimal planning/task/log structure,
and run target-aware dry-run workflows while keeping shared execution assets in
Mini Amplifier.

## Status

Not started.

## Principles

- Mini Amplifier owns shared execution assets and operator UI code.
- Target repositories own plans, tasks, and logs.
- One Operator UI server can manage multiple target repositories.
- Target initialization must never overwrite existing files.
- Local target paths and run state are operator-local settings.
- Start with dry-run execution before enabling real agent execution.
- Record write scope now so future concurrency can be made safer.
- Do not change a target repository's gitignore or log retention policy.

## Sequence

1. [x] Add `.operator` local state conventions with tracked
   `.operator/targets.example.json` and ignored local state files.
2. [ ] Add target registry model and tests for target id, name, path, active
   target, and duplicate detection.
3. [ ] Add target validation that reports `ready` or `init required` from
   required target folders and files.
4. [ ] Add `templates/target-init/` with minimal target files:
   `docs/plan/roadmaps/NEXT.md`, `tasks/000_template.md`, and `logs/.gitkeep`.
5. [ ] Add target init planning that returns missing folders/files without
   mutating the target repository.
6. [ ] Add confirmed target initialization that creates only missing folders and
   files and never overwrites existing files.
7. [ ] Add local folder picker registration flow with editable proposed target
   name and generated target id.
8. [ ] Add a target selector and target readiness status to the Operator UI.
9. [ ] Split Operator UI server configuration into app root and active target
   repo root.
10. [ ] Convert roadmaps, generated task drafts, logs, and execution records to
   resolve against the selected target repository.
11. [ ] Add central `.operator/runs.json` run index for target id, task id,
   command, status, timestamps, log path, exit code, and write scope.
12. [ ] Add write scope model and validation using repo-relative path prefixes.
13. [ ] Enforce the initial background execution rule: one running task per
   target repository.
14. [ ] Keep shared agents, execution specs, workflow specs, and runner adapters
   resolved from Mini Amplifier while target plans/tasks/logs resolve from the
   selected target repository.
15. [ ] Add tests proving generated tasks and logs are written into the target
   repo, not the Operator UI app directory.
16. [ ] Dogfood by registering the current `amplifier` repository as the first
   target and running a dry-run roadmap item through the target-aware flow.

## Acceptance Criteria

- Operator UI can register more than one target repository.
- `.operator/targets.json` remains local and untracked.
- Target readiness clearly reports missing folders or files.
- Target initialization previews exact changes before writing.
- Initialization does not overwrite existing target files.
- Target repositories contain only plans, tasks, and logs created for that repo.
- Shared agents, execution specs, workflows, runners, and templates remain in
  Mini Amplifier.
- Roadmap run, task draft generation, workflow execution, and log inspection all
  use the currently selected target repository.
- `.operator/runs.json` records target-aware execution state.
- Write scope is captured for each run.
- The first concurrency policy blocks overlapping runs by target repository.

## Out Of Scope

- Real agent execution.
- Remote target repositories.
- Database-backed persistence.
- Authentication.
- Background scheduling beyond local process execution.
- Target repository `.gitignore` modification.
- Editing target task drafts from the UI.
- Per-target custom agent persona editing.
- Concurrent runs within the same target repository.
