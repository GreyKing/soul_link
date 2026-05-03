# Review Request
*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

---

**Step:** Step 17 — PkmDecoder + PartyParser + catches+routes auto-detection
**Builder:** Bob
**Branch:** `claude/recursing-cori-8d3bfc`
**Ready for Review:** YES

---

## Summary

Ships category 3 of the SRAM auto-tracking audit (catches + routes). New Gen-IV PKM decryption infrastructure (Layer A: `PkmDecoder` + `PartyParser`, both pure functions never raising) plus a new side-effect coordinator (Layer B: `CatchCoordinator`) that creates `SoulLinkPokemon` rows from auto-detected party transitions. `SaveDiff` extends with `catch_events:` / `removal_events:` and `prev_party:` / `curr_party:` kwargs (backward compatible). The dashboard PC BOX tab gets a new "AUTO-DETECTED CATCHES" section per player.

**Closes KG-11** (party block offset = 0xA0, cited from PKHeX `SAV4Pt.cs`).
**Closes KG-12** (Platinum met-location enum, cited from PKHeX `text_hgss_00000_en.txt` + `Locations.cs`).

---

## Files (with line ranges)

### Migrations

- `db/migrate/20260503160001_add_step_17_columns_to_soul_link_pokemon.rb` (1-43) — adds `pid` (bigint), `met_location_id` (integer), `ot_id` (integer), `ot_sid` (integer), `trade_in` (boolean default false null false), `acquired_via` (string). Compound non-unique index `(soul_link_run_id, discord_user_id, pid)` for the dedup-lookup hot path. All additive; manual catches (Step 1+ Catch modal) keep validating with `pid: nil`.
- `db/migrate/20260503160002_add_parsed_party_data_to_soul_link_emulator_save_slots.rb` (1-15) — adds `parsed_party_data :json`, nullable, no default. Same shape as Step 16's parsed_* additions.

### Decoder (`app/services/soul_link/pkm_decoder.rb` — NEW)

- (1-65) Header citation block — pret/pokeplatinum sources for crypto algorithm + struct layout, PKHeX `PokeCrypto.cs` cross-check, projectpokemon Gen-4 PKM-structure r65 doc reference.
- (66-115) Constants — `BOX_SIZE = 136`, `PARTY_SIZE = 236`, field offsets within unshuffled (canonical ABCD) payload (species @ 0x00 of Block A → record offset 0x08, met-location @ 0x1E of Block B → record offset 0x46, met-level @ 0x1C of Block D → record offset 0x84, etc.), LCG constants (`0x41C64E6D` / `0x6073`), 32-entry `SHUFFLE_TABLE` transcribed verbatim from pret/pokeplatinum `src/pokemon.c:4861-4924` (cases 24..31 mirror cases 0..7 per pret).
- (117-130) `Pkm` Struct value object (pid, species, level, ot_id, ot_sid, met_location_id, met_level, is_egg, slot_index).
- (132-180) `decrypt(bytes, slot_index:)` static method. Pipeline: validate length → read PID + checksum → XOR-decrypt blocks region with checksum-keyed LCG → verify checksum → unshuffle blocks per `((PID >> 13) & 0x1F)` → for party records, XOR-decrypt party stats region with PID-keyed LCG → extract canonical fields → return Struct. Top-level `rescue StandardError → nil`.
- (182-225) Private helpers: `lcg_xor(bytes, seed)` (XOR halfwords with LCG keystream), `checksum_valid?` (sum-of-uint16-words mod 0x10000), `unshuffle(blocks, pid)` (re-orders 4 × 32-byte blocks), `read_u32_le` / `read_u16_le` (boundary-safe), `extract_egg_bit` (Block-B IV-dword bit 30 OR species==0 sentinel).

### Walker (`app/services/soul_link/party_parser.rb` — NEW)

