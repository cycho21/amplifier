import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createWorkflowExecutionRequest,
  formatWorkflowCommand
} from './executionRequest.mjs';

test('createWorkflowExecutionRequest normalizes dry-run workflow execution fields', () => {
  const request = createWorkflowExecutionRequest(
    {
      taskId: 'roadmap-NEXT-6',
      workflowSpec: 'workflows/implementation-review.yaml',
      mode: 'dry-run',
      stepRunnerCommand: 'runner/codex.ps1'
    },
    { timestamp: '2026-05-05T01:02:03.004Z' }
  );

  assert.deepEqual(request, {
    taskId: 'roadmap-NEXT-6',
    workflowSpec: 'workflows/implementation-review.yaml',
    mode: 'dry-run',
    stepRunnerCommand: '.\\runner\\codex.ps1',
    logOut: 'logs/operator-workflow-roadmap-NEXT-6-20260505T010203004Z.json',
    command: '.\\runner\\workflow.ps1 -WorkflowSpec "workflows/implementation-review.yaml" -TaskId "roadmap-NEXT-6" -Mode "dry-run" -StepRunnerCommand ".\\runner\\codex.ps1" -LogOut "logs/operator-workflow-roadmap-NEXT-6-20260505T010203004Z.json"'
  });
});

test('formatWorkflowCommand builds the exact local dry-run command', () => {
  assert.equal(
    formatWorkflowCommand({
      taskId: 'operator-control',
      workflowSpec: 'workflows/implementation-review.yaml',
      mode: 'dry-run',
      stepRunnerCommand: '.\\runner\\codex.ps1',
      logOut: 'logs/operator-control.json'
    }),
    '.\\runner\\workflow.ps1 -WorkflowSpec "workflows/implementation-review.yaml" -TaskId "operator-control" -Mode "dry-run" -StepRunnerCommand ".\\runner\\codex.ps1" -LogOut "logs/operator-control.json"'
  );
});

test('createWorkflowExecutionRequest allows real mode', () => {
  const request = createWorkflowExecutionRequest(
    {
      taskId: 'roadmap-NEXT-6',
      workflowSpec: 'workflows/implementation-review.yaml',
      mode: 'real',
      stepRunnerCommand: 'runner/codex.ps1'
    },
    { timestamp: '2026-05-05T01:02:03.004Z' }
  );

  assert.deepEqual(request, {
    taskId: 'roadmap-NEXT-6',
    workflowSpec: 'workflows/implementation-review.yaml',
    mode: 'real',
    stepRunnerCommand: '.\\runner\\codex.ps1',
    logOut: 'logs/operator-workflow-roadmap-NEXT-6-20260505T010203004Z.json',
    allowReal: true,
    command: '.\\runner\\workflow.ps1 -WorkflowSpec "workflows/implementation-review.yaml" -TaskId "roadmap-NEXT-6" -Mode "real" -StepRunnerCommand ".\\runner\\codex.ps1" -LogOut "logs/operator-workflow-roadmap-NEXT-6-20260505T010203004Z.json" -AllowReal'
  });
});


test('createWorkflowExecutionRequest rejects invalid paths and task ids', () => {
  assert.throws(
    () => createWorkflowExecutionRequest({ taskId: '../bad' }),
    /Task id/
  );
  assert.throws(
    () => createWorkflowExecutionRequest({
      taskId: 'roadmap-NEXT-6',
      workflowSpec: 'docs/plan/roadmaps/NEXT.md'
    }),
    /Workflow spec/
  );
  assert.throws(
    () => createWorkflowExecutionRequest({
      taskId: 'roadmap-NEXT-6',
      stepRunnerCommand: 'runner/../runner/codex.ps1'
    }),
    /Step runner command/
  );
  assert.throws(
    () => createWorkflowExecutionRequest({
      taskId: 'roadmap-NEXT-6',
      logOut: 'logs/nested/out.json'
    }),
    /Log output path/
  );
});
