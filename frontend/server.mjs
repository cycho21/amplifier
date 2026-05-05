import { createServer } from 'node:http';
import { mkdir, readdir, readFile, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { parseRoadmapFile } from './roadmapParser.mjs';

const frontendDir = path.dirname(fileURLToPath(import.meta.url));
const defaultRepoRoot = path.dirname(frontendDir);
const defaultPort = Number.parseInt(process.env.PORT || '4173', 10);

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
  const repoRoot = options.repoRoot || defaultRepoRoot;
  const staticRoot = options.staticRoot || frontendDir;

  return createServer(async (request, response) => {
    try {
      const url = new URL(request.url || '/', 'http://127.0.0.1');

      if (url.pathname === '/api/logs') {
        await sendJson(response, await readLogFiles(repoRoot));
        return;
      }

      if (url.pathname === '/api/roadmaps') {
        await sendJson(response, await readRoadmapFiles(repoRoot));
        return;
      }

      if (url.pathname === '/api/roadmaps/save') {
        if (request.method !== 'POST') {
          response.writeHead(405);
          response.end('Method not allowed');
          return;
        }

        const body = await readJsonRequest(request);
        await sendJson(response, await saveRoadmapFile(repoRoot, body.name, body.content));
        return;
      }

      if (url.pathname === '/api/roadmaps/run') {
        if (request.method !== 'POST') {
          response.writeHead(405);
          response.end('Method not allowed');
          return;
        }

        const body = await readJsonRequest(request);
        await sendJson(response, await runRoadmapItem(repoRoot, body));
        return;
      }

      await sendStatic(response, staticRoot, url.pathname);
    } catch (error) {
      response.writeHead(500, { 'content-type': 'application/json; charset=utf-8' });
      response.end(JSON.stringify({ error: error.message }));
    }
  });
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
