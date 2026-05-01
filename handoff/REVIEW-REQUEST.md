# Review Request
*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

Ready for Review: YES

---

## Step 6 — Convert 8 Controller Tests + 1 Missed Model Test

**Builder:** Bob
**Tests:** 305/305 passing, 0 failures, 0 errors. Per-file:
- `soul_link_pokemon_group_test.rb`: 7/7
- `emulator_controller_test.rb`: 44/44
- `save_slots_controller_test.rb`: 33/33
- `species_assignments_controller_test.rb`: 5/5
- `teams_controller_test.rb`: 6/6
- `pokemon_controller_test.rb`: 5/5
- `pokemon_groups_controller_test.rb`: 6/6
- `gym_drafts_controller_test.rb`: 5/5

**Lint:** `bundle exec rubocop` clean on all 8 modified files.
**Fixture-helper grep:** zero matches in the 9 converted files. Only `test/channels/gym_draft_channel_test.rb` still uses fixtures (Step 7 target — out of scope here).

---

## Files Changed

### Modified (9 test files)

| Path | Change |
|------|--------|
| `test/models/soul_link_pokemon_group_test.rb` | Setup creates `@run`, `@group` (`:route201` trait), and 4 player pokemon (one per player trait into `@group`). Required to satisfy `species_for(GREY)` and `complete?` (which iterates over all 4 player_ids). Tests: 7 (unchanged) |
| `test/controllers/emulator_controller_test.rb` | Setup destroys fixture run for guild + creates factory run. Single fixture-helper call replaced. Tests: 44 (unchanged) |
| `test/controllers/save_slots_controller_test.rb` | Same destroy-then-create setup pattern. Tests: 33 (unchanged) |
| `test/controllers/species_assignments_controller_test.rb` | Setup pattern + inline seed of route201 group + grey pokemon in the "rejects duplicate user" test. Tests: 5 (unchanged) |
| `test/controllers/teams_controller_test.rb` | Setup pattern + inline group/pokemon seeds in `update_slots saves valid group ids` and `update_slots rejects more than 6` (latter seeds 6 groups with grey-pokemon + 1 without, so allowed_ids filter trims to 6 — preserves fixture-era success-not-422 invariant). Also fixed 1 pre-existing rubocop offense on line 65 for acceptance criterion. Tests: 6 (unchanged) |
| `test/controllers/pokemon_controller_test.rb` | Setup pattern + inline route201 group + grey/aratypuss seeds in `create rejects duplicate` and `update rejects other players` tests. Tests: 5 (unchanged) |
| `test/controllers/pokemon_groups_controller_test.rb` | Setup pattern + inline route206 group in 2 tests (`update to dead`, `destroy removes`). Tests: 6 (unchanged) |
| `test/controllers/gym_drafts_controller_test.rb` | Setup builds `@run`, `@draft` from `:lobby` trait; "type analysis" test seeds 6 groups via `%i[route201..route206].map`. Mirrors Step 5's gym_draft model-test pattern. Tests: 5 (unchanged) |

### Modified (handoff)

- `handoff/ARCHITECT-BRIEF.md` — Step 6 brief (Architect overwrote at session start)
- `handoff/BUILD-LOG.md` — Step 6 entry appended
- `handoff/REVIEW-REQUEST.md` — this document
- `handoff/REVIEW-FEEDBACK.md` — Reviewer's verdict (added during same session)

### Untouched (per brief)

- All factories under `test/factories/`
- All fixtures under `test/fixtures/`
- `test/test_helper.rb`
- `test/channels/gym_draft_channel_test.rb` (Step 7 scope)
- All app code (`app/`)

---

## Self-Review

### What would Reviewer most likely flag?

1. **The `SoulLinkRun.where(guild_id: LoginHelper::GUILD_ID).destroy_all` pattern in every controller setup.** This is the discovered constraint — the fixture's `active_run` (guild 999...) coexists with the factory `@run` because `fixtures :all` still loads. Two active runs share a guild, and `SoulLinkRun.current` returns the factory one (higher run_number) by default. But tests that deactivate `@run` and expect "no active run" fall back to the fixture — failing. The destroy_all wipes the fixture run BEFORE the factory creates a fresh @run. Each test gets a transactional rollback, so the destroy_all only affects the current test. After Step 8 (fixtures gone), the destroy_all becomes a no-op — leave it in for now per simplicity. The model test (`soul_link_pokemon_group_test`) doesn't go through HTTP, so it doesn't need this guard.

