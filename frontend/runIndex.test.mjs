import assert from 'node:assert/strict';
import test from 'node:test';

import { createRunIndex, finishRun, startRun } from './runIndex.mjs';

test('startRun records target-aware running state and blocks a second run for the same target', () => {
  const index = createRunIndex();
  const started = startRun(index, {
    runId: 'run-1',
    targetId: 'client-app',
    taskId: 'roadmap-NEXT-6',
    command: 'runner workflow',
    logPath: 'logs/out.json',
    writeScope: ['src']
  });

  assert.equal(started.runs[0].status, 'running');
  assert.equal(started.runs[0].targetId, 'client-app');
  assert.deepEqual(started.runs[0].writeScope.paths, ['src']);
  assert.throws(
    () => startRun(started, {
      runId: 'run-2',
      targetId: 'client-app',
      taskId: 'roadmap-NEXT-7',
      command: 'runner workflow',
      logPath: 'logs/out-2.json',
      writeScope: ['docs']
    }),
    /already has a running task/
  );
});

test('finishRun updates exit code and allows later runs for the same target', () => {
  const started = startRun(createRunIndex(), {
    runId: 'run-1',
    targetId: 'client-app',
    taskId: 'roadmap-NEXT-6',
    command: 'runner workflow',
    logPath: 'logs/out.json',
    writeScope: ['src']
  });
  const finished = finishRun(started, 'run-1', { exitCode: 0 });
  const restarted = startRun(finished, {
    runId: 'run-2',
    targetId: 'client-app',
    taskId: 'roadmap-NEXT-7',
    command: 'runner workflow',
    logPath: 'logs/out-2.json',
    writeScope: ['docs']
  });

  assert.equal(finished.runs[0].status, 'completed');
  assert.equal(finished.runs[0].exitCode, 0);
  assert.equal(restarted.runs.length, 2);
});
