import { createServer } from 'node:http';
import { readdir, readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

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

      await sendStatic(response, staticRoot, url.pathname);
    } catch (error) {
      response.writeHead(500, { 'content-type': 'application/json; charset=utf-8' });
      response.end(JSON.stringify({ error: error.message }));
    }
  });
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
