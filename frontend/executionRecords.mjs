export function summarizeExecutionRequests(runs) {
  return runs
    .filter((run) => run.execution)
    .map((run) => ({
      fileName: run.fileName,
      taskId: run.taskId,
      command: run.execution.command,
      logPath: run.execution.logPath,
      exitCode: run.execution.exitCode,
      status: run.verificationResult || formatExitStatus(run.execution.exitCode)
    }));
}

export function getWorkflowLogReferenceState(executionRun, runs) {
  const logPath = executionRun?.execution?.logPath || '';

  if (!logPath) {
    return {
      status: 'missing-reference',
      label: 'Workflow log reference missing',
      logPath: '',
      workflowFileName: ''
    };
  }

  const workflowRun = runs.find((run) => run.fileName === logPath);

  if (!workflowRun) {
    return {
      status: 'missing-log',
      label: 'Workflow log missing',
      logPath,
      workflowFileName: ''
    };
  }

  if (workflowRun.taskId !== executionRun.taskId) {
    return {
      status: 'stale-reference',
      label: 'Workflow log task mismatch',
      logPath,
      workflowFileName: workflowRun.fileName
    };
  }

  return {
    status: 'ready',
    label: 'Open workflow log',
    logPath,
    workflowFileName: workflowRun.fileName
  };
}

export function createRetryPrefillFromExecutionRun(run) {
  if (!run?.execution || run.execution.exitCode === 0) {
    throw new Error('Only failed dry-run execution records can be retried.');
  }

  const fields = parseWorkflowCommand(run.execution.command);

  if (fields.mode !== 'dry-run') {
    throw new Error('Only failed dry-run execution records can be retried.');
  }

  return {
    taskId: fields.taskId,
    workflowSpec: fields.workflowSpec,
    mode: fields.mode,
    stepRunnerCommand: fields.stepRunnerCommand.replace(/^\.\\/, '').replace(/\\/g, '/'),
    logOut: fields.logOut,
    writeScope: '.'
  };
}

function parseWorkflowCommand(command) {
  return {
    workflowSpec: readCommandOption(command, 'WorkflowSpec'),
    taskId: readCommandOption(command, 'TaskId'),
    mode: readCommandOption(command, 'Mode'),
    stepRunnerCommand: readCommandOption(command, 'StepRunnerCommand'),
    logOut: readCommandOption(command, 'LogOut')
  };
}

function readCommandOption(command, name) {
  const pattern = new RegExp(`-${name}\\s+"([^"]+)"`);
  const match = pattern.exec(command || '');

  if (!match) {
    throw new Error(`Execution command is missing -${name}.`);
  }

  return match[1];
}

function formatExitStatus(exitCode) {
  return Number.isInteger(exitCode) ? `exit ${exitCode}` : 'exit n/a';
}
