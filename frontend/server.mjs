import { createServer } from 'node:http';
import { watch } from 'node:fs';
import { spawn } from 'node:child_process';
import { mkdir, readdir, readFile, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { createWorkflowExecutionRequest } from './executionRequest.mjs';
import { parseRoadmapFile } from './roadmapParser.mjs';
import { cancelRun, createRunIndex, finishRun, startRun } from './runIndex.mjs';
import { createTargetRegistry, findActiveTarget, normalizeTargetId, registerTarget } from './targetRegistry.mjs';
import { createTargetInitPlan, initializeTarget } from './targetInit.mjs';
import { validateTargetStructure } from './targetValidation.mjs';
import { normalizeWriteScope } from './writeScope.mjs';

const frontendDir = path.dirname(fileURLToPath(import.meta.url));
const defaultRepoRoot = path.dirname(frontendDir);
const defaultPort = Number.parseInt(process.env.PORT || '4173', 10);
const defaultTemplateRoot = path.join(defaultRepoRoot, 'templates', 'target-init');

export async function readLogFiles(repoRoot = defaultRepoRoot) {
  return readDirectoryFiles(
    path.join(repoRoot, 'logs'),
    'logs',
    '.json',
    (name) => {
      if (name.startsWith('roadmap-run-')) return false;
      if (name.startsWith('execution-record-roadmap-')) return false;
      // Filter out test files
      if (name === 'test-dry-run.json') return false;
      // Filter out test tasks
      if (name.includes('-000_template') || name.includes('-001_smoke_test')) return false;
      return true;
    }
  );
}

const ROADMAP_INDEX_FILES = new Set(['COMPLETED.md']);

export async function readRoadmapFiles(repoRoot = defaultRepoRoot) {
  return readDirectoryFiles(
    path.join(repoRoot, 'docs', 'plan', 'roadmaps'),
    path.join('docs', 'plan', 'roadmaps'),
    '.md',
    (name) => !ROADMAP_INDEX_FILES.has(name)
  );
}

export async function readTaskDraft(repoRoot = defaultRepoRoot, fileName) {
  const relativeName = normalizeTaskDraftFileName(fileName);

  return {
    name: toBrowserPath(relativeName),
    content: await readFile(path.join(repoRoot, relativeName), 'utf8')
  };
}

export async function readExecutionRunIndex(operatorRoot = defaultRepoRoot) {
  return readRunIndex(path.join(operatorRoot, '.operator', 'runs.json'));
}

export async function readExecutionStepLogs(repoRoot = defaultRepoRoot, runId) {
  const stepDir = path.join(repoRoot, 'logs', 'workflow-steps', runId);
  let entries;
  try {
    entries = await readdir(stepDir);
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
  const results = [];
  for (const name of entries) {
    if (!name.endsWith('.json') || name.endsWith('.retry-attempts.json')) continue;
    try {
      const content = await readFile(path.join(stepDir, name), 'utf8');
      results.push(JSON.parse(content.replace(/^﻿/, '')));
    } catch { /* skip malformed */ }
  }
  return results;
}

export async function readExecutionOptions(operatorRoot = defaultRepoRoot, targetRoot = operatorRoot) {
  const [tasks, workflows, runners] = await Promise.all([
    readDirectoryFileNames(path.join(targetRoot, 'tasks'), 'tasks', '.md'),
    readDirectoryFileNames(path.join(operatorRoot, 'workflows'), 'workflows', '.yaml'),
    readDirectoryFileNames(path.join(operatorRoot, 'runner'), 'runner', '.ps1')
  ]);

  return {
    tasks: tasks.map((filePath) => ({
      taskId: path.basename(filePath, path.extname(filePath)),
      path: filePath
    })),
    workflows,
    stepRunners: runners.filter((filePath) => filePath !== 'runner/workflow.ps1')
  };
}

export async function saveRoadmapFile(repoRoot = defaultRepoRoot, fileName, content) {
  const relativeName = normalizeRoadmapFileName(fileName);
  const filePath = path.join(repoRoot, relativeName);
  await writeFile(filePath, content, 'utf8');

  return {
    name: toBrowserPath(relativeName),
    content
  };
}

export async function toggleRoadmapItem(repoRoot = defaultRepoRoot, request = {}) {
  const relativeName = normalizeRoadmapFileName(request.name);
  const filePath = path.join(repoRoot, relativeName);
  const content = await readFile(filePath, 'utf8');
  const lines = content.split(/\r?\n/);

  const itemIndex = Number(request.itemIndex);

  if (!Number.isInteger(itemIndex) || itemIndex < 0) {
    throw new Error('Item index must be a non-negative integer.');
  }

  let checkboxCount = 0;
  let targetLineIndex = -1;

  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].match(/^\s*(?:[-*]|\d+\.)\s+\[(x|X| )\]\s+(.+)$/);
    if (match) {
      if (checkboxCount === itemIndex) {
        targetLineIndex = i;
        break;
      }
      checkboxCount++;
    }
  }

  if (targetLineIndex === -1) {
    throw new Error('Roadmap item index is out of range.');
  }

  const line = lines[targetLineIndex];
  const flipped = line.replace(/\[(x|X| )\]/, (match, check) => {
    return check.toLowerCase() === 'x' ? '[ ]' : '[x]';
  });

  lines[targetLineIndex] = flipped;
  const newContent = lines.join('\n');

  await writeFile(filePath, newContent, 'utf8');

  return {
    name: toBrowserPath(relativeName),
    content: newContent
  };
}

