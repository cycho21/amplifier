# Task: Roadmap Item Completion Toggle

## Task ID

`002`

## Title

Add a checkbox toggle to each roadmap item that writes `[ ]`/`[x]` back to the `.md` file on disk.

## Goal

Implement the Roadmap Item Completion Toggle feature end-to-end:

1. A `PATCH /api/roadmaps/toggle` endpoint in `frontend/server.mjs` that receives a roadmap file name and item index, reads the file, flips the `[ ]`/`[x]` on the correct checklist line, and overwrites the file.
2. A checkbox rendered next to each roadmap item in `frontend/app.js` that calls the endpoint on change, updates in-memory state, and re-renders the roadmap card without a full page reload.
3. On failure the checkbox reverts and an inline error appears.

## Background

The Operator UI loads roadmap `.md` files from `docs/plan/roadmaps/` and renders their checklist items. The parser (`frontend/roadmapParser.mjs`) already extracts items with `done: boolean` and `text: string`. Items are rendered in `frontend/app.js` via `renderRoadmaps` / `renderRoadmapCard`.

The file format uses GitHub-flavored checklist syntax:
```
- [ ] Not done item
- [x] Done item
```

Reference files:
- `frontend/server.mjs` — add the PATCH endpoint here
- `frontend/app.js` — add checkbox rendering and fetch call here
- `frontend/roadmapParser.mjs` — already parses items; read to understand the shape
- `frontend/styles.css` — add any needed checkbox styles here

## Scope

Allowed changes:
- `frontend/server.mjs`
- `frontend/app.js`
- `frontend/styles.css`

Out of scope:
- `frontend/roadmapParser.mjs` — do not modify the parser
- Any file outside `frontend/`
- Bulk toggle, undo, conflict resolution
- Editing any roadmap field other than item completion

## Requirements

1. **Endpoint**: `PATCH /api/roadmaps/toggle` accepts JSON body `{ fileName, itemIndex, completed }`.
   - `fileName` is the browser-path value already present on each roadmap object (e.g. `docs/plan/roadmaps/FOO.md`).
   - `itemIndex` is the zero-based index into the parsed checklist items array.
   - Read the file, find the Nth checklist line (matching `/^\s*[-*]\s+\[[ xX]\]/`), replace `[ ]` with `[x]` or vice versa, overwrite the file.
   - Return `{ ok: true }` on success.

2. **Checkbox**: In `renderRoadmapCard` (or equivalent), each item row gets an `<input type="checkbox">` that reflects `item.done`.

3. **Optimistic update**: On checkbox change, immediately update the in-memory roadmap item and re-render, then send the PATCH. On error, revert and show a message.

4. **Filter consistency**: After a toggle, re-apply the current roadmap filter so a newly-completed roadmap moves to the correct tab.

## Constraints

- Do not use a full `loadLocalData()` reload after a toggle — update only the affected roadmap in memory.
- The file write must be a single atomic `writeFile` call (read → modify in memory → write).
- Do not add new npm dependencies.

## Verification

- Read `frontend/server.mjs` and confirm the endpoint exists and handles the toggle logic.
- Read `frontend/app.js` and confirm checkboxes are rendered and wired.
- Confirm the endpoint path is `PATCH /api/roadmaps/toggle`.

## Expected Output

The agent response must include:

- `summary`
- `changed_files`
- `verification_result`
- `risks`
- `next_steps`

## Risks

- The file line index for the Nth checklist item must be found by counting only checklist lines, not all lines.
- Concurrent writes are out of scope; a single overwrite is acceptable.
