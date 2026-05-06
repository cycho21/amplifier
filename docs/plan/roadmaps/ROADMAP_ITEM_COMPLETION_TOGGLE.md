# Roadmap Item Completion Toggle

## Status

Not started.

## Goal

Allow operators to toggle roadmap items as complete or incomplete directly from the Operator UI, with the change written back to the roadmap `.md` file on disk immediately.

## Principles

- UI state and file state must stay in sync: a toggle in the browser writes the file.
- No separate save step: the toggle action is the write action.
- Read-parse-toggle-write must be atomic at the file level (single overwrite, no partial writes).
- The backend owns all file writes; the frontend only sends intent.

## Sequence

1. Add a `PATCH /api/roadmaps/:id/items/:index` endpoint to `server.mjs` that accepts `{ completed: boolean }` and rewrites the corresponding `[ ]` / `[x]` checkbox in the file.
2. Expose item index (line position or ordinal within the roadmap's checklist) alongside each rendered item in the frontend.
3. Wire the existing roadmap item render in `app.js` to show a checkbox that calls the new endpoint on change.
4. On success, update the in-memory roadmap state and re-render without a full reload.
5. On failure, revert the checkbox and show an inline error.

## Acceptance Criteria

- Clicking a checkbox in the Roadmap section sends a PATCH request and the corresponding `[ ]` / `[x]` line in the `.md` file is updated.
- Toggling back unchecks the file entry.
- The UI reflects the toggled state immediately without a full page refresh.
- If the write fails, the checkbox reverts and an error message appears inline.
- Roadmap filter tabs (Active / Completed) correctly re-evaluate after a toggle.

## Out Of Scope

- Bulk toggle (select all / clear all).
- Undo / history.
- Conflict resolution when multiple clients edit the same file simultaneously.
- Editing any other roadmap field (title, goal, etc.) from the UI.
