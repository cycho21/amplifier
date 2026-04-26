# Comparison Contract

## Purpose

This document defines the runner-neutral contract for comparing workflow step
results.

Comparison is a structural check. It verifies that step outputs can be compared
across roles and runners. It does not choose a winner, score quality, or vote.

## Required Comparison Output

Workflow logs that support comparison must add `comparison` under `output`.

Minimum comparison fields:

```text
- required_fields
- required_fields_by_step
- missing_required_fields
- status
```

## Required Fields

`required_fields` lists the single-agent output fields that every step must
preserve:

```text
- summary
- changed_files
- verification_result
- risks
- next_steps
```

## Step Comparison

`required_fields_by_step` must include one entry per step log.

Each entry must include:

```text
- step_id
- role
- present_fields
- missing_fields
```

## Missing Fields

`missing_required_fields` is a flattened list of missing fields across all step
logs.

When no fields are missing, `status` must be:

```text
all-required-fields-present
```

When any field is missing, `status` must be:

```text
missing-required-fields
```

Voting or winner selection must be defined in a separate contract when needed.
