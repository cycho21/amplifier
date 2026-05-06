# Real Runner Invocation Contract Specification

## 1. Objective

Transform the Mini Amplifier dry-run kernel into a real LLM execution framework by implementing actual runner invocation while preserving the existing log structure.

**Target Users:**
- Multi-agent orchestration developers
- AI-guided software development workflow authors
- Amplifier framework maintainers

**Success Criteria:**
- Real LLM invocation for OpenAI API (Codex) and Claude CLI providers
- Existing dry-run log shape preserved (summary, changed_files, verification_result, risks, next_steps)
- Dry-run mode remains available for testing
- Provider selection is explicit and configurable
- Runner-specific metadata is additive only

**Out of Scope (for this contract):**
- Other LLM providers (Gemini, etc.)
- Real parallel execution
- Cost calculation with actual API usage
- Persistent memory read/write
- Error recovery and retry logic (covered in OPERATIONS.md)

---

## 2. Commands

### Existing Commands (Modified)

```powershell
# Execute workflow with real runner
.\runner\workflow.ps1 `
    -TaskId "001_implement_auth" `
    -WorkflowSpec "workflows/implementation-review.yaml" `
    -LogOut "logs/workflow-001.json"

# Execute single step with real runner
.\runner\codex.ps1 `
    -TaskId "001_implement_auth" `
    -Role "implementer" `
    -ExecutionSpec "execution/implementer.yaml" `
    -LogOut "logs/implementer-001.json"

# Execute single step with Claude CLI runner
.\runner\claude.ps1 `
    -TaskId "001_implement_auth" `
    -Role "implementer" `
    -ExecutionSpec "execution/implementer.yaml" `
    -LogOut "logs/implementer-001.json"
```

### Dry-Run Mode

```powershell
# Dry-run mode (no real LLM invocation)
# Triggered when execution spec has provider: dry-run
.\runner\workflow.ps1 `
    -TaskId "000_template" `
    -WorkflowSpec "workflows/implementation-review.yaml" `
    -LogOut "logs/dry-run.json"
```

---

## 3. Project Structure

### New/Modified Files

```
amplifier/
├── execution/
│   ├── implementer.yaml          # [MODIFIED] Add provider field
│   ├── tester.yaml               # [MODIFIED] Add provider field
│   ├── reviewer.yaml             # [MODIFIED] Add provider field
│   └── architect.yaml            # [MODIFIED] Add provider field
├── runner/
│   ├── workflow.ps1              # [MODIFIED] Detect provider, invoke real runner
│   ├── codex.ps1                 # [MODIFIED] Real Codex invocation
│   ├── claude.ps1                # [MODIFIED] Real Claude CLI invocation
│   └── lib/
│       ├── runner-interface.ps1  # [NEW] Abstract runner interface
│       └── output-parser.ps1     # [NEW] Parse LLM output to contract
├── docs/
│   └── plan/
│       └── contracts/
│           └── runner-invocation.md  # [NEW] Detailed runner contract
└── SPEC.md                       # [NEW] This file
```

### Execution Spec Schema (Modified)

```yaml
# execution/implementer.yaml
role: implementer

# [NEW FIELD]
provider: codex  # Options: dry-run | codex | claude

input:
  - docs/plan/PLAN.md
  - docs/plan/CONTRACT.md
  - agents/implementer.md
  - tasks/{task_id}.md

instructions:
  - Follow task requirements exactly.
  - Modify only files allowed by the task.
  - Keep changes minimal.
  - Run the narrowest relevant verification command when possible.
  - Report risks and incomplete work explicitly.

output:
  - summary
  - changed_files
  - verification_result
  - risks
  - next_steps

# [NEW SECTION - Provider-specific settings]
provider_config:
  codex:
    model: "sonnet-4.5"          # Default model
    timeout: 600                  # Seconds
    max_tokens: 8000
  claude:
    model: "claude-sonnet-4-5"
    timeout: 600
    max_tokens: 8000
```

---

## 4. Runner Interface Contract

### Input Contract

