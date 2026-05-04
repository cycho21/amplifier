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

Real runners may include `provider_metadata` under step `cost_tracking` and
workflow `step_costs` entries.

Provider metadata fields:

```text
- provider
- tool
- model
- input_tokens
- output_tokens
- total_tokens
- input_token_rate
- output_token_rate
- rate_unit_tokens
- source
```

## Dry-Run Rule

Dry-run runners must set all estimated costs to `0`.

Real runners may record provider metadata sources without calculating cost.
Provider metadata must not change `estimated_cost` or `estimated_total_cost`;
real cost calculation is a separate behavior.

## Real-Run Rule

Real workflow runners must calculate step `estimated_cost` when provider
metadata includes token usage and token rates.

Calculation:

```text
estimated_cost =
  ((input_tokens * input_token_rate) + (output_tokens * output_token_rate))
  / rate_unit_tokens
```

If provider metadata does not include rates, the step `estimated_cost` must stay
`0`.

Workflow `estimated_total_cost` must equal the sum of all step
`estimated_cost` values.
