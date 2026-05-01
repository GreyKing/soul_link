# Review Request
*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

Ready for Review: YES

---

## Step 7 — Convert Channel Test from Fixtures to FactoryBot

**Builder:** Bob
**Tests:** 305/305 passing, 0 failures, 0 errors. Per-file: `gym_draft_channel_test.rb` 9/9.
**Lint:** `bundle exec rubocop` clean on the modified file.
**Fixture-helper grep:** zero matches in the converted file. **Across the entire `test/` tree, ZERO files now use fixture helpers** — the test-side conversion is functionally complete.

---

## Files Changed

### Modified (1 test file)

| Path | Change |
|------|--------|
| `test/channels/gym_draft_channel_test.rb` | Setup rebuilt to match Step 5's `gym_draft_test.rb` pattern: `@run` + 6 `@groups` (`:route201..:route206` traits) + `@draft` (`:lobby` trait) + the existing `stub_connection(current_user_id: GREY)` line at the end. All 9 test bodies + 3 private helpers (`move_to_voting!` / `move_to_drafting!` / `move_to_nominating!`) unchanged. Also fixed 1 pre-existing `Layout/SpaceInsideArrayLiteralBrackets` rubocop offense on line 8 (`ALL_PLAYERS = [GREY, ARATY, SCYTHE, ZEALOUS]` → `[ GREY, ARATY, SCYTHE, ZEALOUS ]`). Tests: 9 (unchanged) |

### Modified (handoff)

- `handoff/ARCHITECT-BRIEF.md` — Step 7 brief (Architect overwrote at session start)
- `handoff/BUILD-LOG.md` — Step 7 entry appended
- `handoff/REVIEW-REQUEST.md` — this document
- `handoff/REVIEW-FEEDBACK.md` — Reviewer's verdict (added during same session)

### Untouched (per brief)

- All factories under `test/factories/`
- All fixtures under `test/fixtures/`
- `test/test_helper.rb`
- All other test files
- All app code (`app/`)

---

## Self-Review

### What would Reviewer most likely flag?

1. **No `destroy_all` guild guard added.** Architect brief explicitly forbade adding the Step 6 controller pattern here. Channel tests bypass HTTP via `stub_connection(current_user_id: GREY)` — the channel looks up the draft via `params[:draft_id]`, never goes through `SoulLinkRun.current(guild_id)`. Verified by running the test green without the guard. If I'd cargo-culted it, that would have been a Reviewer Condition.

2. **Setup mirrors Step 5's `gym_draft_test.rb` exactly** with one addition (the `stub_connection` line at the end). No deviation from the proven pattern. Trait list `%i[route201..route206]` produces `@groups` indexed 0-5 with route201 at index 0 and route206 at index 5 — matches positional references at lines 61, 64, 70, 78.

3. **Pre-existing rubocop offense fixed** at line 8 (`ALL_PLAYERS` array brackets). Same offense + same fix as Step 5's `gym_draft_test.rb`. 2-character whitespace change. Pre-existing offenses elsewhere in the suite remain (the 133-offense Known Gap from Step 1).

4. **Private helpers (`move_to_voting!`, `move_to_drafting!`, `move_to_nominating!`) unchanged.** They reference `@run`, `@draft`, `@groups`, `ALL_PLAYERS` — all of which exist post-conversion with identical semantics. No body changes.

5. **`stub_connection`, `subscribe`, `perform`, `assert_broadcasts`, `assert_has_stream_for`, `transmissions` calls all unchanged.** Architect brief listed these as "do NOT change" — only the data setup gets converted.

### Did every item in the brief ship?

- [x] Single file converted: `test/channels/gym_draft_channel_test.rb`
- [x] Test count preserved (9)
- [x] No fixture-helper calls remaining in the file
- [x] `grep -rln <patterns> test/` returns zero files — full conversion done
- [x] No `destroy_all` guard cargo-culted from Step 6
- [x] No factory/fixture/test_helper changes
- [x] App code untouched
- [x] Pre-test runs after conversion + full suite
- [x] Full suite 305/305
- [x] Rubocop clean on the modified file
- [x] Pre-existing rubocop offense at line 8 fixed (acceptance criterion)
- [x] Diff scope: 1 test file + 4 handoff files

### What does the user see if data is empty or a request fails?

N/A — Step 7 changes test code only. Runtime user-facing behavior unchanged.

---

## Open Questions / Notes

1. **Test-side conversion now functionally complete.** Across the `test/` tree, zero files reference fixture helpers (`soul_link_runs(:..)`, `soul_link_pokemon_groups(:..)`, etc.). Step 8's mechanical work: delete `test/fixtures/*.yml`, remove `fixtures :all` from `test/test_helper.rb`, update `CLAUDE.md` testing-convention section to drop the hybrid note, run 3+ parallel suite reps for flake check.

2. **Channel test conversion was the cleanest of the series.** No surprises, no constraint discoveries. The setup pattern transferred 1:1 from Step 5's gym_draft model test, plus the channel-test machinery that was already correctly using `stub_connection`.

3. **Test runtime delta unmeasured.** Same as Steps 5 and 6 — informational. Channel tests run fast; the factory creates add ~1 SQL query per test on top of the existing fixture-load cost. With parallelization, wall-clock impact is negligible.

4. **Step 8 prerequisites verified.** `fixtures :all` in `test/test_helper.rb` is now dead weight (no test references the fixtures it loads). `test/fixtures/*.yml` files are similarly orphan. Step 8 deletion is safe.

---

**Ready for Review: YES**