**All runners MUST accept:**
```powershell
param(
    [string]$TaskId,           # Task identifier (e.g., "001_implement_auth")
    [string]$Role,             # Agent role (e.g., "implementer")
    [string]$ExecutionSpec,    # Path to execution YAML
    [string]$AgentRole,        # Path to agent role MD
    [string]$LogOut            # Output log path
)
```

### Output Contract

**All runners MUST produce:**
```json
{
  "run_id": "20260427-implementer-001",
  "runner": "codex" | "claude" | "dry-run",
  "role": "implementer",
  "task_id": "001_implement_auth",
  "provider": "codex" | "claude" | "dry-run",
  "inputs": [
    "docs/plan/PLAN.md",
    "agents/implementer.md",
    "tasks/001_implement_auth.md",
    "execution/implementer.yaml"
  ],
  "output": {
    "summary": "string",
    "changed_files": ["array", "of", "paths"],
    "verification_result": "string",
    "risks": ["array", "of", "risks"],
    "next_steps": ["array", "of", "next", "steps"]
  },
  "provider_metadata": {
    // [OPTIONAL] Provider-specific fields (model, tokens, latency, etc.)
    // MUST NOT override or rename required output fields
  }
}
```

### Provider-Specific Metadata (Additive Only)

```json
// Codex provider metadata
"provider_metadata": {
  "model": "sonnet-4.5",
  "prompt_tokens": 1234,
  "completion_tokens": 567,
  "total_tokens": 1801,
  "latency_ms": 3400
}

// Claude CLI provider metadata
"provider_metadata": {
  "model": "claude-sonnet-4-5",
  "session_id": "abc123",
  "tool_calls": 5,
  "latency_ms": 4200
}
```

---

## 5. Code Style

### PowerShell Conventions

**Follow existing codebase patterns:**
- Strict error handling: `$ErrorActionPreference = "Stop"`
- UTF-8 file I/O via `Read-Utf8File` helper
- Ordered hashtables for JSON serialization: `[ordered]@{}`
- JSON depth 8 for ConvertTo-Json
- YAML parsing via regex (no external dependencies)
- PascalCase for functions, camelCase for variables
- Explicit parameter types and validation

### Runner Implementation Pattern

```powershell
# 1. Load execution spec
$execSpec = Read-ExecutionSpec $ExecutionSpec

# 2. Determine provider
$provider = $execSpec.provider
if ($null -eq $provider) {
    $provider = "dry-run"  # Default to dry-run if not specified
}

# 3. Invoke provider-specific runner
switch ($provider) {
    "codex" {
        Invoke-CodexRunner -Params $params
    }
    "claude" {
        Invoke-ClaudeRunner -Params $params
    }
    "dry-run" {
        Invoke-DryRunner -Params $params
    }
    default {
        throw "Unsupported provider: $provider"
    }
}

# 4. Parse output to contract
$output = Parse-RunnerOutput -RawOutput $rawOutput -Provider $provider

# 5. Write structured log
$log = New-StructuredLog -Output $output -Provider $provider
$log | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 -Path $LogOut
```

---

## 6. Authentication and Configuration

### Environment Variables

**Codex (requires OpenAI API key):**
```powershell
$env:OPENAI_API_KEY = "sk-..."
```

**Claude CLI (uses existing ~/.claude/config):**
- No additional environment variables required
- Assumes Claude CLI is installed and authenticated

### Validation

**Runners MUST validate before invocation:**
```powershell
function Test-CodexAuthentication {
    if ([string]::IsNullOrEmpty($env:OPENAI_API_KEY)) {
        throw "OPENAI_API_KEY environment variable is required for Codex provider"
    }
}

function Test-ClaudeCliInstalled {
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($null -eq $claudeCmd) {
        throw "Claude CLI is not installed or not in PATH"
    }
}
```

---

## 7. Testing Strategy

### Test Levels

**1. Unit Tests (Dry-Run Only)**
- Existing dry-run tests MUST continue to pass
- Test execution spec parsing
- Test prompt generation
- Test log structure validation

