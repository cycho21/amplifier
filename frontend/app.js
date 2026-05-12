import { summarizeRuns } from './logParser.mjs';
import { createWorkflowExecutionRequest } from './executionRequest.mjs';
import {
  createWorkflowControlState,
  formatWorkflowConfirmationMessage
} from './executionControlState.mjs';
import { normalizeTargetId } from './targetRegistry.mjs';
import {
  createRoadmapDraftExport,
  createRoadmapDraftFromFormData,
  createRoadmapDraftFromMarkdown,
  validateRoadmapDraft
} from './roadmapDraft.mjs';
import { summarizeRoadmaps } from './roadmapParser.mjs';
import {
  createRetryPrefillFromExecutionRun,
  getWorkflowLogReferenceState,
  summarizeExecutionRequests
} from './executionRecords.mjs';
import {
  createWorkflowPrefillFromRoadmapRun,
  getGeneratedTaskFile
} from './roadmapRunResult.mjs';

const refreshButton = document.querySelector('#refresh-data');
const targetSelect = document.querySelector('#target-select');
const targetStatus = document.querySelector('#target-status');
const registerTargetButton = document.querySelector('#register-target');
const initTargetButton = document.querySelector('#init-target');
const roadmapDraftForm = document.querySelector('#roadmap-draft-form');
const workflowExecutionForm = document.querySelector('#workflow-execution-form');
const workflowCommandPreview = document.querySelector('#workflow-command-preview');
const workflowExecutionStatus = document.querySelector('#workflow-execution-status');
const workflowExecuteButton = document.querySelector('#workflow-execute');
const executionRequestList = document.querySelector('#execution-request-list');
const runConsoleBuffers = new Map();
const executionModal = document.querySelector('#execution-modal');
const executionModalClose = document.querySelector('#execution-modal-close');
const executionModalForm = document.querySelector('#execution-modal-form');
const executionModalStatus = document.querySelector('#execution-modal-status');
const roadmapReviewModal = document.querySelector('#roadmap-review-modal');
const roadmapReviewClose = document.querySelector('#roadmap-review-close');
const roadmapReviewBody = document.querySelector('#roadmap-review-body');
const runList = document.querySelector('#run-list');
const errorList = document.querySelector('#error-list');
const roadmapList = document.querySelector('#roadmap-list');
const roadmapErrorList = document.querySelector('#roadmap-error-list');
const inspector = document.querySelector('#inspector');
const inspectorEmpty = document.querySelector('#inspector-empty');
const runCount = document.querySelector('#run-count');
const errorCount = document.querySelector('#error-count');
const stepCount = document.querySelector('#step-count');
const roadmapCount = document.querySelector('#roadmap-count');

let currentRuns = [];
let currentExecutionIndex = { runs: [] };
let currentExecutionOptions = { tasks: [], workflows: [], stepRunners: [] };
let currentRoadmapDraftExport = null;
let currentRoadmapFiles = [];
let currentTargets = [];
let currentTargetId = '';
let editingRoadmapName = null;
let currentRoadmaps = [];
let currentRoadmapFilter = 'active';

refreshButton.addEventListener('click', loadLocalData);
targetSelect.addEventListener('change', () => {
  currentTargetId = targetSelect.value;
  fetch('/api/targets/active', {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ targetId: currentTargetId })
  }).catch(() => {});
  loadLocalData();
});
registerTargetButton.addEventListener('click', registerTargetFolder);

const registerTargetModal = document.querySelector('#register-target-modal');
const registerTargetClose = document.querySelector('#register-target-close');
const registerTargetForm = document.querySelector('#register-target-form');
const browserUp = document.querySelector('#browser-up');
const browserCurrentPath = document.querySelector('#browser-current-path');
const browserEntries = document.querySelector('#browser-entries');

registerTargetClose.addEventListener('click', () => registerTargetModal.close());
browserUp.addEventListener('click', () => navigateBrowser(browserUp.dataset.parent || ''));
registerTargetForm.addEventListener('submit', handleRegisterTargetSubmit);
registerTargetForm.elements.name.addEventListener('input', () => {
  registerTargetForm.elements.id.value = normalizeTargetId(registerTargetForm.elements.name.value);
});

initTargetButton.addEventListener('click', initializeCurrentTarget);
roadmapDraftForm.addEventListener('submit', createLocalRoadmapDraft);
workflowExecutionForm.addEventListener('input', handleWorkflowExecutionInput);
workflowExecutionForm.addEventListener('submit', executeWorkflow);
roadmapReviewClose.addEventListener('click', () => roadmapReviewModal.close());
executionModalClose.addEventListener('click', () => executionModal.close());
executionModalForm.addEventListener('submit', handleExecutionModalSubmit);

document.querySelectorAll('.filter-tab').forEach((tab) => {
  tab.addEventListener('click', () => {
    currentRoadmapFilter = tab.dataset.filter;
    document.querySelectorAll('.filter-tab').forEach((t) => {
      t.classList.toggle('active', t === tab);
      t.setAttribute('aria-selected', t === tab ? 'true' : 'false');
    });
    applyRoadmapFilter();
  });
});
initCollapsiblePersistence();
renderWorkflowCommandPreview();
loadLocalData();

window.addEventListener('workflow-step', (e) => handleStepEvent(e.detail));
window.addEventListener('workflow-update', () => loadLocalData());
window.addEventListener('stdout-chunk', (e) => {
  const { runId, chunk } = e.detail;
  runConsoleBuffers.set(runId, (runConsoleBuffers.get(runId) || '') + chunk);
  const pre = document.getElementById(`console-${CSS.escape(runId)}`);
  if (pre) {
    pre.textContent += chunk;
    pre.scrollTop = pre.scrollHeight;
  }
});

function initCollapsiblePersistence() {
  document.querySelectorAll('[data-persist-key]').forEach((el) => {
    const key = `collapsible:${el.dataset.persistKey}`;
    const saved = localStorage.getItem(key);
    if (saved === 'closed') el.removeAttribute('open');
    else if (saved === 'open') el.setAttribute('open', '');
    el.addEventListener('toggle', () => {
      localStorage.setItem(key, el.open ? 'open' : 'closed');
    });
  });
}

async function loadLocalData() {
  refreshButton.disabled = true;

  try {
    const targetRegistry = await fetchJson('/api/targets');
    renderTargetRegistry(targetRegistry);

    const targetQuery = `?targetId=${encodeURIComponent(currentTargetId)}`;
    const [logFiles, roadmapFiles, executionIndex, executionOptions] = await Promise.all([
      fetchJson(`/api/logs${targetQuery}`),
      fetchJson(`/api/roadmaps${targetQuery}`),
      fetchJson('/api/executions'),
      fetchJson(`/api/execution-options${targetQuery}`)
    ]);

    currentRoadmapFiles = roadmapFiles;
    currentExecutionIndex = executionIndex;
    currentExecutionOptions = executionOptions;
    renderWorkflowExecutionOptions(executionOptions);
    renderLogSummary(summarizeRuns(logFiles));
    renderRoadmapSummary(summarizeRoadmaps(roadmapFiles));
  } catch (error) {
    renderLoadFailure(error);
  } finally {
    refreshButton.disabled = false;
  }
}

function renderTargetRegistry(registry) {
  currentTargets = registry.targets || [];
  const previousTargetId = currentTargetId;
  const hasPrevious = currentTargets.some((target) => target.id === previousTargetId);
  currentTargetId = hasPrevious ? previousTargetId : registry.activeTargetId || currentTargets[0]?.id || '';

  targetSelect.replaceChildren();

  for (const target of currentTargets) {
    const option = document.createElement('option');
    option.value = target.id;
    option.textContent = target.name;
    targetSelect.append(option);
  }

  targetSelect.value = currentTargetId;
  const target = currentTargets.find((item) => item.id === currentTargetId);
  const readiness = target?.readiness;
  const missingCount = readiness?.missing?.length || 0;
  targetStatus.textContent = target
    ? `${readiness?.status || 'unknown'} / ${target.path}${missingCount > 0 ? ` / ${missingCount} missing` : ''}`
    : 'No target registered';
  initTargetButton.disabled = !target || readiness?.status === 'ready';
}

function getCurrentTargetContext() {
  const target = currentTargets.find((item) => item.id === currentTargetId);

  return {
    targetId: currentTargetId,
    targetName: target?.name || '',
    targetPath: target?.path || ''
  };
}

async function registerTargetFolder() {
  registerTargetForm.reset();
  registerTargetModal.showModal();
  await navigateBrowser('');
}

