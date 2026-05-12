import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { toggleRoadmapItem } from './server.mjs';

test('toggleRoadmapItem flips unchecked to checked', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'toggle-test-'));

  try {
    await mkdir(path.join(repoRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    const content = [
      '# Roadmap',
      '',
      '- [ ] First item',
      '- [ ] Second item'
    ].join('\n');
    await writeFile(path.join(repoRoot, 'docs', 'plan', 'roadmaps', 'TEST.md'), content);

    const result = await toggleRoadmapItem(repoRoot, {
      name: 'docs/plan/roadmaps/TEST.md',
      itemIndex: 0
    });

    assert.equal(result.name, 'docs/plan/roadmaps/TEST.md');
    assert.match(result.content, /- \[x\] First item/);
    assert.match(result.content, /- \[ \] Second item/);
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});

test('toggleRoadmapItem flips checked to unchecked', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'toggle-test-'));

  try {
    await mkdir(path.join(repoRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    const content = [
      '# Roadmap',
      '',
      '- [x] First item',
      '- [ ] Second item'
    ].join('\n');
    await writeFile(path.join(repoRoot, 'docs', 'plan', 'roadmaps', 'TEST.md'), content);

    const result = await toggleRoadmapItem(repoRoot, {
      name: 'docs/plan/roadmaps/TEST.md',
      itemIndex: 0
    });

    assert.match(result.content, /- \[ \] First item/);
    assert.match(result.content, /- \[ \] Second item/);
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});

test('toggleRoadmapItem handles uppercase X', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'toggle-test-'));

  try {
    await mkdir(path.join(repoRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    const content = '- [X] First item\n';
    await writeFile(path.join(repoRoot, 'docs', 'plan', 'roadmaps', 'TEST.md'), content);

    const result = await toggleRoadmapItem(repoRoot, {
      name: 'docs/plan/roadmaps/TEST.md',
      itemIndex: 0
    });

    assert.match(result.content, /- \[ \] First item/);
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});

test('toggleRoadmapItem targets correct item by index', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'toggle-test-'));

  try {
    await mkdir(path.join(repoRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    const content = [
      '# Roadmap',
      '',
      '- [ ] First',
      '- [ ] Second',
      '- [ ] Third'
    ].join('\n');
    await writeFile(path.join(repoRoot, 'docs', 'plan', 'roadmaps', 'TEST.md'), content);

    const result = await toggleRoadmapItem(repoRoot, {
      name: 'docs/plan/roadmaps/TEST.md',
      itemIndex: 1
    });

    assert.match(result.content, /- \[ \] First/);
    assert.match(result.content, /- \[x\] Second/);
    assert.match(result.content, /- \[ \] Third/);
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});

test('toggleRoadmapItem works with asterisk list style', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'toggle-test-'));

  try {
    await mkdir(path.join(repoRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    const content = '* [ ] Item\n';
    await writeFile(path.join(repoRoot, 'docs', 'plan', 'roadmaps', 'TEST.md'), content);

    const result = await toggleRoadmapItem(repoRoot, {
      name: 'docs/plan/roadmaps/TEST.md',
      itemIndex: 0
    });

    assert.match(result.content, /\* \[x\] Item/);
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});

test('toggleRoadmapItem works with numbered list style', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'toggle-test-'));

  try {
    await mkdir(path.join(repoRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    const content = '1. [ ] Item\n';
    await writeFile(path.join(repoRoot, 'docs', 'plan', 'roadmaps', 'TEST.md'), content);

    const result = await toggleRoadmapItem(repoRoot, {
      name: 'docs/plan/roadmaps/TEST.md',
      itemIndex: 0
    });

    assert.match(result.content, /1\. \[x\] Item/);
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});

test('toggleRoadmapItem ignores non-checkbox lines', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'toggle-test-'));

  try {
    await mkdir(path.join(repoRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    const content = [
      '# Title',
      '',
      'Some text',
      '- [ ] First checkbox',
      'More text',
      '- [ ] Second checkbox'
    ].join('\n');
    await writeFile(path.join(repoRoot, 'docs', 'plan', 'roadmaps', 'TEST.md'), content);

    const result = await toggleRoadmapItem(repoRoot, {
      name: 'docs/plan/roadmaps/TEST.md',
      itemIndex: 1
    });

    assert.match(result.content, /- \[ \] First checkbox/);
    assert.match(result.content, /- \[x\] Second checkbox/);
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});

test('toggleRoadmapItem throws on negative index', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'toggle-test-'));

  try {
    await mkdir(path.join(repoRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    await writeFile(path.join(repoRoot, 'docs', 'plan', 'roadmaps', 'TEST.md'), '- [ ] Item\n');

    await assert.rejects(
      async () => toggleRoadmapItem(repoRoot, {
        name: 'docs/plan/roadmaps/TEST.md',
        itemIndex: -1
      }),
      /Item index must be a non-negative integer/
    );
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});

test('toggleRoadmapItem throws on out of range index', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'toggle-test-'));

  try {
    await mkdir(path.join(repoRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    await writeFile(path.join(repoRoot, 'docs', 'plan', 'roadmaps', 'TEST.md'), '- [ ] Item\n');

    await assert.rejects(
      async () => toggleRoadmapItem(repoRoot, {
        name: 'docs/plan/roadmaps/TEST.md',
        itemIndex: 5
      }),
      /Roadmap item index is out of range/
    );
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});

test('toggleRoadmapItem throws on non-integer index', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'toggle-test-'));

  try {
    await mkdir(path.join(repoRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    await writeFile(path.join(repoRoot, 'docs', 'plan', 'roadmaps', 'TEST.md'), '- [ ] Item\n');

    await assert.rejects(
      async () => toggleRoadmapItem(repoRoot, {
        name: 'docs/plan/roadmaps/TEST.md',
        itemIndex: 'not-a-number'
      }),
      /Item index must be a non-negative integer/
    );
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});

test('toggleRoadmapItem preserves file line endings', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'toggle-test-'));

  try {
    await mkdir(path.join(repoRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    const content = '- [ ] First\r\n- [ ] Second\r\n';
    await writeFile(path.join(repoRoot, 'docs', 'plan', 'roadmaps', 'TEST.md'), content);

    const result = await toggleRoadmapItem(repoRoot, {
      name: 'docs/plan/roadmaps/TEST.md',
      itemIndex: 0
    });

    // After toggle, line endings are normalized to \n
    assert.equal(result.content, '- [x] First\n- [ ] Second\n');
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});

test('toggleRoadmapItem writes changes to disk', async () => {
  const repoRoot = await mkdtemp(path.join(tmpdir(), 'toggle-test-'));

  try {
    await mkdir(path.join(repoRoot, 'docs', 'plan', 'roadmaps'), { recursive: true });
    const filePath = path.join(repoRoot, 'docs', 'plan', 'roadmaps', 'TEST.md');
    await writeFile(filePath, '- [ ] Item\n');

    await toggleRoadmapItem(repoRoot, {
      name: 'docs/plan/roadmaps/TEST.md',
      itemIndex: 0
    });

    const diskContent = await readFile(filePath, 'utf8');
    assert.equal(diskContent, '- [x] Item\n');
  } finally {
    await rm(repoRoot, { recursive: true, force: true });
  }
});
