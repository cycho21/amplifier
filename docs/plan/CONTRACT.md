# Mini Amplifier Contract

## Purpose

This document is the contract index for Mini Amplifier.

Runner-neutral behavior is defined in focused contract documents so the core
contract stays small as the framework adds workflow, parallel execution, retry,
cost tracking, and memory features.

## Core Principle

Each runner must preserve the same input contract, output shape, and log shape
for comparable work.

Runner-specific metadata is allowed, but runners must not remove or rename
required fields defined by the relevant contract document.

## Contract Index

Read these contracts by concern:

1. [Execution Contract](contracts/execution.md): single-agent execution inputs,
   outputs, execution specs, runner responsibilities, and prompt structure.
2. [Workflow Contract](contracts/workflow.md): multi-agent workflow specs,
   dependency ordering, and workflow-level outputs.
3. [Parallel Contract](contracts/parallel.md): parallel workflow grouping,
   dependency boundaries, and dry-run reporting requirements.
4. [Comparison Contract](contracts/comparison.md): workflow result comparison
   fields and missing-field reporting.
5. [Retry Contract](contracts/retry.md): retry policy fields, attempt logging,
   and dry-run retry behavior.
6. [Cost Contract](contracts/cost.md): cost tracking policy fields and dry-run
   cost reporting requirements.
7. [Memory Contract](contracts/memory.md): persistent memory policy fields and
   dry-run memory reporting requirements.
8. [Logging Contract](contracts/logging.md): structured log fields and
   comparability requirements.

## Extension Policy

Add a new focused contract file when a feature introduces its own durable rules.

Examples:

Add new focused contract files for future concerns before changing runner log
shape.

Do not expand this index with full feature schemas. Keep detailed rules in the
focused contract files.