async function navigateBrowser(dirPath) {
  browserCurrentPath.textContent = dirPath || 'Drives';
  browserEntries.replaceChildren();

  try {
    const result = await fetchJson(`/api/browse?path=${encodeURIComponent(dirPath)}`);
    browserCurrentPath.textContent = result.path || 'Drives';
    browserUp.disabled = result.parent === null;
    browserUp.dataset.parent = result.parent ?? '';

    for (const entry of result.entries) {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'browser-entry';
      btn.textContent = `📁 ${entry.name}`;
      btn.addEventListener('click', () => selectBrowserEntry(entry));
      browserEntries.append(btn);
    }

    if (result.entries.length === 0) {
      const msg = document.createElement('p');
      msg.className = 'muted compact-line';
      msg.textContent = 'No subfolders.';
      browserEntries.append(msg);
    }
  } catch (error) {
    browserCurrentPath.textContent = `Error: ${error.message}`;
  }
}

function selectBrowserEntry(entry) {
  navigateBrowser(entry.path);
  registerTargetForm.elements.path.value = entry.path;
  registerTargetForm.elements.name.value = entry.name;
  registerTargetForm.elements.id.value = normalizeTargetId(entry.name);
}

async function handleRegisterTargetSubmit(event) {
  event.preventDefault();
  const formData = new FormData(registerTargetForm);
  const path = String(formData.get('path') || '').trim();
  const name = String(formData.get('name') || '').trim();
  const id = String(formData.get('id') || '').trim();

  try {
    await fetchJson('/api/targets', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ id, name, path })
    });
    registerTargetModal.close();
    currentTargetId = id;
    await loadLocalData();
  } catch (error) {
    targetStatus.textContent = error.message;
    registerTargetModal.close();
  }
}

async function initializeCurrentTarget() {
  if (!currentTargetId) {
    return;
  }

  initTargetButton.disabled = true;

  try {
    const plan = await fetchJson('/api/targets/init-plan', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ targetId: currentTargetId })
    });

    if (plan.actions.length === 0) {
      targetStatus.textContent = 'Target is ready.';
      await loadLocalData();
      return;
    }

    const actionText = plan.actions.map((action) => `${action.type}: ${action.path}`).join('\n');

    if (!window.confirm(`Initialize target with these missing items?\n\n${actionText}`)) {
      targetStatus.textContent = 'Target initialization cancelled.';
      return;
    }

    await fetchJson('/api/targets/init', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ targetId: currentTargetId, confirmed: true })
    });
    await loadLocalData();
  } catch (error) {
    targetStatus.textContent = error.message;
  } finally {
    initTargetButton.disabled = false;
  }
}

async function fetchJson(path, options) {
  const response = await fetch(path, options);

  if (!response.ok) {
    let message = `${path} returned ${response.status}`;

    try {
      const body = await response.json();

      if (body && typeof body.error === 'string') {
        message = body.error;
      }
    } catch (error) {
      // Keep the status-based fallback when the response is not JSON.
    }

    throw new Error(message);
  }

  return response.json();
}

function readWorkflowExecutionRequest() {
  const formData = new FormData(workflowExecutionForm);
  const request = {
    taskId: String(formData.get('taskId') || ''),
    workflowSpec: String(formData.get('workflowSpec') || ''),
    mode: String(formData.get('mode') || ''),
    stepRunnerCommand: String(formData.get('stepRunnerCommand') || ''),
    generatedTaskReady: formData.get('generatedTaskReady') === 'true'
  };
  const logOut = String(formData.get('logOut') || '').trim();
  const writeScope = String(formData.get('writeScope') || '').trim();

  if (logOut.length > 0) {
    request.logOut = logOut;
  }

  if (writeScope.length > 0) {
    request.writeScope = writeScope.split(',').map((item) => item.trim()).filter(Boolean);
  }

  return request;
}

function handleWorkflowExecutionInput(event) {
  if (event.target?.name === 'taskId') {
    workflowExecutionForm.elements.generatedTaskReady.value = taskExists(event.target.value) ? 'true' : 'false';
  }

  if (event.target?.name === 'stepRunnerCommand') {
    localStorage.setItem('stepRunnerCommand', event.target.value);
  }

  renderWorkflowCommandPreview();
}

function renderWorkflowExecutionOptions(options) {
  replaceSelectOptions(
    workflowExecutionForm.elements.taskId,
    options.tasks.map((task) => ({
      value: task.taskId,
      label: `${task.taskId} (${task.path})`
    })),
    workflowExecutionForm.elements.taskId.value || '000_template'
  );
  replaceSelectOptions(
    workflowExecutionForm.elements.workflowSpec,
    options.workflows.map((filePath) => ({
      value: filePath,
      label: filePath
    })),
    workflowExecutionForm.elements.workflowSpec.value || 'workflows/implementation-review.yaml'
  );
  replaceSelectOptions(
    workflowExecutionForm.elements.stepRunnerCommand,
    options.stepRunners.map((filePath) => ({
      value: filePath,
      label: filePath
    })),
    workflowExecutionForm.elements.stepRunnerCommand.value ||
      localStorage.getItem('stepRunnerCommand') ||
      'runner/codex.ps1'
  );
  workflowExecutionForm.elements.generatedTaskReady.value = taskExists(workflowExecutionForm.elements.taskId.value)
    ? 'true'
    : 'false';
  renderWorkflowCommandPreview();
}

function replaceSelectOptions(select, options, selectedValue) {
  const values = new Set(options.map((option) => option.value));
  const finalOptions = values.has(selectedValue) || !selectedValue
    ? options
    : [{ value: selectedValue, label: `${selectedValue} (missing)` }, ...options];

  select.replaceChildren();

  for (const option of finalOptions) {
    const element = document.createElement('option');
    element.value = option.value;
    element.textContent = option.label;
    select.append(element);
  }

  select.value = selectedValue;
}

function taskExists(taskId) {
  return currentExecutionOptions.tasks.some((task) => task.taskId === taskId);
}

function renderWorkflowCommandPreview() {
  const formRequest = readWorkflowExecutionRequest();
  const controlState = createWorkflowControlState(formRequest);

workflowExecuteButton.textContent = controlState.buttonLabel;

  if (!controlState.canExecute) {
    workflowCommandPreview.textContent = '';
    workflowExecutionStatus.textContent = controlState.status;
    workflowExecuteButton.disabled = true;
    return;
  }

  try {
    const request = createWorkflowExecutionRequest({
      ...formRequest,
      ...controlState.requestPayload
    });
    workflowCommandPreview.textContent = request.command;
    workflowExecutionStatus.textContent = controlState.status;
    workflowExecuteButton.disabled = false;
  } catch (error) {
    workflowCommandPreview.textContent = '';
    workflowExecutionStatus.textContent = error.message;
    workflowExecuteButton.disabled = true;
  }
}

async function executeWorkflow(event) {
  event.preventDefault();

  let request;
  const formRequest = readWorkflowExecutionRequest();
  const controlState = createWorkflowControlState(formRequest);

  if (!controlState.canExecute) {
    workflowExecutionStatus.textContent = controlState.status;
    return;
  }

  try {
    request = createWorkflowExecutionRequest({
      ...formRequest,
      ...controlState.requestPayload
    });
  } catch (error) {
    workflowExecutionStatus.textContent = error.message;
    return;
  }

  if (!window.confirm(formatWorkflowConfirmationMessage(request, {
    ...getCurrentTargetContext(),
    writeScope: formRequest.writeScope || ['.']
  }))) {
    workflowExecutionStatus.textContent = 'Execution cancelled.';
    return;
  }

  workflowExecuteButton.disabled = true;
  workflowExecutionStatus.textContent = `Starting ${request.mode} workflow...`;

  try {
    const result = await fetchJson('/api/executions/run', {
      method: 'POST',
      headers: {
        'content-type': 'application/json'
      },
      body: JSON.stringify({
        ...request,
        ...controlState.requestPayload,
        targetId: currentTargetId,
        writeScope: formRequest.writeScope || ['.'],
        confirmed: true
      })
    });
    workflowExecutionStatus.textContent = result.pending
      ? `Running... refresh to see result.`
      : `Done: ${result.name}`;
    await loadLocalData();
    if (result.pending) {
      selectRunningByTaskId(result.taskId);
      startPolling(result.name, result.taskId);
    } else if (result.name) {
      selectRunByFileName(result.name);
    }
  } catch (error) {
    workflowExecutionStatus.textContent = error.message;
  } finally {
    workflowExecuteButton.disabled = false;
  }
}

let pollingTimer = null;