2. **`teams_controller_test.rb` "update_slots rejects more than 6" semantic preservation.** The original test asserted SUCCESS while named "rejects more than 6". Pre-conversion this worked because `.limit(7).pluck(:id)` returned only 6 fixture groups (only 6 existed). My direct conversion that seeded 7 groups with grey-pokemon broke this — the controller correctly returned 422. Fixed by seeding exactly 6 groups with grey-pokemon + 1 without — the 7th gets filtered by `allowed_ids`, leaving 6 valid IDs that fit under MAX_SLOTS. Test asserts SUCCESS as before. Test name is a bit misleading (the controller DOES reject >6 valid IDs) but I preserved the original intent and behavior.

3. **`teams_controller_test.rb:65` pre-existing rubocop offense fixed.** Same Step 5 lesson — fix to satisfy "rubocop clean" acceptance criterion. 2-character whitespace change on a line I didn't otherwise touch.

4. **`soul_link_pokemon_group_test.rb` set_position test invariant change.** Pre-conversion the run had 6 fixture groups so new groups got positions 7+8. Post-conversion only @group exists (position 1) so new ones get positions 2+3. Assertion `g2.position > g1.position` still holds (3 > 2).

5. **Architect brief's preliminary test counts were off** for emulator_controller_test (said 36, actual 44) and teams_controller_test (said 5, actual 6). Both are pre-conversion counts — verified by `git show HEAD:<file> | grep -c "^  test "`. Test count IS preserved per file; the brief just undercounted some.

6. **`emulator_controller_test.rb` test "save_data DELETE only wipes the caller's own slots, not other players'"** — I didn't add the destroy_all guard worry there because that test creates its own `@sess` via factory. The destroy_all in setup wipes the fixture run, then `@run = create(:soul_link_run)` creates a fresh one, then the test creates `mine` and `other` sessions in @run. Works.

### Did every item in the brief ship?

- [x] All 9 files converted (8 controllers + 1 model test)
- [x] Per-file test counts preserved
- [x] No fixture-helper calls remaining in the 9 files
- [x] `gym_draft_channel_test.rb` untouched (Step 7 scope)
- [x] `soul_link_pokemon_group:` keyword present on every `create(:soul_link_pokemon, ...)` (verified by grep)
- [x] No factory/fixture/test_helper changes
- [x] App code untouched
- [x] Pre-test runs after each file conversion (Per-file results: each green before moving on)
- [x] Full suite 305/305
- [x] Rubocop clean on 8 modified files (model file was already clean pre-edit)
- [x] Diff scope: 9 test files + 4 handoff files

### What does the user see if data is empty or a request fails?

N/A — Step 6 changes test code only. Runtime user-facing behavior unchanged.

---

## Open Questions / Notes

1. **`destroy_all` in controller test setups is a Step 7/8 cleanup target.** Once `fixtures :all` is dropped from `test_helper.rb` (Step 8), the `SoulLinkRun.where(guild_id: ...).destroy_all` line becomes dead code. Step 8's sweep should remove these defensive lines.

2. **Brief's preliminary test counts (emulator=36, teams=5) were undercounted.** Same pattern as Step 5 (gym_draft was 22 not 21). Architect briefs do approximate counts based on quick scan; Reviewer can validate against pre-conversion file via `git show`.

3. **No new factory traits added.** All 9 conversions use the trait set Step 4 shipped. The "update_slots rejects more than 6" test uses `@run.soul_link_pokemon_groups.create!(...)` and `@run.soul_link_pokemon.create!(...)` for the 7-group seeding because the existing trait set only covers route201..route206 (6 traits) and the test needs ≥6 groups. Using existing model-relation `create!` for the 7th avoids inventing a `:route207` trait.

4. **`pokemon_groups_controller_test.rb` skipped Architect's recommended pattern slightly.** Brief said `group = create(:soul_link_pokemon_group, :route206, soul_link_run: @run)` for both `update to dead` and `destroy removes`. Implemented exactly that. No deviation.

5. **`gym_drafts_controller_test.rb` "show loads type analysis"** seeds 6 groups in route201..route206 order via the array. The picks state references `g.id` for each group, in order. Verified by re-running test.

6. **Test runtime delta unmeasured.** Same as Step 5 — informational. The destroy_all + create_all pattern in controller setups adds 1-2 SQL queries per test; with parallelization the wall-clock impact is negligible.

7. **Step 7 (channel test) and Step 8 (fixture deletion + sweep) remain.** Step 7 will need similar destroy_all guards if the channel test makes HTTP-equivalent state lookups. Step 8 mechanically deletes `test/fixtures/*.yml` and removes `fixtures :all` from `test_helper.rb`, plus updates `CLAUDE.md`'s testing convention section.

---

**Ready for Review: YES**
