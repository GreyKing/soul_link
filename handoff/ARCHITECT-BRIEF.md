# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 3 — Damage Calculator Service

Context: Pure Ruby service that implements the Gen IV damage formula. No UI in this step — just the calculation engine. Will be consumed by Step 4 (Quick Calculator modal) and Step 5 (Full Calculator tab).

### Decisions
- Service lives at `app/services/pokemon/damage_calculator.rb`, namespaced under `Pokemon::` to match the models from Step 2.
- The service is a stateless class with class methods — no instantiation needed.
- Uses `Pokemon::BaseStat` and `Pokemon::Move` from the database. Also uses `SoulLink::TypeChart` for type effectiveness and `PixeldexHelper::NATURES` for nature modifiers.
- Returns a result hash, not a model — this is a calculation, not persisted data.
- The random roll in Gen IV ranges from 85 to 100 (integer, inclusive — 16 possible values). Min damage uses roll 85, max uses roll 100.
- Explosion and Self-Destruct halve the target's Defense stat in Gen IV. This is a move-specific special case.

### Gen IV Formulas

**Stat Calculation (non-HP):**
```
stat = floor((floor((2 * base + iv + floor(ev / 4)) * level / 100) + 5) * nature_modifier)
```

**HP Calculation:**
```
hp = floor((2 * base + iv + floor(ev / 4)) * level / 100) + level + 10
```
Exception: Shedinja always has 1 HP regardless of stats.

**Damage Formula:**
```
damage = floor((floor(floor((2 * level / 5) + 2) * power * attack_stat / defense_stat) / 50) + 2) * modifier
```

Where `modifier` is applied multiplicatively in this order, flooring after each multiply:
1. STAB: 1.5 if move type matches one of the attacker's types, else 1.0
2. Type effectiveness: `SoulLink::TypeChart.combined_effectiveness(move_type, defender_types)` — can be 0, 0.25, 0.5, 1, 2, or 4
3. Random roll: integer 85..100, divided by 100

**Which stat to use:**
- Physical moves → attacker's Atk vs defender's Def
- Special moves → attacker's SpA vs defender's SpD

**Nature modifier mapping:**
The NATURES hash uses abbreviations ("Atk", "Def", "SpA", "SpD", "Spd"). Map to our DB column names:
```ruby
NATURE_STAT_MAP = {
  "Atk" => :atk,
  "Def" => :def_stat,
  "SpA" => :spa,
  "SpD" => :spd,
  "Spd" => :spe
}.freeze
```
If nature boosts a stat: multiply by 1.1. If nature lowers a stat: multiply by 0.9. Neutral natures: 1.0 for all stats. HP is never affected by nature.

**Explosion / Self-Destruct special case:**
In Gen IV, these moves halve the target's effective Defense stat (after all other modifiers to the stat). Check: `move.name.in?(["Explosion", "Self-Destruct"])`. Apply: `defense_stat = (defense_stat / 2).floor` (minimum 1).

### Build Order

**1. Service: `app/services/pokemon/damage_calculator.rb`**

```ruby
module Pokemon
  class DamageCalculator
    # Public API — 3 class methods:

    # 1. calculate(attacker:, defender:, move:)
    #    Returns: { min: Integer, max: Integer, stab: Boolean, effectiveness: Float, 
    #              attacker_stat: Integer, defender_stat: Integer }
    #
    #    Parameters are hashes:
    #    attacker: { species: String, level: Integer, ivs: Hash, evs: Hash, nature: String }
    #    defender: { species: String, level: Integer, ivs: Hash, evs: Hash, nature: String }
    #    move:     Pokemon::Move record OR { name: String } to look up
    #
    #    ivs/evs hashes: { hp: 0..31, atk: 0..31, def_stat: 0..31, spa: 0..31, spd: 0..31, spe: 0..31 }
    #    Defaults: IVs default to 31 (max), EVs default to 0 (untrained)

    # 2. calculate_with_natures(attacker:, defender:, move:)
    #    Runs calculate() three times:
    #    - With the attacker's specified nature (or neutral if nil)
    #    - With the BEST nature for this move (maximizes the relevant attack stat)
    #    - With the WORST nature for this move (minimizes the relevant attack stat)
    #    Returns: { current: <calc_result>, best: <calc_result_with_nature>, worst: <calc_result_with_nature> }
    #    Where best/worst results include a :nature key naming the nature used.

    # 3. calculate_stat(base:, iv:, ev:, level:, nature_modifier:)
    #    Pure stat calculation. Exposed publicly for UI stat displays.
    #    Returns: Integer

    # Private helpers:
    # - compute_stat(base_stat_record, stat_key, iv, ev, level, nature)
    # - nature_modifier(nature_name, stat_key) → 0.9, 1.0, or 1.1
    # - best_nature_for(category) → nature name that boosts the attack stat used
    # - worst_nature_for(category) → nature name that lowers the attack stat used
    # - stab?(move_type, attacker_types) → boolean
    # - explosion_move?(move) → boolean
  end
end
```

**Method details:**

