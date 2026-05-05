export function createRoadmapDraft(input = {}) {
  return {
    title: normalizeText(input.title),
    goal: normalizeText(input.goal),
    status: normalizeText(input.status) || 'Not started.',
    principles: normalizeTextList(input.principles),
    sequence: normalizeSequence(input.sequence),
    acceptanceCriteria: normalizeTextList(input.acceptanceCriteria),
    outOfScope: normalizeTextList(input.outOfScope)
  };
}

export function createRoadmapDraftFromFormData(formData) {
  return createRoadmapDraft({
    title: formData.get('title'),
    goal: formData.get('goal'),
    status: formData.get('status'),
    principles: splitLines(formData.get('principles')),
    sequence: splitLines(formData.get('sequence')),
    acceptanceCriteria: splitLines(formData.get('acceptanceCriteria')),
    outOfScope: splitLines(formData.get('outOfScope'))
  });
}

export function createRoadmapDraftFromMarkdown(content) {
  const lines = normalizeText(content).split(/\r?\n/);

  return createRoadmapDraft({
    title: readMarkdownTitle(lines),
    goal: readMarkdownSectionText(lines, 'Goal'),
    status: readMarkdownSectionText(lines, 'Status'),
    principles: readMarkdownBulletSection(lines, 'Principles'),
    sequence: readMarkdownChecklistSection(lines, 'Sequence'),
    acceptanceCriteria: readMarkdownBulletSection(lines, 'Acceptance Criteria'),
    outOfScope: readMarkdownBulletSection(lines, 'Out Of Scope')
  });
}

export function createRoadmapDraftExport(draftInput) {
  const draft = createRoadmapDraft(draftInput);

  return {
    fileName: createRoadmapDraftFileName(draft.title),
    mimeType: 'text/markdown;charset=utf-8',
    content: formatRoadmapDraftMarkdown(draft)
  };
}

export function formatRoadmapDraftMarkdown(draftInput) {
  const draft = createRoadmapDraft(draftInput);
  const lines = [
    `# ${draft.title}`,
    '',
    '## Goal',
    '',
    draft.goal,
    '',
    '## Status',
    '',
    draft.status,
    '',
    '## Principles',
    ''
  ];

  appendBulletList(lines, draft.principles);
  lines.push('', '## Sequence', '');
  appendSequence(lines, draft.sequence);
  lines.push('', '## Acceptance Criteria', '');
  appendBulletList(lines, draft.acceptanceCriteria);
  lines.push('', '## Out Of Scope', '');
  appendBulletList(lines, draft.outOfScope);
  lines.push('');

  return lines.join('\n');
}

export function validateRoadmapDraft(input = {}) {
  const draft = createRoadmapDraft(input);
  const errors = [];

  requireText(errors, 'title', draft.title, 'Title is required.');
  requireText(errors, 'goal', draft.goal, 'Goal is required.');
  requireList(errors, 'principles', draft.principles, 'At least one principle is required.');
  requireList(errors, 'sequence', draft.sequence, 'At least one sequence checklist item is required.');
  requireList(
    errors,
    'acceptanceCriteria',
    draft.acceptanceCriteria,
    'At least one acceptance criterion is required.'
  );
  requireList(errors, 'outOfScope', draft.outOfScope, 'At least one out-of-scope item is required.');
  errors.push(...validateSequenceShape(input.sequence));

  return {
    ok: errors.length === 0,
    errors
  };
}

function normalizeText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function splitLines(value) {
  return normalizeText(value)
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
}

function createRoadmapDraftFileName(title) {
  const normalizedTitle = normalizeText(title)
    .replace(/^Next Roadmap:\s*/i, 'Next ')
    .replace(/^Roadmap:\s*/i, '')
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');

  return `${normalizedTitle || 'ROADMAP_DRAFT'}.md`;
}

function normalizeTextList(values) {
  if (!Array.isArray(values)) {
    return [];
  }

  return values.map(normalizeText).filter((value) => value.length > 0);
}

