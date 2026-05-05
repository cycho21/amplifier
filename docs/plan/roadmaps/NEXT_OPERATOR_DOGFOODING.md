# Next Roadmap: Operator Dogfooding

## Goal

Make the Operator UI usable for its own development loop: a roadmap added under
`docs/plan/roadmaps/` can be loaded in the web app, converted into a task draft,
executed as a dry-run workflow, and traced back through generated logs without
manual path copying.

## Status

In progress.

## Principles

- Use the local web app as the primary operator surface.
- Keep the first dogfooding loop dry-run only.
- Prefer linking existing files and logs over adding new persistence.
- Make generated task drafts inspectable before execution.
- Preserve explicit confirmation before invoking local runner commands.
- Keep real execution blocked until dogfooding proves the dry-run loop.
- Treat each generated artifact as traceable: roadmap item, task draft,
  execution record, and workflow log.

## Sequence

1. [x] Add a roadmap-created task draft viewer so operators can inspect the
   generated `tasks/roadmap-*.md` file from the UI.
2. [ ] After a Roadmap `Run`, prefill the Workflow Execution panel with the
   generated task id and dry-run defaults.
3. [ ] Add a direct link from an execution record to the generated workflow log
   in the existing Runs inspector.
4. [ ] Add a recent execution request list that shows task id, command, log
   output path, exit code, and timestamp.
5. [ ] Add a retry action for failed dry-run execution records that reuses the
   captured command fields after confirmation.
6. [ ] Add UI states for generated task missing, workflow log missing, and
   stale execution record references.
7. [ ] Add tests that prove the roadmap item, generated task draft, execution
   record, and workflow log stay linked.
8. [ ] Dogfood this roadmap from the web app by running at least one item through
   the local Roadmaps and Workflow Execution controls.

## Acceptance Criteria

- A newly added roadmap appears in the web app without manual upload.
- Running a roadmap item creates a task draft that can be opened from the UI.
- The Workflow Execution panel can be populated from the roadmap run result.
- A completed execution record can navigate to its generated workflow log.
- Failed dry-run executions preserve enough data to retry deliberately.
- Missing generated artifacts are shown as clear UI states, not silent failures.
- Real execution remains unavailable from the UI.
- At least one item in this roadmap is exercised through the Operator UI itself.

## Out Of Scope

- Real workflow execution from the UI.
- Remote execution.
- Background job scheduling.
- Multi-user approvals.
- Authentication.
- Database-backed persistence.
- Editing task drafts from the UI.
- Editing workflow specs, contracts, agents, execution specs, or memory files
  from the UI.
