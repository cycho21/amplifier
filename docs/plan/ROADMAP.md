# Mini Amplifier Roadmap Index

This file is the roadmap index. Detailed roadmap items are split by status and
future work area.

## Current Status

The dry-run based Mini Amplifier roadmap, real runner roadmap, orchestration
roadmap, and operations roadmap are complete.

Completed work includes:

- MVP execution path.
- Runner portability proof.
- Role expansion.
- Sequential and parallel workflow dry-runs.
- Structural result comparison.
- Retry, cost, and memory policy log shapes.
- Real Codex runner invocation behind the runner adapter boundary.
- Structured real Codex output capture, malformed-output failure handling, and
  dry-run/real-run log compatibility coverage.
- Real parallel orchestration, voting gate readiness, retry behavior, cost
  metadata, cost totals, persistent memory, and memory safety rules.

The project now has a stable runner and workflow core. The next roadmap is a
read-only local operator UI for inspecting logs, operational state, and roadmap
status.

## Roadmap Files

Read in this order:

1. [Completed Roadmap](roadmaps/COMPLETED.md): completed dry-run kernel and
   explicit non-completed items.
2. [Real Runners](roadmaps/NEXT_REAL_RUNNERS.md): completed real LLM/tool
   runner invocation roadmap.
3. [Orchestration](roadmaps/NEXT_ORCHESTRATION.md): completed real dependency
   graph, concurrency, failure propagation, and voting gate roadmap.
4. [Operations](roadmaps/NEXT_OPERATIONS.md): completed real retry, cost, and
   memory behavior roadmap.
5. [Next: Operator UI](roadmaps/NEXT_OPERATOR_UI.md): read-only local UI for
   workflow log inspection and operational status.

## High-Level Progress

- [x] Dry-run kernel roadmap.
- [x] Real runner roadmap.
- [x] Orchestration roadmap.
- [x] Operations roadmap.
- [ ] Operator UI roadmap.

## Rule For Future Roadmaps

When a roadmap grows beyond one concern, create a new focused roadmap file under
`docs/plan/roadmaps/` and link it from this index.
