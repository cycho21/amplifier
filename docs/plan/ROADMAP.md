# Mini Amplifier Roadmap Index

This file is the roadmap index. Detailed roadmap items are split by status and
future work area.

## Current Status

The dry-run based Mini Amplifier roadmap, real runner roadmap, orchestration
roadmap, operations roadmap, and read-only operator UI roadmap are complete.

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
- Read-only local Operator UI for inspecting workflow logs, operational state,
  roadmap progress, and captured verification evidence.

The project now has a stable runner and workflow core plus a local operator UI
with guarded roadmap authoring, dry-run execution controls, and explicitly
guarded real execution controls.

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
5. [Operator UI](roadmaps/NEXT_OPERATOR_UI.md): completed read-only local UI for
   workflow log inspection, operational status, roadmap status, and captured
   verification evidence.
6. [Operator Control](roadmaps/NEXT_OPERATOR_CONTROL.md): completed guarded local
   authoring and execution controls for roadmaps and dry-run workflows.
7. [Real Agent Execution](roadmaps/NEXT_REAL_AGENT_EXECUTION.md): completed
   guarded real execution controls for explicit, auditable Operator UI runs.

## High-Level Progress

- [x] Dry-run kernel roadmap.
- [x] Real runner roadmap.
- [x] Orchestration roadmap.
- [x] Operations roadmap.
- [x] Operator UI roadmap.
- [x] Operator Control roadmap.
- [x] Real Agent Execution roadmap.

## Rule For Future Roadmaps

When a roadmap grows beyond one concern, create a new focused roadmap file under
`docs/plan/roadmaps/` and link it from this index.
