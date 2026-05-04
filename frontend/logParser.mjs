export function parseLogFile(fileName, content) {
  let data;

  try {
    data = JSON.parse(stripBom(content));
  } catch (error) {
    return {
      ok: false,
      fileName,
      error: `Invalid JSON: ${error.message}`
    };
  }

  const output = isObject(data.output) ? data.output : {};
  const stepLogs = Array.isArray(output.step_logs) ? output.step_logs : [];
  const isWorkflow = Boolean(data.workflow || stepLogs.length > 0);
  const cost = normalizeWorkflowCost(output.cost_tracking);
  const steps = stepLogs.map(normalizeStep);

  return {
    ok: true,
    fileName,
    run: {
      fileName,
      runId: stringOrFallback(data.run_id, fileName),
      runner: stringOrFallback(data.runner, 'unknown'),
      taskId: stringOrFallback(data.task_id, 'unknown'),
      type: isWorkflow ? 'workflow' : 'single',
      name: isWorkflow
        ? stringOrFallback(data.workflow, data.run_id || fileName)
        : stringOrFallback(data.role, data.run_id || fileName),
      status: stringOrFallback(output.final_status, isWorkflow ? 'unknown' : 'complete'),
      stepCount: stepLogs.length,
      steps,
      verificationResult: stringOrFallback(output.verification_result, ''),
      verificationEvidence: normalizeVerificationEvidence(data, output, steps),
      risks: arrayOfStrings(output.risks),
      nextSteps: arrayOfStrings(output.next_steps),
      retryAttempts: arrayOfObjects(output.retry_attempts).map(normalizeRetryAttempt),
      failedSteps: arrayOfObjects(output.failed_steps).map(normalizeFailedStep),
      cancelledSteps: arrayOfObjects(output.cancelled_steps).map(normalizeOperationalStep),
      skippedSteps: arrayOfObjects(output.skipped_steps).map(normalizeOperationalStep),
      cost,
      costTotal: cost.estimatedTotalCost,
      costTracking: isObject(output.cost_tracking) ? output.cost_tracking : null,
      memory: normalizeMemory(output.memory)
    }
  };
}

function stripBom(content) {
  return content.startsWith('\uFEFF') ? content.slice(1) : content;
}

function normalizeVerificationEvidence(data, output, steps) {
  const evidence = [];
  const workflowResult = stringOrFallback(output.verification_result, '');

  if (workflowResult) {
    evidence.push({
      scope: 'workflow',
      label: stringOrFallback(data.workflow, stringOrFallback(data.role, data.run_id || 'workflow')),
      command: isObject(data.invocation) ? stringOrFallback(data.invocation.command, '') : '',
      exitCode: isObject(data.invocation) ? numberOrNull(data.invocation.exit_code) : null,
      result: workflowResult
    });
  }

  for (const step of steps) {
    if (!step.verificationResult) {
      continue;
    }

    evidence.push({
      scope: 'step',
      label: step.stepId,
      command: '',
      exitCode: null,
      result: step.verificationResult
    });
  }

  return evidence;
}

export function summarizeRuns(files) {
  const runs = [];
  const errors = [];

  for (const file of files) {
    const result = parseLogFile(file.name, file.content);

    if (result.ok) {
      runs.push(result.run);
    } else {
      errors.push(result);
    }
  }

  return {
    runs,
    errors,
    emptyMessage: 'No logs loaded.'
  };
}

function normalizeStep(step) {
  const output = isObject(step.output) ? step.output : {};
  const retryPolicy = isObject(step.retry_policy) ? step.retry_policy : null;
  const cost = normalizeStepCost(step.cost_tracking, step.step_id, step.role);
  const costTracking = isObject(step.cost_tracking) ? step.cost_tracking : null;
  const memory = normalizeMemory(step.memory);

  return {
    stepId: stringOrFallback(step.step_id, 'unknown'),
    role: stringOrFallback(step.role, 'unknown'),
    status: stringOrFallback(step.status, ''),
    attempts: Number.isFinite(step.attempts) ? step.attempts : null,
    retryAttempts: arrayOfObjects(step.retry_attempts).map(normalizeRetryAttempt),
    retryPolicy,
    cost,
    costTracking,
    memory,
    verificationResult: stringOrFallback(output.verification_result, ''),
    risks: arrayOfStrings(output.risks),
    nextSteps: arrayOfStrings(output.next_steps)
  };
}

