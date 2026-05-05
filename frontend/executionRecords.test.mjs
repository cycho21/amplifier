import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createRetryPrefillFromExecutionRun,
  getWorkflowLogReferenceState,
  summarizeExecutionRequests
} from './executionRecords.mjs';

test('summarizeExecutionRequests keeps recent execution records with command metadata', () => {
  const summary = summarizeExecutionRequests([
    workflowRun('logs/operator-workflow-roadmap-NEXT-2.json', 'roadmap-NEXT-2'),
    executionRun({
      fileName: 'logs/execution-record-roadmap-NEXT-2.json',
      taskId: 'roadmap-NEXT-2',
      exitCode: 0
    })
  ]);

  assert.deepEqual(summary, [
    {
      fileName: 'logs/execution-record-roadmap-NEXT-2.json',
      taskId: 'roadmap-NEXT-2',
      command: '.\\runner\\workflow.ps1 -WorkflowSpec "workflows/implementation-review.yaml" -TaskId "roadmap-NEXT-2" -Mode "dry-run" -StepRunnerCommand ".\\runner\\codex.ps1" -LogOut "logs/operator-workflow-roadmap-NEXT-2.json"',
      logPath: 'logs/operator-workflow-roadmap-NEXT-2.json',
      exitCode: 0,
      status: 'exit 0'
    }
  ]);
});

test('getWorkflowLogReferenceState reports ready, missing, and stale workflow log references', () => {
  const execution = executionRun({
    taskId: 'roadmap-NEXT-2',
    logPath: 'logs/operator-workflow-roadmap-NEXT-2.json'
  });

  assert.deepEqual(
    getWorkflowLogReferenceState(execution, [
      execution,
      workflowRun('logs/operator-workflow-roadmap-NEXT-2.json', 'roadmap-NEXT-2')
    ]),
    {
      status: 'ready',
      label: 'Open workflow log',
      logPath: 'logs/operator-workflow-roadmap-NEXT-2.json',
      workflowFileName: 'logs/operator-workflow-roadmap-NEXT-2.json'
    }
  );
  assert.deepEqual(
    getWorkflowLogReferenceState(execution, [execution]),
    {
      status: 'missing-log',
      label: 'Workflow log missing',
      logPath: 'logs/operator-workflow-roadmap-NEXT-2.json',
      workflowFileName: ''
    }
  );
  assert.deepEqual(
    getWorkflowLogReferenceState(execution, [
      execution,
      workflowRun('logs/operator-workflow-roadmap-NEXT-2.json', 'other-task')
    ]),
    {
      status: 'stale-reference',
      label: 'Workflow log task mismatch',
      logPath: 'logs/operator-workflow-roadmap-NEXT-2.json',
      workflowFileName: 'logs/operator-workflow-roadmap-NEXT-2.json'
    }
  );
});

test('createRetryPrefillFromExecutionRun reuses captured dry-run command fields for failed records', () => {
  assert.deepEqual(
    createRetryPrefillFromExecutionRun(executionRun({
      taskId: 'roadmap-NEXT-2',
      exitCode: 1
    })),
    {
      taskId: 'roadmap-NEXT-2',
      workflowSpec: 'workflows/implementation-review.yaml',
      mode: 'dry-run',
      stepRunnerCommand: 'runner/codex.ps1',
      logOut: 'logs/operator-workflow-roadmap-NEXT-2.json',
      writeScope: '.'
    }
  );
  assert.throws(
    () => createRetryPrefillFromExecutionRun(executionRun({ exitCode: 0 })),
    /Only failed dry-run execution records can be retried/
  );
});

function executionRun(overrides = {}) {
  const taskId = overrides.taskId || 'roadmap-NEXT-2';
  const logPath = overrides.logPath || `logs/operator-workflow-${taskId}.json`;

  return {
    fileName: overrides.fileName || `logs/execution-record-${taskId}.json`,
    taskId,
    verificationResult: `exit ${overrides.exitCode ?? 1}`,
    execution: {
      command: `.\\runner\\workflow.ps1 -WorkflowSpec "workflows/implementation-review.yaml" -TaskId "${taskId}" -Mode "dry-run" -StepRunnerCommand ".\\runner\\codex.ps1" -LogOut "${logPath}"`,
      stdout: '',
      stderr: '',
      exitCode: overrides.exitCode ?? 1,
      logPath
    }
  };
}

function workflowRun(fileName, taskId) {
  return {
    fileName,
    taskId,
    type: 'workflow',
    execution: null
  };
}
