import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { getWorkflowLogReferenceState } from './executionRecords.mjs';
import { summarizeRuns } from './logParser.mjs';
import { createWorkflowPrefillFromRoadmapRun } from './roadmapRunResult.mjs';
import {
  executeWorkflowRequest,
  readLogFiles,
  readTaskDraft,
  runRoadmapItem
} from './server.mjs';

test('roadmap run, generated task draft, execution record, and workflow log stay linked', async () => {
  const operatorRoot = await mkdtemp(path.join(tmpdir(), 'operator-trace-app-'));
  const targetRoot = await mkdtemp(path.join(tmpdir(), 'operator-trace-target-'));

  try {
    await mkdir(path.join(operatorRoot, 'workflows'), { recursive: true });
    await mkdir(path.join(operatorRoot, 'runner'), { recursive: true });
    await mkdir(path.join(targetRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    await writeFile(path.join(operatorRoot, 'workflows', 'implementation-review.yaml'), 'workflow: implementation-review\n');
    await writeFile(path.join(operatorRoot, 'runner', 'workflow.ps1'), '# workflow\n');
    await writeFile(path.join(operatorRoot, 'runner', 'codex.ps1'), '# codex\n');
    await writeFile(path.join(targetRoot, 'docs', 'plan', 'roadmaps', 'NEXT.md'), [
      '# Next',
      '',
      '## Sequence',
      '1. [ ] Trace generated artifacts.'
    ].join('\n'));

    const roadmapRun = await runRoadmapItem(targetRoot, {
      name: 'docs/plan/roadmaps/NEXT.md',
      itemIndex: 0
    });
    const prefill = createWorkflowPrefillFromRoadmapRun(roadmapRun);
    const taskDraft = await readTaskDraft(targetRoot, `tasks/${prefill.taskId}.md`);

    const executionRecord = await executeWorkflowRequest(
      targetRoot,
      {
        confirmed: true,
        targetId: 'trace-target',
        taskId: prefill.taskId,
        workflowSpec: prefill.workflowSpec,
        mode: prefill.mode,
        stepRunnerCommand: prefill.stepRunnerCommand
      },
      {
        operatorRoot,
        timestamp: '2026-05-05T06:07:08.009Z',
        invoke: async (roots, request) => {
          await writeFile(
            path.join(roots.targetRoot, request.logOut),
            `${JSON.stringify({
              run_id: `workflow-${request.taskId}`,
              runner: 'workflow-dry-run',
              workflow: 'implementation-review',
              task_id: request.taskId,
              output: {
                final_status: 'dry-run-complete',
                step_logs: []
              }
            }, null, 2)}\n`
          );

          return {
            stdout: 'Workflow log written\n',
            stderr: '',
            exitCode: 0
          };
        }
      }
    );
    const logSummary = summarizeRuns(await readLogFiles(targetRoot));
    const execution = logSummary.runs.find((run) => run.fileName === executionRecord.name);

    assert.match(taskDraft.content, /Trace generated artifacts\./);
    assert.equal(execution.taskId, prefill.taskId);
    assert.deepEqual(
      getWorkflowLogReferenceState(execution, logSummary.runs),
      {
        status: 'ready',
        label: 'Open workflow log',
        logPath: `logs/operator-workflow-${prefill.taskId}-20260505T060708009Z.json`,
        workflowFileName: `logs/operator-workflow-${prefill.taskId}-20260505T060708009Z.json`
      }
    );
    assert.match(
      await readFile(path.join(targetRoot, `logs/operator-workflow-${prefill.taskId}-20260505T060708009Z.json`), 'utf8'),
      /dry-run-complete/
    );
  } finally {
    await rm(operatorRoot, { recursive: true, force: true });
    await rm(targetRoot, { recursive: true, force: true });
  }
});