export async function runRoadmapItem(repoRoot = defaultRepoRoot, request = {}) {
  const relativeName = normalizeRoadmapFileName(request.name);
  const roadmapContent = await readFile(path.join(repoRoot, relativeName), 'utf8');
  const parsed = parseRoadmapFile(toBrowserPath(relativeName), roadmapContent);

  if (!parsed.ok) {
    throw new Error(parsed.error);
  }

  const itemIndex = Number(request.itemIndex);
  const item = parsed.roadmap.items[itemIndex];

  if (!Number.isInteger(itemIndex) || itemIndex < 0 || !item) {
    throw new Error('Roadmap item index is out of range.');
  }

  if (item.done) {
    throw new Error('Completed roadmap items cannot be run.');
  }

  const itemNumber = itemIndex + 1;
  const roadmapStem = path.basename(relativeName, path.extname(relativeName));
  const timestamp = new Date().toISOString().replace(/[-:.]/g, '');
  const taskId = `roadmap-${roadmapStem}-${itemNumber}`;
  const runId = `${taskId}-${timestamp}`;
  const taskName = toBrowserPath(path.join('tasks', `${taskId}.md`));
  const logName = toBrowserPath(path.join('logs', `roadmap-run-${roadmapStem}-${itemNumber}-${timestamp}.json`));
  const workflowLogName = toBrowserPath(path.join('logs', `roadmap-workflow-${taskId}-${timestamp}.json`));
  const workflowCommand = [
    '.\\runner\\workflow.ps1',
    '-WorkflowSpec "workflows/implementation-review.yaml"',
    `-TaskId "${taskId}"`,
    '-Mode "dry-run"',
    `-LogOut "${workflowLogName}"`
  ].join(' ');
  const log = {
    run_id: runId,
    runner: 'operator-ui-dry-run',
    role: 'roadmap-operator',
    task_id: taskId,
    inputs: [toBrowserPath(relativeName), taskName],
    output: {
      summary: `Dry-run roadmap execution draft created for item ${itemNumber}.`,
      changed_files: [],
      verification_result: 'not-run',
      risks: ['This run did not invoke an external runner.'],
      next_steps: [workflowCommand],
      roadmap_item: {
        file: toBrowserPath(relativeName),
        number: itemNumber,
        text: item.text,
        task_file: taskName
      }
    }
  };
  const task = formatRoadmapTaskDraft(taskId, item.text, toBrowserPath(relativeName), itemNumber);

  await mkdir(path.join(repoRoot, 'tasks'), { recursive: true });
  await mkdir(path.join(repoRoot, 'logs'), { recursive: true });
  await writeFile(path.join(repoRoot, taskName), task, 'utf8');
  await writeFile(path.join(repoRoot, logName), `${JSON.stringify(log, null, 2)}\n`, 'utf8');

  return {
    name: logName,
    content: `${JSON.stringify(log, null, 2)}\n`
  };
}