function normalizeSequence(values) {
  if (!Array.isArray(values)) {
    return [];
  }

  return values.flatMap((value) => {
    if (typeof value === 'string') {
      const text = normalizeText(value);
      return text.length > 0 ? [parseSequenceTextLine(text)] : [];
    }

    if (!value || typeof value !== 'object') {
      return [];
    }

    const text = normalizeText(value.text);
    return text.length > 0
      ? [
          {
            done: value.done === true,
            text
          }
        ]
      : [];
  });
}

function parseSequenceTextLine(text) {
  const match = text.match(/^(?:(?:[-*]|\d+\.)\s+)?\[(x|X| )\]\s+(.+)$/);

  if (!match) {
    return {
      done: false,
      text
    };
  }

  return {
    done: match[1].toLowerCase() === 'x',
    text: match[2].trim()
  };
}

function readMarkdownTitle(lines) {
  const titleLine = lines.find((line) => line.startsWith('# '));
  return titleLine ? titleLine.replace(/^#\s+/, '').trim() : '';
}

function readMarkdownSectionText(lines, sectionName) {
  return readMarkdownSectionLines(lines, sectionName)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .join('\n');
}

function readMarkdownBulletSection(lines, sectionName) {
  return readMarkdownListSection(lines, sectionName, /^\s*[-*]\s+(.+)$/);
}

function readMarkdownChecklistSection(lines, sectionName) {
  const values = [];
  let current = null;

  for (const line of readMarkdownSectionLines(lines, sectionName)) {
    const match = line.match(/^\s*(?:[-*]|\d+\.)\s+\[(x|X| )\]\s+(.+)$/);
    const trimmed = line.trim();

    if (match) {
      current = {
        done: match[1].toLowerCase() === 'x',
        text: match[2].trim()
      };
      values.push(current);
    } else if (current && trimmed.length > 0) {
      current.text = `${current.text} ${trimmed}`.trim();
    }
  }

  return values;
}

function readMarkdownListSection(lines, sectionName, pattern) {
  const values = [];
  let currentIndex = -1;

  for (const line of readMarkdownSectionLines(lines, sectionName)) {
    const match = line.match(pattern);
    const trimmed = line.trim();

    if (match) {
      values.push(match[1].trim());
      currentIndex = values.length - 1;
    } else if (currentIndex >= 0 && trimmed.length > 0) {
      values[currentIndex] = `${values[currentIndex]} ${trimmed}`.trim();
    }
  }

  return values;
}

function readMarkdownSectionLines(lines, sectionName) {
  const sectionIndex = lines.findIndex(
    (line) => line.trim().toLowerCase() === `## ${sectionName.toLowerCase()}`
  );

  if (sectionIndex === -1) {
    return [];
  }

  const sectionLines = [];

  for (const line of lines.slice(sectionIndex + 1)) {
    if (line.trim().startsWith('## ')) {
      break;
    }

    sectionLines.push(line);
  }

  return sectionLines;
}

function appendBulletList(lines, values) {
  for (const value of values) {
    lines.push(`- ${value}`);
  }
}

function appendSequence(lines, values) {
  values.forEach((value, index) => {
    const marker = value.done ? 'x' : ' ';
    lines.push(`${index + 1}. [${marker}] ${value.text}`);
  });
}

function requireText(errors, field, value, message) {
  if (value.length === 0) {
    errors.push({ field, message });
  }
}

function requireList(errors, field, values, message) {
  if (values.length === 0) {
    errors.push({ field, message });
  }
}

function validateSequenceShape(values) {
  if (!Array.isArray(values)) {
    return [];
  }

  return values.flatMap((value, index) => {
    if (typeof value === 'string') {
      return normalizeText(value).length > 0
        ? []
        : [
            {
              field: `sequence[${index}].text`,
              message: 'Checklist item text is required.'
            }
          ];
    }

    if (!value || typeof value !== 'object') {
      return [
        {
          field: `sequence[${index}]`,
          message: 'Checklist item must be text or an object.'
        }
      ];
    }

    const errors = [];

    if ('done' in value && typeof value.done !== 'boolean') {
      errors.push({
        field: `sequence[${index}].done`,
        message: 'Checklist item done must be a boolean.'
      });
    }

    if (normalizeText(value.text).length === 0) {
      errors.push({
        field: `sequence[${index}].text`,
        message: 'Checklist item text is required.'
      });
    }

    return errors;
  });
}
