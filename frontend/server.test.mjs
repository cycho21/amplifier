import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { readLogFiles, readRoadmapFiles, runRoadmapItem, saveRoadmapFile } from './server.mjs';

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

test('saveRoadmapFile overwrites a roadmap file under docs/plan/roadmaps', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'operator-server-'));

  try {
    await mkdir(path.join(repoRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    const saved = await saveRoadmapFile(
      repoRoot,
      'docs/plan/roadmaps/NEXT.md',
      '# Updated\n'
    );

    assert.deepEqual(saved, {
      name: 'docs/plan/roadmaps/NEXT.md',
      content: '# Updated\n'
    });
    assert.equal(
      await readFile(path.join(repoRoot, 'docs', 'plan', 'roadmaps', 'NEXT.md'), 'utf8'),
      '# Updated\n'
    );
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});

test('saveRoadmapFile rejects paths outside docs/plan/roadmaps', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'operator-server-'));

  try {
    await mkdir(path.join(repoRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });

    await assert.rejects(
      saveRoadmapFile(repoRoot, 'docs/plan/roadmaps/../DECISIONS.md', '# Bad\n'),
      /Roadmap file must be a top-level markdown file/
    );
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});

test('runRoadmapItem writes a dry-run log for a selected roadmap item', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'operator-server-'));

  try {
    await mkdir(path.join(repoRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    await mkdir(path.join(repoRoot, 'logs'), { recursive: true });
    await writeFile(path.join(repoRoot, 'docs', 'plan', 'roadmaps', 'NEXT.md'), [
      '# Next',
      '',
      '## Status',
      'Not Started',
      '',
      '## Sequence',
      '1. [x] Finish previous work.',
      '2. [ ] Add roadmap run controls.'
    ].join('\n'));

    const result = await runRoadmapItem(repoRoot, {
      name: 'docs/plan/roadmaps/NEXT.md',
      itemIndex: 1
    });
    const written = JSON.parse(await readFile(path.join(repoRoot, result.name), 'utf8'));
    const task = await readFile(path.join(repoRoot, 'tasks', 'roadmap-NEXT-2.md'), 'utf8');

    assert.equal(result.name.startsWith('logs/roadmap-run-'), true);
    assert.equal(written.runner, 'operator-ui-dry-run');
    assert.equal(written.task_id, 'roadmap-NEXT-2');
    assert.deepEqual(written.inputs, [
      'docs/plan/roadmaps/NEXT.md',
      'tasks/roadmap-NEXT-2.md'
    ]);
    assert.equal(written.output.summary, 'Dry-run roadmap execution draft created for item 2.');
    assert.deepEqual(written.output.changed_files, []);
    assert.equal(written.output.verification_result, 'not-run');
    assert.match(written.output.next_steps[0], /runner\\workflow\.ps1/);
    assert.match(written.output.next_steps[0], /-Mode "dry-run"/);
    assert.deepEqual(written.output.roadmap_item, {
      file: 'docs/plan/roadmaps/NEXT.md',
      number: 2,
      text: 'Add roadmap run controls.',
      task_file: 'tasks/roadmap-NEXT-2.md'
    });
    assert.match(task, /## Task ID\n\n`roadmap-NEXT-2`/);
    assert.match(task, /## Goal\n\nAdd roadmap run controls\./);
    assert.match(task, /- `docs\/plan\/roadmaps\/NEXT.md`/);
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});
