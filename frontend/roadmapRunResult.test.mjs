import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createWorkflowPrefillFromRoadmapRun,
  getGeneratedTaskFile
} from './roadmapRunResult.mjs';

test('getGeneratedTaskFile reads the generated task draft path from a roadmap run result', () => {
  assert.equal(
    getGeneratedTaskFile({
      content: JSON.stringify({
        output: {
          roadmap_item: {
            task_file: 'tasks/roadmap-NEXT-2.md'
          }
        }
      })
    }),
    'tasks/roadmap-NEXT-2.md'
  );
});

test('createWorkflowPrefillFromRoadmapRun returns dry-run defaults for generated roadmap tasks', () => {
  assert.deepEqual(
    createWorkflowPrefillFromRoadmapRun({
      content: JSON.stringify({
        task_id: 'roadmap-NEXT-2',
        output: {
          roadmap_item: {
            task_file: 'tasks/roadmap-NEXT-2.md'
          }
        }
      })
    }),
    {
      taskId: 'roadmap-NEXT-2',
      workflowSpec: 'workflows/implementation-review.yaml',
      mode: 'dry-run',
      stepRunnerCommand: 'runner/codex.ps1',
      logOut: '',
      writeScope: '.'
    }
  );
});

test('createWorkflowPrefillFromRoadmapRun rejects malformed roadmap run results', () => {
  assert.throws(
    () => createWorkflowPrefillFromRoadmapRun({ content: '{}' }),
    /Generated roadmap task id is missing/
  );
});