**2. Integration Tests (Real Invocation)**
- Test Codex runner with minimal prompt
- Test Claude CLI runner with minimal prompt
- Verify output contract compliance
- Verify provider metadata is additive only

**3. Contract Verification Tests**
- Compare dry-run log shape vs real-run log shape
- Verify required fields are present
- Verify no required fields are renamed/removed

### Test Fixtures

```
tests/
├── fixtures/
│   ├── execution-specs/
│   │   ├── codex-minimal.yaml
│   │   ├── claude-minimal.yaml
│   │   └── dry-run-minimal.yaml
│   ├── tasks/
│   │   └── 999_test_runner.md
│   └── expected-logs/
│       ├── codex-output-shape.json
│       └── claude-output-shape.json
└── integration/
    ├── test-codex-runner.ps1
    ├── test-claude-runner.ps1
    └── test-contract-compliance.ps1
```

---

## 8. Boundaries

### What This Spec DOES Include

✅ Real LLM invocation for Codex and Claude CLI
✅ Provider selection via execution spec
✅ Preserved dry-run mode
✅ Runner-neutral output contract
✅ Provider-specific metadata (additive)
✅ Authentication validation
✅ Log structure compatibility

### What This Spec DOES NOT Include

❌ Other LLM providers (OpenAI, Gemini, etc.) - future work
❌ Real parallel execution - covered in ORCHESTRATION.md
❌ Cost calculation with actual API usage - covered in OPERATIONS.md
❌ Persistent memory read/write - covered in OPERATIONS.md
❌ Retry logic and error recovery - covered in OPERATIONS.md
❌ Streaming output or progress indicators - nice-to-have
❌ Model parameter tuning UI - nice-to-have

### Always Do

- Validate provider configuration before invocation
- Preserve required output contract fields
- Write structured logs with consistent shape
- Fail fast on authentication errors
- Keep dry-run mode functional for tests

### Ask First About

- Adding new providers beyond Codex/Claude CLI
- Changing required output field names or structure
- Adding new required fields to execution spec
- Breaking changes to log format

### Never Do

- Remove or rename required output fields
- Hard-code role behavior in runner scripts
- Bypass authentication validation
- Merge provider-specific fields into output root
- Break existing dry-run tests

---

## 9. Acceptance Criteria

**This spec is complete when:**

1. ✅ Execution specs support `provider` field (codex | claude | dry-run)
2. ✅ `runner/codex.ps1` invokes real Codex API and returns contract-compliant output
3. ✅ `runner/claude.ps1` invokes real Claude CLI and returns contract-compliant output
4. ✅ `runner/workflow.ps1` detects provider and routes to correct runner
5. ✅ Real runner logs contain all required fields (summary, changed_files, verification_result, risks, next_steps)
6. ✅ Provider-specific metadata is additive only
7. ✅ Dry-run mode remains functional and deterministic
8. ✅ Integration tests verify contract compliance
9. ✅ Authentication validation prevents silent failures

**Out of scope for this spec:**
- Real parallel execution (ORCHESTRATION.md)
- Cost calculation (OPERATIONS.md)
- Memory persistence (OPERATIONS.md)

---

## 10. Implementation Order

**Recommended sequence:**

1. Define runner interface abstraction (`runner/lib/runner-interface.ps1`)
2. Add `provider` field to execution specs
3. Implement output parser (`runner/lib/output-parser.ps1`)
4. Implement Codex runner (`runner/codex.ps1` - real invocation)
5. Implement Claude CLI runner (`runner/claude.ps1` - real invocation)
6. Modify workflow runner to detect provider and route
7. Add integration tests for Codex runner
8. Add integration tests for Claude CLI runner
9. Add contract compliance verification tests
10. Update documentation and examples

---

## 11. Implementation Decisions

**Resolved:**

### 1. Codex API Invocation (OpenAI)
**Decision:** PowerShell `Invoke-RestMethod` to call OpenAI REST API directly.

