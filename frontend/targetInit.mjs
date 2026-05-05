import { copyFile, mkdir, stat } from 'node:fs/promises';
import path from 'node:path';

import { REQUIRED_TARGET_ITEMS } from './targetValidation.mjs';

export async function createTargetInitPlan(targetRoot, templateRoot) {
  const actions = [];

  for (const item of REQUIRED_TARGET_ITEMS) {
    if (!(await itemExists(path.join(targetRoot, item.path), item.type))) {
      actions.push({ ...item });
    }
  }

  return {
    targetRoot,
    templateRoot,
    actions
  };
}

export async function initializeTarget(targetRoot, templateRoot, options = {}) {
  if (options.confirmed !== true) {
    throw new Error('Target initialization confirmation is required before writing files.');
  }

  const plan = await createTargetInitPlan(targetRoot, templateRoot);
  const created = [];

  for (const action of plan.actions.filter((item) => item.type === 'directory')) {
    await mkdir(path.join(targetRoot, action.path), { recursive: true });
    created.push({ ...action });
  }

  for (const action of plan.actions.filter((item) => item.type === 'file')) {
    const targetPath = path.join(targetRoot, action.path);

    if (await itemExists(targetPath, 'file')) {
      continue;
    }

    await mkdir(path.dirname(targetPath), { recursive: true });
    await copyFile(path.join(templateRoot, action.path), targetPath);
    created.push({ ...action });
  }

  return {
    targetRoot,
    created
  };
}

async function itemExists(itemPath, type) {
  try {
    const itemStat = await stat(itemPath);
    return type === 'directory' ? itemStat.isDirectory() : itemStat.isFile();
  } catch (error) {
    if (error.code === 'ENOENT') {
      return false;
    }

    throw error;
  }
}
