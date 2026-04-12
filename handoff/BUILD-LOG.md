# Build Log
*Owned by Architect. Updated by Builder after each step.*

---

## Current Status

**Active step:** None — all steps complete
**Last cleared:** Step 5 — 2026-04-12
**Pending deploy:** YES (6 commits on main)

---

## Step History

### Step 5 — Gym Result: Mark Beaten + Team Snapshot + Backfill — COMPLETE
*Date: 2026-04-12*

Files created:
- `app/models/gym_result.rb` — model with snapshot builder methods
- `app/controllers/gym_results_controller.rb` — backfill endpoint
- `app/javascript/controllers/gym_backfill_controller.js` — Stimulus picker
- `db/migrate/20260412180452_create_gym_results.rb` — gym_results table

Files changed:
- `app/models/soul_link_run.rb` — has_many :gym_results
- `app/models/gym_draft.rb` — has_many :gym_results, dependent: :nullify
- `app/controllers/gym_progress_controller.rb` — reworked to use GymResult
- `app/controllers/gym_drafts_controller.rb` — mark_beaten action + show vars
- `app/controllers/dashboard_controller.rb` — load gym_results + backfill groups
- `app/services/soul_link/game_state.rb` — gym_info_by_number helper
- `app/views/gym_drafts/show.html.erb` — mark beaten button
- `app/views/dashboard/_gyms_content.html.erb` — snapshots, backfill, mark beaten
- `config/routes.rb` — mark_beaten + gym_results routes

Deploy: committed 9883e62

### Step 4 — Test Suite (KG-5) — COMPLETE
*Date: 2026-04-12*

Files created:
- `test/fixtures/soul_link_teams.yml`, `soul_link_team_slots.yml`, `gym_results.yml`
- `test/models/soul_link_pokemon_test.rb` (7 tests)
- `test/models/soul_link_pokemon_group_test.rb` (7 tests)
- `test/models/gym_result_test.rb` (4 tests)
- `test/controllers/pokemon_groups_controller_test.rb` (6 tests)
- `test/controllers/pokemon_controller_test.rb` (5 tests)
- `test/controllers/species_assignments_controller_test.rb` (5 tests)
- `test/controllers/teams_controller_test.rb` (6 tests)

Bugs found during testing:
- Pokemon fixtures had wrong group references (underscore mismatch) — fixed
- TeamsController DISTINCT+ORDER failed on MySQL — fixed with .reorder(nil)

Result: 76 tests, 173 assertions, 0 failures
Deploy: committed be5e9e5

### Step 3 — Fix Known Gaps KG-1 through KG-4 — COMPLETE
*Date: 2026-04-12*

Files changed:
- `db/migrate/20260412120000_make_pokemon_group_user_index_unique.rb` — unique index
- `app/controllers/species_assignments_controller.rb` — transaction + RecordNotUnique
- `app/controllers/pokemon_controller.rb` — transaction + RecordNotUnique
- `app/controllers/teams_controller.rb` — ownership filter with join
- `app/views/dashboard/_pc_box_content.html.erb` — fallen species fallback
- `app/controllers/pokemon_groups_controller.rb` — partial rollback
- `app/views/species_assignments/_group_card.html.erb` — route text 11px bold

Deploy: committed 6d8cb6f

### Step 2 — Gym Draft Playability Fixes — COMPLETE
*Date: 2026-04-12*

Files changed:
- `app/models/gym_draft.rb` — nomination turn enforcement, skip_turn!
- `app/channels/gym_draft_channel.rb` — skip action
- `app/javascript/controllers/gym_draft_controller.js` — innerHTML→DOM, double-click, skip timer, turn indicator
- `app/views/gym_drafts/show.html.erb` — skipButton targets

Deploy: committed abf9a53

### Step 1 — Fix Pokemon Creation Species-Saving Bugs — COMPLETE
*Date: 2026-04-12*

Files changed:
- `app/javascript/controllers/dashboard_controller.js` — userId: Number → String
- `app/javascript/controllers/species_assignment_controller.js` — userId: Number → String
- `app/javascript/controllers/team_builder_controller.js` — userId: Number → String
- `app/javascript/controllers/pixeldex_controller.js` — sprite path + size fix

Deploy: committed 1a179d8

### Step 0 — Pokedex Default Tab — COMPLETE
*Date: 2026-04-12*

Files changed:
- `app/views/species_assignments/show.html.erb` — swapped default tab to Pokedex

Deploy: committed d69f6e7

---

## Known Gaps
*Logged here instead of fixed. Addressed in a future step.*

- **KG-6** — No Pokedex species name validation at model level — logged 2026-04-12
- **KG-7** — No location validation at model level — logged 2026-04-12
- **KG-8** — No GymDraftChannel ActionCable tests — logged 2026-04-12

---

## Architecture Decisions
*Locked decisions that cannot be changed without breaking the system.*

- Discord user IDs stored as String in all Stimulus value types — 2026-04-12
- Gym draft skip-turn callable by any player, no server timers — 2026-04-12
- User-supplied text always rendered via textContent, never innerHTML — 2026-04-12
- GymResult is source of truth for gym victories; gyms_defeated kept in sync — 2026-04-12
- Team snapshots are frozen JSON blobs, not live references — 2026-04-12
- Unmark restricted to highest gym number only — 2026-04-12
