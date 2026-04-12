# Build Log
*Owned by Architect. Updated by Builder after each step.*

---

## Current Status

**Active step:** Step 3 — Damage Calculator Service
**Last cleared:** Fresh start — 2026-04-12
**Pending deploy:** NO

---

## Step History

### Step 3 — Damage Calculator Service (2026-04-12)
**Status:** Built, awaiting review

**Files created:**
- `app/services/pokemon/damage_calculator.rb` — `Pokemon::DamageCalculator` stateless service with Gen IV damage formula
- `test/services/pokemon/damage_calculator_test.rb` — 16 tests covering stat calc, damage ranges, STAB, type effectiveness, immunity, Explosion, nature variants, status moves, defaults

**Key decisions:**
- All class methods via `class << self` — no instantiation
- `calculate_stat` is the public non-HP stat formula. HP calculation not needed (damage formula only uses attack/defense stats)
- `NATURE_STAT_MAP` maps PixeldexHelper abbreviations to DB column symbols
- Explosion/Self-Destruct halving applied before immunity check — `def_stat` in result hash reflects the value actually used in calculation
- `best_nature_for` / `worst_nature_for` pick the first nature alphabetically that boosts/lowers the relevant attack stat (Adamant for physical best, Bold for physical worst, Modest for special best, Calm for special worst)
- Integer division handled naturally by Ruby for integer operands; `.floor` used after float multiplications (nature modifier, STAB, effectiveness)
- `apply_modifiers` applies STAB -> effectiveness -> roll in order, flooring after each, then clamps to min 1
- Status moves and zero-power moves return `{ min: 0, max: 0 }` immediately
- Tests use `OpenStruct` mocks with `stub :find_by!` to avoid DB dependency
- Two hand-calculated spot-check tests (Garchomp EQ vs Infernape, Alakazam Psychic vs Machamp) verify exact min/max values

---

### Step 2 — Database Tables + Seed Data for Pokemon Calculator (2026-04-12)
**Status:** Round 4 — seed task slicing fix, awaiting re-review

**Files created:**
- `db/migrate/20260412000001_create_pokemon_base_stats.rb` — creates `pokemon_base_stats` table with species, dex number, 6 stat columns, type1/type2, unique indexes on species and dex number
- `db/migrate/20260412000002_create_pokemon_moves.rb` — creates `pokemon_moves` table with name, power, move_type, category, accuracy, pp, priority, unique index on name
- `db/migrate/20260412000003_create_pokemon_learnsets.rb` — creates `pokemon_learnsets` table with FK refs to base_stats and moves, learn_method, level_learned, composite unique index
- `app/models/pokemon/base_stat.rb` — `Pokemon::BaseStat` model with has_many learnsets/moves, validations, `base_stat_total` and `types` helpers
- `app/models/pokemon/move.rb` — `Pokemon::Move` model with has_many learnsets/learners, validations, `damaging` and `by_type` scopes
- `app/models/pokemon/learnset.rb` — `Pokemon::Learnset` model with belongs_to associations, uniqueness validation on triple
- `lib/tasks/pokemon_data.rake` — `pokemon:fetch` (PokeAPI to YAML) and `pokemon:seed` (YAML to database) tasks

**Round 2 fixes (review feedback):**
- Wrapped helpers/constants in `module PokemonDataFetcher` to eliminate global scope pollution
- Replaced all 4 `YAML.load_file` with `YAML.safe_load_file`
- Seed counts now report created vs existing separately using `new_record?`
- Move progress line now shows kept vs skipped Gen V+ counts
- Pokemon completion line now includes failure count

**Round 3 changes (extended fetch fields per updated brief):**
- Phase 1 now fetches `/pokemon-species/{id}` alongside `/pokemon/{id}` (2 requests per pokemon)
- Added species fields to base_stats YAML: base_happiness, capture_rate, gender_rate, growth_rate, egg_groups, genus, flavor_text, is_legendary, is_mythical, hatch_counter
- Added pokemon fields to base_stats YAML: base_experience, height, weight, abilities (with is_hidden)
- Added move fields to moves YAML: effect (short_effect with $effect_chance replaced), flavor_text, meta block (ailment, ailment_chance, drain, healing, crit_rate, flinch_chance, min_hits, max_hits)
- 5 new helper methods in PokemonDataFetcher module: normalize_ability_name, extract_species_fields, extract_move_effect, extract_move_meta, extract_move_flavor_text
- Seed task NOT modified in round 3 — incorrectly assumed assign_attributes ignores unknown keys

**Round 4 fixes (review feedback):**
- Fixed `Pokemon::BaseStat` seed: `assign_attributes` now receives `attrs.slice(...)` with only the 9 DB columns (national_dex_number, hp, atk, def_stat, spa, spd, spe, type1, type2)
- Fixed `Pokemon::Move` seed: `assign_attributes` now receives `attrs.slice(...)` with only the 6 DB columns (power, move_type, category, accuracy, pp, priority)
- Without this fix, extra YAML keys (abilities, base_happiness, genus, meta, effect, flavor_text, etc.) would raise `ActiveModel::UnknownAttributeError`

**Key decisions:**
- `def_stat` column name avoids Ruby `def` keyword conflict
- STAT_NAME_MAP translates PokeAPI stat names to our column names
- Name map includes 7 entries (Nidoran-F/M, Farfetch'd, Mr. Mime, Mime Jr., Porygon-Z, Ho-Oh)
- Gen V+ moves skipped via generation URL check in fetch task
- Seed task uses `find_or_initialize_by` / `find_or_create_by!` for idempotency
- Pokedex name mismatch check runs at end of seed task
- YAML files written to `config/pokemon_data/` (to be checked into git)
- No rate limiting on PokeAPI requests per brief

---

### Step 1 — Full Evolution Chain Display (2026-04-12)
**Status:** Built, awaiting review

**Files changed:**
- `app/javascript/controllers/pixeldex_controller.js` — replaced `#populateEvolution` (lines 426-466), added `#buildEvolutionChain` helper (lines 367-424)

**Key decisions:**
- Backward walk iterates `Object.entries(evolutionsDataValue)` to find parent; O(n) on ~500 entries, runs once per modal open — acceptable per brief
- Chain length capped at 5 total entries (backward walk capped at 5 iterations, forward walk capped by total chain length reaching 5)
- Trigger info (level/method) attached to the *destination* species in the chain array, matching the brief's data model
- All DOM text rendered via `textContent` and `document.createElement` — zero innerHTML usage
- `replaceChildren()` used to clear container before rebuilding

---

## Known Gaps
*Logged here instead of fixed. Addressed in a future step.*

---

## Architecture Decisions
*Locked decisions that cannot be changed without breaking the system.*

- Discord user IDs stored as String in all Stimulus value types — 2026-04-12
- User-supplied text always rendered via textContent, never innerHTML — 2026-04-12