export async function executeWorkflowRequest(repoRoot = defaultRepoRoot, input = {}, options = {}) {
  if (input.confirmed !== true) {
    throw new Error('Execution confirmation is required before invoking a local runner command.');
  }

  const targetRoot = options.targetRoot || repoRoot;
  const operatorRoot = options.operatorRoot || repoRoot;
  const timestamp = options.timestamp || new Date().toISOString();
  const request = createWorkflowExecutionRequest(input, {
    timestamp
  });

request.writeScope = normalizeWriteScope(input.writeScope || ['.']);
  await assertExecutionInputFiles(operatorRoot, targetRoot, request);

  const invoke = options.invoke || invokeWorkflowCommand;
  const recordRunId = `execution-record-${request.taskId}-${timestamp.replace(/[-:.]/g, '')}`;
  request.runId = recordRunId;
  const targetId = input.targetId || 'default';
  const realExecutionMetadata = createRealExecutionMetadata(request, targetId);
  const runIndexPath = options.runIndexPath || path.join(operatorRoot, '.operator', 'runs.json');
  const runningIndex = startRun(await readRunIndex(runIndexPath), {
    runId: recordRunId,
    targetId,
    taskId: request.taskId,
    command: request.command,
    logPath: request.logOut,
    writeScope: request.writeScope,
    startedAt: timestamp,
    ...(realExecutionMetadata ? { realExecution: realExecutionMetadata.runIndex } : {})
  });
  await writeRunIndex(runIndexPath, runningIndex);

  const recordName = toBrowserPath(path.join('logs', `${recordRunId}.json`));

  const writeRecord = async (result) => {
    const currentIndex = await readRunIndex(runIndexPath);
    const stillTracked = currentIndex.runs.some((r) => r.runId === recordRunId);

    if (!stillTracked) {
      return; // cancelled — do not overwrite
    }

    await writeRunIndex(runIndexPath, finishRun(
      currentIndex,
      recordRunId,
      { exitCode: result.exitCode, finishedAt: new Date().toISOString() }
    ));
    const executionMessage = formatExecutionRecordMessage(request.mode, result.exitCode);
    const record = {
      run_id: recordRunId,
      runner: 'operator-ui-execution',
      role: 'operator-control',
      task_id: request.taskId,
      inputs: [
        request.workflowSpec,
        `tasks/${request.taskId}.md`,
        'runner/workflow.ps1',
        request.stepRunnerCommand.replace(/\\/g, '/').replace(/^\.\//, '')
      ],
      output: {
        summary: executionMessage.summary,
        changed_files: [request.logOut],
        verification_result: `exit ${result.exitCode}`,
        risks: executionMessage.risks,
        next_steps: executionMessage.nextSteps,
        execution: {
          command: request.command,
          stdout: result.stdout,
          stderr: result.stderr,
          exit_code: result.exitCode,
          log_path: request.logOut,
          write_scope: request.writeScope,
          ...(realExecutionMetadata ? { real_metadata: realExecutionMetadata.log } : {})
        }
      }
    };
    await mkdir(path.join(targetRoot, 'logs'), { recursive: true });
    await writeFile(path.join(targetRoot, recordName), `${JSON.stringify(record, null, 2)}\n`, 'utf8');
  };

  // Run in background — write a pending record immediately so the UI can track it
  const pendingRecord = {
    run_id: recordRunId,
    runner: 'operator-ui-execution',
    role: 'operator-control',
    task_id: request.taskId,
    inputs: [],
    output: {
      summary: 'Execution in progress...',
      changed_files: [],
      verification_result: 'pending',
      risks: [],
      next_steps: [],
      execution: {
        command: request.command,
        stdout: '',
        stderr: '',
        exit_code: null,
        log_path: request.logOut,
        write_scope: request.writeScope,
        ...(realExecutionMetadata ? { real_metadata: realExecutionMetadata.log } : {})
      }
    }
  };
  await mkdir(path.join(targetRoot, 'logs'), { recursive: true });
  await writeFile(path.join(targetRoot, recordName), `${JSON.stringify(pendingRecord, null, 2)}\n`, 'utf8');

  const clients = options.reloadClients;
  const onChunk = clients
    ? (chunk) => broadcast(clients, 'stdout-chunk', { runId: recordRunId, chunk })
    : undefined;

  const _done = invoke({ operatorRoot, targetRoot }, request, { onChunk })
    .then((result) => writeRecord(result))
    .catch((error) => writeRecord({ stdout: '', stderr: error.message, exitCode: 1 }));

  return { name: recordName, taskId: request.taskId, pending: true, _done };
}

function formatExecutionRecordMessage(mode, exitCode) {
  const real = mode === 'real';
  const label = real ? 'Real' : 'Dry-run';
  const lowerLabel = real ? 'real' : 'dry-run';

  if (exitCode === 0) {
    return {
      summary: `${label} workflow command completed.`,
      risks: [],
      nextSteps: ['Inspect the generated workflow log in Runs.']
    };
  }

  return {
    summary: `${label} workflow command failed.`,
    risks: [`The ${lowerLabel} workflow command exited with a non-zero code.`],
    nextSteps: [`Inspect stdout and stderr before retrying the ${lowerLabel} workflow.`]
  };
}

function createRealExecutionMetadata(request, targetId) {
  if (request.mode !== 'real') {
    return null;
  }

  return {
    runIndex: {
      mode: 'real',
      allowReal: request.allowReal === true,
      confirmation: 'RUN REAL',
      workflowSpec: request.workflowSpec,
      stepRunnerCommand: request.stepRunnerCommand,
      writeScope: request.writeScope
    },
    log: {
      mode: 'real',
      allow_real: request.allowReal === true,
      confirmation: 'RUN REAL',
      target_id: targetId,
      workflow_spec: request.workflowSpec,
      step_runner_command: request.stepRunnerCommand,
      write_scope: request.writeScope
    }
  };
}

async function assertExecutionInputFiles(operatorRoot, targetRoot, request) {
  const requiredPaths = [
    { root: operatorRoot, name: request.workflowSpec },
    { root: targetRoot, name: `tasks/${request.taskId}.md` },
    { root: operatorRoot, name: 'runner/workflow.ps1' },
    {
      root: operatorRoot,
      name: request.stepRunnerCommand.replace(/\\/g, '/').replace(/^\.\//, '')
    }
  ];

  for (const item of requiredPaths) {
    try {
      const fileStat = await stat(path.join(item.root, item.name));

      if (!fileStat.isFile()) {
        throw new Error();
      }
    } catch (error) {
      throw new Error(`Required execution input file not found: ${item.name}`);
    }
  }
}

function invokeWorkflowCommand(roots, request, { onChunk } = {}) {
  const stepRunnerCommand = resolveOperatorRunnerPath(roots.operatorRoot, request.stepRunnerCommand);
  const args = [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    path.join(roots.operatorRoot, 'runner', 'workflow.ps1'),
    '-WorkflowSpec',
    request.workflowSpec,
    '-TaskId',
    request.taskId,
    '-Mode',
    request.mode,
    '-StepRunnerCommand',
    stepRunnerCommand,
    '-LogOut',
    request.logOut,
    '-OperatorRoot',
    roots.operatorRoot,
    '-TargetRoot',
    roots.targetRoot
  ];

  if (request.runId) {
    args.push('-RunId', request.runId);
  }

  if (request.allowReal === true) {
    args.push('-AllowReal');
  }

  return new Promise((resolve) => {
    const child = spawn(
      'powershell.exe',
      args,
      { cwd: roots.targetRoot }
    );
    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (chunk) => {
      const text = chunk.toString();
      stdout += text;
      if (onChunk) onChunk(text);
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk;
    });
    child.on('error', (error) => {
      stderr += error.message;
      resolve({ stdout, stderr, exitCode: 1 });
    });
    child.on('close', (code) => {
      resolve({ stdout, stderr, exitCode: code ?? 1 });
    });
  });
}

function resolveOperatorRunnerPath(operatorRoot, stepRunnerCommand) {
  const normalized = stepRunnerCommand.replace(/\\/g, '/').replace(/^\.\//, '');
  return path.join(operatorRoot, normalized);
}

export async function readTargetRegistry(operatorRoot = defaultRepoRoot) {
  const statePath = path.join(operatorRoot, '.operator', 'targets.json');
  const examplePath = path.join(operatorRoot, '.operator', 'targets.example.json');

  for (const filePath of [statePath, examplePath]) {
    try {
      return createTargetRegistry(JSON.parse(await readFile(filePath, 'utf8')));
    } catch (error) {
      if (error.code !== 'ENOENT') {
        throw error;
      }
    }
  }

  return createTargetRegistry({
    activeTargetId: 'amplifier',
    targets: [
      {
        id: 'amplifier',
        name: 'Mini Amplifier',
        path: operatorRoot
      }
    ]
  });
}

export async function writeTargetRegistry(operatorRoot = defaultRepoRoot, registry) {
  const normalized = createTargetRegistry(registry);
  const statePath = path.join(operatorRoot, '.operator', 'targets.json');
  await mkdir(path.dirname(statePath), { recursive: true });
  await writeFile(statePath, `${JSON.stringify(normalized, null, 2)}\n`, 'utf8');
  return normalized;
}

function formatRoadmapTaskDraft(taskId, goal, roadmapFile, itemNumber) {
  return [
    '# Roadmap Task Draft',
    '',
    '## Task ID',
    '',
    `\`${taskId}\``,
    '',
    '## Title',
    '',
    goal,
    '',
    '## Goal',
    '',
    goal,
    '',
    '## Background',
    '',
    'This task was generated from an Operator UI roadmap run request.',
    '',
    'Reference documents:',
    '',
    `- \`${roadmapFile}\``,
    '- `docs/plan/CONTRACT.md`',
    '- `docs/plan/MVP.md`',
    '',
    '## Scope',
    '',
    'Allowed changes:',
    '',
    '- Modify only files directly required by the selected roadmap item.',
    '',
    'Out of scope:',
    '',
    '- Do not execute unrelated roadmap items.',
    '- Do not switch to real runner mode unless explicitly requested.',
    '',
    '## Requirements',
    '',
    `- Complete roadmap item ${itemNumber}: ${goal}`,
    '- Keep the change minimal and verifiable.',
    '- Update relevant roadmap progress notes if the work changes product behavior.',
    '',
    '## Constraints',
    '',
    '- Follow the execution contract in `docs/plan/CONTRACT.md`.',
    '- Keep dry-run behavior deterministic unless real execution is explicitly enabled.',
    '- Report incomplete work explicitly.',
    '',
    '## Verification',
    '',
    'Run the narrowest relevant checks for this task.',
    '',
    'Required verification:',
    '',
    '- Check that all required files exist.',
    '- Check that generated or edited files can be read as UTF-8 text.',
    '- Run task-specific tests for changed behavior.',
    '',
    '## Expected Output',
    '',
    'The agent response must include:',
    '',
    '- `summary`',
    '- `changed_files`',
    '- `verification_result`',
    '- `risks`',
    '- `next_steps`',
    '',
    '## Risks',
    '',
    '- The roadmap item may need refinement before real execution.',
    '',
    '## Notes',
    '',
    'Generated by Operator UI roadmap run controls.',
    ''
  ].join('\n');
}

export function createOperatorServer(options = {}) {
  const operatorRoot = options.operatorRoot || options.repoRoot || defaultRepoRoot;
  const staticRoot = options.staticRoot || frontendDir;
  const templateRoot = options.templateRoot || defaultTemplateRoot;
  const reloadClients = options.reloadClients || new Set();

  return createServer(async (request, response) => {
    try {
      const url = new URL(request.url || '/', 'http://127.0.0.1');

      if (url.pathname === '/api/watch') {
        response.writeHead(200, {
          'content-type': 'text/event-stream',
          'cache-control': 'no-cache',
          'connection': 'keep-alive'
        });
        response.write('data: connected\n\n');
        reloadClients.add(response);
        request.on('close', () => reloadClients.delete(response));
        return;
      }

      if (url.pathname === '/api/targets') {
        if (request.method === 'GET') {
          await sendJson(response, await readTargetsWithReadiness(operatorRoot));
          return;
        }

        if (request.method === 'POST') {
          const body = await readJsonRequest(request);
          const registry = await readTargetRegistry(operatorRoot);
          const updated = registerTarget(registry, {
            id: body.id || normalizeTargetId(body.name),
            name: body.name,
            path: body.path
          });
          await sendJson(response, await writeTargetRegistry(operatorRoot, updated));
          return;
        }

        response.writeHead(405);
        response.end('Method not allowed');
        return;
      }

      if (url.pathname === '/api/targets/active') {
        if (request.method !== 'PATCH') {
          response.writeHead(405);
          response.end('Method not allowed');
          return;
        }

        const body = await readJsonRequest(request);
        const registry = await readTargetRegistry(operatorRoot);
        const updated = { ...registry, activeTargetId: body.targetId };
        await sendJson(response, await writeTargetRegistry(operatorRoot, updated));
        return;
      }

      if (url.pathname === '/api/targets/pick-folder') {
        if (request.method !== 'POST') {
          response.writeHead(405);
          response.end('Method not allowed');
          return;
        }

        await sendJson(response, await pickTargetFolder(options));
        return;
      }

      if (url.pathname === '/api/targets/init-plan') {
        if (request.method !== 'POST') {
          response.writeHead(405);
          response.end('Method not allowed');
          return;
        }

        const body = await readJsonRequest(request);
        const target = await resolveTarget(operatorRoot, body.targetId);
        await sendJson(response, await createTargetInitPlan(target.path, templateRoot));
        return;
      }

      if (url.pathname === '/api/targets/init') {
        if (request.method !== 'POST') {
          response.writeHead(405);
          response.end('Method not allowed');
          return;
        }

        const body = await readJsonRequest(request);
        const target = await resolveTarget(operatorRoot, body.targetId);
        await sendJson(response, await initializeTarget(target.path, templateRoot, body));
        return;
      }

      if (url.pathname === '/api/logs') {
        const target = await resolveTarget(operatorRoot, url.searchParams.get('targetId'));
        await sendJson(response, await readLogFiles(target.path));
        return;
      }

      if (url.pathname === '/api/roadmaps') {
        const target = await resolveTarget(operatorRoot, url.searchParams.get('targetId'));
        await sendJson(response, await readRoadmapFiles(target.path));
        return;
      }

      if (url.pathname === '/api/tasks/read') {
        const target = await resolveTarget(operatorRoot, url.searchParams.get('targetId'));
        await sendJson(response, await readTaskDraft(target.path, url.searchParams.get('name')));
        return;
      }

      if (url.pathname === '/api/roadmaps/save') {
        if (request.method !== 'POST') {
          response.writeHead(405);
          response.end('Method not allowed');
          return;
        }

        const body = await readJsonRequest(request);
        const target = await resolveTarget(operatorRoot, body.targetId);
        await sendJson(response, await saveRoadmapFile(target.path, body.name, body.content));
        return;
      }

      if (url.pathname === '/api/roadmaps/toggle') {
        if (request.method !== 'PATCH') {
          response.writeHead(405);
          response.end('Method not allowed');
          return;
        }

        const body = await readJsonRequest(request);
        const target = await resolveTarget(operatorRoot, body.targetId);
        await sendJson(response, await toggleRoadmapItem(target.path, body));
        return;
      }

      if (url.pathname === '/api/roadmaps/run') {
        if (request.method !== 'POST') {
          response.writeHead(405);
          response.end('Method not allowed');
          return;
        }

        const body = await readJsonRequest(request);
        const target = await resolveTarget(operatorRoot, body.targetId);
        await sendJson(response, await runRoadmapItem(target.path, body));
        return;
      }

      if (url.pathname === '/api/executions/run') {
        if (request.method !== 'POST') {
          response.writeHead(405);
          response.end('Method not allowed');
          return;
        }

        const body = await readJsonRequest(request);
        const target = await resolveTarget(operatorRoot, body.targetId);
        await sendJson(response, await executeWorkflowRequest(target.path, body, { operatorRoot, reloadClients }));
        return;
      }

      if (url.pathname === '/api/executions') {
        if (request.method !== 'GET') {
          response.writeHead(405);
          response.end('Method not allowed');
          return;
        }

        await sendJson(response, await readExecutionRunIndex(operatorRoot));
        return;
      }

      if (url.pathname.startsWith('/api/executions/') && url.pathname !== '/api/executions/run') {
        const runId = decodeURIComponent(url.pathname.slice('/api/executions/'.length));

        if (url.pathname.endsWith('/steps')) {
          if (request.method !== 'GET') {
            response.writeHead(405);
            response.end('Method not allowed');
            return;
          }
          const bareRunId = runId.replace(/\/steps$/, '');
          const runIndexPath = path.join(operatorRoot, '.operator', 'runs.json');
          const index = await readRunIndex(runIndexPath);
          const run = index.runs.find((r) => r.runId === bareRunId);
          const targetPath = run
            ? (await resolveTarget(operatorRoot, run.targetId)).path
            : operatorRoot;
          await sendJson(response, await readExecutionStepLogs(targetPath, bareRunId));
          return;
        }

        if (request.method !== 'DELETE') {
          response.writeHead(405);
          response.end('Method not allowed');
          return;
        }

        const runIndexPath = path.join(operatorRoot, '.operator', 'runs.json');
        const index = await readRunIndex(runIndexPath);
        const run = index.runs.find((r) => r.runId === runId);

        if (!run) {
          response.writeHead(404);
          response.end('Run not found');
          return;
        }

        await writeRunIndex(runIndexPath, cancelRun(index, runId));

        const target = await resolveTarget(operatorRoot, run.targetId);
        const recordFile = path.join(target.path, 'logs', `${runId}.json`);

        try {
          const existing = JSON.parse(await readFile(recordFile, 'utf8'));
          existing.output.verification_result = 'cancelled';
          existing.output.summary = 'Execution cancelled by user.';
          existing.output.execution.exit_code = 1;
          await writeFile(recordFile, `${JSON.stringify(existing, null, 2)}\n`, 'utf8');
        } catch {
          // file may not exist yet — ignore
        }

        await sendJson(response, { ok: true });
        return;
      }

      if (url.pathname === '/api/execution-options') {
        if (request.method !== 'GET') {
          response.writeHead(405);
          response.end('Method not allowed');
          return;
        }

        const target = await resolveTarget(operatorRoot, url.searchParams.get('targetId'));
        await sendJson(response, await readExecutionOptions(operatorRoot, target.path));
        return;
      }

      if (url.pathname === '/api/browse') {
        await sendJson(response, await browseDirectory(url.searchParams.get('path') || ''));
        return;
      }

      await sendStatic(response, staticRoot, url.pathname);
    } catch (error) {
      response.writeHead(500, { 'content-type': 'application/json; charset=utf-8' });
      response.end(JSON.stringify({ error: error.message }));
    }
  });
}

async function readTargetsWithReadiness(operatorRoot) {
  const registry = await readTargetRegistry(operatorRoot);
  const targets = await Promise.all(
    registry.targets.map(async (target) => ({
      ...target,
      readiness: await validateTargetStructure(target.path)
    }))
  );

  return {
    activeTargetId: registry.activeTargetId,
    targets
  };
}

async function resolveTarget(operatorRoot, targetId) {
  const registry = await readTargetRegistry(operatorRoot);
  const normalizedId = targetId ? normalizeTargetId(targetId) : registry.activeTargetId;
  const target = registry.targets.find((item) => item.id === normalizedId) || findActiveTarget(registry);

  if (!target) {
    throw new Error('No registered target repository is available.');
  }

  return target;
}

async function browseDirectory(dirPath) {
  if (!dirPath) {
    const drives = [];
    for (const letter of 'CDEFGHIJKLMNOPQRSTUVWXYZ') {
      try {
        await stat(`${letter}:\\`);
        drives.push({ name: `${letter}:`, path: `${letter}:\\` });
      } catch { }
    }
    return { path: '', parent: null, entries: drives };
  }

  const resolved = path.resolve(dirPath);
  const parentPath = path.dirname(resolved);
  const parent = resolved !== parentPath ? parentPath : '';
  const entries = await readdir(resolved, { withFileTypes: true });
  const dirs = entries
    .filter((e) => e.isDirectory() && !e.name.startsWith('.'))
    .map((e) => ({ name: e.name, path: path.join(resolved, e.name) }))
    .sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));

  return { path: resolved, parent, entries: dirs };
}