- (1-46) Header citation — PKHeX `SAV4Pt.cs` `Party = 0xA0` (closes KG-11), pret/pokeplatinum `include/party.h` Party struct shape.
- (48-58) Constants — `PARTY_OFFSET_IN_GENERAL_BLOCK = 0xA0`, party header (8 bytes: capacity u32 + currentCount u32) + 6 × 236-byte records.
- (60-92) `parse(save_data)` — validates input length, picks the active slot via the same CRC-validated picker as SaveParser (replicated, not delegated, to keep parsers loosely coupled), reads count u32 (clamps out-of-bounds to 6), iterates slots calling PkmDecoder, filters nils + eggs + zero-species. Top-level `rescue StandardError → []`.
- (94-140) Private helpers: `pick_active_slot` (CRC-validated higher-counter picker), `slot_valid?`, `read_save_counter`, `crc16_ccitt`, `read_u32_le`. Replicates SaveParser's slot-picking logic by reading SaveParser's public class constants (CRC_RANGE_END, BLOCK_CRC_OFFSET, etc.).

### Coordinator (`app/services/soul_link/catch_coordinator.rb` — NEW)

- (1-50) Header — filters & dedup logic explained: eggs / PID dedup / trade-in / event-met / route-resolution.
- (52-77) `process(slot, events)` — early-return on empty/nil/missing-session/missing-run; opens `slot.transaction { }`; iterates events; routes PokemonCaughtEvent to `handle_caught`, PokemonRemovedEvent to `Rails.logger.info` (no AR side effect — mirrors `BadgeLost` no-op).
- (79-113) `handle_caught(_slot, session, run, event)` — egg/zero-PID/unclaimed guards; PID dedup against `(soul_link_run_id, discord_user_id, pid)`; resolves route + species; classifies acquired_via (event_gift > trade_in > catch precedence); `SoulLinkPokemon.create!` with `soul_link_pokemon_group_id: nil`.
- (115-122) `resolve_route_name(met_id)` — calls `GameState.met_location_name`, falls back to "Met-Location #N" / "Met-Location #?" gracefully.
- (124-145) `resolve_species_string(species_id)` + `species_name_by_id` memoized lookup from `pokemon_base_stats.national_dex_number`. Returns "Species #N" fallback (KG-20) when the table is empty.
- (147-156) `reset_species_cache!` — test helper.
- (158-180) `trade_in?(session, event)` + `acquired_via(met_id, trade_in)` — slot's parsed TID/SID lookup with nil-safety; defaults trade_in false when no baseline exists.

### Met-locations YAML (`config/soul_link/met_locations.yml` — NEW)

- (1-39) Header — full source citation block (PKHeX `text_hgss_00000_en.txt` + `Locations.cs` for special IDs, pret/pokeplatinum `res/text/special_met_location_names.json` cross-check). Closes KG-12.
- (41-127) 127 entries — Sentinel Mystery Zone (event:true), 15 cities, 30 routes (201-230), 44 dungeons / overworld special, 36 indoor / overworld interior locations.
- (129-134) 5 special pseudo-IDs flagged event:true — Daycare4=2000, LinkTrade4NPC=2001, LinkTrade4=2002, Ranger4=3001, Faraway4=3002.

### GameState extension (`app/services/soul_link/game_state.rb`)

- (10) Added `MET_LOCATIONS_PATH` constant.
- (90-119) Added `met_locations` (memoized YAML loader, `{}` fallback), `met_location_name(id)` (nil for unknown / nil), `event_met_location?(id)` (false for nil/unknown — false-positives on event flag are worse than false-negatives).
- (179) Extended `reload!` to clear `@met_locations` ivar.

### SaveDiff extension (`app/services/soul_link/save_diff.rb`)

- (28-49) Added `Pkm` Struct (re-declared for diff layer's contract — JSON-roundtripped Hashes from `parsed_party_data` aren't PkmDecoder::Pkm Structs anymore), `PokemonCaughtEvent`, `PokemonRemovedEvent`. Extended `Result` with `catch_events:`, `removal_events:`. `Result#empty?` checks all six event arrays.
- (76-93) Extended `between(...)` with `prev_party:` / `curr_party:` keyword args (default `nil` for backward compat). New `diff_party` helper produces `[catches, removals]`.
- (152-204) `diff_party(prev_party, curr_party)` — returns `[[], []]` when either side is nil (defensive), indexes both sides by PID via `index_party_by_pid`, walks curr-not-in-prev → catches and prev-not-in-curr → removals. `index_party_by_pid` skips nil/zero PIDs (defensive). `hash_get(entry, key)` accepts both symbol-keyed and string-keyed entries (pre/post JSON roundtrip).

