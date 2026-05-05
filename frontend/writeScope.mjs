export function normalizeWriteScope(value = ['.']) {
  const rawPaths = Array.isArray(value) ? value : [value];
  const paths = rawPaths.map(normalizeScopePath);

  if (paths.length === 0 || paths.some((item) => item.length === 0)) {
    throw new Error('Write scope must include at least one repo-relative path prefix.');
  }

  return {
    policy: 'repo-relative-prefix',
    paths: [...new Set(paths)]
  };
}

export function writeScopesOverlap(left, right) {
  const leftPaths = normalizeWriteScope(left).paths;
  const rightPaths = normalizeWriteScope(right).paths;

  return leftPaths.some((leftPath) =>
    rightPaths.some((rightPath) => scopePathOverlaps(leftPath, rightPath))
  );
}

function normalizeScopePath(value) {
  const normalized = String(value || '')
    .trim()
    .replace(/\\/g, '/')
    .replace(/\/+/g, '/')
    .replace(/\/$/g, '');

  if (normalized.length === 0) {
    throw new Error('Write scope must include at least one repo-relative path prefix.');
  }

  if (
    normalized.startsWith('/') ||
    /^[A-Za-z]:\//.test(normalized) ||
    normalized === '..' ||
    normalized.startsWith('../') ||
    normalized.includes('/../') ||
    normalized.endsWith('/..')
  ) {
    throw new Error('Write scope paths must be repo-relative path prefixes.');
  }

  return normalized === '' ? '.' : normalized;
}

function scopePathOverlaps(left, right) {
  if (left === '.' || right === '.') {
    return true;
  }

  return left === right || left.startsWith(`${right}/`) || right.startsWith(`${left}/`);
}
