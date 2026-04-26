# Completed Roadmap

This document records completed Mini Amplifier work.

## Completed Scope

The completed scope is a dry-run based Mini Amplifier kernel. It defines stable
contracts, specs, runners, workflows, and logs without invoking external LLMs.

## Phase 1: MVP Execution Path

- [x] Define `tasks/000_template.md`.
- [x] Define `agents/implementer.md`.
- [x] Define `execution/implementer.yaml`.
- [x] Implement the first runner adapter.
- [x] Generate a prompt from the task, role, and execution spec.
- [x] Execute the prompt through the dry-run runner.
- [x] Save the result to `logs/`.
- [x] Validate that the log contains all required fields from `docs/plan/CONTRACT.md`.

## Phase 2: Portability Proof

- [x] Add a second dry-run runner.
- [x] Execute the same task contract with both dry-run runners.
- [x] Compare output structures.
- [x] Document runner-specific metadata differences through separate `runner` and `run_id` log fields.

## Phase 3: Role Expansion

- [x] Add reviewer role.
- [x] Add tester role.
- [x] Add execution YAML for each new role.
- [x] Verify each role can produce the required output fields.
- [x] Add architect, system designer, tech stack specialist, backend engineer, and frontend engineer roles.
- [x] Add execution YAML for specialist roles.
- [x] Verify specialist roles can produce the required output fields.

## Phase 4: Workflow Expansion

- [x] Add multi-agent sequential workflows.
- [x] Add parallel execution only after sequential workflows are stable.
- [x] Add result comparison or voting.

## Phase 5: Operational Log Shape

- [x] Add retry policy.
- [x] Add cost tracking.
- [x] Add persistent memory only after task execution is stable.

## Completed Deliverables

- Product agent role files in `agents/`.
- Execution specs in `execution/`.
- Workflow specs in `workflows/`.
- Contract index and focused contracts in `docs/plan/contracts/`.
- Dry-run workflow runner in `runner/workflow.ps1`.
- Focused PowerShell tests for workflow, parallel, comparison, retry, cost, and memory behavior.
- Agent governance files separated into `agent-governance/`.

## Explicitly Not Completed

- Real external LLM invocation.
- Real concurrent process execution.
- Real retry after runtime failure.
- Real provider cost calculation.
- Real persistent memory read/write.
- Quality voting or winner selection.
- Dependency graph scheduling beyond current dry-run grouping.
