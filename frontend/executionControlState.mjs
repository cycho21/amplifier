const REAL_CONFIRMATION = 'RUN REAL';

export function createWorkflowControlState(input = {}) {
  const mode = input.mode === 'real' ? 'real' : 'dry-run';

  if (mode !== 'real') {
    return {
      mode,
      canExecute: true,
      status: 'Ready.',
      buttonLabel: 'Run dry-run workflow',
      requestPayload: {}
    };
  }

  const missing = [];

  if (input.generatedTaskReady !== true) {
    missing.push('generated task');
  }

  if (!hasWriteScope(input.writeScope)) {
    missing.push('write scope');
  }

  if (input.realExecutionConfirmation !== REAL_CONFIRMATION) {
    missing.push(REAL_CONFIRMATION);
  }

  if (missing.length > 0) {
    return {
      mode,
      canExecute: false,
      status: `Real execution requires ${missing.join(', ')}.`,
      buttonLabel: 'Run real workflow',
      requestPayload: {}
    };
  }

  return {
    mode,
    canExecute: true,
    status: 'Ready for real execution.',
    buttonLabel: 'Run real workflow',
    requestPayload: {
      allowRealExecution: true,
      realExecutionConfirmation: REAL_CONFIRMATION,
      realExecutionConfirmed: true
    }
  };
}

function hasWriteScope(value) {
  const items = Array.isArray(value)
    ? value
    : String(value || '').split(',');

  return items.some((item) => String(item || '').trim().length > 0);
}
