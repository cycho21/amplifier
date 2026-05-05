import { normalizeWriteScope } from './writeScope.mjs';

export function createRunIndex(input = {}) {
  return {
    version: 1,
    runs: Array.isArray(input.runs) ? input.runs.map(normalizeRunRecord) : []
  };
}

export function startRun(index, run) {
  const current = createRunIndex(index);
  const targetId = normalizeRequired(run.targetId, 'Target id');

  if (current.runs.some((record) => record.targetId === targetId && record.status === 'running')) {
    throw new Error(`Target ${targetId} already has a running task.`);
  }

  return createRunIndex({
    runs: [
      {
        runId: normalizeRequired(run.runId, 'Run id'),
        targetId,
        taskId: normalizeRequired(run.taskId, 'Task id'),
        command: String(run.command || ''),
        status: 'running',
        startedAt: run.startedAt || new Date().toISOString(),
        finishedAt: '',
        logPath: normalizeRequired(run.logPath, 'Log path'),
        exitCode: null,
        writeScope: normalizeWriteScope(run.writeScope?.paths || run.writeScope || ['.'])
      },
      ...current.runs
    ]
  });
}

export function finishRun(index, runId, result = {}) {
  const current = createRunIndex(index);
  const normalizedRunId = normalizeRequired(runId, 'Run id');
  let found = false;

  const runs = current.runs.map((record) => {
    if (record.runId !== normalizedRunId) {
      return record;
    }

    found = true;
    return {
      ...record,
      status: result.exitCode === 0 ? 'completed' : 'failed',
      finishedAt: result.finishedAt || new Date().toISOString(),
      exitCode: Number.isInteger(result.exitCode) ? result.exitCode : 1
    };
  });

  if (!found) {
    throw new Error(`Run not found: ${normalizedRunId}`);
  }

  return createRunIndex({ runs });
}

function normalizeRunRecord(record) {
  return {
    runId: normalizeRequired(record.runId, 'Run id'),
    targetId: normalizeRequired(record.targetId, 'Target id'),
    taskId: normalizeRequired(record.taskId, 'Task id'),
    command: String(record.command || ''),
    status: normalizeStatus(record.status),
    startedAt: String(record.startedAt || ''),
    finishedAt: String(record.finishedAt || ''),
    logPath: normalizeRequired(record.logPath, 'Log path'),
    exitCode: Number.isInteger(record.exitCode) ? record.exitCode : null,
    writeScope: normalizeWriteScope(record.writeScope?.paths || record.writeScope || ['.'])
  };
}

function normalizeStatus(status) {
  if (['running', 'completed', 'failed'].includes(status)) {
    return status;
  }

  return 'failed';
}

function normalizeRequired(value, label) {
  const normalized = String(value || '').trim();

  if (normalized.length === 0) {
    throw new Error(`${label} is required.`);
  }

  return normalized;
}
