# Cost Contract

## Purpose

This document defines the runner-neutral cost tracking contract.

Cost tracking records cost-related metadata in workflow logs. Dry-run runners
must keep the log shape stable without estimating real provider costs.

## Cost Tracking Fields

Workflow specs may define a top-level `cost_tracking` block:

```yaml
cost_tracking:
  enabled: true
  currency: USD
  unit: dry-run-estimate
```

Required fields:

```text
- enabled
- currency
- unit
```

## Log Fields

Workflow logs that use cost tracking must add `cost_tracking` under `output`.

Minimum workflow cost fields:

```text
- enabled
- currency
- unit
- estimated_total_cost
- step_costs
```

Each step log must also include `cost_tracking`.

Minimum step cost fields:

```text
- enabled
- currency
- unit
- estimated_cost
```

## Dry-Run Rule

Dry-run runners must set all estimated costs to `0`.

Real runners may replace estimates with provider-specific calculations later,
but they must preserve the same log fields.
