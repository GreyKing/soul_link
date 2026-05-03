# Review Feedback — Step 17
Date: 2026-05-03
Ready for Builder: YES

## Must Fix

None.

## Should Fix

None worth blocking on. Bob's documentation is unusually thorough; nits I considered (e.g. could the species fallback string include a leading space, could the egg-bit short-read of the IV dword default to `false` instead of `true`) are within the design envelope explicitly chosen and documented (KG-20; "false-positives on event flag are worse than false-negatives" pattern reused as "missing IV dword → safer to drop the row by flagging is_egg true").

## Escalate to Architect

None. The brief was complete, primary sources were closed before code was written, and the tests cover every edge case in the brief plus a few defensive cases not asked for.

## Cleared

Reviewed all 8 focus areas Bob surfaced:

1. **PkmDecoder crypto correctness** — verified.
   - PID-shuffle table (`pkm_decoder.rb:112-145`): cross-checked against PKHeX `PokeCrypto.cs`'s `BlockPosition` 96-byte flat array via WebFetch — every one of the 24 4-tuples matches Bob's transcription. The PKHeX comment ("duplicates appended to eliminate modulus") confirms the design choice of mirroring cases 24-31 to cases 0-7 for direct `(pid >> 13) & 0x1F` indexing.
   - LCG (`pkm_decoder.rb:225-237`): advance-then-XOR-with-high-16 ordering matches pret `LCRNG_NextFrom` semantics. Multiplier `0x41C64E6D` and increment `0x6073` correct.
   - Two-region dual-key: blocks A-D keyed with checksum (`pkm_decoder.rb:186`), party stats keyed with PID (`pkm_decoder.rb:199`). Matches pret `Pokemon_DecryptData` calls.
   - Checksum verify before unshuffle (`pkm_decoder.rb:188`) — sum is order-independent so the order is correct. All 24 PID-shuffle orderings exercised in `pkm_decoder_test.rb:144-163`.

2. **PartyParser party block offset (KG-11)** — verified via WebFetch of PKHeX `SAV4Pt.cs`. `GetSAVOffsets()` definitively sets `Party = 0xA0`, `Trainer1 = 0x68`, `Extra = 0x2820`. Bob's citation (`party_parser.rb:22-24`) is real. KG-11 closure is legitimate.

3. **met_locations.yml coverage (KG-12)** — spot-checked 6 IDs against PKHeX `text_hgss_00000_en.txt` via WebFetch. All match exactly:
   - 0: Mystery Zone, 16: Route 201, 48: Eterna Forest, 50: Mt. Coronet, 84: Stark Mountain, 117: Distortion World.
   - The five special pseudo-IDs (2000/2001/2002/3001/3002) match PKHeX `Locations.cs` constants and are correctly tagged `event: true`.
   - Production-file canary in `game_state_met_locations_test.rb:118-148` asserts gym towns + Routes 201/230 + key dungeons + event-flagged IDs.

4. **SaveDiff backward compat** — verified.
   - `save_diff_test.rb:231-235` proves a Step-15-style call (`prev_badges:` / `curr_badges:` only) returns a Result with empty `catch_events`/`removal_events`.
   - All 7 pre-Step-17 dispatcher tests in `save_diff_dispatcher_test.rb:48-122` updated with `catch: 0` baseline assertions and pass.
   - No behavioral change to badge / TID / Pokédex / HoF dispatch — same call sites, same arg order, same coordinator wiring.

5. **CatchCoordinator** — verified.
   - Transaction wrap (`catch_coordinator.rb:60-72`) confirmed by `catch_coordinator_test.rb:154-171` (mid-loop raise rolls back partial creates).
   - PID dedup (`catch_coordinator.rb:83-85`) covered by `catch_coordinator_test.rb:96-117` (same run = no-op; cross-run = allowed via different guild_id).
   - Trade-in detection nil-safe (`catch_coordinator.rb:158-165`) — `to_i` coercion + `&.` chains + zero-baseline early-return prevent both nil deref and false-positive on uninitialized slots.
   - Egg defense in depth (`catch_coordinator.rb:76`).
   - Retry idempotency (`parse_save_data_job_test.rb:526-567`) mirrors the Step 15 regression — `update_columns(parsed_party_data:)` writes BEFORE dispatch, so coordinator-raise-on-first-run does not double-fire on retry.
   - Event-met precedence over trade-in (`catch_coordinator.rb:175-179`) covered by `catch_coordinator_test.rb:145-152`.

6. **Migration shape** — verified.
   - Both migrations are additive only. `pid` is nullable (manual catches keep validating).
   - `trade_in boolean default false null false` is back-compat-safe (existing rows backfill to false at column-add time).
   - Compound non-unique index `(soul_link_run_id, discord_user_id, pid)` per brief decision 9 — application-level dedup handled in `CatchCoordinator.handle_caught` lookup.

7. **Dashboard PC BOX data isolation** — verified.
   - Controller scope (`dashboard_controller.rb:67-72`): `run.soul_link_pokemon.where(discord_user_id: current_user_id).where.not(pid: nil).where(soul_link_pokemon_group_id: nil)`. Per-run + per-player + auto-detected-only + group-unassigned. No data leakage path exists; the AR query is the only join.
   - View (`_pc_box_content.html.erb:17-58`) reads exclusively from `@auto_detected_catches` and computes first-encounter inline. Mirrors existing box-cell visual patterns. Conditional render (`if auto_catches.any?`) avoids empty-section noise.
   - Existing `broadcasts_refreshes_to` on `SoulLinkPokemon` (model line 25) auto-pushes Turbo refreshes — no extra wiring needed for real-time UX.

8. **Rubocop + Brakeman clean** — verified personally.
   - `bundle exec rubocop`: 178 files inspected, **0 offenses**.
   - `bundle exec brakeman -q`: only the 2 pre-existing weak-confidence File Access warnings (EmulatorController#rom send_file, GymScheduleDiscordUpdateJob URL) — unchanged from Step 16.
   - `bundle exec rails test`: **527 runs, 1682 assertions, 0 failures, 0 errors, 0 skips**. Bob's 461→527 (+66 test) claim is correct.

Out-of-scope drift check: nothing flagged. KG-20/21/22/23 are real, well-documented gaps appropriately logged for downstream work — not punted scope. The auto-creation guard ("Step 17 rows live as `soul_link_pokemon_group_id: nil`") that the brief asked the reviewer to flag is honored — `CatchCoordinator.handle_caught` line 96 hardcodes `soul_link_pokemon_group_id: nil` with an inline comment.

Step 17 is clear.
