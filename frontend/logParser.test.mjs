import assert from 'node:assert/strict';
import test from 'node:test';

import { parseLogFile, summarizeRuns } from './logParser.mjs';

test('parseLogFile returns a workflow run summary with step count and status', () => {
  const content = JSON.stringify({
    run_id: '20260426-workflow-implementation-review-000_template',
    runner: 'workflow-dry-run',
    workflow: 'implementation-review',
    task_id: '000_template',
    output: {
      final_status: 'dry-run-complete',
      step_logs: [
        {
          step_id: 'architect',
          role: 'architect',
          attempts: 1,
          output: {
            risks: ['Dry-run only.'],
            next_steps: ['Wire real runner.'],
            verification_result: 'Loaded locally.'
          }
        }
      ],
      risks: ['Workflow risk.'],
      next_steps: ['Workflow next step.'],
      cost_tracking: {
        estimated_total_cost: 0,
        currency: 'USD',
        step_costs: [
          {
            step_id: 'architect',
            role: 'architect',
            estimated_cost: 0,
            currency: 'USD',
            unit: 'dry-run-estimate'
          }
        ]
      },
      memory: {
        loaded: false,
        written: false,
        stale: false,
        overwrite: false
      }
    }
  });

  const result = parseLogFile('workflow.json', content);

  assert.equal(result.ok, true);
  assert.equal(result.run.type, 'workflow');
  assert.equal(result.run.name, 'implementation-review');
  assert.equal(result.run.status, 'dry-run-complete');
  assert.equal(result.run.stepCount, 1);
  assert.deepEqual(result.run.risks, ['Workflow risk.']);
  assert.deepEqual(result.run.nextSteps, ['Workflow next step.']);
  assert.equal(result.run.costTotal, 0);
  assert.equal(result.run.memory.loaded, false);
});

test('parseLogFile accepts JSON logs with a UTF-8 BOM', () => {
  const result = parseLogFile(
    'bom.json',
    '\uFEFF{"run_id":"bom-run","runner":"codex","role":"tester","task_id":"000","output":{"verification_result":"Loaded.","risks":[],"next_steps":[]}}'
  );

  assert.equal(result.ok, true);
  assert.equal(result.run.runId, 'bom-run');
});

test('parseLogFile returns a clear error for malformed JSON', () => {
  const result = parseLogFile('broken.json', '{');

  assert.equal(result.ok, false);
  assert.equal(result.fileName, 'broken.json');
  assert.match(result.error, /Invalid JSON/);
});

test('summarizeRuns keeps parsed runs and malformed files separate', () => {
  const files = [
    {
      name: 'single.json',
      content: JSON.stringify({
        run_id: '20260426-implementer-000_template',
        runner: 'codex',
        role: 'implementer',
        task_id: '000_template',
        output: {
          verification_result: 'Inputs loaded.',
          risks: [],
          next_steps: []
        }
      })
    },
    {
      name: 'broken.json',
      content: '{'
    }
  ];

  const summary = summarizeRuns(files);

  assert.equal(summary.runs.length, 1);
  assert.equal(summary.errors.length, 1);
  assert.equal(summary.runs[0].type, 'single');
  assert.equal(summary.runs[0].name, 'implementer');
});

test('summarizeRuns reports an empty state when no log files are loaded', () => {
  const summary = summarizeRuns([]);

  assert.equal(summary.runs.length, 0);
  assert.equal(summary.errors.length, 0);
  assert.equal(summary.emptyMessage, 'No logs loaded.');
});

test('parseLogFile normalizes retry exhaustion, cancelled steps, and skipped steps', () => {
  const content = JSON.stringify({
    run_id: '20260426-workflow-real-failed-000_template',
    runner: 'workflow-real',
    workflow: 'parallel-review',
    task_id: '000_template',
    output: {
      final_status: 'real-failed',
      step_logs: [
        {
          step_id: 'backend-engineer',
          role: 'backend-engineer',
          attempts: 2,
          retry_attempts: [
            { step_id: 'backend-engineer', attempt: 1, status: 'failed' },
            { step_id: 'backend-engineer', attempt: 2, status: 'failed' }
          ],
          output: {
            verification_result: 'Runner failed.',
            risks: ['Step failed.'],
            next_steps: ['Inspect failed output.']
          }
        }
      ],
      retry_attempts: [
        { step_id: 'backend-engineer', attempt: 1, status: 'failed' },
        { step_id: 'backend-engineer', attempt: 2, status: 'failed' }
      ],
      failed_steps: [
        {
          step_id: 'backend-engineer',
          role: 'backend-engineer',
          attempts: 2,
          retry_exhausted: true,
          reason: 'Step runner failed after retries.'
        }
      ],
      cancelled_steps: [
        {
          step_id: 'frontend-engineer',
          role: 'frontend-engineer',
          reason: 'Cancelled after another step in the parallel batch failed.'
        }
      ],
      skipped_steps: [
        {
          step_id: 'reviewer',
          role: 'reviewer',
          reason: 'Skipped because an upstream parallel batch failed.'
        }
      ],
      risks: ['Workflow failed.'],
      next_steps: ['Inspect failed step logs.']
    }
  });

  const result = parseLogFile('failed-workflow.json', content);

  assert.equal(result.ok, true);
  assert.equal(result.run.retryAttempts.length, 2);
  assert.deepEqual(result.run.retryAttempts[0], {
    stepId: 'backend-engineer',
    attempt: 1,
    status: 'failed'
  });
  assert.equal(result.run.failedSteps.length, 1);
  assert.equal(result.run.failedSteps[0].retryExhausted, true);
  assert.equal(result.run.cancelledSteps[0].stepId, 'frontend-engineer');
  assert.equal(result.run.skippedSteps[0].stepId, 'reviewer');
  assert.equal(result.run.steps[0].retryAttempts.length, 2);
});

