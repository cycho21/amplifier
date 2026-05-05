# Next Roadmap: Operator Control

## Goal

Build a guarded local operator control surface for drafting roadmaps and
launching explicit dry-run workflow executions from the local UI.

## Status

In progress.

## Principles

- Keep inspection read-only by default.
- Treat authoring and execution as separate modes.
- Draft roadmap changes before writing product planning files.
- Validate roadmap shape before any write or execution control is enabled.
- Start with dry-run workflow execution only.
- Require explicit confirmation before invoking any local runner command.
- Do not enable real workflow execution until dry-run controls, logs, and
  failure states are stable.
- Preserve PowerShell runners and existing contracts as the operational
  boundary.

## Sequence

1. [x] Add a roadmap draft model for title, goal, status, principles, sequence,
   acceptance criteria, and out-of-scope sections.
2. [x] Add tests for roadmap draft validation, required sections, and checklist
   shape.
3. [x] Add a local roadmap authoring UI that creates an in-browser draft without
   writing files.
4. [x] Add markdown preview and export for roadmap drafts.
5. [x] Add an explicit local save control for roadmap drafts under
   `docs/plan/roadmaps/`, guarded by validation and confirmation.
6. [ ] Add a workflow execution request model that binds task id, workflow spec,
   mode, step runner command, and log output path.
7. [ ] Add tests for execution request validation and command construction.
8. [ ] Add a dry-run-only execution panel that can invoke `runner/workflow.ps1`
   after explicit confirmation.
9. [ ] Capture execution stdout, stderr, exit code, command, and log path into a
   local UI result record.
10. [ ] Link completed execution records back into the existing log inspector and
    verification panel.
11. [ ] Add blocked controls and UI copy for real execution, explaining that
    `-Mode real` and `-AllowReal` remain out of scope for this roadmap.
12. [ ] Add tests for failed command handling, cancelled confirmation, invalid
    paths, and missing runner prerequisites.

## Acceptance Criteria

- Operators can draft and preview a roadmap without mutating repository files.
- Roadmap writes require validation and an explicit save action.
- Existing roadmap files can be loaded into the draft editor and overwritten
  only after confirmation.
- Invalid roadmap drafts cannot be saved.
- Workflow execution controls are dry-run only.
- Every execution request shows the exact command before it can run.
- Execution results capture command, exit code, output streams, and log path.
- Captured execution logs can be inspected by the existing Operator UI.
- The UI cannot trigger real runner execution in this roadmap.

## Out Of Scope

- Real workflow execution from the UI.
- Remote execution.
- Background job scheduling.
- Multi-user approvals.
- Authentication.
- Database-backed persistence.
- Editing workflow specs, task files, contracts, agents, execution specs, or
  memory files from the UI.
