# Review Request
*Written by Builder. Read by Reviewer.*

Ready for Review: YES

---

## Step 3 — Damage Calculator Service

### New file: `app/services/pokemon/damage_calculator.rb`

**Constants (lines 3-15):** `DEFAULT_IVS`, `DEFAULT_EVS`, `NATURE_STAT_MAP`. IVs default to 31, EVs to 0. Nature stat map translates PixeldexHelper abbreviations to DB column symbols.

**`calculate_stat` (lines 19-22):** Public non-HP stat formula. Takes base/iv/ev/level/nature_modifier, returns Integer. Used internally by `compute_stat` and exposed for UI stat displays.

**`calculate` (lines 32-80):** Main damage method. Looks up BaseStat/Move records, computes attack/defense stats with IVs/EVs/nature, applies Explosion halving, computes type effectiveness, short-circuits on immunity, runs damage formula with roll 85 (min) and 100 (max), returns result hash.

**`calculate_with_natures` (lines 84-99):** Runs calculate three times with current/best/worst natures. Best/worst found via `best_nature_for`/`worst_nature_for`.

**`apply_modifiers` (lines 148-163):** Applies STAB, effectiveness, roll in order with floor after each. Clamps to min 1.

**Private helpers (lines 101-170):** `resolve_move`, `stat_keys_for`, `compute_stat`, `nature_modifier`, `best_nature_for`, `worst_nature_for`, `stab?`, `explosion_move?`, `apply_modifiers`, `zero_result`.

### New file: `test/services/pokemon/damage_calculator_test.rb`

16 test methods covering:
- `calculate_stat` with known values (3 tests: boosted, neutral, lowered nature)
- Min/max damage range (1 test)
- STAB applied / not applied (2 tests)
- Type effectiveness super effective (1 test)
- Immunity returns zero (1 test)
- Explosion and Self-Destruct halve defense (2 tests)
- `calculate_with_natures` returns three keyed results (1 test)
- Best nature maximizes damage (1 test)
- Worst nature minimizes damage (1 test)
- Default IVs/EVs (2 tests)
- Status moves return zero (1 test)
- Hand-calculated spot checks: Garchomp EQ vs Infernape and Alakazam Psychic vs Machamp with exact expected min/max (2 tests, already counted above in damage range / special moves)

All tests use `OpenStruct` mocks and `stub :find_by!` to avoid DB dependency.

### Open Questions

None.
