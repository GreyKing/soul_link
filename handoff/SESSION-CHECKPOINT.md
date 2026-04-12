# Session Checkpoint — 2026-04-12
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*

---

## Where We Stopped

Steps 1-8 all committed and pushed to main. 100 tests passing (256 assertions). DB seeded with full extended data (493 base stats with abilities/flavor_text/etc., 466 moves with crit_rate/min_hits/etc., 29641 learnsets). Both calculator UIs functional.

---

## What Was Built

### Step 1 — Full Evolution Chain Display (COMPLETE)
- `app/javascript/controllers/pixeldex_controller.js` — evolution chain rendering

### Step 2 — Database Tables + Seed Data (COMPLETE)
- 3 migrations, 3 models (`Pokemon::BaseStat`, `Pokemon::Move`, `Pokemon::Learnset`)
- Rake tasks: `pokemon:fetch` + `pokemon:seed` (both run)

### Step 3 — Damage Calculator Service (COMPLETE)
- `app/services/pokemon/damage_calculator.rb` — Gen IV damage formula

### Step 4 — Data Layer Hardening + Schema Extensions (COMPLETE)
- XSS fix: 3 innerHTML sites → createElement in pixeldex_controller.js
- 2 migrations: 14 new BaseStat columns, 10 new Move columns
- Seed task updated to persist all YAML fields
- Validation: national_dex_number 1..493
- 5 query scopes: BaseStat.by_type, Move.with_priority, Move.multi_hit, Learnset.by_method, Learnset.by_level_range

### Step 5 — Calculator Extensions (COMPLETE)
- Multi-hit: per-hit min/max, min_total, max_total, avg_total, is_multi_hit
- Crit: Gen IV 2x multiplier, crit_min/crit_max, crit_stage/crit_chance
- 24 tests, 83 assertions

### Step 6 — Branched Evolution Display (COMPLETE)
- evolutions.yml restructured to array format with all 11 branching pokemon
- JS rewritten: recursive tree builder + renderer, active path highlighted

### Step 7 — Quick Calculator Modal (COMPLETE)
- API: `GET /api/pokemon/:species`, `POST /api/calculator` with `Api::BaseController` auth
- Modal on party page: defender pre-filled, attacker/move selectable, Escape to close
- Stimulus: `quick_calc_controller.js`

### Step 8 — Full Calculator Tab (COMPLETE)
- CALC tab in dashboard (7th tab)
- Two-column attacker/defender with quick-pick team buttons
- Swap button, move dropdown, results display, clickable history (last 5)
- Stimulus: `full_calc_controller.js`

---

## What Was Decided This Session

- Calculator is database-backed: `pokemon_base_stats`, `pokemon_moves`, `pokemon_learnsets` tables
- Models namespaced under `Pokemon::`
- YAML cache files checked into git — PokeAPI is a one-time fetch
- Gen IV damage formula with integer flooring at each step
- Gen IV crit = 2x multiplier (not 1.5x)
- Explosion/Self-Destruct halve target's defense
- No abilities/items/weather in calculator (base damage only, expandable later)
- Multi-hit shows per-hit, total, and average damage
- Branched evolutions: full tree with active path highlighted, inactive branches muted
- evolves_to is array format (breaking change from old string format)
- Two calculator UIs: Quick modal (party page, defender pre-filled) + Full tab (dashboard, both sides selectable)
- API endpoints shared between both calculator UIs
- Api::BaseController extracts shared auth for JSON endpoints
- Server-side sprite URLs via asset_path (not client-constructed paths)
- Calculator history is in-memory only (JS array, not persisted)
- 5-entry cap on evolution chain depth is fine for Gen IV

---

## Known Gaps / Future Work

- No test coverage for API endpoints (functional tests for /api/pokemon, /api/calculator)
- No crit stage 2/3 test coverage
- No crit totals for multi-hit moves (per-hit crit only)
- Stat summary line in full calc shows raw integers without nature label (nit)
- No abilities/items/weather modifiers in calculator
- No HP calculation or percentage damage display

---

## Resume Prompt

Copy and paste this to resume:

---

You are Ava (Architect) on Soul Link — Three Man Team.
Read handoff/SESSION-CHECKPOINT.md, then handoff/BUILD-LOG.md.
Confirm status and next action. Then wait for direction.

---