function startPolling(executionRecordName, taskId = null) {
  if (pollingTimer) return;
  const runId = executionRecordName?.replace(/^logs\//, '').replace(/\.json$/, '');
  pollingTimer = setInterval(async () => {
    await loadLocalData();
    const thisRun = runId
      ? (currentExecutionIndex.runs || []).find((r) => r.runId === runId)
      : null;
    const stillRunning = thisRun
      ? thisRun.status === 'running'
      : (currentExecutionIndex.runs || []).some((r) => r.status === 'running');
    if (!stillRunning) {
      clearInterval(pollingTimer);
      pollingTimer = null;
      workflowExecutionStatus.textContent = 'Execution complete.';

      // Final update to load completed workflow log
      setTimeout(async () => {
        await loadLocalData();

        if (executionRecordName) {
          const record = currentRuns.find((r) => r.fileName === executionRecordName);
          const logPath = record?.execution?.logPath;
          if (logPath) selectRunByFileName(logPath);
        }

        if (taskId && taskId.startsWith('roadmap-')) {
          const completedRun = currentExecutionIndex.runs.find((r) => r.taskId === taskId);
          if (completedRun?.status === 'completed') {
            await autoToggleRoadmapItem(taskId);
          } else if (completedRun?.status === 'failed') {
            workflowExecutionStatus.textContent = 'Execution failed — roadmap item not toggled.';
          }
        }
      }, 500);
    }
  }, 3000);
}

function renderLogSummary(summary) {
  const indexedRuns = currentExecutionIndex.runs || [];
  const runningVirtual = indexedRuns
    .filter((r) => r.status === 'running')
    .map((r) => ({
      fileName: '',
      runId: r.runId,
      taskId: r.taskId,
      type: 'workflow',
      name: r.taskId,
      status: r.realExecution?.mode === 'real' ? 'real running' : 'running',
      stepCount: 0,
      steps: [],
      nextSteps: [],
      risks: [],
      retryAttempts: [],
      failedSteps: [],
      cancelledSteps: [],
      skippedSteps: [],
      verificationResult: '',
      verificationEvidence: [],
      execution: null,
      cost: { enabled: false, stepCosts: [] },
      costTotal: null,
      costTracking: null,
      memory: { enabled: false }
    }));
  const allRuns = [...summary.runs, ...runningVirtual];
  currentRuns = allRuns;
  renderSummary(summary);
  renderRunList(allRuns, summary.emptyMessage);
  renderExecutionRequestList(summary.runs, indexedRuns);
  renderErrors(summary.errors);

  if (inspector.hidden && summary.runs.length > 0) {
    selectRun(0);
  } else if (summary.runs.length === 0) {
    clearInspector();
  }
}

function renderRoadmapSummary(summary) {
  currentRoadmaps = summary.roadmaps;
  roadmapCount.textContent = String(summary.roadmaps.length);
  applyRoadmapFilter();
  renderRoadmapErrors(summary.errors);
}

function applyRoadmapFilter() {
  const filtered = currentRoadmaps.filter((roadmap) => {
    if (currentRoadmapFilter === 'all') return true;
    const s = roadmap.status.toLowerCase();
    const isCompleted = s.startsWith('completed');
    const isInProgress = s.startsWith('in progress') || s.startsWith('in-progress');
    const isNotStarted = !isCompleted && !isInProgress;
    if (currentRoadmapFilter === 'completed') return isCompleted;
    if (currentRoadmapFilter === 'in-progress') return isInProgress;
    if (currentRoadmapFilter === 'not-started') return !isCompleted && !isInProgress;
    return !isCompleted; // active
  });
  renderRoadmaps(filtered, currentRoadmaps.length === 0 ? 'No roadmaps loaded.' : 'No roadmaps match this filter.');
}

function renderLoadFailure(error) {
  renderLogSummary({
    runs: [],
    errors: [
      {
        fileName: 'local server',
        error: error.message
      }
    ],
    emptyMessage: 'No logs loaded.'
  });
  renderRoadmapSummary({
    roadmaps: [],
    errors: [
      {
        fileName: 'local server',
        error: error.message
      }
    ],
    emptyMessage: 'No roadmaps loaded.'
  });
}

function renderSummary(summary) {
  runCount.textContent = String(summary.runs.length);
  errorCount.textContent = String(summary.errors.length);
  stepCount.textContent = String(
    summary.runs.reduce((total, run) => total + run.stepCount, 0)
  );
}

const RUN_TYPE_ORDER = ['workflow', 'single', 'operator-control'];
const RUN_TYPE_LABEL = {
  'workflow': 'Workflows',
  'single': 'Single runs',
  'operator-control': 'Operator executions'
};

function renderRunList(runs, emptyMessage = 'No logs loaded.') {
  runList.replaceChildren();
  runList.classList.toggle('empty', runs.length === 0);

  if (runs.length === 0) {
    const empty = document.createElement('p');
    empty.textContent = emptyMessage;
    runList.append(empty);
    return;
  }

  // Group by type, preserve original index for selectRun
  const groups = new Map();
  runs.forEach((run, index) => {
    const type = run.type || 'single';
    if (!groups.has(type)) groups.set(type, []);
    groups.get(type).push({ run, index });
  });

  const typeOrder = [...RUN_TYPE_ORDER, ...[...groups.keys()].filter(t => !RUN_TYPE_ORDER.includes(t))];

  for (const type of typeOrder) {
    if (!groups.has(type)) continue;
    const entries = groups.get(type).slice().reverse(); // newest first

    const groupEl = document.createElement('div');
    groupEl.className = 'run-group';

    const groupLabel = document.createElement('p');
    groupLabel.className = 'run-group-label';
    groupLabel.textContent = RUN_TYPE_LABEL[type] || type;
    groupEl.append(groupLabel);

    for (const { run, index } of entries) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = run.status === 'real running' ? 'run-item running' : 'run-item';
      button.dataset.index = String(index);
      button.addEventListener('click', () => selectRun(index));

      const header = document.createElement('div');
      header.className = 'run-item-header';

      const title = document.createElement('span');
      title.className = 'run-title';
      title.textContent = run.name;

      const badge = document.createElement('span');
      badge.className = run.status === 'success' || run.status === 'complete'
        ? 'run-status-badge ok'
        : run.status === 'failed' || run.status === 'error'
          ? 'run-status-badge fail'
          : 'run-status-badge';
      badge.textContent = run.status;

      header.append(title, badge);

      const meta = document.createElement('div');
      meta.className = 'run-item-meta';

      const taskSpan = document.createElement('div');
      taskSpan.className = 'run-file';
      taskSpan.textContent = run.taskId !== 'unknown' ? run.taskId : run.fileName;
      meta.append(taskSpan);

      if (run.status === 'real running' && run.taskId && liveSteps.has(run.taskId)) {
        const steps = liveSteps.get(run.taskId);
        const completedCount = steps.filter(s => s.status === 'completed').length;
        const inProgressStep = steps.find(s => s.status === 'in-progress');

        const stepInfo = document.createElement('div');
        stepInfo.className = 'run-step-info';
        stepInfo.textContent = inProgressStep
          ? `${completedCount}/${steps.length} steps · ${inProgressStep.stepId} running`
          : `${completedCount}/${steps.length} steps`;
        meta.append(stepInfo);
      }

      const timeSpan = document.createElement('div');
      timeSpan.className = 'run-time';
      timeSpan.textContent = formatRunTime(run.fileName);
      meta.append(timeSpan);

      button.append(header, meta);
      groupEl.append(button);
    }

    runList.append(groupEl);
  }
}

function renderErrors(errors) {
  errorList.replaceChildren();

  for (const error of errors) {
    const item = document.createElement('div');
    item.className = 'error-item';

    const title = document.createElement('strong');
    title.textContent = error.fileName;

    const detail = document.createElement('span');
    detail.textContent = error.error;

    item.append(title, detail);
    errorList.append(item);
  }
}

function renderRoadmaps(roadmaps, emptyMessage = 'No roadmaps loaded.') {
  roadmapList.replaceChildren();
  roadmapList.classList.toggle('empty', roadmaps.length === 0);

  if (roadmaps.length === 0) {
    const empty = document.createElement('p');
    empty.textContent = emptyMessage;
    roadmapList.append(empty);
    return;
  }

  for (const roadmap of roadmaps) {
    roadmapList.append(renderRoadmapCard(roadmap));
  }
}

function renderRoadmapErrors(errors) {
  roadmapErrorList.replaceChildren();

  for (const error of errors) {
    const item = document.createElement('div');
    item.className = 'error-item';
    const title = document.createElement('strong');
    title.textContent = error.fileName;
    const detail = document.createElement('span');
    detail.textContent = error.error;
    item.append(title, detail);
    roadmapErrorList.append(item);
  }
}

function createLocalRoadmapDraft(event) {
  event.preventDefault();

  const draft = createRoadmapDraftFromFormData(new FormData(roadmapDraftForm));
  const validation = validateRoadmapDraft(draft);

  if (!validation.ok) {
    renderRoadmapDraftErrors(validation.errors);
    return;
  }

  renderRoadmapDraft(draft);
}

function renderRoadmapDraftErrors(errors) {
  currentRoadmapDraftExport = null;
  roadmapReviewBody.replaceChildren(renderTextList('Draft errors', errors.map((error) => error.message)));
  showRoadmapReviewModal();
}

