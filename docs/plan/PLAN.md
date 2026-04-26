# Mini Amplifier Plan

## Project Vision

Mini Amplifier is an LLM-agnostic agent execution framework.

The goal is to make agent work reproducible across different runners such as
Codex, Claude, API clients, or local LLMs. The LLM is only the execution engine.
The durable behavior of the system must live in versioned documents:

- task definitions
- agent role definitions
- execution specifications
- structured logs

If the same task is executed through two different runners, the input contract,
expected behavior, and output shape should remain the same.

## Core Principle

The framework is organized as a small set of explicit layers.

```text
Task Definition (tasks/*.md)
        -> Agent Role (agents/*.md)
        -> Execution Spec (execution/*.yaml)
        -> Runner (codex / claude / api / local)
        -> Structured Log (logs/*.json)
```

Each layer has one responsibility:

- **Task Definition** describes what must be done.
- **Agent Role** describes the persona, constraints, and operating rules.
- **Execution Spec** describes which inputs, instructions, and output fields are required.
- **Runner** adapts the execution spec to a concrete tool.
- **Structured Log** records what happened in a runner-neutral format.

## Design Goals

- **LLM portability**: switch between Codex, Claude, GPT, and local models.
- **Runner separation**: keep runner logic outside task and agent definitions.
- **Prompt standardization**: generate prompts from the same document structure.
- **Output standardization**: require consistent structured results.
- **Reproducibility**: preserve enough input and output metadata to replay or compare runs.
- **Minimal kernel**: keep the core framework small and policy-neutral.

## Document Index

Read these documents in order:

1. [PLAN.md](PLAN.md): vision, principles, and document index.
2. [CONTRACT.md](CONTRACT.md): shared input, output, prompt, and log contracts.
3. [MVP.md](MVP.md): first milestone, deliverables, and validation criteria.
4. [ROADMAP.md](ROADMAP.md): execution order from MVP to later extensions.
5. [DECISIONS.md](DECISIONS.md): accepted design decisions and their reasons.

## Non-Goals

The MVP will not attempt to solve every agent orchestration problem.

Out of scope for the first version:

- multi-agent parallel execution
- voting or consensus between models
- long-term memory
- task dependency graphs
- automatic retry policy
- cost tracking
- web UI
- database persistence

These can be added later only after the single-task execution path is stable.

## Target Repository Shape

```text
.
├── PLAN.md
├── AGENTS.md
├── EXECUTION.md
├── agents/
│   ├── architect.md
│   ├── implementer.md
│   ├── reviewer.md
│   └── tester.md
├── tasks/
│   └── 000_template.md
├── execution/
│   ├── architect.yaml
│   ├── implementer.yaml
│   ├── reviewer.yaml
│   └── tester.yaml
├── logs/
└── runner/
    ├── codex.sh
    ├── claude.sh
    └── api.go
```

For the MVP, only one role, one task template, one execution spec, one runner,
and one log format are required.
