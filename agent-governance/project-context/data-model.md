# Data Model

## Core Tables

- `projects`: project metadata plus serialized settings and optional optimized prompt
- `characters`: standalone character records tied to a project
- `sessions`: one playthrough per row, including serialized `player_state`
- `messages`: ordered user/assistant chat history
- `snapshots`: periodic saved state during play
- `skill_settings`: reusable lore/context units for a project
- `session_active_skills`: many-to-many link between sessions and active skills
- `session_skill_overrides`: session-local modifications to project skills
- `message_summaries`: compressed history blocks and meta-summaries
- `brainstorming_sessions`: unfinished AI-led project creation sessions

## Important JSON Fields

- `projects.settings`
  - usually contains world setting, rules, status template, image template, and related options
- `sessions.player_state`
  - player character info, stats, inventory, location, initialization flags
- `messages.metadata`
  - state changes, image references, dialogues, usage info, summaries, and other structured output
- `skill_settings.metadata`
  - image analysis and related structured data

## Skill Categories

- `character`
- `location`
- `item`
- `rule`
- `lore`
- `image`
- `custom`

## Session Override Types

- `override`: replace base skill
- `extend`: append to base skill
- `disable`: remove from session context
- `new`: add session-only skill

## Data Model Notes

- SQLite is the only persistence layer.
- Most complex state is stored as JSON blobs rather than normalized tables.
- That makes feature delivery easy, but schema guarantees weaker than a more normalized design.
