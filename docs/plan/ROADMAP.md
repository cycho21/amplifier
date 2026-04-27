# Mini Amplifier Roadmap Index

This file is the roadmap index. Detailed roadmap items are split by status and
future work area.

## Current Status

The original dry-run based Mini Amplifier roadmap is complete.

Completed work includes:

- MVP execution path.
- Runner portability proof.
- Role expansion.
- Sequential and parallel workflow dry-runs.
- Structural result comparison.
- Retry, cost, and memory policy log shapes.

The project is not yet a real LLM execution framework. It currently provides a
stable dry-run kernel and runner-neutral contracts.

## Roadmap Files

Read in this order:

1. [Completed Roadmap](roadmaps/COMPLETED.md): completed dry-run kernel and
   explicit non-completed items.
2. [Next: Real Runners](roadmaps/NEXT_REAL_RUNNERS.md): real LLM/tool runner
   invocation.
3. [Next: Orchestration](roadmaps/NEXT_ORCHESTRATION.md): real dependency graph,
   concurrency, failure propagation, and voting.
4. [Next: Operations](roadmaps/NEXT_OPERATIONS.md): real retry, cost, and memory
   behavior.

## High-Level Progress

- [x] Dry-run kernel roadmap.
- [x] Real runner roadmap (Completed 2026-04-27).
- [ ] Orchestration roadmap.
- [ ] Operations roadmap.

## Rule For Future Roadmaps

When a roadmap grows beyond one concern, create a new focused roadmap file under
`docs/plan/roadmaps/` and link it from this index.
