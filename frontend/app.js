import { summarizeRuns } from './logParser.mjs';
import {
  createRoadmapDraftExport,
  createRoadmapDraftFromFormData,
  createRoadmapDraftFromMarkdown,
  validateRoadmapDraft
} from './roadmapDraft.mjs';
import { summarizeRoadmaps } from './roadmapParser.mjs';

const refreshButton = document.querySelector('#refresh-data');
const roadmapDraftForm = document.querySelector('#roadmap-draft-form');
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
let currentRoadmapDraftExport = null;
let currentRoadmapFiles = [];
let editingRoadmapName = null;

refreshButton.addEventListener('click', loadLocalData);
roadmapDraftForm.addEventListener('submit', createLocalRoadmapDraft);
roadmapReviewClose.addEventListener('click', () => roadmapReviewModal.close());
loadLocalData();

async function loadLocalData() {
  refreshButton.disabled = true;

  try {
    const [logFiles, roadmapFiles] = await Promise.all([
      fetchJson('/api/logs'),
      fetchJson('/api/roadmaps')
    ]);

    currentRoadmapFiles = roadmapFiles;
    renderLogSummary(summarizeRuns(logFiles));
    renderRoadmapSummary(summarizeRoadmaps(roadmapFiles));
  } catch (error) {
    renderLoadFailure(error);
  } finally {
    refreshButton.disabled = false;
  }
}

async function fetchJson(path, options) {
  const response = await fetch(path, options);

  if (!response.ok) {
    throw new Error(`${path} returned ${response.status}`);
  }

  return response.json();
}

function renderLogSummary(summary) {
  currentRuns = summary.runs;
  renderSummary(summary);
  renderRunList(summary.runs, summary.emptyMessage);
  renderErrors(summary.errors);

  if (summary.runs.length > 0) {
    selectRun(0);
  } else {
    clearInspector();
  }
}

function renderRoadmapSummary(summary) {
  roadmapCount.textContent = String(summary.roadmaps.length);
  renderRoadmaps(summary.roadmaps, summary.emptyMessage);
  renderRoadmapErrors(summary.errors);
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

function renderRunList(runs, emptyMessage = 'No logs loaded.') {
  runList.replaceChildren();
  runList.classList.toggle('empty', runs.length === 0);

  if (runs.length === 0) {
    const empty = document.createElement('p');
    empty.textContent = emptyMessage;
    runList.append(empty);
    return;
  }

  runs.forEach((run, index) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'run-item';
    button.dataset.index = String(index);
    button.addEventListener('click', () => selectRun(index));

    const title = document.createElement('span');
    title.className = 'run-title';
    title.textContent = run.name;

    const meta = document.createElement('span');
    meta.className = 'run-meta';
    meta.textContent = `${run.type} / ${run.status}`;

    const file = document.createElement('span');
    file.className = 'run-file';
    file.textContent = run.fileName;

    button.append(title, meta, file);
    runList.append(button);
  });
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

    preview.style.blockSize = `${previewHeight}px`;
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
  for (const item of roadmap.items) {
    const row = document.createElement('li');
    row.className = item.done ? 'done' : '';
    row.textContent = item.text;
    list.append(row);
  }

  card.append(header, progress, progressText, list);
  return card;
}

function selectRun(index) {
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
    renderOperationalState(run),
    renderCostTracking(run),
    renderMemoryState(run),
    renderVerificationPanel(run),
    renderTextList('Risks', run.risks),
    renderTextList('Next steps', run.nextSteps),
    renderSteps(run.steps)
  );
}

function clearInspector() {
  inspector.hidden = true;
  inspectorEmpty.hidden = false;
  inspector.replaceChildren();
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
  const heading = document.createElement('h3');
  heading.textContent = title;
  const list = document.createElement('ul');

  const items = values.length > 0 ? values : ['None'];
  for (const value of items) {
    const item = document.createElement('li');
    item.textContent = value;
    list.append(item);
  }

  section.append(heading, list);
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