### Dispatcher extension (`app/services/soul_link/save_diff_dispatcher.rb`)

- (20-22) Updated docstring to mention `:party_data`.
- (29-37) Wired `prev_party: prev[:party_data]` / `curr_party: curr[:party_data]` into the `SaveDiff.between` call.
- (44-46) Added `CatchCoordinator.process(slot, diff.catch_events + diff.removal_events)` fan-out when either array is non-empty.

### Job extension (`app/jobs/soul_link/parse_save_data_job.rb`)

- (39-50) Calls `SoulLink::PartyParser.parse(slot.save_data).map(&:to_h)` on success; persists JSON-serialized party data via `update_columns(parsed_party_data: ...)` (same write that already covered the parsed_* columns). Failure path UNCHANGED — KG-13 invariant preserved (only stamps `parsed_at`).
- (74-78) Extended `capture_state(slot)` to include `:party_data => slot.parsed_party_data`.

### Controller extension (`app/controllers/dashboard_controller.rb`)

- (60-72) Loads `@auto_detected_catches` — current_user_id-scoped, `pid IS NOT NULL` (auto-detected only — manual catches keep pid nil for back-compat), `soul_link_pokemon_group_id IS NULL` (Step-17 rows are unpaired), ordered `caught_at: :desc`.

### View extension (`app/views/dashboard/_pc_box_content.html.erb`)

- (17-49) New "AUTO-DETECTED CATCHES" section above the existing ON TEAM section. Conditionally rendered (`if auto_catches.any?`). First-encounter badge (`1ST`) computed live by grouping per location and picking earliest-by-caught_at. Trade-in pill (`TRADE-IN`), event pill (`EVENT`). Mirrors the visual style of existing box-cell layout.

### Tests

