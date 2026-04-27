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

For detailed documentation, see `.claude/documents/`:

| Document | Description |
|----------|-------------|
| [domain-models.md](.claude/documents/domain-models.md) | Models, relationships, validations, JSON state patterns, cascading behaviors |
| [discord-bot.md](.claude/documents/discord-bot.md) | Bot setup, slash commands, button/modal interactions, panel management, rake tasks |
| [discord-auth.md](.claude/documents/discord-auth.md) | OAuth flow, session keys, guild validation, DiscordAuthentication concern |
| [gym-draft.md](.claude/documents/gym-draft.md) | 5-phase draft state machine, ActionCable channel, Stimulus controller |
| [gym-schedule.md](.claude/documents/gym-schedule.md) | RSVP scheduling, auto-confirm, Discord message sync |
| [frontend.md](.claude/documents/frontend.md) | Stimulus controllers, SortableJS drag-and-drop, Importmap, Tailwind theme |
| [services.md](.claude/documents/services.md) | GameState config loader, TypeChart analysis, YAML file reference |
| [controllers-routes.md](.claude/documents/controllers-routes.md) | Full route map, controller actions, common patterns |
| [deployment.md](.claude/documents/deployment.md) | CI/CD pipeline, systemd services, nginx, Puma, database config |

### Quick Reference

- **Domain model:** `SoulLinkRun` → `PokemonGroup` → `Pokemon` (one per player per group). Teams have max 6 slots referencing groups.
- **Auth:** Discord OAuth, session-based, no User model. Guild ID scopes all data.
- **Real-time:** ActionCable channels for GymDraft and GymSchedule. Pattern: `stream_for @record`, broadcast full state, client re-renders.
- **Dev gotcha:** Async cable adapter only works within same process — `rails console` broadcasts won't reach browser.
- **Config:** YAML files in `config/soul_link/`, loaded via `SoulLink::GameState`.
- **Bot:** Separate process (`rake soul_link:bot`), shares Rails models. Custom ID format: `soul_link:action:context:value`.
- **Frontend:** Stimulus + Importmap + SortableJS + Tailwind (dark theme). No Node/npm.

### Testing conventions

- **New tests** use FactoryBot factories from `test/factories/`.
- **Legacy tests** use fixtures from `test/fixtures/`. Do not convert without an explicit step.
- Factories should be minimum-viable — just enough to satisfy validations and associations. Don't add fields the test doesn't need.
