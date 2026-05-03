# Review Feedback — Step 16
Date: 2026-05-03
Ready for Builder: YES

## Must Fix

None.

## Should Fix

- `app/models/soul_link_run.rb:91` — `group_by { |tid, sid, _sid| [ tid, sid ] }`. The third element of each tuple is `session_id` (line 87), not a SID. Naming it `_sid` reads like it shadows the prior `sid` and is confusing on first read. Rename to `_session_id` for clarity. Logic is correct; this is purely a readability fix. Under 5 minutes — fix inline.

## Escalate to Architect

None.

## Cleared

Verified all eight focus areas Bob flagged plus the spec checks the Architect called out:

1. **KG-14 closure (Pokédex offsets cited from primary sources).** Comments at `save_parser.rb:75-110` cite PKHeX `SAV4Pt.cs` (`PokeDex = 0x1328`), `Zukan4.cs` (`SIZE_REGION = 0x40`, `4 + (region * SIZE_REGION) + (index >> 3)`), and pret/pokeplatinum `include/pokedex.h` (`struct Pokedex { u32 magic; u32 caughtPokemon[16]; u32 seenPokemon[16]; ... }`). Constants match: `POKEDEX_OFFSET = 0x1328`, `POKEDEX_CAUGHT_OFFSET = 0x132C` (= 0x1328 + 4 magic), `POKEDEX_SEEN_OFFSET = 0x136C` (= 0x132C + 0x40 region), `POKEDEX_BIT_LIMIT = 493` (NATIONAL_DEX_COUNT). Defensive cap is documented as wrong-offset sentinel, not contract. KG-14 closure rule satisfied.

2. **HoF CRC range and variant (`save_parser.rb:111-160, 397-430`).** CRC range is `block.byteslice(0, HOF_CRC_RANGE_END)` where `HOF_CRC_RANGE_END = 0x2ABE` — covers everything before the trailing 2-byte CRC field. Reuses the existing `crc16_ccitt` helper (CRC16-CCITT-FALSE: poly 0x1021, init 0xFFFF, MSB-first, no xorout) — same variant the general block uses. Matches PKHeX `Dendou4.cs Checksums.CRC16_CCITT(GetRegion()[..^2])`.

3. **HoF CRC fail returns nil, NOT 0 (`save_parser.rb:411-430`).** Every failure path in `extract_hof_count` returns `nil` (block-too-short, body/crc-slice nil, CRC mismatch, ClearCount slice short, rescue). `safe_hof_count` `compact`s and returns `nil` if both partitions failed. Coordinator's `>= 1` check on `nil.to_i = 0` correctly fails — no false-positive run completion possible from a corrupted HoF block.

4. **HoF count semantics documented (`save_parser.rb:137-142`).** Comment explicitly states `hof_count == ClearCount` (number of times entered HoF). `>= 1` means "entered at least once." Higher values are repeat clears, also treated as completed. Clear and unambiguous.

5. **Backward compat for Step-15 SaveDiff signature (`save_diff.rb:59-64`).** All ten new keyword args (`prev_tid:`, `curr_tid:`, `prev_sid:`, `curr_sid:`, `prev_pokedex_caught:`, `curr_pokedex_caught:`, `prev_pokedex_seen:`, `curr_pokedex_seen:`, `prev_hof_count:`, `curr_hof_count:`) default to `nil`. Step-15 call form `SaveDiff.between(prev_badges: 0, curr_badges: 1)` works unchanged. Pinned by `save_diff_test.rb:63-74`.

6. **Dispatcher baseline rule gates ALL coordinators (`save_diff_dispatcher.rb:25`).** `return if prev[:parsed_at].nil?` is the first line after the doc — fires before SaveDiff.between is even called. None of the four coordinators run on first-ever parse. Verified by `save_diff_dispatcher_test.rb:44-52` which stubs all four and asserts `{ gym: 0, tid: 0, pokedex: 0, hof: 0 }` after a `prev[:parsed_at] = nil` dispatch carrying badges/TID/HoF transitions.

7. **TID conflict pair-key is `[tid, sid]` (`soul_link_run.rb:91`).** `group_by { |tid, sid, _| [ tid, sid ] }` — two players with the same TID but different SIDs are NOT flagged. Pinned by `soul_link_run_test.rb:255-266`.

8. **GymBeatenCoordinator body untouched.** `git diff main...HEAD -- app/services/soul_link/gym_beaten_coordinator.rb` returns zero output. Only the call site moved (from `ParseSaveDataJob` to `SaveDiffDispatcher`).

9. **`broadcasts_refreshes_to` mirrors GymResult shape (`soul_link_run.rb:20`).** Form `->(record) { [ record, :dashboard ] }` matches the lambda shape used in `gym_result.rb:18`, `soul_link_pokemon.rb:25`, `soul_link_pokemon_group.rb:20`. Run is the broadcast key itself rather than `record.soul_link_run` because this IS the run. HoF coordinator uses `update!` (not `update_columns`), so the callback fires.

10. **Migrations use plain `:integer` (no `limit: 2`).** Both Step-16 migrations add columns as `:integer` per the brief — uint16 max 65535 fits cleanly in 4-byte signed int; `limit: 2` (smallint) would cap at 32767 and overflow on the upper half. Documented in the migration comments.

11. **HoF coordinator idempotency and inactive-run guard (`hall_of_fame_coordinator.rb:21`).** Triple-guard: `run.nil? || !run.active? || run.completed_at.present?` — once `completed_at` is set, repeat invocations are no-ops. Tests in `hall_of_fame_coordinator_test.rb:47-64` cover both branches. The "0 sessions returns false" guard at line 38 mirrors `GymBeatenCoordinator.all_players_have_badge?`'s same-shape guard correctly.

12. **HoF integration test exercises the full chain (`parse_save_data_job_test.rb:366-399`).** 4 sessions, all start at `parsed_hof_count: 0`, parse stub returns `hof_count: 1` for all 4. After saves 1/2/3 the run is NOT complete (3/4 fails the AND-gate); the 4th save flips `run.completed_at`. Real end-to-end: parse → persist → dispatcher → SaveDiff → coordinator → `run.update!`.

13. **HoF dual-partition simplification is sound for our use-case.** The "higher ClearCount among CRC-valid copies" simplification (vs PKHeX's footer-revision-counter active-block picker) is fine because the coordinator only cares about `>= 1`. A stale higher-count copy still satisfies the AND-gate; an incorrectly-low value would just delay run completion until the correct copy is observed. No false-positive risk.

Step 16 is clear.
