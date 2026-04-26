# Task Template

## Task ID

`000`

## Title

Short, action-oriented task title.

## Goal

Describe the concrete outcome this task must produce. The goal should be small
enough for one agent run and specific enough to verify.

## Background

Provide only the context required to complete this task.

Reference documents:

- `docs/plan/PLAN.md`
- `docs/plan/CONTRACT.md`
- `docs/plan/MVP.md`

## Scope

Allowed changes:

- List files or directories the agent may create or modify.

Out of scope:

- List files, behaviors, or follow-up ideas the agent must not change.

## Requirements

- Requirement 1.
- Requirement 2.
- Requirement 3.

## Constraints

- Follow the execution contract in `docs/plan/CONTRACT.md`.
- Modify only files allowed by this task.
- Keep changes minimal.
- Report incomplete work explicitly.

## Verification

Run the narrowest relevant checks for this task.

Required verification:

- Check that all required files exist.
- Check that generated or edited files can be read as UTF-8 text.
- Check any task-specific output shape required by `docs/plan/CONTRACT.md`.

## Expected Output

The agent response must include:

- `summary`
- `changed_files`
- `verification_result`
- `risks`
- `next_steps`

## Risks

- List known risks or assumptions before execution.

## Notes

Add any runner-specific instructions only when they are required for this task.
