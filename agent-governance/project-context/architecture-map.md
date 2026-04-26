# Architecture Map

## High-Level Shape

- `frontend/`: React single-page app
- `backend/`: Express API server and SQLite access
- `docs/`: existing project documentation
- root `*.md`: feature-specific human docs and guides

## Request Flow

1. User interacts with the React UI.
2. Frontend calls REST endpoints through `frontend/src/api/client.js`.
3. Express routes in `backend/src/routes/` dispatch to controllers.
4. Controllers read/write SQLite through `better-sqlite3`.
5. For AI work, controllers call `backend/src/services/aiService.js`.
6. `aiService.js` selects the configured provider service and shared prompt helpers.

## Important Backend Entry Points

- `backend/src/server.js`: server startup, middleware, route mounting
- `backend/src/routes/story.js`: main app API
- `backend/src/routes/brainstorming.js`: brainstorming API
- `backend/src/controllers/storyController.js`: projects, sessions, messages, skills, overrides, vision, prompt optimization
- `backend/src/controllers/brainstormingController.js`: brainstorming lifecycle

## Important Frontend Entry Points

- `frontend/src/App.jsx`: route table
- `frontend/src/pages/HomePage.jsx`: project list, export/import, brainstorming entry
- `frontend/src/pages/ProjectDetail.jsx`: large project management screen
- `frontend/src/pages/PlaySession.jsx`: session play UI
- `frontend/src/components/StoryChat.jsx`: main story chat component
- `frontend/src/components/BrainstormingChat.jsx`: brainstorming UI

## Design Reality

- The codebase leans toward large controller/component files instead of many small modules.
- Backend behavior is centralized more than abstracted.
- Existing docs are extensive, but scattered across many markdown files.