async function pickTargetFolder(options) {
  if (options.pickFolder) {
    return options.pickFolder();
  }

  return pickWindowsFolder();
}

function pickWindowsFolder() {
  return new Promise((resolve) => {
    const child = spawn('powershell.exe', [
      '-NoProfile',
      '-STA',
      '-Command',
      [
        'Add-Type -AssemblyName System.Windows.Forms',
        '$owner = New-Object System.Windows.Forms.Form',
        '$owner.TopMost = $true',
        '$dialog = New-Object System.Windows.Forms.FolderBrowserDialog',
        '$dialog.Description = "Select target repository folder"',
        'if ($dialog.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {',
        '  [pscustomobject]@{ cancelled = $false; path = $dialog.SelectedPath; name = [System.IO.Path]::GetFileName($dialog.SelectedPath) } | ConvertTo-Json -Compress',
        '} else {',
        '  [pscustomobject]@{ cancelled = $true; path = ""; name = "" } | ConvertTo-Json -Compress',
        '}'
      ].join('; ')
    ]);
    let stdout = '';

    child.stdout.on('data', (chunk) => {
      stdout += chunk;
    });
    child.on('error', () => {
      resolve({ cancelled: true, path: '', name: '' });
    });
    child.on('close', () => {
      try {
        resolve(JSON.parse(stdout || '{}'));
      } catch (error) {
        resolve({ cancelled: true, path: '', name: '' });
      }
    });
  });
}

