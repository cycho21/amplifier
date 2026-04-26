# Operations Notes

## Local Run Commands

- Backend: `cd backend && npm run dev`
- Frontend: `cd frontend && npm run dev`
- Init DB: `cd backend && npm run init-db`
- Seed debug data: `cd backend && npm run seed-debug`
- Frontend build: `cd frontend && npm run build`

## Environment Signals

- Backend defaults to port `3001`
- Frontend defaults to Vite dev port `5173`
- `AI_PROVIDER` selects provider
- `USE_CLAUDE_CODE=true` still exists as deprecated compatibility behavior
- `DYNAMIC_SKILL_LOADING=true` enables AI-based skill selection

## Useful Source Files For Troubleshooting

- `backend/src/server.js`
- `backend/src/controllers/storyController.js`
- `backend/src/services/aiService.js`
- `backend/src/models/init-db.js`
- `frontend/src/api/client.js`

## Existing Human Docs Worth Checking

- `README.md`
- `docs/API.md`
- `docs/DATABASE.md`
- `docs/FEATURES.md`
- `docs/TROUBLESHOOTING.md`
- feature-specific guides in the repo root, such as brainstorming, document parsing, image, export/import, and skill compression guides

## Practical Caveats

- The repo already contains many product docs; this `docs/agents/` set is a compact navigation layer, not a replacement.
- Some displayed Korean text may look corrupted in terminal output. Treat source structure as more reliable than rendered console text.
- The repository currently has unrelated uncommitted changes in app files. Documentation work should stay isolated unless the user asks otherwise.
