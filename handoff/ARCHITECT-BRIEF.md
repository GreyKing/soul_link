# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 5 — Damage Calculator Extensions (Multi-Hit + Crit)

Context: The damage calculator (`app/services/pokemon/damage_calculator.rb`) currently returns `{ min, max, stab, effectiveness, attacker_stat, defender_stat }`. Step 4 added `min_hits`, `max_hits`, and `crit_rate` columns to `pokemon_moves`. This step extends the calculator to use them.

### 5a. Multi-hit support

When a move has `min_hits` and `max_hits` (e.g., Bonemerang: 2/2, Pin Missile: 2/5), the calculator should report per-hit AND total damage.

**New fields in result hash:**

```ruby
{
  # Existing (unchanged):
  min: Integer,              # per-hit min damage (85% roll)
  max: Integer,              # per-hit max damage (100% roll)
  stab: Boolean,
  effectiveness: Float,
  attacker_stat: Integer,
  defender_stat: Integer,

  # New — multi-hit:
  min_hits: Integer,         # 1 for normal moves, move.min_hits for multi-hit
  max_hits: Integer,         # 1 for normal moves, move.max_hits for multi-hit
  is_multi_hit: Boolean,     # true when min_hits > 1 OR max_hits > 1
  min_total: Integer,        # min * min_hits
  max_total: Integer,        # max * max_hits
  avg_total: Integer,        # ((min + max) / 2.0 * avg_hits).round
                             # where avg_hits = (min_hits + max_hits) / 2.0

  # New — crit:
  crit_min: Integer,         # min damage with 2x crit multiplier
  crit_max: Integer,         # max damage with 2x crit multiplier
  crit_stage: Integer,       # crit stage from move's crit_rate (0, 1, 2, 3)
  crit_chance: String        # human-readable: "6.25%", "12.5%", "25%", "33.3%"
}
```

**Implementation:**
```ruby
hit_min = move_record.respond_to?(:min_hits) ? (move_record.min_hits || 1) : 1
hit_max = move_record.respond_to?(:max_hits) ? (move_record.max_hits || 1) : 1
is_multi_hit = hit_min > 1 || hit_max > 1
min_total = min_damage * hit_min
max_total = max_damage * hit_max
avg_hits = (hit_min + hit_max) / 2.0
avg_total = ((min_damage + max_damage) / 2.0 * avg_hits).round
```

Flag: Use `respond_to?` guards because tests pass OpenStruct mocks that may not have `min_hits`/`max_hits`/`crit_rate`. The mock_move helper will be updated with defaults, but guard defensively anyway.

### 5b. Critical hit calculation

**Gen IV crit rules:**
- Crit multiplier = **2x** (Gen IV, not 1.5x which is Gen VI+)
- `crit_rate` from DB maps to stages:
  - 0 → 1/16 = 6.25%
  - 1 → 1/8 = 12.5%
  - 2 → 1/4 = 25%
  - 3+ → 1/3 ≈ 33.3%

**Implementation:**
```ruby
CRIT_CHANCES = { 0 => "6.25%", 1 => "12.5%", 2 => "25%" }.freeze

crit_stage = move_record.respond_to?(:crit_rate) ? (move_record.crit_rate || 0) : 0
crit_chance = CRIT_CHANCES[crit_stage] || "33.3%"

# Crit damage: 2x applied to base_damage BEFORE modifiers (STAB, effectiveness, roll)
crit_min = apply_modifiers(base_damage * 2, stab, effectiveness, 85)
crit_max = apply_modifiers(base_damage * 2, stab, effectiveness, 100)
```

Flag: The 2x is applied to `base_damage` (the pre-modifier value), then STAB/effectiveness/roll are applied on top. This matches Gen IV mechanics where crit doubles the damage level.

### 5c. Update zero/immunity results

The `calculate` method has two early-return paths that must include the new keys:

1. **Status move / zero power** (around line 36-37): Return all-zero result with defaults.
2. **Immunity** (around line 61-64): Return zero damage with `effectiveness: 0.0`.

Create a private helper:
```ruby
def zero_result(stab: false, effectiveness: 0.0, attacker_stat: 0, defender_stat: 0)
  {
    min: 0, max: 0,
    min_total: 0, max_total: 0, avg_total: 0,
    min_hits: 1, max_hits: 1, is_multi_hit: false,
    crit_min: 0, crit_max: 0, crit_stage: 0, crit_chance: "6.25%",
    stab: stab, effectiveness: effectiveness,
    attacker_stat: attacker_stat, defender_stat: defender_stat
  }
end
```

