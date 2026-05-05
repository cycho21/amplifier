# Mini Amplifier Decisions

## Decision 1: LLMs Are Runners

**Decision:** Treat Codex, Claude, API clients, and local models as replaceable
runners.

**Reason:** The project should preserve agent behavior in documents rather than
in a specific tool's prompt or CLI behavior.

## Decision 2: Execution Specs Are YAML

**Decision:** Define agent execution rules in `execution/*.yaml`.

**Reason:** YAML is readable, easy to diff, and simple for runner adapters to
load before generating prompts.

## Decision 3: PLAN.md Is a Hub

**Decision:** Keep `PLAN.md` focused on vision, principles, and document links.

**Reason:** Execution details are easier to maintain when contracts, MVP scope,
roadmap, and design decisions live in focused documents.

## Decision 4: MVP Proves One Complete Path

**Decision:** The first milestone proves a single path from task file to log
file with one role, one execution spec, and one runner.

**Reason:** Portability and orchestration features should be built only after
the smallest runner-neutral execution loop works.

## Decision 5: Logs Are Structured JSON

**Decision:** Each run should produce a JSON log with required input and output
fields.

**Reason:** Structured logs make runner behavior comparable and provide the
first debugging surface when outputs differ.

## Decision 6: Operator Manages Target Repositories

**Decision:** Treat Mini Amplifier as the operator/orchestrator and target
repositories as the owners of their plans, tasks, and results.

**Reason:** Shared execution assets should be maintained once in Mini
Amplifier, while repository-specific roadmaps, generated tasks, and logs stay
with the repository they describe.

Details: `docs/plan/decisions/OPERATOR_TARGET_REPOS.md`.
