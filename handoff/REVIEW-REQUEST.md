# Review Request
*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

Ready for Review: YES

---

## Step 5 — Convert Model Unit Tests from Fixtures to FactoryBot

**Builder:** Bob
**Tests:** 305/305 passing, 0 failures, 0 errors. Per-file: pokemon=7/7, gym_draft=22/22, gym_result=4/4.
**Lint:** `bundle exec rubocop` clean on all 3 modified files.
**Fixture-helper grep:** zero matches in the 3 converted files.

---

## Files Changed

### Modified (3 test files)

| Path | Change |
|------|--------|
| `test/models/soul_link_pokemon_test.rb` | Added `setup` block creating `@run` / `@group_201` / `@group_202` / `@pokemon`; replaced 9 fixture-helper calls with ivar references; renamed "fixture pokemon is valid" → "factory pokemon is valid" (per brief). Test count: 7 (unchanged) |
| `test/models/gym_draft_test.rb` | Replaced setup block with factory creates (`@run`, `@groups[0..5]` from `:route201..:route206` traits, `@draft` from `:lobby` trait). All 22 test bodies + 3 private helpers unchanged. Fixed 2 pre-existing `Layout/SpaceInsideArrayLiteralBrackets` offenses on lines 8 + 83. Test count: 22 (unchanged; brief said 21 but it was always 22) |
| `test/models/gym_result_test.rb` | Added `@groups` to setup (6 group factories); inline-seeded 6 pokemon in the `snapshot_from_groups` test to make `.limit(2)` order-independent. Test count: 4 (unchanged) |

### Modified (handoff)

- `handoff/ARCHITECT-BRIEF.md` — Step 5 brief (Architect overwrote at session start)
- `handoff/BUILD-LOG.md` — Step 5 entry appended
- `handoff/REVIEW-REQUEST.md` — this document
- `handoff/REVIEW-FEEDBACK.md` — Reviewer's verdict (added during same session)

### Untouched (per brief)

- All factories under `test/factories/`
- All fixtures under `test/fixtures/`
- `test/test_helper.rb`
- All app code (`app/`)
- All other test files

---

## Self-Review

### What would Reviewer most likely flag?

1. **gym_result_test snapshot test seeding.** Initial conversion seeded only 2 pokemon (in `@groups[0]` and `@groups[1]`) and the test failed because `.limit(2)` returned different groups (DB row order is not deterministic without explicit ORDER BY). Fixed by seeding all 6 groups inline — replicates fixture-era state where every group had pokemon. Considered alternatives: adding `.order(:id)` to the test query (but brief said preserve assertions/queries), moving seeding to setup (but only one test needs pokemon — pollutes the other 3). The all-6-seed approach is the most robust and least intrusive.

2. **Pre-existing rubocop offenses fixed.** `gym_draft_test.rb:8` and `gym_draft_test.rb:83` had `Layout/SpaceInsideArrayLiteralBrackets` offenses (`[GREY, ARATY, SCYTHE, ZEALOUS]` should be `[ GREY, ARATY, SCYTHE, ZEALOUS ]` per `rubocop-rails-omakase`). Brief required rubocop clean; fixed inline. Two trivial whitespace changes. Pre-existing means they weren't introduced by Step 5 — but the alternative (leaving them as a Known Gap) would fail the acceptance criteria. The fix preserves test semantics 1:1.

3. **Test count discrepancy in brief.** The Architect brief said gym_draft has 21 tests; actual count was always 22 (manual count + `grep -c "^  test "` confirms). Not a regression from Step 5 — just an Architect undercount in the brief. All 22 tests still pass.

4. **Test name change.** Renamed `test "fixture pokemon is valid"` → `test "factory pokemon is valid"`. Architect explicitly approved this in the brief: "Watch `test 'fixture pokemon is valid'`. Rename the test to `test 'factory pokemon is valid'` to keep semantics honest."

5. **`@groups[0]` is route201 in gym_draft_test.** Verified by reading the new setup block: `%i[route201 route202 route203 route204 route205 route206].map` produces a 6-element array with `route201` at index 0 and `route206` at index 5 — exactly what tests at lines 96 (`@groups[0]`), 145 (`@groups[4]`), 207-220 (`@groups[4]` and `@groups[5]`) expect.

### Did every item in the brief ship?

- [x] `soul_link_pokemon_test.rb` converted: setup with @run / @group_201 / @group_202 / @pokemon; 9 fixture calls replaced
- [x] `gym_draft_test.rb` converted: setup with factory creates; @groups stays as Array indexed 0-5
- [x] `gym_result_test.rb` converted: @run + @groups in setup; pokemon seeded inline in snapshot test
- [x] Per-file test runs green before moving on (verified during conversion)
- [x] Full suite 305/305
- [x] Rubocop clean on 3 files
- [x] Fixture-helper grep returns zero matches in the 3 files
- [x] Diff scope: only 3 test files + 4 handoff files
- [x] No factory/fixture/test_helper changes
- [x] Test count preserved per file (7 / 22 / 4)
- [x] Test names preserved except documented "fixture → factory" rename
- [x] `soul_link_pokemon_group:` keyword present on every `create(:soul_link_pokemon, ...)` call (grep confirms 2 calls, both compliant)

### What does the user see if data is empty or a request fails?

N/A — Step 5 changes test code only. Runtime user-facing behavior unchanged.

---

## Open Questions / Notes

1. **gym_result_test snapshot now seeds 6 pokemon, not 2.** Original brief recommended seeding 2; Bob escalated to 6 due to `.limit(2)` ordering non-determinism. Inline pattern, low cost (6 lines), preserves the test's query shape exactly.

2. **Test runtime delta unmeasured.** Brief said this is informational (not a Condition). Quick eyeball: pre-conversion full suite ~ same as post (both ~30s in dev). Factories rebuild rows per test, but with `parallelize(workers: :number_of_processors)` the wall-clock impact is negligible at this scale.

3. **`fixtures :all` still loads in test_helper.** Step 6 removes it. For now, fixtures still preload for the other ~40+ test files that haven't been converted yet. The 3 converted files don't reference any fixture by name, but they don't suffer from the load — fixtures load once per process, not per test.

4. **Pre-existing rubocop offenses in OTHER files** (per the Step 1 BUILD-LOG entry: 133 offenses across 127 files) untouched. Step 5 scope was the 3 test files only.

5. **No new factory traits added.** All `create(:soul_link_pokemon, :route20N_<player>, ...)` and `create(:soul_link_pokemon_group, :route20N, ...)` calls use traits that Step 4 already shipped.

6. **gym_draft_test private helpers (`move_to_voting!` / `move_to_drafting!` / `move_to_nominating!`) untouched.** They reference `@run`, `@draft`, `@groups`, `ALL_PLAYERS` — all of which exist post-conversion with identical semantics.

---

**Ready for Review: YES**
