# Review Request
*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

---

**Step:** Step 16 — Non-decryption SRAM expansion: TID/SID + Pokédex caught/seen + Hall of Fame
**Builder:** Bob
**Branch:** `claude/funny-liskov-99a6b6`
**Ready for Review:** YES

---

## Summary

Bundles the three highest-ROI SRAM additions on top of the Step 15 SaveDiff infrastructure:

1. **TID/SID surfacing** — save-mix-up detection across the 4 players. Read-side only via `SoulLinkRun#tid_conflict_groups` + a "⚠ TID CONFLICT" pill on affected cards.
2. **Pokédex caught/seen counters** — closes **KG-14**. Offsets cited from PKHeX `SAV4Pt.cs` + pret/pokeplatinum `include/pokedex.h` primary sources in code comments.
3. **Hall of Fame run-completion detection** — when 4/4 sessions report `parsed_hof_count >= 1`, `HallOfFameCoordinator` stamps `run.completed_at = Time.current`. Dashboard renders "🏆 COMPLETE" pill.

`ParseSaveDataJob` refactored to "pure parser + persist" — diff/dispatch logic relocated to a new `SoulLink::SaveDiffDispatcher` so the job stays a thin facade and per-category branching lives in one place.

---

## Files (with line ranges)

### Migrations

- `db/migrate/20260503135725_add_step_16_parsed_columns_to_soul_link_emulator_save_slots.rb` (1-22) — adds `parsed_trainer_id`, `parsed_secret_id`, `parsed_pokedex_caught`, `parsed_pokedex_seen`, `parsed_hof_count` (all `:integer`, nullable, no defaults). Avoided `limit: 2` to prevent uint16 upper-half overflow.
- `db/migrate/20260503135726_add_completed_at_to_soul_link_runs.rb` (1-11) — adds `completed_at :datetime` + index.

### Parser (`app/services/soul_link/save_parser.rb`)

- (75-99) New constants block for Pokédex offsets with primary-source citations (PKHeX SAV4Pt.cs + Zukan4.cs + pret/pokeplatinum include/pokedex.h). Closes KG-14.
- (101-138) New constants block for Hall of Fame block layout with primary-source citations (PKHeX SAV4Pt.cs ExtraBlocks + Dendou4.cs + pret/pokeplatinum save_table.h).
- (140-152) Extended `Result` struct with 5 new fields (`trainer_id`, `secret_id`, `pokedex_caught`, `pokedex_seen`, `hof_count`).
- (244-249) `parse(...)` populates the 5 new fields via `read_uint16_le`, `count_pokedex_bits`, `safe_hof_count` helpers.
- (281-291) New `read_uint16_le(slot, offset)` private helper — 2-byte LE read with nil-safe boundary check.
- (303-318) New `count_pokedex_bits(slot, offset, byte_length, bit_limit)` — popcount the bit region; returns nil if total exceeds `bit_limit` (defensive cap = wrong-offset sentinel).
- (320-359) New `safe_hof_count(bytes)` + `extract_hof_count(bytes, base_offset)` — read both partition mirrors, CRC-validate (CRC16-CCITT-FALSE, same variant as general block), return higher valid `ClearCount` or nil if both partitions corrupt.

### SaveDiff (`app/services/soul_link/save_diff.rb`)

- (20-22) New event structs: `TidObserved`, `PokedexProgress`, `HallOfFameEntered`.
- (24-28) Extended `Result` with `tid_events:`, `pokedex_events:`, `hof_events:` keyword fields; `empty?` checks all four.
- (51-65) Extended `between(...)` with new keyword args (default `nil`). Step-15-style call signature still works (verified in test).
- (75-119) Per-dimension diff helpers: `diff_badges` (Step 15 logic preserved verbatim), `diff_tid` (TidObserved emit rules), `diff_pokedex` (PokedexProgress emit rules), `diff_hof` (HallOfFameEntered emit rules).

### Dispatcher (`app/services/soul_link/save_diff_dispatcher.rb` — NEW, 1-44)

Owns the baseline rule (skip on first-ever parse), the empty-diff short-circuit, and the fan-out to four coordinators. Replaces the inline dispatch logic in `ParseSaveDataJob`.

### Coordinators

- `app/services/soul_link/tid_observation_coordinator.rb` (NEW, 1-23) — log-only, no AR side effects. Logs each TidObserved event at info level with TID/SID/run/session/slot.
- `app/services/soul_link/pokedex_progress_coordinator.rb` (NEW, 1-22) — log-only, same shape as TID coordinator.
- `app/services/soul_link/hall_of_fame_coordinator.rb` (NEW, 1-37) — side-effect coordinator. All-4 AND-gate; sets `run.completed_at` only when every session's active slot has `parsed_hof_count >= 1`. Idempotent (skips if `completed_at` is already set or if run inactive).

