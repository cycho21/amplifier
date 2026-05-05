import { stat } from 'node:fs/promises';
import path from 'node:path';

export const REQUIRED_TARGET_ITEMS = [
  { type: 'directory', path: 'docs/plan/roadmaps' },
  { type: 'directory', path: 'tasks' },
  { type: 'directory', path: 'logs' },
  { type: 'file', path: 'docs/plan/roadmaps/NEXT.md' },
  { type: 'file', path: 'tasks/000_template.md' },
  { type: 'file', path: 'logs/.gitkeep' }
];

export async function validateTargetStructure(targetRoot, options = {}) {
  const missing = [];
  const checkStat = options.stat || stat;

  for (const item of REQUIRED_TARGET_ITEMS) {
    const exists = await targetItemExists(targetRoot, item, checkStat);

    if (!exists) {
      missing.push({ ...item });
    }
  }

  return {
    status: missing.length === 0 ? 'ready' : 'init-required',
    required: REQUIRED_TARGET_ITEMS.map((item) => ({ ...item })),
    missing
  };
}

async function targetItemExists(targetRoot, item, checkStat) {
  try {
    const itemStat = await checkStat(path.join(targetRoot, item.path));
    return item.type === 'directory' ? itemStat.isDirectory() : itemStat.isFile();
  } catch (error) {
    if (error.code === 'ENOENT') {
      return false;
    }

    throw error;
  }
}
