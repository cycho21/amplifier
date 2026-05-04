# Retry Contract

## Purpose

This document defines the runner-neutral retry policy contract.

Retry policy describes how runners should retry failed workflow or step
execution. Dry-run runners record the policy and attempt count without actually
re-running work.

## Retry Policy Fields

Workflow specs may define a top-level `retry` block:

```yaml
retry:
  max_attempts: 2
  retry_on:
    - runner-error
  backoff: none
```

Required fields:

```text
- max_attempts
- retry_on
- backoff
```

## Log Fields

Workflow logs that use retry policy must add:

```text
- retry_policy
- attempts
- retry_attempts
```

Each step log must also include:

```text
- retry_policy
- attempts
- retry_attempts
```

`retry_attempts` records each real step runner invocation as:

```text
- step_id
- role
- attempt
- status
- reason
```

## Dry-Run Rule

Dry-run runners must not perform real retries.

They must set `attempts` to `1` and copy the parsed retry policy into workflow
and step logs. They must set `retry_attempts` to an empty list so real runners
can later record each attempt without changing the log shape.

## Real-Run Rule

Real runners must retry runner failures only when `retry_on` includes
`runner-error`.

Retry attempts must be bounded by `max_attempts`. A successful retry must keep
the workflow running and record the final step `attempts` count. A workflow-level
retry policy does not imply rerunning the whole workflow unless a later contract
explicitly adds whole-workflow retry behavior.

Real workflow logs must aggregate step `retry_attempts`. Real step logs must
record each attempt with `status` set to `failed` or `succeeded`; failed attempts
must include the runner failure reason.

When `retry_on` does not include `runner-error`, real runners must not retry
runner failures.
