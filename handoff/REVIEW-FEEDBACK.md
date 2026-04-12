# Review Feedback -- Step 5: Damage Calculator Extensions (Multi-Hit + Crit)
*Written by Reviewer (Richard). Read by Architect and Builder.*

---

## Verdict: PASS

All 24 tests pass (83 assertions, 0 failures, 0 errors). The implementation matches the architect brief. No blocking issues found.

---

## Must Fix

None.

## Should Fix

None.

## Escalate to Architect

None.

---

## Correctness Checks

### Multi-hit math -- CORRECT

- `min_total = min_damage * hit_min` -- correct, worst case is min roll repeated min times.
- `max_total = max_damage * hit_max` -- correct, best case is max roll repeated max times.
- `avg_total = ((min_damage + max_damage) / 2.0 * avg_hits).round` where `avg_hits = (hit_min + hit_max) / 2.0` -- correct.
- Non-multi-hit defaults to `hit_min=1, hit_max=1`, so totals collapse to per-hit values -- verified in test.

### Crit calculation -- CORRECT

- Gen IV 2x multiplier applied to `base_damage` before `apply_modifiers` (line 93-94): `apply_modifiers(base_damage * 2, stab, effectiveness, roll)` -- matches the brief exactly.
- `CRIT_CHANCES` constant correctly maps stages 0/1/2 to "6.25%"/"12.5%"/"25%", with fallback "33.3%" for stage 3+ -- correct per Gen IV.
- `crit_stage` and `crit_chance` both use `respond_to?` guard with nil-coalescing to 0 -- correct.

### zero_result helper -- CORRECT

- Contains all 16 keys matching the normal result hash.
- Accepts keyword args for `stab`, `effectiveness`, `attacker_stat`, `defender_stat`.
- Used in both early-return paths: status/zero-power (line 41) and immunity (lines 65-71).
- Default `crit_chance: "6.25%"` for zero result is sensible (stage 0 default).

### respond_to? guards -- CORRECT

- All three fields (`min_hits`, `max_hits`, `crit_rate`) are guarded with `respond_to?` (lines 82-83, 91).
- Each guard falls back through nil-coalescing: `respond_to?(:min_hits) ? (move_record.min_hits || 1) : 1`.
- This handles both the case where the attribute is missing entirely AND where it is present but nil.

### Test coverage -- GOOD

- 6 new tests covering: fixed multi-hit (2/2), variable multi-hit (2/5), non-multi-hit backward compat, crit stage 0, crit stage 1, immunity with new fields.
- Existing 18 tests unchanged and passing.
- The immunity test (lines 534-562) checks all 16 keys explicitly -- thorough.

---

## Edge Case Analysis

### min_hits=nil, max_hits=5

The `respond_to?` guard handles this correctly: `move_record.min_hits || 1` yields 1 when `min_hits` is nil. So `hit_min=1, hit_max=5, is_multi_hit=true`. This is a reasonable interpretation -- a move with only `max_hits` set would be treated as 1-5 hits.

### min_hits=1, max_hits=1

`is_multi_hit = 1 > 1 || 1 > 1 = false`. Totals equal per-hit values. Correct -- a 1/1 hit move is NOT multi-hit.

### crit_rate=nil (no guard test but covered by logic)

`move_record.crit_rate || 0` yields 0 when nil. Correct default.

### crit_stage >= 3

`CRIT_CHANCES[3]` returns nil, so fallback `|| "33.3%"` catches it. Stage 4+ also falls through correctly.

---

## Nits (non-blocking)

1. **No test for crit_rate >= 2 or 3.** There are tests for stage 0 and stage 1, but no test for stage 2 ("25%") or the fallback stage 3+ ("33.3%"). Low risk since the lookup is trivial, but worth adding if someone touches this code later.

2. **Crit totals for multi-hit moves are not calculated.** The result has `crit_min`/`crit_max` for per-hit crit damage but no `crit_min_total`/`crit_max_total`. This matches the brief (which did not request it), but a future step may want multi-hit crit totals. Not a defect -- just noting for the architect.

3. **avg_total for non-multi-hit.** When `hit_min=1, hit_max=1`, `avg_total = ((min + max) / 2.0 * 1.0).round` which equals the midpoint of the damage range. For a non-multi-hit move this is arguably more useful as just `avg_damage` but the naming is consistent with the multi-hit framing. Fine as-is.

---

## Definition of Done Checklist

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

All 12 items satisfied.
