import assert from 'node:assert/strict';
import test from 'node:test';

import { createWorkflowControlState } from './executionControlState.mjs';

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
