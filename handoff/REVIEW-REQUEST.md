# Review Request
*Written by Builder. Read by Reviewer.*

Ready for Review: YES

---

## Step 5 — Damage Calculator Extensions (Multi-Hit + Crit)

### Files Changed

#### 1. `app/services/pokemon/damage_calculator.rb`

- Added `CRIT_CHANCES` constant mapping Gen IV crit stages to human-readable percentages (0 -> "6.25%", 1 -> "12.5%", 2 -> "25%", 3+ -> "33.3%")
- Extended `calculate` method with multi-hit support: `min_hits`, `max_hits`, `is_multi_hit`, `min_total`, `max_total`, `avg_total`
- Extended `calculate` method with crit support: `crit_min`, `crit_max`, `crit_stage`, `crit_chance` (Gen IV 2x multiplier applied to base_damage before STAB/effectiveness/roll)
- Updated `zero_result` helper to accept keyword args (`stab:`, `effectiveness:`, `attacker_stat:`, `defender_stat:`) and include all new fields with zero/default values
- Updated immunity early-return to use `zero_result` with proper keyword args instead of raw hash
- All field access on move records uses `respond_to?` guards for OpenStruct mock compatibility

#### 2. `test/services/pokemon/damage_calculator_test.rb`

- Updated `mock_move` helper with new kwargs: `min_hits: nil`, `max_hits: nil`, `crit_rate: 0`
- Added 6 new tests:
  1. Multi-hit (Bonemerang, 2/2 hits): Marowak vs Pikachu -- verifies totals = per-hit * hits, is_multi_hit true
  2. Variable multi-hit (Pin Missile, 2/5 hits): Pinsir vs Caterpie -- verifies min_total = min*2, max_total = max*5, avg uses 3.5
  3. Non-multi-hit backward compat (Earthquake): verifies totals == single-hit, is_multi_hit false
  4. Crit damage (stage 0): verifies crit_min > 0, crit_max > max, stage/chance correct
  5. High-crit move (stage 1): verifies crit_stage == 1, crit_chance == "12.5%"
  6. Immunity with new fields: Normal vs Ghost -- all new fields present with zeros/defaults

### Test Results

```
24 runs, 83 assertions, 0 failures, 0 errors, 0 skips
```

All 18 existing tests pass unchanged. All 6 new tests pass.

### Definition of Done

- [x] `min_total`, `max_total`, `avg_total` in result hash
- [x] `min_hits`, `max_hits`, `is_multi_hit` in result hash
- [x] `crit_min`, `crit_max`, `crit_stage`, `crit_chance` in result hash
- [x] `zero_result` helper used for all early returns
- [x] Multi-hit test (Bonemerang, 2 hits): totals = per-hit * hits
- [x] Variable multi-hit test (2-5 hits): min_total = min*2, max_total = max*5
- [x] Non-multi-hit backward compat: totals == single-hit
- [x] Crit test: crit values > normal values, stage/chance correct
- [x] High-crit move test: stage 1, chance "12.5%"
- [x] Immunity test: all new fields present with zeros
- [x] All 18 existing tests still pass
- [x] No UI code

### Notes for Reviewer

- Gen IV crit is 2x (not 1.5x). The 2x is applied to base_damage before STAB/effectiveness/roll via the existing `apply_modifiers` method.
- `calculate_with_natures` was NOT modified -- it calls `calculate` internally so new keys propagate automatically.
- No migrations were run or needed -- `min_hits`, `max_hits`, `crit_rate` columns already exist from Step 4.

### Open Questions

None.