test('parseLogFile normalizes cost totals and per-step provider metadata', () => {
  const content = JSON.stringify({
    run_id: '20260426-workflow-real-cost-000_template',
    runner: 'workflow-real',
    workflow: 'parallel-review',
    task_id: '000_template',
    output: {
      final_status: 'real-complete',
      step_logs: [
        {
          step_id: 'backend-engineer',
          role: 'backend-engineer',
          cost_tracking: {
            enabled: true,
            currency: 'USD',
            unit: 'estimated',
            estimated_cost: 0.015,
            provider_metadata: {
              provider: 'codex',
              tool: 'codex-cli',
              model: 'gpt-5.4',
              input_tokens: 1000,
              output_tokens: 500,
              total_tokens: 1500,
              input_token_rate: 1,
              output_token_rate: 2,
              rate_unit_tokens: 1000000,
              source: 'usage'
            }
          },
          output: {
            verification_result: 'Completed.',
            risks: [],
            next_steps: []
          }
        }
      ],
      cost_tracking: {
        enabled: true,
        currency: 'USD',
        unit: 'estimated',
        estimated_total_cost: 0.015,
        step_costs: [
          {
            step_id: 'backend-engineer',
            role: 'backend-engineer',
            estimated_cost: 0.015,
            currency: 'USD',
            unit: 'estimated',
            provider_metadata: {
              provider: 'codex',
              tool: 'codex-cli',
              model: 'gpt-5.4',
              input_tokens: 1000,
              output_tokens: 500,
              total_tokens: 1500,
              source: 'usage'
            }
          }
        ]
      },
      risks: [],
      next_steps: []
    }
  });

  const result = parseLogFile('cost-workflow.json', content);

  assert.equal(result.ok, true);
  assert.deepEqual(result.run.cost, {
    enabled: true,
    currency: 'USD',
    unit: 'estimated',
    estimatedTotalCost: 0.015,
    stepCosts: [
      {
        stepId: 'backend-engineer',
        role: 'backend-engineer',
        estimatedCost: 0.015,
        currency: 'USD',
        unit: 'estimated',
        providerMetadata: {
          provider: 'codex',
          tool: 'codex-cli',
          model: 'gpt-5.4',
          inputTokens: 1000,
          outputTokens: 500,
          totalTokens: 1500,
          inputTokenRate: null,
          outputTokenRate: null,
          rateUnitTokens: null,
          source: 'usage'
        }
      }
    ]
  });
  assert.equal(result.run.steps[0].cost.estimatedCost, 0.015);
  assert.equal(result.run.steps[0].cost.providerMetadata.totalTokens, 1500);
});

test('parseLogFile normalizes workflow and step memory state', () => {
  const content = JSON.stringify({
    run_id: '20260426-workflow-real-memory-000_template',
    runner: 'workflow-real',
    workflow: 'implementation-review',
    task_id: '000_template',
    output: {
      final_status: 'real-complete',
      step_logs: [
        {
          step_id: 'implementer',
          role: 'implementer',
          memory: {
            enabled: true,
            scope: 'workflow',
            persistence: 'real',
            path: 'logs/memory/implementation-review-000_template.json',
            loaded: true,
            written: false,
            stale: true,
            overwrite_allowed: false
          },
          output: {
            verification_result: 'Memory loaded but not overwritten.',
            risks: [],
            next_steps: []
          }
        }
      ],
      memory: {
        enabled: true,
        scope: 'workflow',
        persistence: 'real',
        path: 'logs/memory/implementation-review-000_template.json',
        loaded: true,
        written: false,
        stale: true,
        overwrite_allowed: false
      },
      risks: [],
      next_steps: []
    }
  });

  const result = parseLogFile('memory-workflow.json', content);

  assert.equal(result.ok, true);
  assert.deepEqual(result.run.memory, {
    enabled: true,
    scope: 'workflow',
    persistence: 'real',
    path: 'logs/memory/implementation-review-000_template.json',
    loaded: true,
    written: false,
    stale: true,
    overwriteAllowed: false
  });
  assert.deepEqual(result.run.steps[0].memory, {
    enabled: true,
    scope: 'workflow',
    persistence: 'real',
    path: 'logs/memory/implementation-review-000_template.json',
    loaded: true,
    written: false,
    stale: true,
    overwriteAllowed: false
  });
});

test('parseLogFile collects verification evidence from captured logs', () => {
  const content = JSON.stringify({
    run_id: '20260426-workflow-implementation-review-000_template',
    runner: 'workflow-dry-run',
    workflow: 'implementation-review',
    task_id: '000_template',
    output: {
      final_status: 'dry-run-complete',
      verification_result: 'Workflow verification completed.',
      step_logs: [
        {
          step_id: 'tester',
          role: 'tester',
          output: {
            verification_result: 'PowerShell tests passed.',
            risks: [],
            next_steps: []
          }
        }
      ],
      risks: [],
      next_steps: []
    },
    invocation: {
      command: '.\\runner\\workflow.ps1',
      exit_code: 0
    }
  });

  const result = parseLogFile('verification-workflow.json', content);

  assert.equal(result.ok, true);
  assert.deepEqual(result.run.verificationEvidence, [
    {
      scope: 'workflow',
      label: 'implementation-review',
      command: '.\\runner\\workflow.ps1',
      exitCode: 0,
      result: 'Workflow verification completed.'
    },
    {
      scope: 'step',
      label: 'tester',
      command: '',
      exitCode: null,
      result: 'PowerShell tests passed.'
    }
  ]);
});
