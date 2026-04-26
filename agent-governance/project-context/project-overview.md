# Project Overview

## Purpose

InteractiveNovel is an AI-powered storytelling tool. A user creates a project, defines world data and reusable lore units, starts one or more play sessions, and chats with the story engine. The app keeps player state, active lore, message history, and optional images in sync.

## Primary Concepts

- `project`: top-level container for world setting, rules, characters, and reusable skills
- `session`: one playthrough inside a project
- `message`: one user or assistant turn in a session
- `skill`: structured lore/context unit such as a character, location, item, rule, lore note, image, or custom entry
- `override`: session-local modification of an existing skill
- `brainstorming session`: AI-guided intake flow that generates a new project from Q&A

## Main User Flows

- Create a project manually
- Create a project through brainstorming
- Manage skills and character lore
- Start a play session with player state
- Send story messages and receive AI responses
- Import/export the whole database
- Analyze images and attach appearance summaries to character skills

## AI Features

- Multiple providers: Claude API, Claude CLI mode, Gemini, OpenRouter
- Prompt optimization for project world/rule text
- Dynamic skill selection to reduce prompt size
- Message compression and meta-summary generation for long sessions
- Vision analysis for image-based character details

## What Matters Most For Agents

- The backend is the source of truth for workflows and data shape.
- `storyController.js` is large and contains most core behavior.
- The project is feature-rich but structurally simple: one SPA, one API server, one SQLite DB.
