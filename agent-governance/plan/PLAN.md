# PLAN.md

## Project: Mini Amplifier (LLM-agnostic)

이 프로젝트는 특정 LLM 도구(Codex, Claude 등)에 종속되지 않는
**Agent Execution Framework**를 만드는 것을 목표로 한다.

핵심은 “어떤 모델을 쓰든 동일한 방식으로 작업을 수행하게 하는 것”이다.

---

## 1. Core Principle

이 시스템은 다음 레이어로 구성된다.

```text
Task Definition (tasks/*.md)
        ↓
Agent Role (agents/*.md)
        ↓
Execution Spec (execution/*.yaml)
        ↓
Runner (codex / claude / api / etc)
```

LLM은 Runner일 뿐이며, 핵심 로직은 모두 문서로 정의한다.

---

## 2. Design Goal

* LLM 교체 가능 (Codex / Claude / GPT / local LLM)
* 실행 방식 분리
* 프롬프트 표준화
* 결과 로그 표준화
* 재현 가능성 확보

---

## 3. Repository Structure

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
│   ├── 000_template.md
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

---

## 4. Execution Spec (핵심)

모든 에이전트 실행은 YAML로 정의한다.

### example: execution/implementer.yaml

```yaml
role: implementer

input:
  - PLAN.md
  - agents/implementer.md
  - tasks/{task_id}.md

instructions:
  - Follow task requirements exactly
  - Do not modify unrelated files
  - Keep changes minimal
  - Run tests if possible

output:
  - changed_files
  - test_result
  - risks
  - summary
```

---

## 5. Task Contract

모든 LLM은 아래 계약을 반드시 따른다.

```text
INPUT:
- PLAN.md
- agent role
- task file

OUTPUT:
- summary
- changed files
- verification result
- risks
```

이 포맷은 모든 Runner에서 동일하다.

---

## 6. Runner Layer

Runner는 단순히 execution spec을 LLM에 맞게 변환한다.

---

### Codex Runner

```bash
codex run "<generated prompt>"
```

---

### Claude Runner

```bash
claude "<generated prompt>"
```

---

### API Runner (Go)

```go
// execution.yaml → prompt 생성 → OpenAI/Anthropic 호출
```

---

## 7. Execution Flow

```text
1. task 선택
2. execution yaml 로드
3. prompt 생성
4. runner 선택
5. 실행
6. 결과 로그 저장
```

---

## 8. Prompt Generation Rule

prompt는 항상 다음 구조를 따른다.

```text
[System]
- role 정의

[Context]
- PLAN.md
- task
- constraints

[Instruction]
- execution.yaml instructions

[Output Format]
- 반드시 structured output
```

---

## 9. Why This Matters

이 구조의 장점:

* Codex → Claude 교체 가능
* CLI → API → Web 전환 가능
* 테스트 가능
* 재현 가능
* agent behavior 비교 가능

Amplifier도 동일하게:

* kernel은 중립
* module이 policy 결정 ([GitHub][1])

---

## 10. MVP

MVP 범위:

* execution yaml 1개
* runner 1개 (아무거나)
* task 1개
* 로그 저장

---

## 11. Future

* multi-agent parallel execution
* voting system (N개 결과 비교)
* memory module
* task dependency graph
* automatic retry
* cost tracking

---

## 12. Definition of Done

* 동일 task를 Codex / Claude 둘 다 실행 가능
* 결과 구조 동일
* runner만 바꿔도 동작 동일
* 최소 1개 기능 개발 완료

[1]: https://github.com/microsoft/amplifier-core?utm_source=chatgpt.com "microsoft/amplifier-core"
