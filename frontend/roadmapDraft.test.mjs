import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createRoadmapDraft,
  createRoadmapDraftExport,
  createRoadmapDraftFromFormData,
  createRoadmapDraftFromMarkdown,
  formatRoadmapDraftMarkdown,
  validateRoadmapDraft
} from './roadmapDraft.mjs';

test('createRoadmapDraft normalizes roadmap authoring fields', () => {
  const draft = createRoadmapDraft({
    title: '  Next Roadmap: Operator Control  ',
    goal: '  Build local operator controls.  ',
    status: 'In progress.',
    principles: [' Draft first. ', '', ' Validate before save. '],
    sequence: [' Add a draft model. ', { text: ' Add preview. ', done: true }],
    acceptanceCriteria: [' Drafts can be previewed. '],
    outOfScope: [' Real workflow execution. ']
  });

  assert.deepEqual(draft, {
    title: 'Next Roadmap: Operator Control',
    goal: 'Build local operator controls.',
    status: 'In progress.',
    principles: ['Draft first.', 'Validate before save.'],
    sequence: [
      {
        done: false,
        text: 'Add a draft model.'
      },
      {
        done: true,
        text: 'Add preview.'
      }
    ],
    acceptanceCriteria: ['Drafts can be previewed.'],
    outOfScope: ['Real workflow execution.']
  });
});

test('formatRoadmapDraftMarkdown emits the roadmap sections in repository format', () => {
  const markdown = formatRoadmapDraftMarkdown(
    createRoadmapDraft({
      title: 'Next Roadmap: Operator Control',
      goal: 'Build local operator controls.',
      status: 'Not started.',
      principles: ['Draft first.'],
      sequence: ['Add a draft model.'],
      acceptanceCriteria: ['Drafts can be previewed.'],
      outOfScope: ['Real workflow execution.']
    })
  );

  assert.equal(
    markdown,
    [
      '# Next Roadmap: Operator Control',
      '',
      '## Goal',
      '',
      'Build local operator controls.',
      '',
      '## Status',
      '',
      'Not started.',
      '',
      '## Principles',
      '',
      '- Draft first.',
      '',
      '## Sequence',
      '',
      '1. [ ] Add a draft model.',
      '',
      '## Acceptance Criteria',
      '',
      '- Drafts can be previewed.',
      '',
      '## Out Of Scope',
      '',
      '- Real workflow execution.',
      ''
    ].join('\n')
  );
});

test('validateRoadmapDraft accepts a complete roadmap draft', () => {
  assert.deepEqual(
    validateRoadmapDraft({
      title: 'Next Roadmap: Operator Control',
      goal: 'Build local operator controls.',
      status: 'Not started.',
      principles: ['Draft first.'],
      sequence: [{ done: false, text: 'Add validation.' }],
      acceptanceCriteria: ['Invalid drafts cannot be saved.'],
      outOfScope: ['Real workflow execution.']
    }),
    {
      ok: true,
      errors: []
    }
  );
});

test('validateRoadmapDraft reports missing required sections', () => {
  assert.deepEqual(validateRoadmapDraft({}), {
    ok: false,
    errors: [
      {
        field: 'title',
        message: 'Title is required.'
      },
      {
        field: 'goal',
        message: 'Goal is required.'
      },
      {
        field: 'principles',
        message: 'At least one principle is required.'
      },
      {
        field: 'sequence',
        message: 'At least one sequence checklist item is required.'
      },
      {
        field: 'acceptanceCriteria',
        message: 'At least one acceptance criterion is required.'
      },
      {
        field: 'outOfScope',
        message: 'At least one out-of-scope item is required.'
      }
    ]
  });
});

test('validateRoadmapDraft reports invalid checklist item shape', () => {
  assert.deepEqual(
    validateRoadmapDraft({
      title: 'Next Roadmap: Operator Control',
      goal: 'Build local operator controls.',
      principles: ['Draft first.'],
      sequence: [
        { done: 'yes', text: 'Add validation.' },
        { done: false, text: ' ' },
        42
      ],
      acceptanceCriteria: ['Invalid drafts cannot be saved.'],
      outOfScope: ['Real workflow execution.']
    }),
    {
      ok: false,
      errors: [
        {
          field: 'sequence[0].done',
          message: 'Checklist item done must be a boolean.'
        },
        {
          field: 'sequence[1].text',
          message: 'Checklist item text is required.'
        },
        {
          field: 'sequence[2]',
          message: 'Checklist item must be text or an object.'
        }
      ]
    }
  );
});

