import assert from 'node:assert/strict';
import test from 'node:test';

import { parseRoadmapFile, summarizeRoadmaps } from './roadmapParser.mjs';

test('parseRoadmapFile extracts title, status, and sequence progress', () => {
  const content = [
    '# Next Roadmap: Operator UI',
    '',
    '## Status',
    '',
    'In progress.',
    '',
    '## Sequence',
    '',
    '1. [x] Add a small local web app scaffold under `frontend/`.',
    '2. [ ] Add a read-only roadmap dashboard from `docs/plan/roadmaps/`.'
  ].join('\n');

  const result = parseRoadmapFile('docs/plan/roadmaps/OPERATOR_UI.md', content);

  assert.equal(result.ok, true);
  assert.equal(result.roadmap.title, 'Next Roadmap: Operator UI');
  assert.equal(result.roadmap.status, 'In progress.');
  assert.equal(result.roadmap.completedCount, 1);
  assert.equal(result.roadmap.totalCount, 2);
  assert.deepEqual(result.roadmap.items, [
    {
      done: true,
      text: 'Add a small local web app scaffold under `frontend/`.'
    },
    {
      done: false,
      text: 'Add a read-only roadmap dashboard from `docs/plan/roadmaps/`.'
    }
  ]);
});

test('summarizeRoadmaps separates parsed roadmaps and files without checklists', () => {
  const summary = summarizeRoadmaps([
    {
      name: 'docs/plan/roadmaps/OPERATOR_UI.md',
      content: '# Next Roadmap: Operator UI\n\n## Status\n\nIn progress.\n\n- [x] One'
    },
    {
      name: 'docs/plan/roadmaps/EMPTY.md',
      content: '# Empty\n\nNo sequence.'
    }
  ]);

  assert.equal(summary.roadmaps.length, 1);
  assert.equal(summary.errors.length, 1);
  assert.equal(summary.errors[0].fileName, 'docs/plan/roadmaps/EMPTY.md');
});

test('summarizeRoadmaps reports an empty state when no roadmap files are loaded', () => {
  const summary = summarizeRoadmaps([]);

  assert.equal(summary.roadmaps.length, 0);
  assert.equal(summary.errors.length, 0);
  assert.equal(summary.emptyMessage, 'No roadmaps loaded.');
});
