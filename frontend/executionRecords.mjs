export function summarizeExecutionRequests(runs, indexedRuns = []) {
  const runningRequests = indexedRuns
    .filter((run) => run.status === 'running')
    .map((run) => ({
      fileName: '',
      runId: run.runId,
      taskId: run.taskId,
      command: run.command,
      logPath: run.logPath,
      exitCode: run.exitCode,
      mode: run.realExecution?.mode === 'real' ? 'real' : 'dry-run',
      state: run.realExecution?.mode === 'real' ? 'real-running' : 'dry-run-running',
      status: run.realExecution?.mode === 'real' ? 'real running' : 'dry-run running'
    }));
  const runningLogPaths = new Set(runningRequests.map((r) => r.logPath).filter(Boolean));
  const recordRequests = runs
    .filter((run) => run.execution && !runningLogPaths.has(run.execution.logPath))
    .map((run) => summarizeExecutionRecord(run))
    .reverse();

  return [
    ...runningRequests,
    ...recordRequests
  ];
}

function summarizeExecutionRecord(run) {
  const request = {
    fileName: run.fileName,
    taskId: run.taskId,
    command: run.execution.command,
    logPath: run.execution.logPath,
    exitCode: run.execution.exitCode,
    status: run.verificationResult || formatExitStatus(run.execution.exitCode)
  };

  if (run.execution.realMetadata?.mode === 'real') {
    const pending = run.execution.exitCode === null;
    const completed = run.execution.exitCode === 0;
    request.mode = 'real';
    request.state = pending ? 'real-running' : completed ? 'real-completed' : 'real-failed';
    request.status = pending ? 'real running' : completed ? 'real completed' : 'real failed';
  }

  return request;
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
