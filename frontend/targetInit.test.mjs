import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { createTargetInitPlan, initializeTarget } from './targetInit.mjs';

test('createTargetInitPlan returns missing folders and files without mutating target', async () => {
  const targetRoot = await mkdtemp(path.join(tmpdir(), 'target-init-'));
  const templateRoot = await createTemplateRoot();

  try {
    const plan = await createTargetInitPlan(targetRoot, templateRoot);

    assert.deepEqual(
      plan.actions.map((action) => `${action.type}:${action.path}`),
      [
        'directory:docs/plan/roadmaps',
        'directory:tasks',
        'directory:logs',
        'file:docs/plan/roadmaps/NEXT.md',
        'file:tasks/000_template.md',
        'file:logs/.gitkeep'
      ]
    );
    await assert.rejects(
      readFile(path.join(targetRoot, 'docs', 'plan', 'roadmaps', 'NEXT.md'), 'utf8'),
      /ENOENT/
    );
  } finally {
    await rm(targetRoot, { recursive: true, force: true });
    await rm(templateRoot, { recursive: true, force: true });
  }
});

test('initializeTarget requires confirmation and never overwrites existing files', async () => {
  const targetRoot = await mkdtemp(path.join(tmpdir(), 'target-init-'));
  const templateRoot = await createTemplateRoot();

  try {
    await mkdir(path.join(targetRoot, 'tasks'), { recursive: true });
    await writeFile(path.join(targetRoot, 'tasks', '000_template.md'), '# Existing\n');

    await assert.rejects(
      initializeTarget(targetRoot, templateRoot, { confirmed: false }),
      /Target initialization confirmation is required/
    );

    const result = await initializeTarget(targetRoot, templateRoot, { confirmed: true });

    assert.equal(result.created.some((item) => item.path === 'tasks/000_template.md'), false);
    assert.equal(
      await readFile(path.join(targetRoot, 'tasks', '000_template.md'), 'utf8'),
      '# Existing\n'
    );
    assert.equal(
      await readFile(path.join(targetRoot, 'docs', 'plan', 'roadmaps', 'NEXT.md'), 'utf8'),
      '# Template Next\n'
    );
  } finally {
    await rm(targetRoot, { recursive: true, force: true });
    await rm(templateRoot, { recursive: true, force: true });
  }
});

async function createTemplateRoot() {
  const templateRoot = await mkdtemp(path.join(tmpdir(), 'target-template-'));
  await mkdir(path.join(templateRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
  await mkdir(path.join(templateRoot, 'tasks'), { recursive: true });
  await mkdir(path.join(templateRoot, 'logs'), { recursive: true });
  await writeFile(path.join(templateRoot, 'docs', 'plan', 'roadmaps', 'NEXT.md'), '# Template Next\n');
  await writeFile(path.join(templateRoot, 'tasks', '000_template.md'), '# Template Task\n');
  await writeFile(path.join(templateRoot, 'logs', '.gitkeep'), '');
  return templateRoot;
}
