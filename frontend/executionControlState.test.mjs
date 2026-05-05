import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createWorkflowControlState,
  formatWorkflowConfirmationMessage
} from './executionControlState.mjs';

test('createWorkflowControlState keeps dry-run execution enabled by default', () => {
  assert.deepEqual(createWorkflowControlState({
    mode: 'dry-run',
    taskId: 'roadmap-NEXT-3',
    writeScope: []
  }), {
    mode: 'dry-run',
    canExecute: true,
    status: 'Ready.',
    buttonLabel: 'Run dry-run workflow',
    requestPayload: {}
  });
});

test('createWorkflowControlState blocks real execution until task, scope, and confirmation are present', () => {
  const blocked = createWorkflowControlState({
    mode: 'real',
    taskId: 'roadmap-NEXT-3',
    writeScope: ['src'],
    generatedTaskReady: false,
    realExecutionConfirmation: ''
  });

  assert.equal(blocked.mode, 'real');
  assert.equal(blocked.canExecute, false);
  assert.equal(blocked.buttonLabel, 'Run real workflow');
  assert.deepEqual(blocked.requestPayload, {});
  assert.match(blocked.status, /generated task/);
  assert.match(blocked.status, /RUN REAL/);
});

test('createWorkflowControlState enables real execution with explicit UI and server confirmations', () => {
  assert.deepEqual(createWorkflowControlState({
    mode: 'real',
    taskId: 'roadmap-NEXT-3',
    writeScope: ['src/app'],
    generatedTaskReady: true,
    realExecutionConfirmation: 'RUN REAL'
  }), {
    mode: 'real',
    canExecute: true,
    status: 'Ready for real execution.',
    buttonLabel: 'Run real workflow',
    requestPayload: {
      allowRealExecution: true,
      realExecutionConfirmation: 'RUN REAL',
      realExecutionConfirmed: true
    }
  });
});

test('formatWorkflowConfirmationMessage keeps dry-run confirmation concise', () => {
  assert.equal(
    formatWorkflowConfirmationMessage({
      mode: 'dry-run',
      command: '.\\runner\\workflow.ps1 -Mode "dry-run"'
    }),
    'Run this dry-run workflow command?\n\n.\\runner\\workflow.ps1 -Mode "dry-run"'
  );
});

test('formatWorkflowConfirmationMessage shows real execution risk summary', () => {
  const message = formatWorkflowConfirmationMessage(
    {
      mode: 'real',
      taskId: 'roadmap-NEXT-4',
      stepRunnerCommand: '.\\runner\\codex.ps1',
      command: '.\\runner\\workflow.ps1 -TaskId "roadmap-NEXT-4" -Mode "real" -AllowReal'
    },
    {
      targetId: 'client-app',
      targetName: 'Client App',
      targetPath: 'I:\\client-app',
      writeScope: ['src/app', 'tests']
    }
  );

  assert.match(message, /Real execution risk summary/);
  assert.match(message, /Target: Client App \(client-app\)/);
  assert.match(message, /Target path: I:\\client-app/);
  assert.match(message, /Task: roadmap-NEXT-4/);
  assert.match(message, /Write scope: src\/app, tests/);
  assert.match(message, /Step runner: \.\\runner\\codex\.ps1/);
  assert.match(message, /Allow real: enabled/);
  assert.match(message, /-AllowReal/);
});