```powershell
$headers = @{
    "Authorization" = "Bearer $($env:OPENAI_API_KEY)"
    "Content-Type" = "application/json"
}

$body = @{
    model = "gpt-4"  # Configurable: gpt-4, gpt-3.5-turbo, codex-mini-latest, gpt-5.5
    max_tokens = 8000
    messages = @(
        @{ role = "user"; content = $prompt }
    )
} | ConvertTo-Json -Depth 10

$response = Invoke-RestMethod `
    -Uri "https://api.openai.com/v1/chat/completions" `
    -Method Post `
    -Headers $headers `
    -Body $body
```

**Rationale:** No external dependencies, native PowerShell, straightforward. Model selection configurable via execution spec.

---

### 2. Claude CLI Output Parsing
**Decision:** JSON mode via prompt + stdout parsing.

```powershell
# Force JSON output in prompt
$prompt = @"
[Output Format]
You MUST respond with valid JSON only. No markdown, no explanation.
{
  "summary": "...",
  "changed_files": [...],
  "verification_result": "...",
  "risks": [...],
  "next_steps": [...]
}
"@

# Execute Claude CLI and capture stdout
$rawOutput = & claude --prompt $promptFile 2>&1 | Out-String

# Parse JSON
try {
    $output = $rawOutput | ConvertFrom-Json
} catch {
    # Retry on parse failure
    throw "Failed to parse Claude CLI output as JSON: $_"
}
```

**Rationale:**
- Works with any Claude CLI version
- No dependency on specific CLI flags
- Error handling via try/catch + retry

**Fallback:** If Claude CLI adds `--format json` flag in future, use that instead.

---

### 3. Error Handling
**Decision:** HTTP status code based classification.

```powershell
function Get-ErrorType {
    param($StatusCode, $Exception)

    # Transient failures (retry)
    if ($StatusCode -ge 500 -and $StatusCode -lt 600) {
        return "transient"  # 5xx server errors
    }
    if ($StatusCode -eq 429) {
        return "transient"  # Rate limit
    }
    if ($Exception -match "timeout|timed out|network") {
        return "transient"  # Network issues
    }

    # Permanent failures (don't retry)
    if ($StatusCode -ge 400 -and $StatusCode -lt 500) {
        return "permanent"  # 4xx client errors
    }

    return "unknown"  # Log and fail
}
```

**Rationale:** Standard HTTP semantics, widely understood, easy to debug.

---

### 4. Timeout Behavior
**Decision:** Start-Job with timeout monitoring, kill on timeout.

```powershell
$job = Start-Job -ScriptBlock {
    param($Params)
    Invoke-RestMethod @Params
} -ArgumentList @($params)

$timeout = 600  # 10 minutes (from execution spec)
$result = Wait-Job $job -Timeout $timeout

if ($null -eq $result) {
    # Timeout occurred
    Stop-Job $job
    Remove-Job $job
    throw "Runner execution timed out after $timeout seconds"
}

$output = Receive-Job $job
Remove-Job $job
```

**Rationale:**
- Clean process management
- Configurable timeout per execution spec
- Prevents hung processes

---

### 5. Malformed JSON Output
**Decision:** Retry with increased specificity.

```powershell
$maxRetries = 3
$attempt = 0

while ($attempt -lt $maxRetries) {
    try {
        $rawOutput = Invoke-LLM $prompt
        $output = $rawOutput | ConvertFrom-Json

        # Validate required fields
        Validate-OutputContract $output

        break  # Success
    } catch {
        $attempt++
        if ($attempt -ge $maxRetries) {
            # Log raw output for debugging
            Write-Error "Failed to parse LLM output after $maxRetries attempts"
            Write-Error "Raw output: $rawOutput"
            throw
        }

        # Add stricter instructions for retry
        $prompt = Add-StricterJsonInstructions $prompt
        Start-Sleep -Seconds 2
    }
}
```

**Rationale:**
- LLMs occasionally add markdown formatting
- Retry with stricter prompt usually succeeds
- Logs raw output for debugging persistent failures

---

**These decisions will be detailed in `docs/plan/contracts/runner-invocation.md`**
