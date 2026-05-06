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

  return {
    mode,
    canExecute: true,
    status: 'Ready for real execution.',
    buttonLabel: 'Run real workflow',
    requestPayload: {
      allowRealExecution: true,
      realExecutionConfirmed: true
    }
  };
}

export function formatWorkflowConfirmationMessage(request = {}, context = {}) {
  if (request.mode !== 'real') {
    return `Run this ${request.mode || 'dry-run'} workflow command?\n\n${request.command || ''}`;
  }

  const targetLabel = context.targetName
    ? `${context.targetName}${context.targetId ? ` (${context.targetId})` : ''}`
    : context.targetId || 'default';
  const writeScope = formatList(context.writeScope || request.writeScope || ['.']);

  return [
    'Real execution risk summary',
    '',
    `Target: ${targetLabel}`,
    `Target path: ${context.targetPath || 'unknown'}`,
    `Task: ${request.taskId || 'unknown'}`,
    `Write scope: ${writeScope}`,
    `Step runner: ${request.stepRunnerCommand || 'unknown'}`,
    `Allow real: ${request.allowReal === true || request.command?.includes('-AllowReal') ? 'enabled' : 'missing'}`,
    '',
    'Command:',
    request.command || ''
  ].join('\n');
}

function hasWriteScope(value) {
  const items = Array.isArray(value)
    ? value
    : String(value || '').split(',');

  return items.some((item) => String(item || '').trim().length > 0);
}

function formatList(value) {
  const items = Array.isArray(value)
    ? value
    : String(value || '').split(',');

  const normalized = items
    .map((item) => String(item || '').trim())
    .filter(Boolean);

  return normalized.length > 0 ? normalized.join(', ') : '.';
}
