import assert from 'node:assert/strict';
import test from 'node:test';

import { normalizeWriteScope, writeScopesOverlap } from './writeScope.mjs';

test('normalizeWriteScope accepts repo-relative path prefixes', () => {
  assert.deepEqual(
    normalizeWriteScope(['src/app', 'docs\\plan']),
    {
      policy: 'repo-relative-prefix',
      paths: ['src/app', 'docs/plan']
    }
  );
});

test('normalizeWriteScope rejects absolute, parent, and empty path prefixes', () => {
  assert.throws(() => normalizeWriteScope(['C:\\work\\repo']), /repo-relative/);
  assert.throws(() => normalizeWriteScope(['../outside']), /repo-relative/);
  assert.throws(() => normalizeWriteScope(['']), /Write scope/);
});

test('writeScopesOverlap treats parent and child prefixes as overlapping', () => {
  assert.equal(writeScopesOverlap(['src'], ['src/app']), true);
  assert.equal(writeScopesOverlap(['docs/plan'], ['tasks']), false);
  assert.equal(writeScopesOverlap(['.'], ['tasks']), true);
});
