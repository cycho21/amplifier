# Frontend Guide

## Stack

- React 19
- React Router
- Axios
- Vite
- TailwindCSS

## App Routes

- `/`: home page and project list
- `/create`: manual project creation
- `/brainstorm`: brainstorming flow
- `/project/:id`: project detail and management
- `/project/:projectId/session/:sessionId`: active play session

## Main Screens

- `HomePage`: project selection, import/export, brainstorming entry
- `CreateProject`: manual project creation
- `ProjectDetail`: overview, skills, settings, sessions, image/skill tools
- `PlaySession`: actual game/session experience

## Main Components

- `StoryChat`: story interaction UI
- `SkillManager`: skill CRUD and activation management
- `PlayerStatus`: player stats/inventory/location display
- `DetailedStatus`: expanded status view
- `OverrideModal`: session override editing
- `DocumentParser`: convert raw text documents into skill candidates
- `BrainstormingChat`: guided project setup Q&A

## Frontend API Layer

All HTTP calls are centralized in `frontend/src/api/client.js`.

Key client groups:

- `projectAPI`
- `sessionAPI`
- `messageAPI`
- `skillAPI`
- `overrideAPI`
- `visionAPI`
- `brainstormingAPI`
- `dataAPI`

## Frontend Reality

- `ProjectDetail.jsx` is large and acts as a feature hub.
- The UI exposes many backend capabilities directly rather than hiding them behind a deep state layer.
- A lot of text labels are Korean even though the structure is straightforward.