async function readRunIndex(runIndexPath) {
  try {
    return createRunIndex(JSON.parse(await readFile(runIndexPath, 'utf8')));
  } catch (error) {
    if (error.code === 'ENOENT') {
      return createRunIndex();
    }

    throw error;
  }
}

async function writeRunIndex(runIndexPath, index) {
  await mkdir(path.dirname(runIndexPath), { recursive: true });
  await writeFile(runIndexPath, `${JSON.stringify(createRunIndex(index), null, 2)}\n`, 'utf8');
}

function normalizeRoadmapFileName(fileName) {
  const normalized = typeof fileName === 'string' ? fileName.replace(/\\/g, '/') : '';
  const roadmapPrefix = 'docs/plan/roadmaps/';
  const leafName = normalized.startsWith(roadmapPrefix)
    ? normalized.slice(roadmapPrefix.length)
    : '';

  if (
    leafName.length === 0 ||
    leafName.includes('/') ||
    leafName.includes('..') ||
    !leafName.toLowerCase().endsWith('.md')
  ) {
    throw new Error('Roadmap file must be a top-level markdown file under docs/plan/roadmaps.');
  }

  return path.join('docs', 'plan', 'roadmaps', leafName);
}

function normalizeTaskDraftFileName(fileName) {
  const normalized = typeof fileName === 'string' ? fileName.replace(/\\/g, '/') : '';
  const taskPrefix = 'tasks/';
  const leafName = normalized.startsWith(taskPrefix)
    ? normalized.slice(taskPrefix.length)
    : '';

  if (
    leafName.length === 0 ||
    leafName.includes('/') ||
    leafName.includes('..') ||
    !leafName.startsWith('roadmap-') ||
    !leafName.toLowerCase().endsWith('.md')
  ) {
    throw new Error('Task draft file must be a generated roadmap task under tasks/.');
  }

  return path.join('tasks', leafName);
}

