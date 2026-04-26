# Backend Guide

## Stack

- Node.js
- Express 5
- `better-sqlite3`
- Provider SDKs for Anthropic, Gemini, OpenAI/OpenRouter

## Core Files

- `backend/src/server.js`: mounts `/api`, `/api/export`, `/api/brainstorming`, plus `/health`
- `backend/src/controllers/storyController.js`: primary application logic
- `backend/src/controllers/brainstormingController.js`: project generation interview flow
- `backend/src/services/aiService.js`: provider switching layer
- `backend/src/services/claudeService.js`: shared prompt-building and Claude-centric helper logic
- `backend/src/models/database.js`: DB connection
- `backend/src/models/init-db.js`: schema initialization and lightweight migrations

## Main API Groups

- Projects: CRUD plus prompt optimization
- Sessions: create/update/delete, fetch messages, debug endpoints
- Messages: send/update/delete
- Skills: CRUD, compression, document parsing, image analysis helpers
- Session skill activation: activate/deactivate/list
- Session overrides: create/update/delete/list
- Brainstorming: start, answer, finalize, resume, delete
- Export/import: full database backup and restore
- Vision: image analysis and character appearance summarization

## AI Execution Model

- The backend picks a provider from env configuration.
- Prompt helpers are mostly centralized in Claude-oriented service code and reused across providers.
- Message sending can include:
  - compressed history
  - selected active skills
  - session overrides
  - recent assistant summaries
  - strict response-format instructions

## Notable Backend Behaviors

- Long message histories are compressed into `message_summaries`.
- Three normal summaries can be folded into one meta-summary.
- Session skills are separate from project skills; sessions activate only the skills they should carry.
- Overrides let a session replace, extend, disable, or add skill content without changing the base project.

## Known Structural Risk

`backend/src/controllers/storyController.js` is the main risk concentration point. Many features are coupled there, so changes often need broad regression awareness.
