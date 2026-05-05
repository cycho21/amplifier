import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createTargetRegistry,
  findActiveTarget,
  normalizeTargetId,
  registerTarget
} from './targetRegistry.mjs';

test('normalizeTargetId creates a stable lowercase id from a target name', () => {
  assert.equal(normalizeTargetId('Mini Amplifier'), 'mini-amplifier');
  assert.equal(normalizeTargetId(' Client_App 2026 '), 'client-app-2026');
});

test('createTargetRegistry normalizes targets and keeps the active target', () => {
  const registry = createTargetRegistry({
    activeTargetId: 'amplifier',
    targets: [
      {
        id: 'amplifier',
        name: 'Mini Amplifier',
        path: 'I:/amplifier'
      }
    ]
  });

  assert.deepEqual(registry, {
    activeTargetId: 'amplifier',
    targets: [
      {
        id: 'amplifier',
        name: 'Mini Amplifier',
        path: 'I:\\amplifier'
      }
    ]
  });
  assert.deepEqual(findActiveTarget(registry), registry.targets[0]);
});

test('registerTarget adds a target with a generated id and preserves active target', () => {
  const registry = createTargetRegistry({
    activeTargetId: 'amplifier',
    targets: [
      {
        id: 'amplifier',
        name: 'Mini Amplifier',
        path: 'I:\\amplifier'
      }
    ]
  });

  const updated = registerTarget(registry, {
    name: 'Client App',
    path: 'D:/work/client-app'
  });

  assert.equal(updated.activeTargetId, 'amplifier');
  assert.deepEqual(updated.targets[1], {
    id: 'client-app',
    name: 'Client App',
    path: 'D:\\work\\client-app'
  });
});

test('registerTarget sets the first target as active when registry is empty', () => {
  const updated = registerTarget(createTargetRegistry(), {
    name: 'Client App',
    path: 'D:\\work\\client-app'
  });

  assert.equal(updated.activeTargetId, 'client-app');
});

test('createTargetRegistry rejects duplicate ids and paths', () => {
  assert.throws(
    () => createTargetRegistry({
      targets: [
        { id: 'client-app', name: 'Client App', path: 'D:\\work\\client-app' },
        { id: 'client-app', name: 'Other App', path: 'D:\\work\\other-app' }
      ]
    }),
    /Duplicate target id/
  );
  assert.throws(
    () => createTargetRegistry({
      targets: [
        { id: 'client-app', name: 'Client App', path: 'D:\\work\\client-app' },
        { id: 'client-app-copy', name: 'Client App Copy', path: 'D:/work/client-app' }
      ]
    }),
    /Duplicate target path/
  );
});

test('createTargetRegistry rejects invalid target fields and active target ids', () => {
  assert.throws(
    () => createTargetRegistry({
      activeTargetId: 'missing',
      targets: [{ id: 'client-app', name: 'Client App', path: 'D:\\work\\client-app' }]
    }),
    /Active target id/
  );
  assert.throws(
    () => createTargetRegistry({
      targets: [{ id: '../bad', name: 'Bad', path: 'D:\\work\\bad' }]
    }),
    /Target id/
  );
  assert.throws(
    () => createTargetRegistry({
      targets: [{ id: 'bad', name: '', path: 'D:\\work\\bad' }]
    }),
    /Target name/
  );
  assert.throws(
    () => createTargetRegistry({
      targets: [{ id: 'bad', name: 'Bad', path: '' }]
    }),
    /Target path/
  );
});