function renderRoadmapDraft(draft) {
  currentRoadmapDraftExport = createRoadmapDraftExport(draft);
  const summary = document.createElement('div');
  summary.className = 'review-summary';
  summary.append(
    renderDraftHeader(draft),
    renderDraftStats(draft),
    renderTextList('Principles', draft.principles),
    renderDraftSequence(draft.sequence),
    renderTextList('Acceptance Criteria', draft.acceptanceCriteria),
    renderTextList('Out Of Scope', draft.outOfScope)
  );

  const content = document.createElement('div');
  content.className = 'review-content';
  const preview = renderMarkdownPreview(currentRoadmapDraftExport);
  content.append(summary, preview);

  roadmapReviewBody.replaceChildren(
    content,
    renderDraftActions(currentRoadmapDraftExport)
  );
  showRoadmapReviewModal();
  syncMarkdownPreviewHeight(summary, preview);
}

function showRoadmapReviewModal() {
  if (roadmapReviewModal.open) {
    return;
  }

  if (typeof roadmapReviewModal.showModal === 'function') {
    roadmapReviewModal.showModal();
  } else {
    roadmapReviewModal.setAttribute('open', '');
  }
}

function renderDraftHeader(draft) {
  const header = document.createElement('header');
  header.className = 'roadmap-card-header';
  const titleGroup = document.createElement('div');
  const title = document.createElement('h3');
  title.textContent = draft.title;
  const file = document.createElement('p');
  file.className = 'muted compact-line';
  file.textContent = editingRoadmapName || 'In-browser draft';
  titleGroup.append(title, file);

  const status = document.createElement('span');
  status.className = 'status-badge';
  status.textContent = draft.status;
  header.append(titleGroup, status);
  return header;
}

function renderDraftStats(draft) {
  const grid = document.createElement('div');
  grid.className = 'status-grid compact';
  grid.append(
    renderMetric('Principles', draft.principles.length),
    renderMetric('Steps', draft.sequence.length),
    renderMetric('Criteria', draft.acceptanceCriteria.length),
    renderMetric('Out of scope', draft.outOfScope.length)
  );
  return grid;
}

function renderDraftSequence(sequence) {
  const section = document.createElement('section');
  section.className = 'detail-section';
  const heading = document.createElement('h3');
  heading.textContent = 'Sequence';
  const list = document.createElement('ol');
  list.className = 'review-sequence';

  for (const item of sequence) {
    const row = document.createElement('li');
    row.className = item.done ? 'done' : '';
    row.textContent = item.text;
    list.append(row);
  }

  section.append(heading, list);
  return section;
}

function renderDraftActions(exported) {
  const actions = document.createElement('div');
  actions.className = 'draft-actions';
  const fileName = document.createElement('span');
  fileName.className = 'muted compact-line';
  fileName.textContent = editingRoadmapName || exported.fileName;
  const exportButton = document.createElement('button');
  exportButton.className = 'open-button secondary';
  exportButton.type = 'button';
  exportButton.textContent = 'Export markdown';
  exportButton.addEventListener('click', exportCurrentRoadmapDraft);

  if (editingRoadmapName) {
    const saveButton = document.createElement('button');
    saveButton.className = 'open-button';
    saveButton.type = 'button';
    saveButton.textContent = 'Save changes';
    saveButton.addEventListener('click', saveCurrentRoadmapDraft);
    actions.append(fileName, saveButton, exportButton);
  } else {
    actions.append(fileName, exportButton);
  }

  return actions;
}

function renderMarkdownPreview(exported) {
  const section = document.createElement('section');
  section.className = 'review-preview';
  const heading = document.createElement('h3');
  heading.textContent = 'Markdown';
  const preview = document.createElement('pre');
  preview.className = 'markdown-preview';
  preview.textContent = exported.content;
  section.append(heading, preview);
  return section;
}

function syncMarkdownPreviewHeight(summary, previewSection) {
  const preview = previewSection.querySelector('.markdown-preview');
  const heading = previewSection.querySelector('h3');

  if (!preview) {
    return;
  }

  requestAnimationFrame(() => {
    const summaryHeight = summary.getBoundingClientRect().height;
    const headingHeight = heading ? heading.getBoundingClientRect().height : 0;
    const previewStyle = getComputedStyle(previewSection);
    const gap = Number.parseFloat(previewStyle.rowGap || previewStyle.gap) || 0;
    const previewHeight = Math.max(0, Math.floor(summaryHeight - headingHeight - gap));

    previewSection.style.setProperty('--markdown-preview-block-size', `${previewHeight}px`);
  });
}

