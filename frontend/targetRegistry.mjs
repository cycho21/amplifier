export function createTargetRegistry(input = {}) {
  const targets = Array.isArray(input.targets)
    ? input.targets.map(normalizeTarget)
    : [];
  const activeTargetId = normalizeOptionalActiveTargetId(input.activeTargetId, targets);

  assertUniqueTargets(targets);

  return {
    activeTargetId,
    targets
  };
}

export function registerTarget(registry, target) {
  const current = createTargetRegistry(registry);
  const normalizedTarget = normalizeTarget({
    ...target,
    id: target.id || normalizeTargetId(target.name)
  });

  return createTargetRegistry({
    activeTargetId: current.activeTargetId || normalizedTarget.id,
    targets: [...current.targets, normalizedTarget]
  });
}

export function findActiveTarget(registry) {
  const current = createTargetRegistry(registry);

  return current.targets.find((target) => target.id === current.activeTargetId) || null;
}

export function normalizeTargetId(value) {
  const id = String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');

  if (!isValidTargetId(id)) {
    throw new Error('Target id must contain only lowercase letters, numbers, and hyphens.');
  }

  return id;
}

function normalizeTarget(target) {
  const id = normalizeExplicitTargetId(target.id);
  const name = normalizeTargetName(target.name);
  const targetPath = normalizeTargetPath(target.path);

  return {
    id,
    name,
    path: targetPath
  };
}

function normalizeExplicitTargetId(value) {
  const id = String(value || '').trim();

  if (!isValidTargetId(id)) {
    throw new Error('Target id must contain only lowercase letters, numbers, and hyphens.');
  }

  return id;
}

function normalizeOptionalActiveTargetId(activeTargetId, targets) {
  if (targets.length === 0) {
    return '';
  }

  const normalizedId = activeTargetId
    ? normalizeTargetId(activeTargetId)
    : targets[0].id;

  if (!targets.some((target) => target.id === normalizedId)) {
    throw new Error('Active target id must match a registered target.');
  }

  return normalizedId;
}

function normalizeTargetName(value) {
  const name = String(value || '').trim();

  if (name.length === 0) {
    throw new Error('Target name is required.');
  }

  return name;
}

function normalizeTargetPath(value) {
  const targetPath = String(value || '').trim().replace(/\//g, '\\');

  if (targetPath.length === 0) {
    throw new Error('Target path is required.');
  }

  return targetPath;
}

function assertUniqueTargets(targets) {
  const ids = new Set();
  const paths = new Set();

  for (const target of targets) {
    const pathKey = target.path.toLowerCase();

    if (ids.has(target.id)) {
      throw new Error(`Duplicate target id: ${target.id}`);
    }

    if (paths.has(pathKey)) {
      throw new Error(`Duplicate target path: ${target.path}`);
    }

    ids.add(target.id);
    paths.add(pathKey);
  }
}

function isValidTargetId(value) {
  return /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(value);
}