`calculate(attacker:, defender:, move:)`:
1. Look up `Pokemon::BaseStat` for attacker and defender species.
2. Look up `Pokemon::Move` if move is a hash (find_by name).
3. Determine category: physical → atk/def_stat, special → spa/spd.
4. Compute attacker's attack stat using IVs, EVs, level, nature.
5. Compute defender's defense stat using IVs, EVs, level, nature.
6. Apply Explosion/Self-Destruct halving to defense stat.
7. Run damage formula with roll=85 (min) and roll=100 (max).
8. Return result hash.

`calculate_with_natures(attacker:, defender:, move:)`:
1. Call `calculate` with the given nature.
2. Find best nature: for physical moves, boost Atk (Adamant if no speed concern); for special moves, boost SpA (Modest). Specifically, find the nature where `up` matches the attack stat used AND `down` does NOT match the defense stat being targeted. Simplest: just pick the nature that maximizes the attack stat — iterate all 25 natures, compute the attack stat with each, pick the max.
3. Find worst nature: same approach but pick the min.
4. Return all three results with nature names.

**IV/EV defaults:**
```ruby
DEFAULT_IVS = { hp: 31, atk: 31, def_stat: 31, spa: 31, spd: 31, spe: 31 }.freeze
DEFAULT_EVS = { hp: 0, atk: 0, def_stat: 0, spa: 0, spd: 0, spe: 0 }.freeze
```

**2. Tests: `test/services/pokemon/damage_calculator_test.rb`**

Test against known damage values. Use specific pokemon matchups with known results:

```ruby
# Test cases (verify these produce correct min/max):
# 1. Garchomp (Lv.50, Adamant, 31 IVs, 252 Atk EVs) using Earthquake vs 
#    Infernape (Lv.50, Jolly, 31 IVs, 0 Def EVs)
#    → Ground is super effective (2x) + STAB (1.5x)
#
# 2. Alakazam (Lv.50, Modest, 31 IVs, 252 SpA EVs) using Psychic vs 
#    Machamp (Lv.50, Adamant, 31 IVs, 0 SpD EVs)
#    → Psychic is super effective (2x) + STAB (1.5x)
#
# 3. Normal vs Ghost → 0 damage (immunity)
#
# 4. Explosion test: Golem using Explosion vs any target → defense halved
#
# 5. Neutral nature vs best/worst nature comparison
#
# 6. calculate_stat spot checks against known stat calculators
```

