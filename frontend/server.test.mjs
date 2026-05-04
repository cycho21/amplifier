import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { readLogFiles, readRoadmapFiles } from './server.mjs';

test('readLogFiles reads top-level JSON logs from the repo logs folder', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'operator-server-'));

  try {
    await mkdir(path.join(repoRoot, 'logs', 'prompts'), { recursive: true });
    await writeFile(path.join(repoRoot, 'logs', 'run-a.json'), '{"run_id":"a"}');
    await writeFile(path.join(repoRoot, 'logs', 'notes.txt'), 'ignore');
    await writeFile(path.join(repoRoot, 'logs', 'prompts', 'prompt.json'), '{"ignore":true}');

    const files = await readLogFiles(repoRoot);

    assert.deepEqual(files, [
      {
        name: 'logs/run-a.json',
        content: '{"run_id":"a"}'
      }
    ]);
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});

test('readRoadmapFiles reads markdown files from docs/plan/roadmaps', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'operator-server-'));

  try {
    await mkdir(path.join(repoRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    await writeFile(path.join(repoRoot, 'docs', 'plan', 'roadmaps', 'NEXT.md'), '# Next\n');
    await writeFile(path.join(repoRoot, 'docs', 'plan', 'roadmaps', 'ignore.txt'), 'ignore');

    const files = await readRoadmapFiles(repoRoot);

    assert.deepEqual(files, [
      {
        name: 'docs/plan/roadmaps/NEXT.md',
        content: '# Next\n'
      }
    ]);
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});