async function readJsonRequest(request) {
  let body = '';

  for await (const chunk of request) {
    body += chunk;
  }

  return JSON.parse(body || '{}');
}

async function readDirectoryFiles(directory, relativeDirectory, extension, nameFilter = () => true) {
  let entries;

  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch (error) {
    if (error.code === 'ENOENT') {
      return [];
    }

    throw error;
  }

  const files = entries
    .filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith(extension) && nameFilter(entry.name))
    .map((entry) => entry.name)
    .sort((left, right) => left.localeCompare(right));

  return Promise.all(
    files.map(async (fileName) => ({
      name: toBrowserPath(path.join(relativeDirectory, fileName)),
      content: await readFile(path.join(directory, fileName), 'utf8')
    }))
  );
}

async function readDirectoryFileNames(directory, relativeDirectory, extension) {
  let entries;

  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch (error) {
    if (error.code === 'ENOENT') {
      return [];
    }

    throw error;
  }

  return entries
    .filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith(extension))
    .map((entry) => toBrowserPath(path.join(relativeDirectory, entry.name)))
    .sort((left, right) => left.localeCompare(right));
}

async function sendJson(response, value) {
  response.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
  response.end(JSON.stringify(value));
}

async function sendStatic(response, staticRoot, requestedPath) {
  const relativePath = requestedPath === '/' ? 'index.html' : requestedPath.slice(1);
  const resolvedPath = path.resolve(staticRoot, relativePath);
  const resolvedRoot = path.resolve(staticRoot);

  if (!resolvedPath.startsWith(resolvedRoot)) {
    response.writeHead(403);
    response.end('Forbidden');
    return;
  }

  try {
    const fileStat = await stat(resolvedPath);

    if (!fileStat.isFile()) {
      response.writeHead(404);
      response.end('Not found');
      return;
    }

    response.writeHead(200, { 'content-type': contentTypeFor(resolvedPath) });
    response.end(await readFile(resolvedPath));
  } catch (error) {
    if (error.code === 'ENOENT') {
      response.writeHead(404);
      response.end('Not found');
      return;
    }

    throw error;
  }
}

