# Archived Session — 2026-04-12 — Pixeldex + Damage Calculator

Archived from `handoff/SESSION-CHECKPOINT.md` and `handoff/BUILD-LOG.md` on 2026-04-26.
Read this only if you need historical context for the pixeldex/calculator work.

---

## Session Summary

Steps 1–8 all committed and pushed to `main`. 100 tests passing (256 assertions).
DB seeded with full extended data: 493 base stats with abilities/flavor_text/etc.,
466 moves with crit_rate/min_hits/etc., 29641 learnsets. Both calculator UIs
functional (Quick modal on party page, Full CALC tab on dashboard).

Last logged commit: `b7a3f06` — 2026-04-12.

Five post-session commits landed on `main` outside the Three Man Team flow
(calc UI tweaks, species assigner link, species/move input fixes, gym team
picker showing dead pokemon).

---

## What Was Built

### Step 1 — Full Evolution Chain Display
- `app/javascript/controllers/pixeldex_controller.js` — evolution chain rendering

### Step 2 — Database Tables + Seed Data
- 3 migrations, 3 models (`Pokemon::BaseStat`, `Pokemon::Move`, `Pokemon::Learnset`)
- Rake tasks: `pokemon:fetch` + `pokemon:seed`

### Step 3 — Damage Calculator Service
- `app/services/pokemon/damage_calculator.rb` — Gen IV damage formula

### Step 4 — Data Layer Hardening + Schema Extensions
- XSS fix: 3 innerHTML sites → createElement in pixeldex_controller.js
- 2 migrations: 14 new BaseStat columns, 10 new Move columns
- Seed task updated to persist all YAML fields
- Validation: national_dex_number 1..493
- 5 query scopes: BaseStat.by_type, Move.with_priority, Move.multi_hit,
  Learnset.by_method, Learnset.by_level_range

### Step 5 — Calculator Extensions
- Multi-hit: per-hit min/max, min_total, max_total, avg_total, is_multi_hit
- Crit: Gen IV 2x multiplier, crit_min/crit_max, crit_stage/crit_chance
- 24 tests, 83 assertions

### Step 6 — Branched Evolution Display
- evolutions.yml restructured to array format with all 11 branching pokemon
- JS rewritten: recursive tree builder + renderer, active path highlighted

### Step 7 — Quick Calculator Modal
- API: `GET /api/pokemon/:species`, `POST /api/calculator` with `Api::BaseController` auth
- Modal on party page: defender pre-filled, attacker/move selectable, Escape to close
- Stimulus: `quick_calc_controller.js`

### Step 8 — Full Calculator Tab
- CALC tab in dashboard (7th tab)
- Two-column attacker/defender with quick-pick team buttons
- Swap button, move dropdown, results display, clickable history (last 5)
- Stimulus: `full_calc_controller.js`

---

## Decisions From This Session

- Calculator is database-backed: `pokemon_base_stats`, `pokemon_moves`, `pokemon_learnsets`
- Models namespaced under `Pokemon::`
- YAML cache files checked into git — PokeAPI is a one-time fetch
- Gen IV damage formula with integer flooring at each step
- Gen IV crit = 2x multiplier (not 1.5x)
- Explosion/Self-Destruct halve target's defense
- No abilities/items/weather in calculator (base damage only, expandable later)
- Multi-hit shows per-hit, total, and average damage
- Branched evolutions: full tree with active path highlighted, inactive branches muted
- evolves_to is array format (breaking change from old string format)
- Two calculator UIs: Quick modal (party page, defender pre-filled) + Full tab (dashboard)
- API endpoints shared between both calculator UIs
- Api::BaseController extracts shared auth for JSON endpoints
- Server-side sprite URLs via asset_path (not client-constructed paths)
- Calculator history is in-memory only (JS array, not persisted)
- 5-entry cap on evolution chain depth is fine for Gen IV

---

## Architecture Decisions Locked This Session

These are durable. They may have been moved to a persistent doc — check there
before treating this list as authoritative.

- Discord user IDs stored as String in all Stimulus value types — 2026-04-12
- User-supplied text always rendered via textContent, never innerHTML — 2026-04-12
- evolves_to is array format `[{species, level/method}]` — 2026-04-12
- Gen IV crit multiplier is 2x — 2026-04-12
- Api::BaseController is the base class for all JSON API controllers — 2026-04-12
- Server-side sprite URLs via asset_path in API responses — 2026-04-12

