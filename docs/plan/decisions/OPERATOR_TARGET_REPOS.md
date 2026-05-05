# Operator Target Repositories

## Status

Accepted.

## Context

Mini Amplifier is evolving from a single-repository execution kernel into a
local operator console. The operator should be able to manage work across
multiple target repositories while keeping execution behavior consistent.

The Operator UI is a tool that lives in this repository. Target repositories
own their own planning documents, generated tasks, and execution logs. Shared
agent roles, execution specs, workflows, runner adapters, and initialization
templates remain in Mini Amplifier.

## Decision

Mini Amplifier is the operator/orchestrator. Each target repository is a working
repository that stores plans, tasks, and results.

Mini Amplifier owns:

- `operator-ui/`
- `runner/`
- `agents/`
- `execution/`
- `workflows/`
- `templates/`

Each target repository owns:

- `docs/plan/roadmaps/`
- `tasks/`
- `logs/`

Target repository registry and run index are local operator state:

- `.operator/targets.json` stores registered target repositories and active
  target selection.
- `.operator/targets.example.json` documents the registry shape and is tracked.
- `.operator/runs.json` stores the central background execution index.
- Actual execution artifacts remain in each target repository.

## Target Initialization

Target repository initialization creates only the minimum target-owned
structure:

- `docs/plan/roadmaps/`
- `docs/plan/roadmaps/NEXT.md`
- `tasks/`
- `tasks/000_template.md`
- `logs/`
- `logs/.gitkeep`

Initialization templates live under:

```text
templates/target-init/
```

Initialization must not overwrite existing target repository files. The
Operator UI must provide an init plan before writing files.

## Target Registration

One Operator UI server can manage multiple target repositories.

Target registration uses a folder picker from the local server. After folder
selection, the UI proposes a target name and id from the folder name, but the
operator can edit the name before registration.

Registering a target does not initialize it automatically. If required
structure or files are missing, the target is shown as `init required`.

A target is `ready` only when all required folders and minimum files exist.

## Execution Ownership

Shared execution assets are read from Mini Amplifier:

- agent personas from `agents/`
- execution specs from `execution/`
- workflow specs from `workflows/`
- runner adapters from `runner/`

Target-specific execution inputs and results are read from or written to the
target repository:

- roadmap files from `docs/plan/roadmaps/`
- task files from `tasks/`
- logs from `logs/`

Runner commands must carry enough context to resolve both sides. The intended
shape is:

```powershell
.\runner\workflow.ps1 -AppRoot "I:\amplifier" -TargetRepoRoot "D:\repo" -TaskId "roadmap-NEXT-1"
```

Exact runner parameters can evolve, but the ownership boundary must remain:
Mini Amplifier provides shared execution assets; the target repository provides
plans, tasks, and results.

## Run Index And Concurrency

`.operator/runs.json` stores a central execution index with fields such as:

- run id
- target id
- task id
- mode
- status
- command
- started and finished timestamps
- exit code
- log path
- write scope

The first background execution policy allows one running task per target
repository. The model must record write scope so future versions can permit
multiple concurrent runs in the same target when write scopes do not overlap.

Write scope is a list of repository-relative path prefixes:

```json
{
  "policy": "repo-relative-prefix",
  "paths": ["src/auth/", "tests/auth/"]
}
```

Rules:

- absolute paths are not allowed
- `..` is not allowed
- empty paths are not allowed
- path separators normalize to `/`
- `.` means the entire target repository

Real execution must require an explicit write scope.

## Git Policy

Target repository `logs/` git policy belongs to the target repository.
Initialization does not modify `.gitignore`.

Mini Amplifier ignores local operator state except tracked examples:

```gitignore
.operator/*
!.operator/targets.example.json
```

## Consequences

- Operator UI code and target execution artifacts no longer share ownership.
- A single Operator UI server can supervise multiple repositories.
- Target repositories remain portable because their plans, tasks, and logs stay
  local to the repository.
- Real agent execution can be added later with clearer write ownership and
  concurrency boundaries.
