# Mini Amplifier

Mini Amplifier is a small multi-agent execution kernel for defining agent roles,
execution specs, workflow specs, runner contracts, and structured logs.

The project currently focuses on making agent execution comparable across
runners. It keeps role behavior, execution metadata, workflow orchestration, and
logs explicit so real runner integration can be added without changing the
required output shape.

## Current Status

Implemented:

- Product agent role definitions under `agents/`.
- Execution specs under `execution/`.
- Workflow specs under `workflows/`.
- Focused contracts under `docs/plan/contracts/`.
- Deterministic dry-run workflow execution.
- Workflow dependency graph validation, including cycle detection.
- Codex-only runner selection in execution specs.
- Codex real invocation boundary behind explicit `-AllowReal`.
- Structured JSON capture from real Codex raw output when the output matches the
  required fields.
- PowerShell tests for workflow, graph validation, runner contracts, Codex
  invocation boundaries, retry shape, cost shape, and memory shape.

Not implemented yet:

- Real parallel workflow execution.
- Strict malformed real-output failure fixtures.
- Real retry behavior after runtime failure.
- Real provider cost calculation.
- Real persistent memory read/write.
- Claude runner integration beyond the existing dry-run adapter.

## Repository Layout

```text
agents/                 Product agent role definitions.
execution/              Per-role execution specs.
runner/                 Runner adapters.
workflows/              Multi-agent workflow specs.
tasks/                  Task definitions.
docs/plan/              Product plans, contracts, and roadmaps.
logs/                   Generated dry-run logs and prompts.
test-fixtures/          Local fixtures used by tests.
test_*.ps1              PowerShell test scripts.
agent-governance/       Agent operating context, not product runtime input.
```

## Requirements

- Windows PowerShell.
- Git.
- Codex CLI only if you want to exercise real Codex invocation.

Dry-run tests do not require network access, model access, or external LLM
credentials.

## Execution Specs

Execution specs are YAML files under `execution/`. Each spec defines:

- `role`
- `runner`
- `input`
- `instructions`
- `output`

The current runner selection is Codex-only:

```yaml
runner:
  provider: codex
  tool: codex-cli
  mode: dry-run
```

`mode: dry-run` is deterministic and safe for local tests. Real invocation must
be enabled explicitly from the command line.

## Running A Single Codex Dry Run

```powershell
.\runner\codex.ps1 `
  -TaskId "000_template" `
  -Role "implementer" `
  -ExecutionSpec "execution/implementer.yaml" `
  -AgentRole "agents/implementer.md" `
  -PromptOut "logs/prompts/implementer-000_template.prompt.txt" `
  -LogOut "logs/20260426-implementer-000_template.json"
```

This writes:

- a generated prompt to `logs/prompts/`
- a structured dry-run log to `logs/`

It does not invoke an external LLM.

## Running Real Codex Invocation

Real Codex invocation is guarded by both `-Mode real` and `-AllowReal`:

```powershell
.\runner\codex.ps1 `
  -TaskId "000_template" `
  -Role "implementer" `
  -ExecutionSpec "execution/implementer.yaml" `
  -AgentRole "agents/implementer.md" `
  -Mode "real" `
  -AllowReal `
  -RawOutputOut "logs/raw/codex-implementer-000_template-output.txt" `
  -LogOut "logs/20260426-implementer-real-000_template.json"
```

The adapter invokes `codex exec` and asks for a JSON object with these fields:

```text
summary
changed_files
verification_result
risks
next_steps
```

If the raw Codex final response is valid JSON with those fields, the adapter
copies the values into the structured runner log.

## Running Workflows

Sequential implementation review dry run:

```powershell
.\runner\workflow.ps1 `
  -TaskId "000_template" `
  -WorkflowSpec "workflows/implementation-review.yaml" `
  -LogOut "logs/test-workflow-implementation-review-000_template.json"
```

Parallel review dry-run grouping:

```powershell
.\runner\workflow.ps1 `
  -TaskId "000_template" `
  -WorkflowSpec "workflows/parallel-review.yaml" `
  -LogOut "logs/test-workflow-parallel-review-000_template.json"
```

Parallel mode currently records deterministic `parallel_groups`. It does not
launch real concurrent processes unless real workflow execution is explicitly
enabled.

Real parallel workflow execution is guarded by both `-Mode real` and
`-AllowReal`:

```powershell
.\runner\workflow.ps1 `
  -TaskId "000_template" `
  -WorkflowSpec "workflows/parallel-review.yaml" `
  -Mode "real" `
  -AllowReal `
  -StepRunnerCommand ".\runner\codex.ps1" `
  -LogOut "logs/test-workflow-real-parallel-review-000_template.json"
```

## Running Tests

Run individual tests with Windows PowerShell:

```powershell
.\tests\test_workflow_runner.ps1
.\tests\test_parallel_workflow_runner.ps1
.\tests\test_real_parallel_workflow_runner.ps1
.\tests\test_real_parallel_workflow_failure.ps1
.\tests\test_workflow_graph_validation.ps1
.\tests\test_runner_invocation_contract.ps1
.\tests\test_execution_runner_selection.ps1
.\tests\test_execution_input_paths.ps1
.\tests\test_codex_runner_invocation_boundary.ps1
.\tests\test_codex_runner_structured_output.ps1
.\tests\test_codex_runner_malformed_output.ps1
.\tests\test_codex_runner_log_compatibility.ps1
.\tests\test_workflow_comparison.ps1
.\tests\test_workflow_voting_contract.ps1
.\tests\test_workflow_voting_gate.ps1
.\tests\test_workflow_retry_policy.ps1
.\tests\test_real_workflow_retry.ps1
.\tests\test_workflow_cost_tracking.ps1
.\tests\test_workflow_memory_policy.ps1
.\tests\test_real_workflow_memory.ps1
```

The Codex boundary tests use local fake Codex fixtures and do not call the real
Codex CLI.

## Contracts And Roadmaps

Start with:

- `docs/plan/CONTRACT.md`
- `docs/plan/contracts/execution.md`
- `docs/plan/contracts/runner-invocation.md`
- `docs/plan/contracts/workflow.md`
- `docs/plan/roadmaps/NEXT_REAL_RUNNERS.md`
- `docs/plan/roadmaps/NEXT_ORCHESTRATION.md`
- `docs/plan/roadmaps/NEXT_OPERATIONS.md`

Progress logs:

- `docs/plan/roadmaps/REAL_RUNNERS_PROGRESS.md`
- `docs/plan/roadmaps/ORCHESTRATION_PROGRESS.md`

## Development Rules

- Keep product runtime inputs under `agents/`, `execution/`, `runner/`,
  `workflows/`, `tasks/`, and `docs/plan/`.
- Do not use `agent-governance/` as product runtime input.
- Preserve required output fields across all runners.
- Keep dry-run behavior deterministic.
- Add tests before changing behavior.
- Record progress in the relevant roadmap progress document.