### 5d. Update mock_move test helper

Add defaults for the new fields so existing tests keep passing:
```ruby
def mock_move(name:, power:, move_type:, category:, accuracy: 100, pp: 10,
              priority: 0, min_hits: nil, max_hits: nil, crit_rate: 0)
```

### 5e. New tests

Add to `test/services/pokemon/damage_calculator_test.rb`:

**1. Multi-hit move (Bonemerang):**
- Use Marowak (Atk 80, Ground) vs Pikachu (Def 40, Electric)
- Bonemerang: power 50, Ground, physical, min_hits 2, max_hits 2
- Assert: `min_total == min * 2`, `max_total == max * 2`
- Assert: `is_multi_hit == true`, `min_hits == 2`, `max_hits == 2`
- Assert: `avg_total == ((min + max) / 2.0 * 2.0).round`

**2. Variable multi-hit (Pin Missile style):**
- Use any physical attacker vs defender
- Mock move: power 25, Bug, physical, min_hits 2, max_hits 5
- Assert: `min_total == min * 2`, `max_total == max * 5`
- Assert: `avg_total == ((min + max) / 2.0 * 3.5).round`

**3. Non-multi-hit backward compat:**
- Use Earthquake (no min_hits/max_hits)
- Assert: `min_total == min`, `max_total == max`, `is_multi_hit == false`
- Assert: `min_hits == 1`, `max_hits == 1`

**4. Crit damage:**
- Use any physical move with crit_rate 0
- Assert: `crit_min` and `crit_max` are both > 0
- Assert: `crit_max > max` (crit does more damage)
- Assert: `crit_stage == 0`, `crit_chance == "6.25%"`
- Verify the ratio: `crit_max` should be approximately `max * 2` (may differ slightly due to flooring)

**5. High-crit move:**
- Mock move with crit_rate 1
- Assert: `crit_stage == 1`, `crit_chance == "12.5%"`

**6. Immunity with new fields:**
- Normal vs Ghost
- Assert all new fields present: `min_total == 0`, `crit_min == 0`, `is_multi_hit == false`

### Build Order

1. Update `mock_move` helper with new kwargs (5d)
2. Add `CRIT_CHANCES` constant and `zero_result` helper (5c)
3. Extend `calculate` method with multi-hit and crit logic (5a, 5b)
4. Update early-return paths to use `zero_result` (5c)
5. Write new tests (5e)
6. Run all tests to confirm existing + new pass

### Flags
- Flag: Use `respond_to?` guards on `min_hits`, `max_hits`, `crit_rate` — tests use OpenStruct mocks.
- Flag: Gen IV crit is 2x, NOT 1.5x. This is a common mistake.
- Flag: `apply_modifiers` already exists as a private method. Reuse it for crit calculation — just pass `base_damage * 2` instead of `base_damage`.
- Flag: The `calculate_with_natures` method does NOT need changes — it calls `calculate` internally so new keys propagate automatically.
- Flag: Do NOT run migrations — they're already done.
- Flag: Use `mise exec -- ruby -S bundle exec rails test test/services/pokemon/damage_calculator_test.rb` to run tests.

### Definition of Done
- [ ] `min_total`, `max_total`, `avg_total` in result hash
- [ ] `min_hits`, `max_hits`, `is_multi_hit` in result hash
- [ ] `crit_min`, `crit_max`, `crit_stage`, `crit_chance` in result hash
- [ ] `zero_result` helper used for all early returns
- [ ] Multi-hit test (Bonemerang, 2 hits): totals = per-hit * hits
- [ ] Variable multi-hit test (2-5 hits): min_total = min*2, max_total = max*5
- [ ] Non-multi-hit backward compat: totals == single-hit
- [ ] Crit test: crit values > normal values, stage/chance correct
- [ ] High-crit move test: stage 1, chance "12.5%"
- [ ] Immunity test: all new fields present with zeros
- [ ] All 18 existing tests still pass
- [ ] No UI code

---

## Builder Plan
*Builder adds their plan here before building. Architect reviews and approves.*