### Job (`app/jobs/soul_link/parse_save_data_job.rb`)

- Full file rewrite (1-79) — refactored to "pure parser + persist". `capture_state(slot)` builds prev/curr snapshot Hashes before/after the parsed_* write; dispatcher receives both. KG-13 contract preserved (parse failure stamps only `parsed_at`, no dispatch).

### Run model (`app/models/soul_link_run.rb`)

- (15-19) Added `broadcasts_refreshes_to ->(record) { [ record, :dashboard ] }` (mirrors Step 15 GymResult pattern). When HoF coordinator updates `completed_at`, the dashboard refreshes and the "🏆 COMPLETE" pill appears in real time.
- (49-55) Added `completed?` method.
- (57-83) Added `tid_conflict_groups` method — returns `Array<Array<Integer>>` of session-id groups sharing the same `(parsed_trainer_id, parsed_secret_id)` pair. Sessions with nil/zero TID excluded.

### Views

- `app/views/emulator/_run_sidebar_card.html.erb` (60-90) — appended TID/SID line, Pokédex line, HoF pill, TID-conflict pill after the existing badges line. Conflict computation runs inline per card render (cheap because `includes(:save_slots)` is eager-loaded; no controller-context-needing helper).
- `app/views/emulator/_save_slots_sidebar.html.erb` (95-118) — mirrored TID/SID, Pokédex, HoF pill on the player's own slot column. Skipped TID conflict pill (player's own slots can't conflict with themselves).
- `app/views/dashboard/_runs_content.html.erb` (19-32, 50-58) — added "🏆 COMPLETE" pill next to the "ACTIVE" pill in the run header; added "COMPLETED" timestamp tile as a row below the gb-grid-4 stats.

### Test files (NEW)

- `test/services/soul_link/save_diff_dispatcher_test.rb` (1-103) — 7 tests covering baseline rule, empty diff, per-category dispatch, all-4 fan-out.
- `test/services/soul_link/tid_observation_coordinator_test.rb` (1-65) — 4 tests (empty events, log assertion, orphan slot, no AR side effects).
- `test/services/soul_link/pokedex_progress_coordinator_test.rb` (1-66) — 4 tests (same shape as TID).
- `test/services/soul_link/hall_of_fame_coordinator_test.rb` (1-93) — 7 tests (4/4 sets completed_at, 3/4 no-op, idempotency, inactive run, 0 sessions, missing active slot, empty events).

### Test files (extended)

