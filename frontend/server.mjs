import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { mkdir, readdir, readFile, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { createWorkflowExecutionRequest } from './executionRequest.mjs';
import { parseRoadmapFile } from './roadmapParser.mjs';
import { createRunIndex, finishRun, startRun } from './runIndex.mjs';
import { createTargetRegistry, findActiveTarget, normalizeTargetId, registerTarget } from './targetRegistry.mjs';
import { createTargetInitPlan, initializeTarget } from './targetInit.mjs';
import { validateTargetStructure } from './targetValidation.mjs';
import { normalizeWriteScope } from './writeScope.mjs';

const frontendDir = path.dirname(fileURLToPath(import.meta.url));
const defaultRepoRoot = path.dirname(frontendDir);
const defaultPort = Number.parseInt(process.env.PORT || '4173', 10);
const defaultTemplateRoot = path.join(defaultRepoRoot, 'templates', 'target-init');

export async function readLogFiles(repoRoot = defaultRepoRoot) {
  return readDirectoryFiles(path.join(repoRoot, 'logs'), 'logs', '.json');
}

export async function readRoadmapFiles(repoRoot = defaultRepoRoot) {
  return readDirectoryFiles(
    path.join(repoRoot, 'docs', 'plan', 'roadmaps'),
    path.join('docs', 'plan', 'roadmaps'),
    '.md'
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

  if (request.mode === 'real' && input.realExecutionConfirmed !== true) {
    throw new Error('Real execution server confirmation is required before invoking a real local runner command.');
  }

  request.writeScope = normalizeWriteScope(input.writeScope || ['.']);
  await assertExecutionInputFiles(operatorRoot, targetRoot, request);

  const invoke = options.invoke || invokeWorkflowCommand;
  const recordRunId = `execution-record-${request.taskId}-${timestamp.replace(/[-:.]/g, '')}`;
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

  let result;

  try {
    result = await invoke({ operatorRoot, targetRoot }, request);
  } catch (error) {
    result = {
      stdout: '',
      stderr: error.message,
      exitCode: 1
    };
  }

  await writeRunIndex(runIndexPath, finishRun(
    runningIndex,
    recordRunId,
    {
      exitCode: result.exitCode,
      finishedAt: new Date().toISOString()
    }
  ));
  const recordName = toBrowserPath(path.join(
    'logs',
    `${recordRunId}.json`
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

  return {
    name: recordName,
    content: `${JSON.stringify(record, null, 2)}\n`
  };
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

function invokeWorkflowCommand(roots, request) {
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
      stdout += chunk;
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

  return createServer(async (request, response) => {
    try {
      const url = new URL(request.url || '/', 'http://127.0.0.1');

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
        await sendJson(response, await executeWorkflowRequest(target.path, body, { operatorRoot }));
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
        '$dialog = New-Object System.Windows.Forms.FolderBrowserDialog',
        '$dialog.Description = "Select target repository folder"',
        'if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {',
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

async function readDirectoryFiles(directory, relativeDirectory, extension) {
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
    .filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith(extension))
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

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const server = createOperatorServer();
  server.listen(defaultPort, '127.0.0.1', () => {
    console.log(`Operator UI: http://127.0.0.1:${defaultPort}/`);
  });
}
