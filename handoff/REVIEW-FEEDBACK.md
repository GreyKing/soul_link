# Review Feedback — Step 3
Date: 2026-04-12
Ready for Builder: YES

## Must Fix
None.

## Should Fix

1. **damage_calculator.rb:18** — `calculate_stat` has optional parameters (iv: 31, ev: 0, level: 50, nature_modifier: 1.0) while the brief specifies all five as required: `calculate_stat(base:, iv:, ev:, level:, nature_modifier:)`. The defaults are convenient and the test on line 296 relies on them, but this is a signature drift from the spec. Recommendation: make all parameters required to match the brief, update the one test that relies on defaults.

2. **damage_calculator_test.rb:175-176** — Comment says "The defense stat in the result is the pre-halving value" then immediately contradicts itself. The code actually returns the halved value (line 79 of the service reads `def_stat` after halving on line 54-55). The comment is misleading. Recommendation: fix the comment or add an assertion that `defender_stat` is the halved value.

## Escalate to Architect
None.

## Cleared

Reviewed `app/services/pokemon/damage_calculator.rb` (190 lines) and `test/services/pokemon/damage_calculator_test.rb` (415 lines) against the Step 3 brief.

**Spec compliance:** All three public methods present with correct return types. `calculate` returns the specified 6-key hash. `calculate_with_natures` returns `{ current:, best:, worst: }` with `:nature` keys on best/worst only. `calculate_stat` returns Integer.

**Gen IV formula:** Integer flooring at each step is correct. Ruby integer division handles the base damage computation. Float multiplies for STAB and effectiveness use explicit `.floor`. Random roll uses integer arithmetic (`damage * roll / 100`) which is equivalent to flooring.

**STAB, effectiveness, Explosion:** All implemented per brief. STAB checks `attacker_types.include?(move_type)`. Effectiveness delegates to `SoulLink::TypeChart.combined_effectiveness`. Explosion/Self-Destruct halve defense with minimum 1.

**Nature modifier mapping:** NATURE_STAT_MAP correctly maps all five abbreviations to DB columns. `nature_modifier` method handles nil nature, neutral natures, boost (1.1), and lower (0.9).

**Best/worst nature:** Picks first nature (insertion order) that boosts/lowers the relevant attack stat. Functionally equivalent to the brief's "iterate all natures, compute stat, pick max/min" approach since all boosting natures give 1.1x and all lowering give 0.9x.

**Edge cases:** Immunity short-circuits to zero. Status moves return zero. Default IVs (31) and EVs (0) applied via hash merge. Minimum damage clamped to 1 after modifiers (immunity handled separately).

**Hand-calculated test values verified:**
- Garchomp Earthquake vs Infernape: Atk=200, Def=91, base=98, after STAB=147, after 2x=294. Min=249, Max=294. Matches test assertions on lines 360-364.
- Alakazam Psychic vs Machamp: SpA=205, SpD=105, base=79, after STAB=118, after 2x=236. Min=200, Max=236. Matches test assertions on lines 407-411.

**Drift:** None beyond the optional parameters noted in Should Fix.