- `test/services/soul_link/save_parser_test.rb` (16-18, 26-31, 56-66, 70-110, 261-403) — extended `build_slot` with TID/SID/Pokédex kwargs; extended `build_sram` with HoF kwargs and pads to full 0x80000; added `build_hof_block` and `bytes_with_n_bits_set` helpers; added 14 new tests for TID/SID parse, Pokédex popcount + defensive cap, HoF count + CRC fail + dual-partition picking + backward-compat smoke.
- `test/services/soul_link/save_diff_test.rb` (62-227) — added 16 new tests (Step-16 backward compat, Result#empty?, TidObserved 5 cases, PokedexProgress 4 cases, HallOfFameEntered 5 cases).
- `test/jobs/soul_link/parse_save_data_job_test.rb` (16-44, 73-83, 173-211, 263-300) — extended success-path test to assert all 5 new columns; switched KG-13 dispatch-suppression test stub from `GymBeatenCoordinator.process` to `SaveDiffDispatcher.dispatch`; added a dispatcher call-args test (asserts prev/curr snapshot shape + values); added a 4-session HoF integration test.
- `test/models/soul_link_run_test.rb` (175-274) — added 7 new tests (`completed?`, `tid_conflict_groups`: empty / unique TIDs / 2-of-4 share / 4-of-4 share / nil-zero excluded / TID-only-match no-conflict).

---

## Tests

- 461/461 (was 400) — +61 tests. 0 failures, 0 errors.
- Rubocop clean (169 files, 0 offenses).
- Brakeman: no new warnings; the 2 weak-confidence pre-existing File Access warnings (in `EmulatorController#rom` and `GymScheduleDiscordUpdateJob`) are unchanged from Step 15.

## Backward-compat invariants verified

- Step-15-style `SaveDiff.between(prev_badges: 0, curr_badges: 1)` returns `Result.new(badge_events: [BadgeGained.new(gym_number: 1)], tid_events: [], pokedex_events: [], hof_events: [])`. The 8 existing Step-15 SaveDiff tests pass unchanged.
- `SaveParser::Result.new(trainer_name: "X", money: 0, play_seconds: 0, badges_count: 0, map_id: nil)` (Step-15 form used in 7 existing job tests) still works because `keyword_init: true` defaults missing fields to nil.
- `GymBeatenCoordinator` body is untouched. The dispatcher relocates the *call* to `process(slot, diff.badge_events)` — no change to all-4 gate, suppression, idempotency, or transaction-wrap semantics.
- Step 15's retry-safety regression test (`coordinator raise on first run does not double-fire on the retry`) still passes — the dispatcher refactor moved call sites but not invariants.

---

## Suggested focus areas for review

1. **Pokédex offset citations.** Verify the comments at `save_parser.rb:75-99` actually reflect what PKHeX `SAV4Pt.cs` (`private const int PokeDex = 0x1328;`) and `Zukan4.cs` (`SIZE_REGION = 0x40`, `var ofs = 4 + (region * SIZE_REGION) + (index >> 3)`) say. The defensive cap (`POKEDEX_BIT_LIMIT = 493`) is the belt-and-suspenders if the offset is wrong, not the contract.
2. **HoF block CRC.** Verify the CRC range I'm computing (`block.byteslice(0, HOF_CRC_RANGE_END)` where `HOF_CRC_RANGE_END = 0x2ABE`) matches PKHeX `Dendou4.cs`'s `Checksums.CRC16_CCITT(GetRegion()[..^2])`. The existing `crc16_ccitt` helper from the general block is reused — confirm same variant (CRC16-CCITT-FALSE, init 0xFFFF, poly 0x1021, MSB-first, no xorout).
3. **HoF dual-partition picking.** `safe_hof_count(bytes)` reads both primary (0x20000) and secondary (0x60000) partitions, takes the higher valid `ClearCount`. The brief said "match what pret/PKHeX says about the active-block-picker" — for HoF this is `SAV4BlockDetection.CompareExtra` which uses the footer revision counter. I simplified to "higher ClearCount among CRC-valid copies" because we only care about the boolean "has the player entered HoF" (and even if we read a slightly-stale copy, an N-1 ClearCount still satisfies `>= 1`). The test `hof_count is the higher of two valid partition mirrors` pins this behavior. Worth a sanity check.
4. **Dispatcher baseline rule.** `prev[:parsed_at].nil?` short-circuits the dispatch (no events fire on first-ever parse). Test `first-ever parse (prev[:parsed_at] nil) does not call any coordinator` asserts this with all 4 coordinators stubbed — verify the test actually covers what it claims.
5. **All-4 AND-gate symmetry between gyms and HoF.** `HallOfFameCoordinator.all_players_in_hall_of_fame?` mirrors `GymBeatenCoordinator.all_players_have_badge?` — same 0-sessions-returns-false guard, same `&.parsed_*.to_i` nil-safe chain. Tests cover both branches in `hall_of_fame_coordinator_test.rb`.
6. **TID-conflict pair key.** `tid_conflict_groups` keys on `[trainer_id, secret_id]` — two players with the same TID but different SIDs are NOT flagged. Test `#tid_conflict_groups distinguishes (TID, SID) pairs` covers this. Verify the spec aligns with what "save mix-up" actually means (a real save mix-up would clone both fields).
7. **TID pill computation in the broadcast partial.** `_run_sidebar_card.html.erb:84` runs `s.soul_link_run.tid_conflict_groups.flatten` per card render. The brief explicitly disallowed extracting this to a controller-level memo because the partial is broadcast-rendered without controller context. With 4 cards × 1 query = 4 queries per render, all eager-loaded by `includes(:save_slots)` — should be cheap. Worth verifying nothing in the broadcast renderer breaks because the partial now reads `s.soul_link_run` (already-loaded association).
8. **HoF integration test.** The 4-session integration test in `parse_save_data_job_test.rb:263-300` uses a single stubbed `SaveParser::Result` returned for all 4 saves. In production each session is a separate run-state — the test simulates "every player saves with HoF entered." Verify the test's setup actually exercises the chain end-to-end (parse → dispatch → coordinator → run.update!).
9. **Brief's "broadcast doesn't break" assumption on the new run model `broadcasts_refreshes_to`.** The brief said "verified absent today" via grep. I added it. Manual smoke step recommended: open dashboard in 2 tabs, trigger a `run.update!(completed_at: Time.current)` from the rails console, confirm the 🏆 COMPLETE pill appears in both tabs in real time.

---

## Open questions

None blocking. All Project Owner decisions in the brief were locked; no scope expansion attempted.

If you want me to add a `gb-grid-5` CSS class instead of the row-below tile in `_runs_content.html.erb`, that's a 2-line CSS addition (one for the base class, one for the responsive breakpoint override that mirrors `gb-grid-4`'s 2-col fallback). Currently chose row-below because the panel is narrow and the brief said "pick the cleaner of the two layouts" with the pill being the must-have.

---

— Bob
