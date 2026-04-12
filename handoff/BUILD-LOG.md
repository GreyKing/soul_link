# Build Log
*Owned by Architect. Updated by Builder after each step.*

---

## Current Status

**Active step:** None — Steps 1-8 complete
**Last committed:** b7a3f06 — 2026-04-12
**Pending deploy:** NO

---

## Step History

### Step 8 — Full Calculator Tab in Dashboard (2026-04-12)
**Status:** Complete, committed b7a3f06, pushed

**Files created:**
- `app/views/dashboard/_calc_content.html.erb` — full calculator tab partial with two-column attacker/defender layout, swap button, move section, results, history
- `app/javascript/controllers/full_calc_controller.js` — self-contained Stimulus controller managing both sides, swap, quick-pick team buttons, clickable history (last 5)

**Files changed:**
- `app/views/dashboard/_tab_bar.html.erb` — added CALC tab button (7th tab)
- `app/views/dashboard/show.html.erb` — added calc tab content div
- `app/controllers/dashboard_controller.rb` — added `@calc_team_pokemon` for quick-pick data

**Key decisions:**
- Reuses Step 7 API endpoints (no new backend)
- Self-contained controller (no shared code with quick_calc_controller)
- History is in-memory only (lost on reload)
- Swap re-fetches both sides and repopulates move dropdown

---

### Step 7 — Quick Calculator Modal on Party Page (2026-04-12)
**Status:** Complete, committed 77abf1a, pushed

**Files created:**
- `app/controllers/api/base_controller.rb` — shared auth for API endpoints
- `app/controllers/api/pokemon_controller.rb` — GET /api/pokemon/:species (stats, types, sprite_url, damaging moves)
- `app/controllers/api/calculator_controller.rb` — POST /api/calculator (damage result with param validation)
- `app/views/teams/_quick_calc_modal.html.erb` — modal partial following .gb-modal pattern
- `app/javascript/controllers/quick_calc_controller.js` — Stimulus controller for modal lifecycle, fetch, display

**Files changed:**
- `config/routes.rb` — added namespace :api with pokemon + calculator routes
- `app/views/teams/_pokemon_card.html.erb` — added calc button (⚔) to each pokemon badge
- `app/views/teams/show.html.erb` — wrapped in quick-calc controller, renders modal partial

**Key decisions:**
- Server-side sprite URLs via helpers.asset_path (handles digested assets + special char species)
- Parameter validation on calculator endpoint (returns 422 for missing params)
- Escape key closes modal (keydown handler + tabindex for focus)
- Api::BaseController extracts shared require_login_json

---

### Step 6 — Branched Evolution Display (2026-04-12)
**Status:** Complete, committed de17890, pushed

**Files changed:**
- `config/soul_link/evolutions.yml` — restructured evolves_to from string to array of {species, level/method}; added all 11 branching pokemon
- `app/javascript/controllers/pixeldex_controller.js` — replaced #buildEvolutionChain with recursive #buildEvolutionTree, #findParentOf, #buildNode, #markActivePath, #renderEvoNode

**Key decisions:**
- Tree structure: {name, trigger, children, isSelected, onActivePath}
- Active path: accent color, inactive branches muted with opacity
- Linear chains inline, branches indent vertically with left border
- No server-side changes needed

---

### Step 5 — Calculator Extensions: Multi-Hit + Crit (2026-04-12)
**Status:** Complete, committed de17890, pushed

**Files changed:**
- `app/services/pokemon/damage_calculator.rb` — CRIT_CHANCES, multi-hit fields, crit fields, zero_result helper
- `test/services/pokemon/damage_calculator_test.rb` — 6 new tests (24 total, 83 assertions)

**Key decisions:**
- Gen IV crit = 2x (not 1.5x)
- Crit applied to base_damage before modifiers
- Multi-hit: min_total, max_total, avg_total with average hits
- respond_to? guards for mock compatibility

---

### Step 4 — Data Layer Hardening + Schema Extensions (2026-04-12)
**Status:** Complete, committed de17890, pushed

**Files created:**
- `db/migrate/20260412100001_add_extended_fields_to_pokemon_base_stats.rb` — 14 columns
- `db/migrate/20260412100002_add_meta_fields_to_pokemon_moves.rb` — 10 columns

**Files changed:**
- `app/javascript/controllers/pixeldex_controller.js` — XSS fix (3 innerHTML → createElement)
- `lib/tasks/pokemon_data.rake` — expanded seed slices, meta flatten
- `app/models/pokemon/base_stat.rb` — validation + by_type scope
- `app/models/pokemon/move.rb` — with_priority, multi_hit scopes
- `app/models/pokemon/learnset.rb` — by_method, by_level_range scopes

---

### Step 3 — Damage Calculator Service (2026-04-12)
**Status:** Complete, committed f19fe4b, pushed

**Files created:**
- `app/services/pokemon/damage_calculator.rb` — Gen IV damage formula
- `test/services/pokemon/damage_calculator_test.rb` — 18 tests

---

### Step 2 — Database Tables + Seed Data (2026-04-12)
**Status:** Complete, committed f19fe4b, pushed

**Files created:**
- 3 migrations (pokemon_base_stats, pokemon_moves, pokemon_learnsets)
- 3 models (Pokemon::BaseStat, Pokemon::Move, Pokemon::Learnset)
- `lib/tasks/pokemon_data.rake` — fetch + seed tasks

---

### Step 1 — Full Evolution Chain Display (2026-04-12)
**Status:** Complete, committed f19fe4b, pushed

**Files changed:**
- `app/javascript/controllers/pixeldex_controller.js` — #buildEvolutionChain + #populateEvolution

---

## Known Gaps
*Logged here instead of fixed. Addressed in a future step.*

- No functional/integration tests for API endpoints (/api/pokemon, /api/calculator)
- No crit stage 2/3 test coverage
- No crit totals for multi-hit moves (per-hit crit only)
- Stat summary in full calc shows raw integers without nature label
- No abilities/items/weather modifiers in calculator
- No HP calculation or percentage damage display
- 5-entry cap on evolution chain depth (fine for Gen IV)

---

## Architecture Decisions
*Locked decisions that cannot be changed without breaking the system.*

- Discord user IDs stored as String in all Stimulus value types — 2026-04-12
- User-supplied text always rendered via textContent, never innerHTML — 2026-04-12
- evolves_to is array format [{species, level/method}] — 2026-04-12
- Gen IV crit multiplier is 2x — 2026-04-12
- Api::BaseController is the base class for all JSON API controllers — 2026-04-12
- Server-side sprite URLs via asset_path in API responses — 2026-04-12
