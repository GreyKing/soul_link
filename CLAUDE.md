# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Soul Link is a Rails 8.1 web app + Discord bot for managing Pokemon Platinum Soul Link Nuzlocke runs. It tracks catches, deaths, team composition, gym drafts, and battle scheduling across 4 players in a shared Discord server.

**Stack:** Ruby 3.4.5, Rails 8.1, MySQL 8, Puma, Importmap (no Node), Stimulus, Turbo, Tailwind CSS, discordrb, Discord OAuth2

## Commands

```bash
bin/dev                              # Start web server + Tailwind watcher (Procfile.dev)
rake soul_link:bot                   # Start Discord bot (separate process, must run alongside web)
bin/rails test                       # Run all tests
bin/rails test test/models/foo_test.rb       # Single test file
bin/rails test test/models/foo_test.rb:42    # Single test by line number
bin/rails db:migrate                 # Run pending migrations
bin/rails db:schema:load             # Load schema (used in CI instead of migrate)
bundle exec rubocop                  # Lint (rubocop-rails-omakase)
bundle exec brakeman                 # Security scan
```

CI uses `DATABASE_HOST=127.0.0.1` (TCP) — not Unix socket. Test database: `soul_link_test`.

## Architecture

### Domain Model

```
SoulLinkRun (one active per guild)
├── SoulLinkPokemonGroup (shared nickname, location, caught/dead status)
│   └── SoulLinkPokemon (one per player per group — species assignment)
├── SoulLinkTeam (one per player, max 6 slots)
│   └── SoulLinkTeamSlot → belongs_to PokemonGroup
├── GymDraft (multi-phase: lobby → voting → drafting → nominating → complete)
└── GymSchedule (RSVP-based scheduling: proposed → confirmed → completed/cancelled)
```

### Authentication

Discord OAuth via `omniauth-discord`. Session-based with no User model. Session keys: `discord_user_id`, `discord_username`, `discord_avatar_url`, `guild_id`. The `DiscordAuthentication` concern (`app/controllers/concerns/discord_authentication.rb`) provides `current_user_id`, `logged_in?`, `require_login`.

### Real-Time (ActionCable)

Channels: `GymDraftChannel`, `GymScheduleChannel`. Pattern: `stream_for @record`, broadcast full state via `Model#broadcast_state`, client receives `{ type: "state_update", state: {...} }`.

**Dev gotcha:** The async cable adapter (`config/cable.yml`) only works within the same process. `rails console` broadcasts won't reach the browser — use the web console (add `console` to an ERB template or controller action) instead.

Connection auth (`app/channels/application_cable/connection.rb`) uses `request.session[:discord_user_id]`.

### Game Configuration

YAML files in `config/soul_link/`: `settings.yml` (player roster, category prefix), `gym_info.yml` (8 gyms), `locations.yml`, `pokedex.yml`, `types.yml`, `progression.yml`, `map_coordinates.yml`. Loaded via `SoulLink::GameState` service which memoizes file reads.

### Discord Bot

Separate process (`rake soul_link:bot`) using `discordrb`. Handles slash commands, button interactions, and panel updates. Custom ID format: `soul_link:action:resource_id:variant`. Service code in `app/services/soul_link/`.

### Frontend

Stimulus controllers in `app/javascript/controllers/` with Importmap (no build step). Sortable.js for drag-and-drop team building. Dark Discord-inspired theme via Tailwind CSS. Propshaft asset pipeline.

### Deployment

GitHub Actions (`.github/workflows/deploy.yml`): test → SSH deploy to Vultr VPS. Production runs nginx (reverse proxy with WebSocket support at `/cable`) + Puma + systemd services (`soul-link-web`, `soul-link-bot`). Nginx config in `config/deploy/`.