function contentTypeFor(filePath) {
  if (filePath.endsWith('.html')) {
    return 'text/html; charset=utf-8';
  }

  if (filePath.endsWith('.js') || filePath.endsWith('.mjs')) {
    return 'text/javascript; charset=utf-8';
  }

  if (filePath.endsWith('.css')) {
    return 'text/css; charset=utf-8';
  }

  return 'application/octet-stream';
}

function toBrowserPath(filePath) {
  return filePath.split(path.sep).join('/');
}

async function clearStuckRuns(operatorRoot) {
  const runIndexPath = path.join(operatorRoot, '.operator', 'runs.json');
  try {
    const index = await readRunIndex(runIndexPath);
    const hadStuck = index.runs.some((r) => r.status === 'running');
    if (!hadStuck) return;
    const fixed = {
      ...index,
      runs: index.runs.map((r) =>
        r.status === 'running'
          ? { ...r, status: 'failed', finishedAt: new Date().toISOString(), exitCode: 1 }
          : r
      )
    };
    await writeRunIndex(runIndexPath, fixed);
    console.log('Cleared stuck running tasks from previous session.');
  } catch {
    // no runs.json yet — nothing to clear
  }
}

function broadcast(clients, event, data) {
  const payload = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  for (const res of clients) {
    try { res.write(payload); } catch {}
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await clearStuckRuns(defaultRepoRoot);
  const reloadClients = new Set();
  const server = createOperatorServer({ reloadClients });

  // Watch frontend files → reload
  let reloadTimeout = null;
  watch(frontendDir, { recursive: false }, (_, filename) => {
    if (!filename || filename.endsWith('.json')) return;
    clearTimeout(reloadTimeout);
    reloadTimeout = setTimeout(() => broadcast(reloadClients, 'reload', {}), 300);
  });

  // Watch runs.json → workflow completion
  const runsJsonPath = path.join(defaultRepoRoot, '.operator', 'runs.json');
  watch(runsJsonPath, async () => {
    broadcast(reloadClients, 'workflow-update', { timestamp: Date.now() });
  });

  // Watch workflow-steps dir → step events
  const stepsDir = path.join(defaultRepoRoot, 'logs', 'workflow-steps');
  await mkdir(stepsDir, { recursive: true });
  watch(stepsDir, { recursive: true }, async (_, filename) => {
    if (!filename) return;

    // Recursive watch on Windows returns "runId\file.json" — normalise to forward slashes
    const normalizedFilename = filename.replace(/\\/g, '/');
    const parts = normalizedFilename.split('/');
    const bareFilename = parts[parts.length - 1];
    const watchedRunId = parts.length > 1 ? parts[0] : null;

    // Step started: .attempts file updated
    if (bareFilename.endsWith('.json.attempts')) {
      const jsonFilename = bareFilename.replace(/\.attempts$/, '');
      const base = jsonFilename.replace(/\.json$/, '');
      // Parse: implementation-review-architect-roadmap-TASK-1.json
      // Format: {workflow}-{stepId}-{taskId}.json
      const match = base.match(/^(.+?)-([^-]+)-(.+)$/);
      if (match) {
        const [, , stepId, taskId] = match;
        broadcast(reloadClients, 'step', {
          taskId,
          stepId,
          status: 'in-progress',
          summary: '',
          fileName: jsonFilename,
          runId: watchedRunId
        });
      }
      return;
    }

    // Step completed: .json file created (ignore runner-internal files)
    if (bareFilename.endsWith('.json') && !bareFilename.endsWith('.retry-attempts.json')) {
      try {
        const stepFilePath = watchedRunId
          ? path.join(stepsDir, watchedRunId, bareFilename)
          : path.join(stepsDir, bareFilename);
        const content = await readFile(stepFilePath, 'utf8');
        const data = JSON.parse(content.replace(/^﻿/, ''));
        broadcast(reloadClients, 'step', {
          taskId: data.task_id,
          stepId: data.role,
          status: 'completed',
          summary: data.output?.summary || '',
          fileName: bareFilename,
          runId: watchedRunId
        });
      } catch {}
    }
  });

  server.listen(defaultPort, '127.0.0.1', () => {
    console.log(`Operator UI: http://127.0.0.1:${defaultPort}/`);
  });
}
