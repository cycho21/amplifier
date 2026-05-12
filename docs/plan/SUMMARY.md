# Mini Amplifier Summary

## What It Is

Mini Amplifier is an LLM-agnostic agent execution framework designed to make agent work reproducible across different runners (Codex, Claude, API clients, or local LLMs).

## Core Concept

The LLM is only the execution engine. The durable behavior lives in versioned documents rather than runner-specific code. This allows the same task to be executed through different runners while preserving the same input contract, behavior, and output shape.

## Architecture

The framework uses explicit layers with single responsibilities:

```
Task Definition (tasks/*.md)
    -> Agent Role (agents/*.md)
    -> Execution Spec (execution/*.yaml)
    -> Runner (codex / claude / api / local)
    -> Structured Log (logs/*.json)
```

Each layer is independent and replaceable without breaking the contract.

## Key Design Goals

- **LLM portability**: switch between different models and providers
- **Runner separation**: keep runner logic outside task and agent definitions
- **Prompt standardization**: generate prompts from the same document structure
- **Output standardization**: require consistent structured results
- **Reproducibility**: preserve enough metadata to replay or compare runs
- **Minimal kernel**: keep the core framework small and policy-neutral

## Current State: MVP

The first milestone proves one complete execution path:

```
task file -> execution spec -> prompt -> runner -> structured output -> log file
```

The MVP focuses on single-task execution with one implementer role, one runner, and structured logging. Future extensions will add workflow orchestration, parallel execution, retry policies, cost tracking, and memory persistence.

## Document Index

- **PLAN.md**: vision, principles, and design goals
- **CONTRACT.md**: runner-neutral contracts for execution, workflow, logging, and extensions
- **MVP.md**: first milestone deliverables and validation criteria
- **ROADMAP.md**: execution order from MVP to later features
- **DECISIONS.md**: accepted design decisions and their rationale

## Non-Goals (for MVP)

Out of scope until the single-task path is stable:

- multi-agent parallel execution
- voting or consensus between models
- long-term memory
- task dependency graphs
- automatic retry policy
- cost tracking
- web UI
- database persistence