function normalizeWorkflowCost(costTracking) {
  if (!isObject(costTracking)) {
    return {
      enabled: false,
      currency: '',
      unit: '',
      estimatedTotalCost: null,
      stepCosts: []
    };
  }

  return {
    enabled: costTracking.enabled === true,
    currency: stringOrFallback(costTracking.currency, ''),
    unit: stringOrFallback(costTracking.unit, ''),
    estimatedTotalCost: readCostTotal(costTracking),
    stepCosts: arrayOfObjects(costTracking.step_costs).map((stepCost) =>
      normalizeStepCost(stepCost, stepCost.step_id, stepCost.role)
    )
  };
}

function normalizeMemory(memory) {
  const source = isObject(memory) ? memory : {};

  return {
    enabled: source.enabled === true,
    scope: stringOrFallback(source.scope, ''),
    persistence: stringOrFallback(source.persistence, ''),
    path: stringOrFallback(source.path, ''),
    loaded: booleanOrNull(source.loaded),
    written: booleanOrNull(source.written),
    stale: booleanOrNull(source.stale),
    overwriteAllowed: booleanOrNull(source.overwrite_allowed)
  };
}

function normalizeStepCost(costTracking, stepId, role) {
  const source = isObject(costTracking) ? costTracking : {};

  return {
    stepId: stringOrFallback(source.step_id, stringOrFallback(stepId, 'unknown')),
    role: stringOrFallback(source.role, stringOrFallback(role, 'unknown')),
    estimatedCost: Number.isFinite(source.estimated_cost) ? source.estimated_cost : null,
    currency: stringOrFallback(source.currency, ''),
    unit: stringOrFallback(source.unit, ''),
    providerMetadata: normalizeProviderMetadata(source.provider_metadata)
  };
}

function normalizeProviderMetadata(metadata) {
  const source = isObject(metadata) ? metadata : {};

  return {
    provider: stringOrFallback(source.provider, ''),
    tool: stringOrFallback(source.tool, ''),
    model: stringOrFallback(source.model, ''),
    inputTokens: numberOrNull(source.input_tokens),
    outputTokens: numberOrNull(source.output_tokens),
    totalTokens: numberOrNull(source.total_tokens),
    inputTokenRate: numberOrNull(source.input_token_rate),
    outputTokenRate: numberOrNull(source.output_token_rate),
    rateUnitTokens: numberOrNull(source.rate_unit_tokens),
    source: stringOrFallback(source.source, '')
  };
}

function normalizeRetryAttempt(attempt) {
  return {
    stepId: stringOrFallback(attempt.step_id, 'unknown'),
    attempt: Number.isFinite(attempt.attempt) ? attempt.attempt : null,
    status: stringOrFallback(attempt.status, 'unknown')
  };
}

function normalizeFailedStep(step) {
  return {
    ...normalizeOperationalStep(step),
    attempts: Number.isFinite(step.attempts) ? step.attempts : null,
    retryExhausted: step.retry_exhausted === true
  };
}

function normalizeOperationalStep(step) {
  return {
    stepId: stringOrFallback(step.step_id, 'unknown'),
    role: stringOrFallback(step.role, 'unknown'),
    reason: stringOrFallback(step.reason, '')
  };
}

function readCostTotal(costTracking) {
  if (!isObject(costTracking)) {
    return null;
  }

  if (Number.isFinite(costTracking.estimated_total_cost)) {
    return costTracking.estimated_total_cost;
  }

  if (Number.isFinite(costTracking.estimated_cost)) {
    return costTracking.estimated_cost;
  }

  return null;
}

function numberOrNull(value) {
  return Number.isFinite(value) ? value : null;
}

function booleanOrNull(value) {
  return typeof value === 'boolean' ? value : null;
}

function arrayOfStrings(value) {
  return Array.isArray(value) ? value.map(String) : [];
}

function arrayOfObjects(value) {
  return Array.isArray(value) ? value.filter(isObject) : [];
}

function stringOrFallback(value, fallback) {
  return typeof value === 'string' && value.length > 0 ? value : fallback;
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
