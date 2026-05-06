# Task: Smoke Test — Write Project Summary

## Task ID

`001`

## Title

Write a one-paragraph project summary to `docs/plan/SUMMARY.md`.

## Goal

Create `docs/plan/SUMMARY.md` containing a single paragraph (3–5 sentences)
that describes what Mini Amplifier is, what problem it solves, and its current
state. The file must not exist before this task runs; if it already exists,
overwrite it.

## Background

Mini Amplifier is an LLM-agnostic agent execution framework. It defines a
task → role → spec → runner → log pipeline where each step is runner-neutral.
The project is documented in `docs/plan/CONTRACT.md`.

## Scope

Allowed changes:

- `docs/plan/SUMMARY.md` (create or overwrite)

Out of scope:

- Any other file in the repository.

## Requirements

- The file must be UTF-8 encoded Markdown.
- The first line must be a level-1 heading: `# Mini Amplifier`.
- The body must be a single paragraph of 3–5 sentences.
- The paragraph must mention: agent execution, runner-neutral, and log output.

## Constraints

- Follow the execution contract in `docs/plan/CONTRACT.md`.
- Modify only `docs/plan/SUMMARY.md`.
- Keep the file short — one heading and one paragraph only.
- Report incomplete work explicitly.

## Verification

- Confirm `docs/plan/SUMMARY.md` exists.
- Read the file as UTF-8 and confirm the first line is `# Mini Amplifier`.
- Confirm the file contains a non-empty paragraph body.

## Expected Output

The agent response must include:

- `summary`
- `changed_files`
- `verification_result`
- `risks`
- `next_steps`

## Risks

- File may already exist from a previous run; overwriting is allowed.

## Notes

This is a smoke test task. Minimal output is correct output.
