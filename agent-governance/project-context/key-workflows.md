# Key Workflows

## 1. Manual Project Flow

1. Create project.
2. Add or edit skills, characters, settings, and optional prompt optimization.
3. Start a session.
4. Activate needed skills for that session.
5. Play through `POST /api/messages`.

## 2. Brainstorming Flow

1. Start brainstorming session with a project name.
2. Backend returns generated questions.
3. User answers questions in batches.
4. Session can be resumed later.
5. Finalize brainstorming to create project records and skills.

## 3. Story Message Flow

1. Load session, project, characters, active skills, and overrides.
2. Gather message history.
3. Compress older history if needed.
4. Select required skills if dynamic loading is enabled.
5. Build system prompt.
6. Send request to current AI provider.
7. Parse response, update player/session state, and persist metadata.

## 4. Skill Management Flow

1. Create project-level skill entries.
2. Optionally compress long skill content.
3. Activate/deactivate skills per session.
4. Apply session overrides where needed.

## 5. Image Flow

1. Analyze image skill entries.
2. Save structured vision metadata.
3. Summarize multiple images into a character appearance description.
4. Append that description back into a character skill.

## 6. Backup Flow

1. Export full DB to JSON.
2. Import restores whole app state.
3. This is effectively a full-environment backup/restore path, not a narrow content import.