function exportCurrentRoadmapDraft() {
  if (!currentRoadmapDraftExport) {
    return;
  }

  const blob = new Blob([currentRoadmapDraftExport.content], {
    type: currentRoadmapDraftExport.mimeType
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = currentRoadmapDraftExport.fileName;
  link.click();
  URL.revokeObjectURL(url);
}

async function saveCurrentRoadmapDraft() {
  if (!editingRoadmapName) {
    return;
  }

  const draft = createRoadmapDraftFromFormData(new FormData(roadmapDraftForm));
  const validation = validateRoadmapDraft(draft);

  if (!validation.ok) {
    renderRoadmapDraftErrors(validation.errors);
    return;
  }

  const exported = createRoadmapDraftExport(draft);

  if (!window.confirm(`Overwrite ${editingRoadmapName}?`)) {
    return;
  }

  await fetchJson('/api/roadmaps/save', {
    method: 'POST',
    headers: {
      'content-type': 'application/json'
    },
    body: JSON.stringify({
      targetId: currentTargetId,
      name: editingRoadmapName,
      content: exported.content
    })
  });
  currentRoadmapDraftExport = exported;
  await loadLocalData();
}

function editRoadmapDraft(fileName) {
  const file = currentRoadmapFiles.find((roadmapFile) => roadmapFile.name === fileName);

  if (!file) {
    return;
  }

  editingRoadmapName = file.name;
  const draft = createRoadmapDraftFromMarkdown(file.content);
  fillRoadmapDraftForm(draft);
  currentRoadmapDraftExport = null;
}

function fillRoadmapDraftForm(draft) {
  roadmapDraftForm.elements.title.value = draft.title;
  roadmapDraftForm.elements.goal.value = draft.goal;
  roadmapDraftForm.elements.status.value = draft.status;
  roadmapDraftForm.elements.principles.value = draft.principles.join('\n');
  roadmapDraftForm.elements.sequence.value = draft.sequence
    .map((item, index) => `${index + 1}. [${item.done ? 'x' : ' '}] ${item.text}`)
    .join('\n');
  roadmapDraftForm.elements.acceptanceCriteria.value = draft.acceptanceCriteria.join('\n');
  roadmapDraftForm.elements.outOfScope.value = draft.outOfScope.join('\n');
}

function renderRoadmapCard(roadmap) {
  const card = document.createElement('article');
  card.className = 'roadmap-card';

  const header = document.createElement('header');
  header.className = 'roadmap-card-header';
  const titleGroup = document.createElement('div');
  const title = document.createElement('h3');
  title.textContent = roadmap.title;
  const file = document.createElement('p');
  file.className = 'muted compact-line';
  file.textContent = roadmap.fileName;
  titleGroup.append(title, file);

  const status = document.createElement('span');
  status.className = 'status-badge';
  status.textContent = roadmap.status;
  const editButton = document.createElement('button');
  editButton.className = 'open-button secondary compact';
  editButton.type = 'button';
  editButton.textContent = 'Edit';
  editButton.addEventListener('click', () => editRoadmapDraft(roadmap.fileName));
  const actions = document.createElement('div');
  actions.className = 'roadmap-card-actions';
  actions.append(status, editButton);
  header.append(titleGroup, actions);

  const progress = document.createElement('progress');
  progress.max = roadmap.totalCount;
  progress.value = roadmap.completedCount;
  progress.setAttribute(
    'aria-label',
    `${roadmap.completedCount} of ${roadmap.totalCount} roadmap items complete`
  );

  const progressText = document.createElement('p');
  progressText.className = 'muted compact-line';
  progressText.textContent = `${roadmap.completedCount}/${roadmap.totalCount} complete`;

  const list = document.createElement('ol');
  list.className = 'roadmap-items';
  roadmap.items.forEach((item, index) => {
    const row = document.createElement('li');
    row.className = item.done ? 'done' : '';
    const content = document.createElement('div');
    content.className = 'roadmap-item-row';

    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.checked = item.done;
    checkbox.addEventListener('change', async () => {
      checkbox.disabled = true;
      try {
        await toggleRoadmapCheckbox(roadmap.fileName, index);
        await loadLocalData();
      } catch (error) {
        renderLoadFailure(error);
        checkbox.checked = !checkbox.checked;
      } finally {
        checkbox.disabled = false;
      }
    });

    const text = document.createElement('span');
    text.textContent = item.text;
    content.append(checkbox, text);

    if (!item.done) {
      const runButton = document.createElement('button');
      runButton.className = 'open-button secondary compact';
      runButton.type = 'button';
      runButton.textContent = 'Run';
      runButton.addEventListener('click', () => runRoadmapItem(roadmap.fileName, index, runButton));
      content.append(runButton);
    }

    row.append(content);
    list.append(row);
  });

  card.append(header, progress, progressText, list);
  return card;
}

async function toggleRoadmapCheckbox(fileName, itemIndex) {
  await fetchJson('/api/roadmaps/toggle', {
    method: 'PATCH',
    headers: {
      'content-type': 'application/json'
    },
    body: JSON.stringify({
      targetId: currentTargetId,
      name: fileName,
      itemIndex
    })
  });
}

async function autoToggleRoadmapItem(taskId) {
  const match = taskId.match(/^roadmap-(.+)-(\d+)$/);
  if (!match) return;

  const roadmapName = match[1];
  const itemIndex = parseInt(match[2], 10) - 1;
  const fileName = `docs/plan/roadmaps/${roadmapName}.md`;

  try {
    await toggleRoadmapCheckbox(fileName, itemIndex);
    workflowExecutionStatus.textContent = 'Execution complete. Roadmap item checked.';
    await loadLocalData();
  } catch (error) {
    workflowExecutionStatus.textContent = `Auto-toggle failed: ${error.message}`;
  }
}

async function runRoadmapItem(fileName, itemIndex, button) {
  button.disabled = true;

  try {
    const result = await fetchJson('/api/roadmaps/run', {
      method: 'POST',
      headers: {
        'content-type': 'application/json'
      },
      body: JSON.stringify({
        targetId: currentTargetId,
        name: fileName,
        itemIndex
      })
    });
    await openExecutionModal(result);
    await loadLocalData();
  } catch (error) {
    renderLoadFailure(error);
  } finally {
    button.disabled = false;
  }
}

function openExecutionModal(runResult) {
  const prefill = createWorkflowPrefillFromRoadmapRun(runResult);
  const opts = currentExecutionOptions;

  executionModalForm.elements.taskId.value = prefill.taskId;

  const workflowSelect = executionModalForm.elements.workflowSpec;
  workflowSelect.replaceChildren();
  for (const w of opts.workflows) {
    const opt = document.createElement('option');
    opt.value = w;
    opt.textContent = w;
    workflowSelect.append(opt);
  }
  ensureSelectOption(workflowSelect, prefill.workflowSpec, prefill.workflowSpec);
  workflowSelect.value = prefill.workflowSpec;

  const runnerSelect = executionModalForm.elements.stepRunnerCommand;
  runnerSelect.replaceChildren();
  for (const r of opts.stepRunners) {
    const opt = document.createElement('option');
    opt.value = r;
    opt.textContent = r;
    runnerSelect.append(opt);
  }
  ensureSelectOption(runnerSelect, prefill.stepRunnerCommand, prefill.stepRunnerCommand);
  runnerSelect.value = prefill.stepRunnerCommand;

  executionModalForm.elements.mode.value = prefill.mode;
  executionModalStatus.textContent = '';
  executionModal.dataset.runResult = JSON.stringify(runResult);

  const taskPreview = document.querySelector('#execution-modal-task-preview');
  const taskContent = document.querySelector('#execution-modal-task-content');
  taskPreview.hidden = true;
  taskContent.textContent = '';

  fetchJson(`/api/tasks/read?targetId=${encodeURIComponent(currentTargetId)}&name=${encodeURIComponent(getGeneratedTaskFile(runResult))}`)
    .then((task) => {
      taskContent.textContent = task.content;
      taskPreview.hidden = false;
    })
    .catch(() => {});

  executionModal.showModal();
}

async function handleExecutionModalSubmit(event) {
  event.preventDefault();
  const runButton = executionModalForm.querySelector('#execution-modal-run');
  runButton.disabled = true;
  executionModalStatus.textContent = 'Starting...';

  try {
    const prefill = createWorkflowPrefillFromRoadmapRun(JSON.parse(executionModal.dataset.runResult));
    const request = createWorkflowExecutionRequest({
      taskId: prefill.taskId,
      workflowSpec: executionModalForm.elements.workflowSpec.value,
      mode: executionModalForm.elements.mode.value,
      stepRunnerCommand: executionModalForm.elements.stepRunnerCommand.value
    });

    const result = await fetchJson('/api/executions/run', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ ...request, targetId: currentTargetId, writeScope: ['.'], confirmed: true })
    });

    executionModal.close();
    await loadLocalData();
    if (result.pending) {
      selectRunningByTaskId(result.taskId);
      startPolling(result.name, result.taskId);
    } else if (result.name) {
      selectRunByFileName(result.name);
    }
  } catch (error) {
    executionModalStatus.textContent = error.message;
    runButton.disabled = false;
  }
}

function prefillWorkflowExecutionFromRoadmapRun(runResult) {
  const prefill = createWorkflowPrefillFromRoadmapRun(runResult);
  prefill.generatedTaskReady = true;
  fillWorkflowExecutionForm(prefill);
  workflowExecutionStatus.textContent = `Ready to run ${prefill.taskId}.`;
}

function fillWorkflowExecutionForm(prefill) {
  ensureSelectOption(workflowExecutionForm.elements.taskId, prefill.taskId, `${prefill.taskId} (generated)`);
  ensureSelectOption(workflowExecutionForm.elements.workflowSpec, prefill.workflowSpec, prefill.workflowSpec);
  ensureSelectOption(workflowExecutionForm.elements.stepRunnerCommand, prefill.stepRunnerCommand, prefill.stepRunnerCommand);
  workflowExecutionForm.elements.taskId.value = prefill.taskId;
  workflowExecutionForm.elements.workflowSpec.value = prefill.workflowSpec;
  workflowExecutionForm.elements.mode.value = prefill.mode;
  workflowExecutionForm.elements.stepRunnerCommand.value = prefill.stepRunnerCommand;
  workflowExecutionForm.elements.logOut.value = prefill.logOut;
  workflowExecutionForm.elements.writeScope.value = prefill.writeScope;
  workflowExecutionForm.elements.generatedTaskReady.value = prefill.generatedTaskReady === true ? 'true' : 'false';
  renderWorkflowCommandPreview();
}

function ensureSelectOption(select, value, label) {
  if (!value || Array.from(select.options).some((option) => option.value === value)) {
    return;
  }

  const option = document.createElement('option');
  option.value = value;
  option.textContent = label;
  select.append(option);
}

async function openGeneratedTaskDraft(runResult) {
  const taskFile = getGeneratedTaskFile(runResult);

  if (!taskFile) {
    return;
  }

  try {
    const task = await fetchJson(
      `/api/tasks/read?targetId=${encodeURIComponent(currentTargetId)}&name=${encodeURIComponent(taskFile)}`
    );

    renderTaskDraftViewer(task);
  } catch (error) {
    renderArtifactState('Generated task missing', taskFile, error.message);
  }
}

function renderTaskDraftViewer(task) {
  const header = document.createElement('header');
  header.className = 'roadmap-card-header';

  const titleGroup = document.createElement('div');
  const title = document.createElement('h3');
  title.textContent = 'Generated Task Draft';
  const file = document.createElement('p');
  file.className = 'muted compact-line';
  file.textContent = task.name;
  titleGroup.append(title, file);

  const badge = document.createElement('span');
  badge.className = 'status-badge';
  badge.textContent = 'Ready';
  header.append(titleGroup, badge);

  const preview = document.createElement('pre');
  preview.className = 'task-draft-preview';
  preview.textContent = task.content;

  roadmapReviewBody.replaceChildren(header, preview);
  showRoadmapReviewModal();
}

function renderArtifactState(titleText, fileName, detailText) {
  const section = document.createElement('section');
  section.className = 'artifact-state warning';
  const title = document.createElement('h3');
  title.textContent = titleText;
  const file = document.createElement('p');
  file.className = 'muted compact-line';
  file.textContent = fileName || 'No file reference captured.';
  const detail = document.createElement('p');
  detail.className = 'compact-line';
  detail.textContent = detailText;
  section.append(title, file, detail);
  roadmapReviewBody.replaceChildren(section);
  showRoadmapReviewModal();
}