---

## Known Gaps Carried Forward

These were not addressed during the session. Future steps may pick them up.

- No functional/integration tests for API endpoints (`/api/pokemon`, `/api/calculator`)
- No crit stage 2/3 test coverage
- No crit totals for multi-hit moves (per-hit crit only)
- Stat summary in full calc shows raw integers without nature label
- No abilities/items/weather modifiers in calculator
- No HP calculation or percentage damage display
- 5-entry cap on evolution chain depth (fine for Gen IV)

---

## Step History — File Manifest

### Step 8 — Full Calculator Tab (committed `b7a3f06`)
**Created:** `app/views/dashboard/_calc_content.html.erb`,
`app/javascript/controllers/full_calc_controller.js`
**Changed:** `app/views/dashboard/_tab_bar.html.erb`,
`app/views/dashboard/show.html.erb`, `app/controllers/dashboard_controller.rb`

### Step 7 — Quick Calculator Modal (committed `77abf1a`)
**Created:** `app/controllers/api/base_controller.rb`,
`app/controllers/api/pokemon_controller.rb`,
`app/controllers/api/calculator_controller.rb`,
`app/views/teams/_quick_calc_modal.html.erb`,
`app/javascript/controllers/quick_calc_controller.js`
**Changed:** `config/routes.rb`, `app/views/teams/_pokemon_card.html.erb`,
`app/views/teams/show.html.erb`

### Step 6 — Branched Evolution Display (committed `de17890`)
**Changed:** `config/soul_link/evolutions.yml`,
`app/javascript/controllers/pixeldex_controller.js`

### Step 5 — Calculator Extensions: Multi-Hit + Crit (committed `de17890`)
**Changed:** `app/services/pokemon/damage_calculator.rb`,
`test/services/pokemon/damage_calculator_test.rb`

### Step 4 — Data Layer Hardening + Schema Extensions (committed `de17890`)
**Created:** `db/migrate/20260412100001_add_extended_fields_to_pokemon_base_stats.rb`,
`db/migrate/20260412100002_add_meta_fields_to_pokemon_moves.rb`
**Changed:** `app/javascript/controllers/pixeldex_controller.js`,
`lib/tasks/pokemon_data.rake`, `app/models/pokemon/base_stat.rb`,
`app/models/pokemon/move.rb`, `app/models/pokemon/learnset.rb`

### Step 3 — Damage Calculator Service (committed `f19fe4b`)
**Created:** `app/services/pokemon/damage_calculator.rb`,
`test/services/pokemon/damage_calculator_test.rb`

### Step 2 — Database Tables + Seed Data (committed `f19fe4b`)
**Created:** 3 migrations, 3 models, `lib/tasks/pokemon_data.rake`

### Step 1 — Full Evolution Chain Display (committed `f19fe4b`)
**Changed:** `app/javascript/controllers/pixeldex_controller.js`

---

## Last Review (Step 8)

**Verdict:** PASS — 12 of 12 Definition of Done items passed. No must-fix items.

**Builder summary (from REVIEW-REQUEST.md):**
- Created `app/views/dashboard/_calc_content.html.erb` and `app/javascript/controllers/full_calc_controller.js`
- Modified `app/views/dashboard/_tab_bar.html.erb`, `app/views/dashboard/show.html.erb`, `app/controllers/dashboard_controller.rb`
- 100 runs / 256 assertions passing
- Reused Step 7 API endpoints (no new backend code)

**Reviewer findings (Richard, from REVIEW-FEEDBACK.md):**
- Zero `innerHTML` with variables — confirmed via grep
- Tab switching, quick-pick buttons, swap, history reload, sprite URLs all verified
- No shared code with `quick_calc_controller.js` — duplication intentional per brief
- Security: textContent everywhere, CSRF on all API calls, `@calc_team_pokemon` scoped to `current_user_id`

**Non-blocking observations:**
- O-1: Stat summary line shows raw integers without stat-name/nature labels (cosmetic, brief specified `200 Atk (Adamant)` format, code shows `148`). Carried forward into Known Gaps.
- O-2: `_loadFromHistory` re-fetches both sides instead of using cache. Correct but slightly redundant. Not worth fixing.