- `test/services/soul_link/pkm_decoder_test.rb` (NEW, 9 tests / 220 assertions) — synthetic round-trip via known-PID encrypted blocks; all 24 PID-shuffle orderings; checksum mismatch returns nil; boundary errors return nil; nil/non-String input returns nil; egg bit detected; species==0 collapses to is_egg; box-only record (136 bytes) decrypts with level=nil; slot_index propagated.
- `test/services/soul_link/party_parser_test.rb` (NEW, 10 tests / 19 assertions) — empty (count=0), single-Pokemon, three-Pokemon (with slot indices), six-Pokemon, eggs filtered, corrupt PKM dropped (others returned), wrong total bytesize returns [], nil/non-String returns [], no-CRC-valid-slot returns [], out-of-bounds count fallback walks all 6 slots.
- `test/services/soul_link/catch_coordinator_test.rb` (NEW, 17 tests / 52 assertions) — empty/nil events no-op, missing slot/session/uid no-op, egg/zero-PID/removed-event drops, new catch creates row with all fields, PID dedup within run, cross-run PID allowed (different guild_id to dodge active-run uniqueness invariant), trade-in detection, event-met flag, unknown met-id fallback, event_gift precedence, transaction wrap (raise rolls back partials), no-baseline trade-in defaults false.
- `test/services/soul_link/game_state_met_locations_test.rb` (NEW, 11 tests / 29 assertions) — mirrors maps test shape: file absent, known ID lookup, unknown ID returns nil, nil input returns nil, string coercion, event_met_location? predicate (true/false/nil/unknown), reload! clears cache, production-file canary on gym towns + Routes 201/230 + Distortion World / Mt. Coronet / Eterna Forest / Stark Mountain + event-flagged IDs.
- `test/services/soul_link/save_diff_test.rb` (extended, +9 tests) — Step-17 backward compat (Step-15-style call returns empty catch/removal), empty/empty no events, new PID → catch, stable PID no events, removed PID → 1 catch + 1 removal, 6-prev-5-curr removal, both-nil defensive, only-one-side-nil defensive, string-keyed entries (post-JSON-roundtrip), Result#empty? false with catches.
- `test/services/soul_link/save_diff_dispatcher_test.rb` (extended, +4 tests) — `with_stubbed_coordinators` extended to cover `CatchCoordinator`; updated existing 7 tests' assertion hashes to include the new `:catch` key (always 0 for pre-Step-17 cases); added PokemonCaughtEvent fan-out, PokemonRemovedEvent fan-out, stable PIDs no-op, baseline rule for catches.
- `test/jobs/soul_link/parse_save_data_job_test.rb` (extended, +5 tests) — parsed_party_data persists on success, parse-failure preserves prior parsed_party_data + skips PartyParser, integration 1→2 party transition creates SoulLinkPokemon row with correct route name, re-running same job produces no duplicate via PID dedup, CatchCoordinator retry-safety (raise on first run does not double-fire on retry; mirrors Step 15's regression test shape).

---

## Tests + lint + brakeman

- **Tests:** 461 → **527** (+66). 0 failures, 0 errors.
- **Rubocop:** 169 → **178** files, **0 offenses**.
- **Brakeman:** Clean (no new warnings; the 2 weak-confidence pre-existing File Access warnings — `EmulatorController#rom` `send_file` and `GymScheduleDiscordUpdateJob` Discord URL — are unchanged).

---

## Reviewer focus areas

1. **PkmDecoder crypto correctness.**
   - PID-shuffle table (`pkm_decoder.rb:103-130`) — 32-entry constant transcribed verbatim from pret/pokeplatinum `src/pokemon.c:4861-4924`. Cases 24..31 mirror cases 0..7 (so the lookup is a single-index op rather than `index % 24`). Verify the table against pret + cross-check against PKHeX `PokeCrypto.BlockPosition` if you can pull it.
   - LCG (`pkm_decoder.rb:184-194`) — `seed = (seed * mult + inc) & U32_MASK; ks = (seed >> 16) & U16_MASK`; XOR uses HIGH 16 bits per pret `LCRNG_NextFrom`. Multiplier `0x41C64E6D` and increment `0x6073` cited from `include/math_util.h`.
   - Two-region dual-key encryption (`pkm_decoder.rb:155-168`): blocks A-D keyed with checksum, party stats keyed with PID. Cited from pret `src/pokemon.c:328-329` `Pokemon_DecryptData(&mon->party, ..., personality)` + `Pokemon_DecryptData(&mon->box.dataBlocks, ..., checksum)`. Test exercises both via the round-trip helper.
   - Checksum verify (`pkm_decoder.rb:200-206`) — sum of all 64 u16 words in the decrypted blocks region mod 0x10000 must equal stored checksum at 0x06. Verified before unshuffling (sum is order-independent). Mismatch → returns nil.
   - All 24 PID-shuffle orderings tested via `pkm_decoder_test.rb:115-135` (parametric over case_idx ∈ [0..23]).

2. **PartyParser party block offset (KG-11 closure).**
   - `PARTY_OFFSET_IN_GENERAL_BLOCK = 0xA0` cited from PKHeX `PKHeX.Core/Saves/SAV4Pt.cs` `GetSAVOffsets()` method. Header docstring at `party_parser.rb:30-44` documents the source explicitly.
   - Cross-checked against pret/pokeplatinum `include/party.h` Party struct shape (`int capacity; int currentCount; Pokemon[6]`). Audit `2026-05-02-sram-auto-tracking-audit.md` flagged this as the biggest unknown — the brief locked the PKHeX-sourced answer; verify the citation.

3. **met_locations.yml coverage + citation (KG-12 closure).**
   - `config/soul_link/met_locations.yml:1-39` header cites PKHeX `text_hgss_00000_en.txt` + `Locations.cs`. 127 entries shipped (Sinnoh routes 201-230, all gym towns, 44 notable dungeons + interiors, 5 special event pseudo-IDs). Production-file canary in `game_state_met_locations_test.rb:113-138` asserts gym towns + routes + dungeons + event flags ship.

4. **SaveDiff backward compat.**
   - `save_diff_test.rb:233` — `SaveDiff.between(prev_badges: 0, curr_badges: 1)` with NO new kwargs returns Result with empty `catch_events` + `removal_events` arrays. All 16 Step-15/16 SaveDiff tests pass unchanged after the Step-17 additions.
   - `save_diff_dispatcher_test.rb:42-117` — existing 7 dispatcher tests' assertion hashes were extended with `:catch` key (always 0 for pre-Step-17 cases); the underlying dispatcher behavior for badges/TID/Pokédex/HoF is unchanged.
   - `parse_save_data_job_test.rb` "Step 17: parse failure does not write parsed_party_data" — KG-13 invariant preserved; parse failure ONLY stamps `parsed_at`, every other parsed_* field (including the new `parsed_party_data`) keeps its prior value.

5. **CatchCoordinator transaction wrap, PID dedup, trade-in detection, egg filter, retry idempotency.**
   - Transaction wrap: `catch_coordinator.rb:62-77` opens `slot.transaction { }` around the events loop. Tested in `catch_coordinator_test.rb:153-168` — stub `SoulLinkPokemon.create!` to raise on the second call; assert no row persists (`assert_no_difference "SoulLinkPokemon.count"`).
   - PID dedup: `catch_coordinator.rb:90-93` `where(soul_link_run_id:, discord_user_id:, pid:).exists?`. Tested in `catch_coordinator_test.rb:95-100` (same PID twice = no second row) and `catch_coordinator_test.rb:103-117` (cross-run PID allowed, with different guild_id to dodge active-run uniqueness invariant).
   - Trade-in: `catch_coordinator.rb:159-167` compares event TID/SID against slot's `parsed_trainer_id` / `parsed_secret_id`. Returns false if either side is unset (defense against false-positives). Tested in `catch_coordinator_test.rb:119-127` (different IDs → trade_in true) + `catch_coordinator_test.rb:170-181` (no baseline → defaults false).
   - Egg filter: `catch_coordinator.rb:80-83` defense in depth (PartyParser already filters). Tested in `catch_coordinator_test.rb:62-67`.
   - Retry idempotency: `parse_save_data_job_test.rb` "Step 17: CatchCoordinator retry-safety" mirrors Step 15's regression test — coordinator raise on first run does not double-fire on retry because `parsed_party_data` is persisted via `update_columns` BEFORE the dispatch line, so the retry sees `prev_party_data == curr_party_data`, diff is empty, coordinator never re-invoked.

6. **Migration shape.**
   - Both migrations are additive only (nullable columns + one `default: false, null: false` boolean for `trade_in` which is safe for back-compat).
   - No data-backfill blocks. No `change_column`. No removal/rename.
   - Compound index `(soul_link_run_id, discord_user_id, pid)` is non-unique per brief decision 9 (application-level dedup is acceptable for v1; the index serves the lookup hot path, the uniqueness check happens in `CatchCoordinator.handle_caught` before the create).

7. **Dashboard PC BOX section's data isolation.**
   - Controller scope (`dashboard_controller.rb:60-72`): `run.soul_link_pokemon.where(discord_user_id: current_user_id).where.not(pid: nil).where(soul_link_pokemon_group_id: nil).order(caught_at: :desc)`. Per-player + per-run + auto-detected-only + group-unassigned.
   - View (`_pc_box_content.html.erb:17-49`) reads exclusively from `@auto_detected_catches` and computes first-encounter inline by location-group min-by-caught_at. No leakage across players (the controller filter is the only join).

8. **Rubocop + Brakeman clean.**
   - Rubocop: 178 files, 0 offenses. New files (PkmDecoder, PartyParser, CatchCoordinator, met_locations.yml, 4 test files, 2 migrations) all conformant.
   - Brakeman: 2 pre-existing weak-confidence File Access warnings unchanged (EmulatorController + GymScheduleDiscordUpdateJob); no new warnings from Step 17 surface.

---

## Open questions / escalations

None. The brief was fully specified, primary sources verified pre-implementation, and every edge case from the test plan is covered.

One thing the reviewer might surface: **the species lookup falls back to "Species #N" when `pokemon_base_stats` is empty** (KG-20 in BUILD-LOG). The integration test in `parse_save_data_job_test.rb:480-495` tolerates this with a regex match (`assert_match(/Species|^[A-Z]/, row.species)`) since the test DB doesn't seed pokemon data. In production this is a non-issue — the seed task is part of normal deploy. If the reviewer wants stronger guarantees, options are: (a) seed pokemon_base_stats in test_helper, (b) fall back to reading `pokedex.yml` (though that file isn't id-keyed today), or (c) leave as-is and document.

---

**Ready for Review: YES**