function renderExecutionRequestList(runs, indexedRuns = []) {
  const requests = summarizeExecutionRequests(runs, indexedRuns);
  executionRequestList.replaceChildren();
  executionRequestList.classList.toggle('empty', requests.length === 0);

  if (requests.length === 0) {
    const empty = document.createElement('p');
    empty.textContent = 'No execution requests loaded.';
    executionRequestList.append(empty);
    return;
  }

  for (const request of requests) {
    const run = runs.find((item) => item.fileName === request.fileName);
    const item = document.createElement('article');
    item.className = 'execution-request-item';

    const header = document.createElement('div');
    header.className = 'execution-request-header';
    const title = document.createElement('strong');
    title.textContent = request.taskId;
    if (request.fileName) {
      title.className = 'clickable-title';
      title.title = 'View in inspector';
      title.addEventListener('click', () => selectRunByFileName(request.fileName));
    }
    const badge = document.createElement('span');
    badge.className = request.exitCode === 0 || request.state === 'real-completed'
      ? 'verification-badge passed'
      : 'verification-badge';
    badge.textContent = request.status;
    header.append(title, badge);

    const logLine = document.createElement('p');
    logLine.className = 'muted compact-line';
    logLine.textContent = `Log: ${request.logPath || 'not captured'}`;

    const command = document.createElement('p');
    command.className = 'muted compact-line';
    command.textContent = `Command: ${request.command || 'not captured'}`;

    const actions = document.createElement('div');
    actions.className = 'execution-request-actions';
    if (request.state !== 'real-running' && request.state !== 'dry-run-running') {
      const logState = getWorkflowLogReferenceState(run, runs);
      actions.append(renderWorkflowLogAction(logState));
    }

    if (request.state === 'real-running' && request.runId) {
      const cancelButton = document.createElement('button');
      cancelButton.type = 'button';
      cancelButton.className = 'open-button secondary compact';
      cancelButton.textContent = 'Cancel';
      cancelButton.addEventListener('click', () => cancelExecutionRequest(request.runId, cancelButton));
      actions.append(cancelButton);
    }

    if (request.exitCode !== 0 && request.state !== 'real-running' && run) {
      const retryButton = document.createElement('button');
      retryButton.type = 'button';
      retryButton.className = 'open-button secondary compact';
      retryButton.textContent = 'Retry';
      retryButton.addEventListener('click', () => retryExecutionRequest(run));
      actions.append(retryButton);
    }

    if (request.state !== 'real-running' && request.state !== 'dry-run-running') {
      const runId = request.runId ||
        (request.fileName ? request.fileName.replace(/^logs\//, '').replace(/\.json$/, '') : null);
      if (runId) {
        const stepsButton = document.createElement('button');
        stepsButton.type = 'button';
        stepsButton.className = 'open-button secondary compact';
        stepsButton.textContent = 'Step logs';
        stepsButton.addEventListener('click', () => toggleStepLogsPanel(stepsButton, runId, item));
        actions.append(stepsButton);
      }
    }

    item.append(header, logLine, command, actions);

    if ((request.state === 'real-running' || request.state === 'dry-run-running') && request.runId) {
      const panel = document.createElement('div');
      panel.className = 'console-panel';
      const pre = document.createElement('pre');
      pre.id = `console-${CSS.escape(request.runId)}`;
      pre.className = 'console-output';
      pre.textContent = runConsoleBuffers.get(request.runId) || '';
      panel.append(pre);
      item.append(panel);
      setTimeout(() => { pre.scrollTop = pre.scrollHeight; }, 0);
    }

    executionRequestList.append(item);
  }
}

function renderWorkflowLogAction(state) {
  if (state.status !== 'ready') {
    const status = document.createElement('span');
    status.className = 'artifact-status warning';
    status.textContent = `${state.label}: ${state.logPath || 'None'}`;
    return status;
  }

  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'open-button secondary compact';
  button.textContent = state.label;
  button.addEventListener('click', () => selectRunByFileName(state.workflowFileName));
  return button;
}

async function toggleStepLogsPanel(button, runId, container) {
  const existing = container.querySelector('.step-logs-panel');
  if (existing) {
    existing.remove();
    button.textContent = 'Step logs';
    return;
  }

  button.disabled = true;
  button.textContent = 'Loading…';

  const panel = document.createElement('div');
  panel.className = 'step-logs-panel';

  try {
    const steps = await fetchJson(`/api/executions/${encodeURIComponent(runId)}/steps`);

    if (steps.length === 0) {
      const empty = document.createElement('p');
      empty.className = 'muted compact-line';
      empty.textContent = 'No step logs recorded for this run.';
      panel.append(empty);
    } else {
      const list = document.createElement('ul');
      list.className = 'step-logs-list';

      for (const step of steps) {
        const li = document.createElement('li');
        li.className = 'step-log-item';

        const header = document.createElement('div');
        header.className = 'step-log-header';

        const role = document.createElement('strong');
        role.textContent = step.role || step.run_id || 'unknown';

        const verif = step.output?.verification_result ?? '';
        const badge = document.createElement('span');
        badge.className = verif === 'exit 0' || verif === 0
          ? 'verification-badge passed'
          : 'verification-badge';
        badge.textContent = verif || 'n/a';

        header.append(role, badge);

        const summary = document.createElement('p');
        summary.className = 'muted compact-line';
        summary.textContent = step.output?.summary || 'No summary.';

        li.append(header, summary);
        list.append(li);
      }

      panel.append(list);
    }
  } catch (error) {
    const errP = document.createElement('p');
    errP.className = 'muted compact-line';
    errP.textContent = `Error: ${error.message}`;
    panel.append(errP);
  }

  container.append(panel);
  button.textContent = 'Hide steps';
  button.disabled = false;
}

async function cancelExecutionRequest(runId, button) {
  button.disabled = true;

  try {
    await fetchJson(`/api/executions/${encodeURIComponent(runId)}`, { method: 'DELETE' });
    await loadLocalData();
  } catch (error) {
    workflowExecutionStatus.textContent = `Cancel failed: ${error.message}`;
    button.disabled = false;
  }
}

function retryExecutionRequest(run) {
  try {
    const prefill = createRetryPrefillFromExecutionRun(run);
    fillWorkflowExecutionForm(prefill);
    workflowExecutionStatus.textContent = `Ready to retry ${prefill.taskId}.`;
  } catch (error) {
    workflowExecutionStatus.textContent = error.message;
  }
}

function selectRun(index) {
  currentSelectedIndex = index;
  const run = currentRuns[index];
  if (!run) {
    clearInspector();
    return;
  }

  document.querySelectorAll('.run-item').forEach((item) => {
    item.classList.toggle('selected', item.dataset.index === String(index));
  });

  inspector.hidden = false;
  inspectorEmpty.hidden = true;
  inspector.replaceChildren(
    renderRunHeader(run),
    renderStatusGrid(run),
    renderVerificationPanel(run),
    renderTextList('Next steps', run.nextSteps),
    renderCollapsible('Steps', renderSteps(run.steps), run.steps.length > 0),
    renderCollapsible('Execution result', renderExecutionResult(run)),
    renderCollapsible('Operational state', renderOperationalState(run)),
    renderCollapsible('Cost tracking', renderCostTracking(run)),
    renderCollapsible('Memory', renderMemoryState(run)),
    renderCollapsible('Risks', renderTextList('', run.risks))
  );
}

const liveSteps = new Map(); // taskId → step[]

function handleStepEvent(detail) {
  const { taskId, stepId, status, summary } = detail;
  console.log('[STEP EVENT]', { taskId, stepId, status, summary });
  if (!taskId) return;

  if (!liveSteps.has(taskId)) liveSteps.set(taskId, []);
  const steps = liveSteps.get(taskId);
  const existing = steps.findIndex((s) => s.stepId === stepId);
  const step = { stepId, status, summary };
  if (existing >= 0) steps[existing] = step;
  else steps.push(step);

  // Update live steps panel if this task is currently selected
  const selectedRun = currentRuns[currentSelectedIndex];
  console.log('[STEP EVENT] Selected run:', {
    currentIndex: currentSelectedIndex,
    selectedTaskId: selectedRun?.taskId,
    selectedFileName: selectedRun?.fileName,
    eventTaskId: taskId,
    match: selectedRun?.taskId === taskId
  });

  // Render if the selected run matches this task (regardless of fileName)
  if (selectedRun?.taskId === taskId) {
    console.log('[STEP EVENT] Rendering live steps for', taskId);
    renderLiveSteps(taskId);
  }

  updateRunningItemStepCount(taskId);
}

function updateRunningItemStepCount(taskId) {
  const runIndex = currentRuns.findIndex(r => r.taskId === taskId && r.fileName === '');
  if (runIndex >= 0) {
    renderRunList(currentRuns);
    document.querySelectorAll('.run-item').forEach((item) => {
      item.classList.toggle('selected', item.dataset.index === String(currentSelectedIndex));
    });
  }
}

function renderLiveSteps(taskId) {
  const steps = liveSteps.get(taskId) || [];
  let livePanel = inspector.querySelector('.live-steps-panel');

  if (!livePanel) {
    livePanel = document.createElement('div');
    livePanel.className = 'live-steps-panel';
    const heading = document.createElement('h3');
    heading.className = 'live-steps-heading';
    heading.textContent = 'Steps';
    livePanel.append(heading);
    inspector.append(livePanel);
  }

  const list = livePanel.querySelector('.live-steps-list') || document.createElement('ul');
  list.className = 'live-steps-list';

  if (steps.length === 0) {
    const empty = document.createElement('li');
    empty.className = 'live-step-item muted';
    empty.textContent = 'Waiting for workflow to start...';
    list.replaceChildren(empty);
  } else {
    list.replaceChildren(...steps.map((step) => {
      const li = document.createElement('li');
      li.className = 'live-step-item';
      const badge = document.createElement('span');
      let badgeClass = 'live-step-badge';
      if (step.status === 'completed') badgeClass += ' ok';
      else if (step.status === 'in-progress') badgeClass += ' running';
      badge.className = badgeClass;
      badge.textContent = step.status === 'in-progress' ? '⟳' : step.status;
      const label = document.createElement('strong');
      label.textContent = step.stepId;
      const summary = document.createElement('p');
      summary.className = 'muted compact-line';
      summary.textContent = step.summary || (step.status === 'in-progress' ? 'Running...' : '');
      li.append(badge, label, summary);
      return li;
    }));
  }

  if (!livePanel.contains(list)) livePanel.append(list);
}

let currentSelectedIndex = -1;

function selectRunningByTaskId(taskId) {
  const index = currentRuns.findIndex((run) => run.fileName === '' && run.taskId === taskId);
  console.log('[SELECT RUNNING]', { taskId, index, currentRuns: currentRuns.length });
  if (index >= 0) {
    selectRun(index);
    const runsSection = document.querySelector('.runs-section');
    if (runsSection) {
      runsSection.open = true;
      inspector.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
    // Always render live steps panel (even if empty initially)
    if (!liveSteps.has(taskId)) liveSteps.set(taskId, []);
    renderLiveSteps(taskId);
  }
}

function selectRunByFileName(fileName) {
  const index = currentRuns.findIndex((run) => run.fileName === fileName);

  if (index >= 0) {
    selectRun(index);
    const runsSection = document.querySelector('.runs-section');
    if (runsSection) {
      runsSection.open = true;
      inspector.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  }
}

function clearInspector() {
  inspector.hidden = true;
  inspectorEmpty.hidden = false;
  inspector.replaceChildren();
}

function renderCollapsible(label, content, open = false) {
  const details = document.createElement('details');
  details.className = 'inspector-collapsible';
  if (open) details.open = true;
  const summary = document.createElement('summary');
  summary.className = 'inspector-collapsible-summary';
  summary.textContent = label;
  details.append(summary, content);
  return details;
}

function renderRunHeader(run) {
  const header = document.createElement('header');
  header.className = 'inspector-header';

  const title = document.createElement('div');
  const eyebrow = document.createElement('p');
  eyebrow.className = 'eyebrow';
  eyebrow.textContent = run.type;
  const heading = document.createElement('h2');
  heading.textContent = run.name;
  const meta = document.createElement('p');
  meta.className = 'muted';
  meta.textContent = `${run.runId} / ${run.runner} / ${run.taskId}`;
  title.append(eyebrow, heading, meta);

  const badge = document.createElement('span');
  badge.className = 'status-badge';
  badge.textContent = run.status;

  header.append(title, badge);
  return header;
}

function renderStatusGrid(run) {
  const grid = document.createElement('section');
  grid.className = 'status-grid';
  grid.append(
    renderMetric('Steps', run.stepCount),
    renderMetric('Retries', run.retryAttempts.length),
    renderMetric('Cancelled', run.cancelledSteps.length),
    renderMetric('Skipped', run.skippedSteps.length),
    renderMetric('Cost', formatCost(run)),
    renderMetric('Memory loaded', formatBoolean(run.memory.loaded)),
    renderMetric('Memory stale', formatBoolean(run.memory.stale))
  );
  return grid;
}

function renderMetric(label, value) {
  const item = document.createElement('div');
  item.className = 'status-cell';
  const labelNode = document.createElement('span');
  labelNode.className = 'metric-label';
  labelNode.textContent = label;
  const valueNode = document.createElement('strong');
  valueNode.textContent = String(value);
  item.append(labelNode, valueNode);
  return item;
}

function renderTextList(title, values) {
  const section = document.createElement('section');
  section.className = 'detail-section';
  const list = document.createElement('ul');

  if (title) {
    const heading = document.createElement('h3');
    heading.textContent = title;
    section.append(heading);
  }

  const items = values.length > 0 ? values : ['None'];
  for (const value of items) {
    const item = document.createElement('li');
    item.textContent = value;
    list.append(item);
  }

  section.append(list);
  return section;
}

function renderOperationalState(run) {
  const section = document.createElement('section');
  section.className = 'detail-section';
  const heading = document.createElement('h3');
  heading.textContent = 'Operational state';
  const grid = document.createElement('div');
  grid.className = 'state-grid';

  grid.append(
    renderRetryAttempts(run.retryAttempts),
    renderFailedSteps(run.failedSteps),
    renderOperationalSteps('Cancelled steps', run.cancelledSteps),
    renderOperationalSteps('Skipped steps', run.skippedSteps)
  );

  section.append(heading, grid);
  return section;
}

function renderCostTracking(run) {
  const section = document.createElement('section');
  section.className = 'detail-section';
  const heading = document.createElement('h3');
  heading.textContent = 'Cost tracking';
  const grid = document.createElement('div');
  grid.className = 'cost-grid';

  grid.append(renderCostSummary(run.cost), renderStepCosts(run.cost.stepCosts));
  section.append(heading, grid);
  return section;
}

function renderMemoryState(run) {
  const section = document.createElement('section');
  section.className = 'detail-section';
  const heading = document.createElement('h3');
  heading.textContent = 'Memory';
  const grid = document.createElement('div');
  grid.className = 'memory-grid';

  grid.append(renderMemorySummary(run.memory), renderStepMemory(run.steps));
  section.append(heading, grid);
  return section;
}

function renderVerificationPanel(run) {
  const section = document.createElement('section');
  section.className = 'detail-section';
  const heading = document.createElement('h3');
  heading.textContent = 'Local verification';
  const panel = document.createElement('div');
  panel.className = 'verification-panel';

  if (run.verificationEvidence.length === 0) {
    panel.append(renderMutedLine('No verification evidence in this captured log.'));
  }

  for (const evidence of run.verificationEvidence) {
    panel.append(renderVerificationEvidence(evidence));
  }

  section.append(heading, panel);
  return section;
}

function renderVerificationEvidence(evidence) {
  const item = document.createElement('article');
  item.className = evidence.exitCode === 0 ? 'verification-item passed' : 'verification-item';

  const header = document.createElement('div');
  header.className = 'verification-header';
  const title = document.createElement('strong');
  title.textContent = `${evidence.scope} / ${evidence.label}`;
  const badge = document.createElement('span');
  badge.className = evidence.exitCode === 0 ? 'verification-badge passed' : 'verification-badge';
  badge.textContent = evidence.exitCode === null ? 'recorded' : `exit ${evidence.exitCode}`;
  header.append(title, badge);

  const command = document.createElement('p');
  command.className = 'muted compact-line';
  command.textContent = `Command: ${evidence.command || 'not captured'}`;

  const result = document.createElement('p');
  result.className = 'verification-result';
  result.textContent = evidence.result;

  item.append(header, command, result);
  return item;
}

function renderExecutionResult(run) {
  const section = document.createElement('section');
  section.className = 'detail-section';
  const heading = document.createElement('h3');
  heading.textContent = 'Execution result';

  if (!run.execution) {
    section.append(heading, renderMutedLine('No execution result in this captured log.'));
    return section;
  }

  const panel = document.createElement('div');
  panel.className = 'execution-result';
  const workflowLogState = getWorkflowLogReferenceState(run, currentRuns);
  panel.append(
    renderExecutionLine('Command', run.execution.command),
    renderExecutionLine('Log path', run.execution.logPath),
    renderExecutionLine('Exit code', String(run.execution.exitCode ?? 'n/a')),
    renderExecutionWorkflowLogState(workflowLogState),
    renderExecutionBlock('stdout', run.execution.stdout),
    renderExecutionBlock('stderr', run.execution.stderr)
  );

  section.append(heading, panel);
  return section;
}

function renderExecutionWorkflowLogState(state) {
  const row = document.createElement('div');
  row.className = state.status === 'ready' ? 'execution-log-state' : 'execution-log-state warning';
  const label = document.createElement('span');
  label.className = 'metric-label';
  label.textContent = 'Workflow log';
  row.append(label, renderWorkflowLogAction(state));
  return row;
}

function renderExecutionLine(label, value) {
  const row = document.createElement('p');
  row.className = 'muted compact-line';
  row.textContent = `${label}: ${value || 'None'}`;
  return row;
}

function renderExecutionBlock(label, value) {
  const block = document.createElement('div');
  block.className = 'execution-stream';
  const title = document.createElement('span');
  title.className = 'metric-label';
  title.textContent = label;
  const output = document.createElement('pre');
  output.textContent = value || 'None';
  block.append(title, output);
  return block;
}

function renderMemorySummary(memory) {
  const panel = document.createElement('article');
  panel.className = memory.stale === true ? 'memory-panel warning' : 'memory-panel';
  const heading = document.createElement('h4');
  heading.textContent = 'Workflow memory';

  panel.append(
    heading,
    renderKeyValue('Enabled', formatBoolean(memory.enabled)),
    renderKeyValue('Loaded', formatBoolean(memory.loaded)),
    renderKeyValue('Written', formatBoolean(memory.written)),
    renderKeyValue('Stale', formatBoolean(memory.stale)),
    renderKeyValue('Overwrite allowed', formatBoolean(memory.overwriteAllowed)),
    renderKeyValue('Persistence', memory.persistence || 'n/a'),
    renderKeyValue('Scope', memory.scope || 'n/a'),
    renderKeyValue('Path', memory.path || 'n/a')
  );

  return panel;
}

function renderStepMemory(steps) {
  const panel = document.createElement('article');
  panel.className = 'memory-panel wide';
  const heading = document.createElement('h4');
  heading.textContent = 'Step memory';
  panel.append(heading);

  if (steps.length === 0) {
    panel.append(renderMutedLine('No workflow steps.'));
    return panel;
  }

  for (const step of steps) {
    const row = document.createElement('div');
    row.className = step.memory.stale === true ? 'memory-step warning' : 'memory-step';
    const title = document.createElement('strong');
    title.textContent = `${step.stepId} / ${step.role}`;
    const details = document.createElement('p');
    details.className = 'muted compact-line';
    details.textContent = [
      `loaded ${formatBoolean(step.memory.loaded)}`,
      `written ${formatBoolean(step.memory.written)}`,
      `stale ${formatBoolean(step.memory.stale)}`,
      `overwrite ${formatBoolean(step.memory.overwriteAllowed)}`
    ].join(' / ');

    row.append(title, details);
    panel.append(row);
  }

  return panel;
}

function renderCostSummary(cost) {
  const panel = document.createElement('article');
  panel.className = 'cost-panel';
  const heading = document.createElement('h4');
  heading.textContent = 'Total';

  panel.append(
    heading,
    renderKeyValue('Enabled', formatBoolean(cost.enabled)),
    renderKeyValue('Estimated total', formatMoney(cost.estimatedTotalCost, cost.currency)),
    renderKeyValue('Currency', cost.currency || 'n/a'),
    renderKeyValue('Unit', cost.unit || 'n/a')
  );

  return panel;
}

function renderStepCosts(stepCosts) {
  const panel = document.createElement('article');
  panel.className = 'cost-panel wide';
  const heading = document.createElement('h4');
  heading.textContent = 'Per-step provider metadata';
  panel.append(heading);

  if (stepCosts.length === 0) {
    panel.append(renderMutedLine('No per-step cost records.'));
    return panel;
  }

  for (const stepCost of stepCosts) {
    const row = document.createElement('div');
    row.className = 'cost-step';
    const title = document.createElement('strong');
    title.textContent = `${stepCost.stepId} / ${formatMoney(stepCost.estimatedCost, stepCost.currency)}`;

    const metadata = stepCost.providerMetadata;
    const details = document.createElement('p');
    details.className = 'muted compact-line';
    details.textContent = [
      metadata.provider || 'unknown provider',
      metadata.tool || 'unknown tool',
      metadata.model || 'unknown model',
      formatTokens(metadata)
    ].join(' / ');

    row.append(title, details);
    panel.append(row);
  }

  return panel;
}

function renderKeyValue(label, value) {
  const row = document.createElement('p');
  row.className = 'key-value';
  const key = document.createElement('span');
  key.textContent = label;
  const val = document.createElement('strong');
  val.textContent = value;
  row.append(key, val);
  return row;
}

function renderRetryAttempts(attempts) {
  const panel = renderStatePanel('Retry attempts');

  if (attempts.length === 0) {
    panel.append(renderMutedLine('None'));
    return panel;
  }

  for (const attempt of attempts) {
    const line = document.createElement('p');
    line.className = 'state-line';
    line.textContent = `${attempt.stepId} / attempt ${attempt.attempt ?? 'n/a'} / ${attempt.status}`;
    panel.append(line);
  }

  return panel;
}

function renderFailedSteps(steps) {
  const panel = renderStatePanel('Failed steps');

  if (steps.length === 0) {
    panel.append(renderMutedLine('None'));
    return panel;
  }

  for (const step of steps) {
    const line = document.createElement('p');
    line.className = step.retryExhausted ? 'state-line danger' : 'state-line';
    line.textContent = `${step.stepId} / attempts ${step.attempts ?? 'n/a'} / retry exhausted ${formatBoolean(step.retryExhausted)}`;
    panel.append(line);

    if (step.reason) {
      panel.append(renderMutedLine(step.reason));
    }
  }

  return panel;
}

function renderOperationalSteps(title, steps) {
  const panel = renderStatePanel(title);

  if (steps.length === 0) {
    panel.append(renderMutedLine('None'));
    return panel;
  }

  for (const step of steps) {
    const line = document.createElement('p');
    line.className = 'state-line';
    line.textContent = `${step.stepId} / ${step.role}`;
    panel.append(line);

    if (step.reason) {
      panel.append(renderMutedLine(step.reason));
    }
  }

  return panel;
}

function renderStatePanel(title) {
  const panel = document.createElement('article');
  panel.className = 'state-panel';
  const heading = document.createElement('h4');
  heading.textContent = title;
  panel.append(heading);
  return panel;
}

function renderMutedLine(text) {
  const line = document.createElement('p');
  line.className = 'muted compact-line';
  line.textContent = text;
  return line;
}

function renderSteps(steps) {
  const section = document.createElement('section');
  section.className = 'detail-section';
  const heading = document.createElement('h3');
  heading.textContent = 'Steps';
  const list = document.createElement('div');
  list.className = 'step-list';

  if (steps.length === 0) {
    const empty = document.createElement('p');
    empty.className = 'muted';
    empty.textContent = 'No workflow steps.';
    list.append(empty);
  }

  for (const step of steps) {
    const item = document.createElement('article');
    item.className = 'step-item';

    const title = document.createElement('div');
    title.className = 'step-title';
    const name = document.createElement('strong');
    name.textContent = step.stepId;
    const role = document.createElement('span');
    role.textContent = step.role;
    title.append(name, role);

    const details = document.createElement('p');
    details.className = 'muted';
    details.textContent = `attempts ${step.attempts ?? 'n/a'} / ${step.verificationResult || 'no verification result'}`;

    item.append(
      title,
      details,
      renderInlineList('Retry attempts', formatStepRetryAttempts(step.retryAttempts)),
      renderInlineList('Risks', step.risks),
      renderInlineList('Next', step.nextSteps)
    );
    list.append(item);
  }

  section.append(heading, list);
  return section;
}

function formatRunTime(fileName) {
  const match = fileName.match(/(\d{8})T(\d{2})(\d{2})(\d{2})/);
  if (!match) return '';
  const [, date, h, m, s] = match;
  const y = date.slice(0, 4), mo = date.slice(4, 6), d = date.slice(6, 8);
  const dt = new Date(`${y}-${mo}-${d}T${h}:${m}:${s}Z`);
  return dt.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}

function formatCost(run) {
  return formatMoney(run.costTotal, run.cost.currency);
}

function formatBoolean(value) {
  if (typeof value !== 'boolean') {
    return 'n/a';
  }

  return value ? 'yes' : 'no';
}

function renderInlineList(label, values) {
  const row = document.createElement('p');
  row.className = 'muted compact-line';
  row.textContent = `${label}: ${values.length > 0 ? values.join('; ') : 'None'}`;
  return row;
}

function formatStepRetryAttempts(attempts) {
  return attempts.map((attempt) =>
    `attempt ${attempt.attempt ?? 'n/a'} ${attempt.status}`
  );
}

function formatMoney(value, currency) {
  if (value === null) {
    return 'n/a';
  }

  return `${value} ${currency || ''}`.trim();
}

function formatTokens(metadata) {
  if (metadata.totalTokens === null) {
    return 'tokens n/a';
  }

  const input = metadata.inputTokens ?? 'n/a';
  const output = metadata.outputTokens ?? 'n/a';
  return `${metadata.totalTokens} tokens (${input} in, ${output} out)`;
}
