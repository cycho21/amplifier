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
```

Each step log must also include:

```text
- retry_policy
- attempts
```

## Dry-Run Rule

Dry-run runners must not perform real retries.

They must set `attempts` to `1` and copy the parsed retry policy into workflow
and step logs so real runners can later implement the same policy without
changing the log shape.
