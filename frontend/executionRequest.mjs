const DEFAULT_WORKFLOW_SPEC = 'workflows/implementation-review.yaml';
const DEFAULT_MODE = 'dry-run';
const DEFAULT_STEP_RUNNER_COMMAND = '.\\runner\\codex.ps1';

export function createWorkflowExecutionRequest(input = {}, options = {}) {
  const taskId = normalizeTaskId(input.taskId);
  const workflowSpec = normalizeWorkflowSpec(input.workflowSpec || DEFAULT_WORKFLOW_SPEC);
  const mode = normalizeMode(input.mode || DEFAULT_MODE, input);
  const stepRunnerCommand = normalizeStepRunnerCommand(
    input.stepRunnerCommand || DEFAULT_STEP_RUNNER_COMMAND
  );
  const logOut = normalizeLogOut(input.logOut || defaultLogOut(taskId, options.timestamp));
  const allowReal = mode === 'real';

  return {
    taskId,
    workflowSpec,
    mode,
    stepRunnerCommand,
    logOut,
    ...(allowReal ? { allowReal } : {}),
    command: formatWorkflowCommand({
      workflowSpec,
      taskId,
      mode,
      stepRunnerCommand,
      logOut,
      allowReal
    })
  };
}

export function formatWorkflowCommand(request) {
  const parts = [
    '.\\runner\\workflow.ps1',
    `-WorkflowSpec "${request.workflowSpec}"`,
    `-TaskId "${request.taskId}"`,
    `-Mode "${request.mode}"`,
    `-StepRunnerCommand "${request.stepRunnerCommand}"`,
    `-LogOut "${request.logOut}"`
  ];

  if (request.allowReal === true) {
    parts.push('-AllowReal');
  }

  return parts.join(' ');
}

function defaultLogOut(taskId, timestamp = new Date().toISOString()) {
  const normalizedTimestamp = timestamp.replace(/[-:.]/g, '');
  return `logs/operator-workflow-${taskId}-${normalizedTimestamp}.json`;
}

function normalizeTaskId(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new Error('Task id must contain only letters, numbers, underscores, or hyphens.');
  }

  return value;
}

function normalizeWorkflowSpec(value) {
  const normalized = normalizeBrowserPath(value);

  if (
    !normalized.startsWith('workflows/') ||
    normalized.includes('..') ||
    normalized.split('/').length !== 2 ||
    !normalized.endsWith('.yaml')
  ) {
    throw new Error('Workflow spec must be a top-level YAML file under workflows/.');
  }

  return normalized;
}

function normalizeMode(value, input) {
  if (value === DEFAULT_MODE) {
    return value;
  }

  if (value === 'real') {
    return value;
  }

  throw new Error(`Unknown workflow mode: ${value}`);
}

function normalizeStepRunnerCommand(value) {
  const normalized = normalizeBrowserPath(value).replace(/^\.\//, '');

  if (
    !normalized.startsWith('runner/') ||
    normalized.includes('..') ||
    normalized.split('/').length !== 2 ||
    !normalized.endsWith('.ps1')
  ) {
    throw new Error('Step runner command must be a top-level PowerShell script under runner/.');
  }

  return `.\\${normalized.replace(/\//g, '\\')}`;
}

function normalizeLogOut(value) {
  const normalized = normalizeBrowserPath(value);

  if (
    !normalized.startsWith('logs/') ||
    normalized.includes('..') ||
    normalized.split('/').length !== 2 ||
    !normalized.endsWith('.json')
  ) {
    throw new Error('Log output path must be a top-level JSON file under logs/.');
  }

  return normalized;
}

function normalizeBrowserPath(value) {
  return typeof value === 'string' ? value.replace(/\\/g, '/').trim() : '';
}