Test structure:
- `test_calculate_returns_min_max_range`
- `test_stab_bonus_applied`
- `test_type_effectiveness_applied`
- `test_immunity_returns_zero`
- `test_explosion_halves_defense`
- `test_calculate_with_natures_returns_three_results`
- `test_best_nature_maximizes_damage`
- `test_worst_nature_minimizes_damage`
- `test_calculate_stat_known_values`
- `test_default_ivs_and_evs`
- `test_shedinja_hp_always_one` (if you want to handle this — optional, Shedinja isn't in Platinum wild encounters but IS in the dex)

### Flags
- Flag: All division in the damage formula is INTEGER division (floor). Ruby's integer `/` already floors for positive numbers, but use `.floor` explicitly after float operations (nature modifier is a float multiply).
- Flag: The random roll is 85..100 inclusive. Min damage = formula with 85/100. Max damage = formula with 100/100 (no random factor).
- Flag: Type effectiveness of 0 (immunity) should short-circuit — return `{ min: 0, max: 0 }` immediately.
- Flag: Do NOT handle abilities, items, weather, or held items. This is a base damage calculator. Those can be added later.
- Flag: Status moves (category == "status") have no power. If a status move is passed, return `{ min: 0, max: 0 }`.
- Flag: The NATURES constant is in `PixeldexHelper`. Access it as `PixeldexHelper::NATURES`. Do NOT duplicate the data.
- Flag: Minimum damage after all modifiers is 1 (unless type immunity makes it 0). The formula naturally produces at least 1 from the `+ 2` term, but floor operations could theoretically drop it. Guard with `.clamp(1, ..)` after applying modifiers, except for immunity.
- Flag: `def_stat` column name — be consistent. IV/EV hash keys use `def_stat`, not `def`.

### Definition of Done
- [ ] `Pokemon::DamageCalculator.calculate` returns `{ min:, max:, stab:, effectiveness:, attacker_stat:, defender_stat: }`
- [ ] `Pokemon::DamageCalculator.calculate_with_natures` returns `{ current:, best:, worst: }` with nature names
- [ ] `Pokemon::DamageCalculator.calculate_stat` returns correct stat values
- [ ] Gen IV damage formula implemented with integer flooring at each step
- [ ] STAB (1.5x) applied when move type matches attacker type
- [ ] Type effectiveness from `SoulLink::TypeChart.combined_effectiveness`
- [ ] Explosion/Self-Destruct halve defense
- [ ] Immunity (0x effectiveness) returns zero damage
- [ ] Status moves return zero damage
- [ ] Default IVs (31) and EVs (0) when not specified
- [ ] Nature modifiers correctly applied (1.1x boost, 0.9x lower)
- [ ] Best/worst nature calculation picks optimal natures
- [ ] Tests pass with known damage values
- [ ] No UI code, no controller code, no view code

---

## Builder Plan
*Builder adds their plan here before building. Architect reviews and approves.*

### Plan: Pokemon::DamageCalculator

**File 1: `app/services/pokemon/damage_calculator.rb`**

Structure: Module `Pokemon`, class `DamageCalculator`, all class methods via `class << self`.

Constants:
- `DEFAULT_IVS` / `DEFAULT_EVS` — frozen hashes with the 6 stat keys
- `NATURE_STAT_MAP` — maps PixeldexHelper abbreviations ("Atk", "Def", etc.) to our DB column symbols (:atk, :def_stat, etc.)

Public methods:
1. `calculate_stat(base:, iv:, ev:, level:, nature_modifier: 1.0)` — pure stat formula, returns Integer. No HP variant here — this is the non-HP formula only, matching the brief's public API.
2. `calculate(attacker:, defender:, move:)` — main method. Looks up BaseStat/Move records, computes attack/defense stats, runs damage formula twice (roll 85 and 100), returns result hash.
3. `calculate_with_natures(attacker:, defender:, move:)` — calls calculate 3 times with current/best/worst natures.

Private helpers:
- `compute_stat(base_stat_record, stat_key, iv, ev, level, nature)` — uses BaseStat record to get the base value, calls through to the formula with nature modifier looked up.
- `compute_hp(base_stat_record, iv, ev, level)` — HP formula (only used internally for Shedinja check if needed, but brief says HP calc isn't needed for damage — actually re-reading, HP isn't used in the damage formula at all, only attack/defense stats are). Skip HP computation entirely since damage formula only needs atk/def/spa/spd.
- `nature_modifier(nature_name, stat_key)` — looks up PixeldexHelper::NATURES, maps stat abbreviation via NATURE_STAT_MAP, returns 0.9/1.0/1.1.
- `best_nature_for(category)` / `worst_nature_for(category)` — iterates all 25 natures, picks the one that boosts/lowers the relevant attack stat (Atk for physical, SpA for special).
- `stab?(move_type, attacker_types)` — checks inclusion.
- `explosion_move?(move)` — checks name.
- `apply_modifier(damage, modifier)` — floors after float multiply.

Damage formula implementation:
1. Look up BaseStat records by species name.
2. Look up Move record if hash given.
3. Bail early if status move or nil power.
4. Determine category -> stat keys (physical: :atk/:def_stat, special: :spa/:spd).
5. Compute attacker's attack stat and defender's defense stat with IVs/EVs/nature.
6. Apply Explosion/Self-Destruct halving to defense stat (floor, min 1).
7. Compute base damage: `floor((floor(floor((2*level/5)+2) * power * atk / def) / 50) + 2)`
8. Compute effectiveness via TypeChart.combined_effectiveness.
9. Short-circuit on immunity (effectiveness == 0).
10. Determine STAB.
11. For min/max, apply modifiers in order (STAB, effectiveness, roll), flooring after each.
12. Clamp to minimum 1.
13. Return result hash.

**File 2: `test/services/pokemon/damage_calculator_test.rb`**

Uses ActiveSupport::TestCase (no DB fixtures needed — will mock/stub BaseStat and Move lookups).

Actually, re-reading the brief: the tests need BaseStat and Move records. Since we can't run tests, I'll write tests that create records with `Pokemon::BaseStat.new` stubs or use mocking. Better approach: use `stub` on `Pokemon::BaseStat.find_by!` and `Pokemon::Move.find_by!` to return OpenStruct/mock objects with the needed attributes.

Tests:
1. `test_calculate_stat_known_values` — spot-check stat formula against known values
2. `test_calculate_returns_min_max_range` — min <= max, both positive
3. `test_stab_bonus_applied` — damage higher with STAB than without
4. `test_type_effectiveness_applied` — super effective returns effectiveness: 2.0
5. `test_immunity_returns_zero` — Normal vs Ghost = 0 damage
6. `test_explosion_halves_defense` — Explosion damage higher than equivalent non-Explosion move
7. `test_calculate_with_natures_returns_three_results` — has :current, :best, :worst keys
8. `test_best_nature_maximizes_damage` — best >= current
9. `test_worst_nature_minimizes_damage` — worst <= current
10. `test_default_ivs_and_evs` — passing no IVs/EVs uses defaults
11. `test_status_move_returns_zero` — status category returns 0/0

**Decisions:**
- Will stub `Pokemon::BaseStat.find_by!` and `Pokemon::Move` lookups using Minitest stubs to avoid needing DB records in tests.
- `calculate_stat` is the non-HP formula per the brief (the brief says "Pure stat calculation. Exposed publicly for UI stat displays."). HP calculation is a private concern if needed.
- The brief says minimum damage is 1 after modifiers (unless immunity). I'll apply `.clamp(1, Float::INFINITY)` after all modifier applications, before the immunity check bypasses this.

**Uncertainties:**
- None. The brief is precise.

Architect approval: [ ] Approved / [ ] Redirect — see notes below