test('createRoadmapDraftFromFormData creates a draft from authoring fields', () => {
  const formData = new FormData();
  formData.set('title', 'Next Roadmap: Operator Control');
  formData.set('goal', 'Build local operator controls.');
  formData.set('status', 'Not started.');
  formData.set('principles', 'Draft first.\n\nValidate before save.');
  formData.set('sequence', 'Add authoring UI.\nAdd preview.');
  formData.set('acceptanceCriteria', 'Drafts can be created in browser.');
  formData.set('outOfScope', 'File writes.');

  assert.deepEqual(createRoadmapDraftFromFormData(formData), {
    title: 'Next Roadmap: Operator Control',
    goal: 'Build local operator controls.',
    status: 'Not started.',
    principles: ['Draft first.', 'Validate before save.'],
    sequence: [
      {
        done: false,
        text: 'Add authoring UI.'
      },
      {
        done: false,
        text: 'Add preview.'
      }
    ],
    acceptanceCriteria: ['Drafts can be created in browser.'],
    outOfScope: ['File writes.']
  });
});

test('createRoadmapDraftFromFormData preserves checklist state from sequence input', () => {
  const formData = new FormData();
  formData.set('title', 'Next Roadmap: Operator Control');
  formData.set('goal', 'Build local operator controls.');
  formData.set('status', 'In progress.');
  formData.set('principles', 'Draft first.');
  formData.set('sequence', '1. [x] Add authoring UI.\n2. [ ] Add save control.');
  formData.set('acceptanceCriteria', 'Drafts can be edited.');
  formData.set('outOfScope', 'Real workflow execution.');

  assert.deepEqual(createRoadmapDraftFromFormData(formData).sequence, [
    {
      done: true,
      text: 'Add authoring UI.'
    },
    {
      done: false,
      text: 'Add save control.'
    }
  ]);
});

test('createRoadmapDraftFromMarkdown creates an editable draft from an existing roadmap', () => {
  const markdown = [
    '# Next Roadmap: Operator Control',
    '',
    '## Goal',
    '',
    'Build local operator controls.',
    '',
    '## Status',
    '',
    'In progress.',
    '',
    '## Principles',
    '',
    '- Draft first.',
    '- Validate before save.',
    '',
    '## Sequence',
    '',
    '1. [x] Add authoring UI.',
    '2. [ ] Add save control that can',
    '   overwrite existing roadmaps.',
    '',
    '## Acceptance Criteria',
    '',
    '- Existing roadmaps can be edited.',
    '',
    '## Out Of Scope',
    '',
    '- Real workflow execution.'
  ].join('\n');

  assert.deepEqual(createRoadmapDraftFromMarkdown(markdown), {
    title: 'Next Roadmap: Operator Control',
    goal: 'Build local operator controls.',
    status: 'In progress.',
    principles: ['Draft first.', 'Validate before save.'],
    sequence: [
      {
        done: true,
        text: 'Add authoring UI.'
      },
      {
        done: false,
        text: 'Add save control that can overwrite existing roadmaps.'
      }
    ],
    acceptanceCriteria: ['Existing roadmaps can be edited.'],
    outOfScope: ['Real workflow execution.']
  });
});

test('createRoadmapDraftExport returns markdown content and a repository-style filename', () => {
  const draft = createRoadmapDraft({
    title: 'Next Roadmap: Operator Control',
    goal: 'Build local operator controls.',
    status: 'Not started.',
    principles: ['Draft first.'],
    sequence: ['Add markdown preview.'],
    acceptanceCriteria: ['Drafts can be exported.'],
    outOfScope: ['File writes.']
  });

  const exported = createRoadmapDraftExport(draft);

  assert.equal(exported.fileName, 'NEXT_OPERATOR_CONTROL.md');
  assert.equal(exported.mimeType, 'text/markdown;charset=utf-8');
  assert.equal(exported.content, formatRoadmapDraftMarkdown(draft));
});
