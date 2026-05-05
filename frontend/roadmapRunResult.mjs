export function getGeneratedTaskFile(runResult) {
  const log = parseRoadmapRunResult(runResult);
  return log?.output?.roadmap_item?.task_file || '';
}

export function createWorkflowPrefillFromRoadmapRun(runResult) {
  const log = parseRoadmapRunResult(runResult);
  const taskId = String(log?.task_id || '').trim();
  const taskFile = getGeneratedTaskFile(runResult);

  if (!taskId || !taskFile) {
    throw new Error('Generated roadmap task id is missing from the run result.');
  }

  return {
    taskId,
    workflowSpec: 'workflows/implementation-review.yaml',
    mode: 'dry-run',
    stepRunnerCommand: 'runner/codex.ps1',
    logOut: '',
    writeScope: '.'
  };
}

function parseRoadmapRunResult(runResult) {
  try {
    return JSON.parse(runResult?.content || '{}');
  } catch (error) {
    return {};
  }
}
