import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { validateTargetStructure } from './targetValidation.mjs';

test('validateTargetStructure reports init-required with missing target files', async () => {
  const targetRoot = await mkdtemp(path.join(tmpdir(), 'target-validation-'));

  try {
    const result = await validateTargetStructure(targetRoot);

    assert.equal(result.status, 'init-required');
    assert.deepEqual(
      result.missing.map((item) => item.path),
      [
        'docs/plan/roadmaps',
        'tasks',
        'logs',
        'docs/plan/roadmaps/NEXT.md',
        'tasks/000_template.md',
        'logs/.gitkeep'
      ]
    );
  } finally {
    await rm(targetRoot, { recursive: true, force: true });
  }
});

test('validateTargetStructure reports ready when required target structure exists', async () => {
  const targetRoot = await mkdtemp(path.join(tmpdir(), 'target-validation-'));

  try {
    await mkdir(path.join(targetRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    await mkdir(path.join(targetRoot, 'tasks'), { recursive: true });
    await mkdir(path.join(targetRoot, 'logs'), { recursive: true });
    await writeFile(path.join(targetRoot, 'docs', 'plan', 'roadmaps', 'NEXT.md'), '# Next\n');
    await writeFile(path.join(targetRoot, 'tasks', '000_template.md'), '# Task\n');
    await writeFile(path.join(targetRoot, 'logs', '.gitkeep'), '');

    const result = await validateTargetStructure(targetRoot);

    assert.equal(result.status, 'ready');
    assert.deepEqual(result.missing, []);
  } finally {
    await rm(targetRoot, { recursive: true, force: true });
  }
});
