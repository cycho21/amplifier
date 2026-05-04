# Mini Amplifier Roadmap Index

This file is the roadmap index. Detailed roadmap items are split by status and
future work area.

## Current Status

The original dry-run based Mini Amplifier roadmap and the first real runner
roadmap are complete.

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

The project now has a stable dry-run kernel, runner-neutral contracts, a real
Codex runner path, and real parallel orchestration behavior. Operations
behavior remains future roadmap work.

## Roadmap Files

Read in this order:

1. [Completed Roadmap](roadmaps/COMPLETED.md): completed dry-run kernel and
   explicit non-completed items.
2. [Real Runners](roadmaps/NEXT_REAL_RUNNERS.md): completed real LLM/tool
   runner invocation roadmap.
3. [Orchestration](roadmaps/NEXT_ORCHESTRATION.md): completed real dependency
   graph, concurrency, failure propagation, and voting gate roadmap.
4. [Next: Operations](roadmaps/NEXT_OPERATIONS.md): real retry, cost, and memory
   behavior.

## High-Level Progress

- [x] Dry-run kernel roadmap.
- [x] Real runner roadmap.
- [x] Orchestration roadmap.
- [ ] Operations roadmap.

## Rule For Future Roadmaps

When a roadmap grows beyond one concern, create a new focused roadmap file under
`docs/plan/roadmaps/` and link it from this index.
