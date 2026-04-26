# Agent Operating Bootstrap

This file defines how agents should work in this repository. It is operational
governance, not a Mini Amplifier product artifact.

## Encoding Rules

- In this repo, default to `Get-Content -Encoding utf8` when reading text files
  in PowerShell.
- Use `Set-Content -Encoding utf8` when writing text files in PowerShell.
- All files must be UTF-8 encoded.

## Repository Boundary

Mini Amplifier product files live in:

- `agents/`: product agent role definitions.
- `execution/`: product execution specs.
- `runner/`: product runner adapters.
- `workflows/`: product workflow specs.
- `tasks/`: product task definitions.
- `docs/plan/`: product planning and contract documents.
- `logs/`: generated product run logs.

Agent governance files live in:

- `agent-governance/`: instructions, team personas, and context used to operate
  agents while working on the repository.

Do not treat `agent-governance/` as product runtime input unless a task
explicitly asks for governance behavior.

## Governance Index

- Engineering boardroom and team persona files:
  - `agent-governance/teams/architect/AGENTS.md`
  - `agent-governance/teams/developer/AGENTS.md`
  - `agent-governance/teams/reviewer/AGENTS.md`
- Additional project context for agents:
  - `agent-governance/project-context/project-overview.md`
  - `agent-governance/project-context/architecture-map.md`
  - `agent-governance/project-context/backend-guide.md`
  - `agent-governance/project-context/frontend-guide.md`
  - `agent-governance/project-context/data-model.md`
  - `agent-governance/project-context/key-workflows.md`
  - `agent-governance/project-context/operations-notes.md`

## Operating Rules

1. Keep analysis, scope identification, design, implementation, and validation
   as distinct phases.
2. Start from the smallest useful scope.
3. Do not traverse unrelated files or expand scope without user confirmation.
4. Before code changes, list affected files and ask for confirmation when the
   scope exceeds one file.
5. Prefer test-first implementation for behavior changes.
6. Run the narrowest useful local verification after changes.
7. Do not revert unrelated user changes.

## Sub-Agent Approval

Before spawning or delegating tasks to any sub-agent:

1. Present which sub-agents will be tasked and why.
2. State the model tier to be used.
3. Wait for explicit user approval.

## Communication

Use the identity icon appropriate to the role:

- Architect: `🏛️`
- Developer: `💻`
- Tester: `🧪`
- Reviewer: `🔍`
- Manager: `👔`

Be concise, scoped, and explicit.
