import { summarizeRuns } from './logParser.mjs';

const fileInput = document.querySelector('#log-files');
const runList = document.querySelector('#run-list');
const errorList = document.querySelector('#error-list');
const inspector = document.querySelector('#inspector');
const inspectorEmpty = document.querySelector('#inspector-empty');
const runCount = document.querySelector('#run-count');
const errorCount = document.querySelector('#error-count');
const stepCount = document.querySelector('#step-count');

let currentRuns = [];

fileInput.addEventListener('change', async (event) => {
  const files = Array.from(event.target.files || []).filter((file) =>
    file.name.toLowerCase().endsWith('.json')
  );
  const fileContents = await Promise.all(
    files.map(async (file) => ({
      name: file.webkitRelativePath || file.name,
      content: await file.text()
    }))
  );

  const summary = summarizeRuns(fileContents);
  currentRuns = summary.runs;
  renderSummary(summary);
  renderRunList(summary.runs);
  renderErrors(summary.errors);

  if (summary.runs.length > 0) {
    selectRun(0);
  } else {
    clearInspector();
  }
});

function renderSummary(summary) {
  runCount.textContent = String(summary.runs.length);
  errorCount.textContent = String(summary.errors.length);
  stepCount.textContent = String(
    summary.runs.reduce((total, run) => total + run.stepCount, 0)
  );
}

function renderRunList(runs) {
  runList.replaceChildren();
  runList.classList.toggle('empty', runs.length === 0);

  if (runs.length === 0) {
    const empty = document.createElement('p');
    empty.textContent = 'No logs loaded.';
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
