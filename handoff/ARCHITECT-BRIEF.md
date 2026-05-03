# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 17 — PkmDecoder + PartyParser + catches+routes auto-detection

### Context

Step 15 shipped `SoulLink::SaveDiff` (pure diff layer) + `SoulLink::GymBeatenCoordinator` + KG-13 fix. Step 16 (8965e47) extended SaveDiff with TID/SID, Pokédex, Hall of Fame; introduced `SoulLink::SaveDiffDispatcher`; locked the three-layer dispatch pattern (SaveDiff → SaveDiffDispatcher → per-category coordinators).

This step builds the **Gen-IV PKM decryption infrastructure** the audit (`handoff/2026-05-02-sram-auto-tracking-audit.md` § 2-3, esp. § 4) earmarked for categories 2 and 3. We ship category 3 (catches + routes) on top. Category 2 (gym battle teams) and Step 18 (Nature/IVs/EVs/movesets) reuse the same infrastructure later.

**Closes KG-11** (party block offset within slot) and **KG-12** (met-location → route-name table).

### Project Owner decisions (locked)

1. **Two new pure-function layers, mirroring `SaveParser`'s shape.**
   - `SoulLink::PkmDecoder` — decrypts a single 236-byte PKM record (PID-shuffle + LCG XOR + checksum verify). Returns a `Pkm` value object on success, `nil` on bad checksum / boundary error / any error. **No AR, no I/O, no `Time.current`. Never raises.**
   - `SoulLink::PartyParser` — walks the SRAM party block, calls `PkmDecoder` on each occupied slot, returns `Array<Pkm>` (size 0..6). Same nil-on-any-error contract.
   - Both reusable by Step 18 (Nature/IVs/EVs/moveset just adds new fields to the `Pkm` struct).
2. **Citation discipline (Step-15/16 pattern).** Every offset / constant / structural decision (PID-shuffle table, LCG constants, party block offset, met-location enum, PKM field offsets) must be cited inline from a primary source: pret/pokeplatinum (`include/pokemon.h`, `include/savedata.h`, `include/constants/location.h`), PKHeX (`PK4.cs`, `SAV4Pt.cs`, `Locations.cs`), or projectpokemon Gen-IV docs. **WebFetch before writing code.** No closing of KG-11 / KG-12 without a primary-source citation in code comments.
3. **`Pkm` struct fields for Step 17 (Step 18 will extend, do not over-fit now):**
   - `pid` (uint32) — encryption seed; primary identity for de-dup
   - `species` (Integer national-dex ID, post-decrypt block-A `0x08-0x09` uint16)
   - `level` (Integer 1-100, party-only block at byte `0x8C`)
   - `ot_id` (uint16) + `ot_sid` (uint16) — block-A `0x0C-0x0F`; trade-in detection compares vs the slot's `parsed_trainer_id` / `parsed_secret_id`
   - `met_location_id` (uint16) — block-D `0x46-0x47` (Platinum-specific layout per audit § 2)
   - `met_level` (Integer) — block-D `0x42` (low 7 bits)
   - `is_egg` (Boolean) — block-B `0x40` IV/Egg/Nicknamed dword bit 30, OR species==0
   - `slot_index` (Integer 0..5) — informational, useful for tests
4. **Party block offset is the single biggest unknown — close KG-11 first.**
   - Authoritative source: pret/pokeplatinum `include/savedata.h` + `include/pokemon.h` (search for `PARTY_BLOCK` / `PartyPokemon` struct + `Party` field on `SaveData` / general block). Also cross-check PKHeX `SAV4Pt.cs` `Party`/`PartyData` getter.
   - **The audit notes `0xA0` within the small/general block** but flags projectpokemon's page as "under construction." **Do not trust `0xA0` without primary-source confirmation.** WebFetch pret/pokeplatinum first; cite the exact file and line in the constant definition.
   - Layout (per Gen-IV docs): the party block starts with a uint32 `count` (occupied slots, 0..6), then 6 × 236-byte party-PKM records back-to-back. Confirm structure shape against pret.
5. **PKM crypto specifics (audit § 2 + projectpokemon Gen-4 PKM-structure doc):**
   - PID at byte `0x00-0x03` (uint32 LE) — never encrypted.
   - Checksum at byte `0x06-0x07` (uint16 LE) — also the encryption key.
   - Bytes `0x08-0x87` are 4 × 32-byte blocks A/B/C/D (Box-PKM format = 136 bytes total).
   - Party records add a 100-byte battle-stats block at `0x88-0xEB` (236 bytes total). The battle-stats block is encrypted with a SECOND LCG seeded from the PID (not the checksum). For Step 17 we only need `level` (`0x8C`) — confirm whether that field needs the second LCG or is in the unencrypted region. (PKHeX `PK4.cs` is the authority. WebFetch.)
   - PID-shuffle: block ordering is `((PID & 0x3E000) >> 0xD) % 24` → index into a 24-permutation table (cite the full table in code; same constant table PKHeX + projectpokemon publish).
   - LCG: `seed = checksum`, then for each 16-bit word in `0x08-0x87`: `seed = (0x41C64E6D * seed + 0x6073) & 0xFFFFFFFF`, XOR `(seed >> 16) & 0xFFFF` against the word.
   - Checksum verification (post-decrypt): sum of all 64 little-endian uint16 words in the 128-byte payload, modulo 0x10000, must equal the stored checksum. **Mismatch → return nil.**
6. **`SaveDiff` extension — extend the existing `Result` struct (NEVER replace).**
   - Add `Pkm` value struct used by both events.
   - Add `PokemonCaughtEvent(player_session_id:, pid:, species_id:, met_location_id:, level:, ot_id:, ot_sid:, is_egg:)` and `PokemonRemovedEvent(player_session_id:, pid:)` to `SaveDiff`.
   - Add `catch_events:` and `removal_events:` keyword fields to `Result` (default `[]`); extend `Result#empty?` accordingly.
   - Extend `SaveDiff.between(...)` with `prev_party:` and `curr_party:` keyword args (each an Array of `Pkm`-shaped Hashes or `nil`); add a `diff_party` helper.
   - **Diff key = PID** (uint32). New PIDs → `PokemonCaughtEvent`. PIDs in prev but not in curr → `PokemonRemovedEvent`. Same PID present in both → no event (covers deposit-and-re-catch and party reorder).
   - Backward compat: existing Step-15/16 callers (no `prev_party:` / `curr_party:`) keep working. Step-15 `SaveDiff.between(prev_badges:, curr_badges:)` still returns a Result with empty catch/removal arrays.
7. **Persistence of party state across parses.** Add `parsed_party_data` JSON column to `soul_link_emulator_save_slots` (nullable). The job writes the current PartyParser output (an Array of Pkm Hashes) to this column on every successful parse with party data; the next parse reads it as `prev_party` for the diff. **Pre-parse capture happens before `update_columns`** — same shape as Step 16's TID/Pokédex/HoF pre/post snapshots.
8. **Catch coordinator (`SoulLink::CatchCoordinator`) — the side-effect handler.**
   - Symmetric to `GymBeatenCoordinator`'s shape: `process(slot, events)` → guards → AR writes wrapped in `slot.transaction { }`.
   - For each `PokemonCaughtEvent`:
     - **Skip eggs** (`event.is_egg` true → no-op, no record). Eggs hatch later → on the hatch parse, `is_egg` flips false, the PID is "new" relative to the prior parse (because eggs were filtered from the prev set too — see point 11), fires PokemonCaughtEvent at hatch.
     - **De-dup against existing SoulLinkPokemon** by PID scoped to (run, discord_user_id). If a row exists, no-op (covers deposit-and-re-catch round-trip across the box block which we don't parse in Step 17).
     - **Detect trade-ins** by comparing `event.ot_id` + `event.ot_sid` to `slot.parsed_trainer_id` + `slot.parsed_secret_id`. If different → still create the record but set `trade_in: true` AND set `acquired_via: 'trade_in'`. If matching → `acquired_via: 'catch'`.
     - **Resolve route name** via `SoulLink::GameState.met_location_name(event.met_location_id)`. Unknown ID → fall back to `"Met-Location ##{id}"` (mirrors `EmulatorHelper#format_map_name`). NEVER raise.
     - **Filter event-only met-locations** (in-game trades, mystery gifts, distant-land sentinel IDs). Tag these in `met_locations.yml` with `event: true` (or a separate `event_met_locations` set) and skip catch creation for them — flag as `acquired_via: 'event_gift'`.
     - **Create the SoulLinkPokemon row.** No group association (`soul_link_pokemon_group_id: nil`). Soul Link 4-player partner-linking is downstream Step 18+ work — explicitly out of scope. `name: species_string` (default), `species: species_name_from_pokedex`, `level: event.level`, `location: route_name`, `discord_user_id: slot.soul_link_emulator_session.discord_user_id`, `caught_at: Time.current` (set by existing before_create), `pid: event.pid`, `met_location_id: event.met_location_id`, `ot_id: event.ot_id`, `ot_sid: event.ot_sid`, `trade_in: …`, `acquired_via: …`.
   - For each `PokemonRemovedEvent`: **log only** at `info` (`"CatchCoordinator: PokemonRemovedEvent pid=… run=… session=… — no auto-mark-dead"`). No AR side effect. Same shape as `BadgeLost` no-op.
9. **`SoulLinkPokemon` schema additions (one migration):**
   - `pid` (`bigint`, nullable — manual catches stay nil; only auto-detected catches populate it)
   - `met_location_id` (`integer`, `limit: 2`-safe shape — use plain `:integer` like the Step-16 `parsed_*` columns to avoid uint16 upper-half overflow)
   - `ot_id` (`integer`, nullable)
   - `ot_sid` (`integer`, nullable)
   - `trade_in` (`boolean`, default `false`, null `false`)
   - `acquired_via` (`string`, nullable — values: `'catch'`, `'trade_in'`, `'event_gift'`. Manual creations stay nil for back-compat with the existing Catch flow.)
   - **Compound index** `[soul_link_run_id, discord_user_id, pid] WHERE pid IS NOT NULL` for de-dup lookup (use a partial unique index — MySQL 8 supports virtual-column unique indexes; mirror the Step 11 `active_guild_id` pattern if a partial index isn't directly available, or just a non-unique compound index + application-level uniqueness check is acceptable for v1).
   - **Validations stay backward-compatible**: `pid` is nullable; manual catches keep working unchanged.
10. **`met_locations.yml` — new reference data file (closes KG-12).**
    - Path: `config/soul_link/met_locations.yml`. Same shape as `maps.yml`: `id => { name: "Route 201" }`. Optional fields: `event: true` (filters to event-gift/mystery-gift/in-game-trade pseudo-locations), `dungeon: true`, `region: 'Sinnoh'` — extension hooks, ship `name:` only for v1.
    - Source: pret/pokeplatinum `include/constants/location.h` (Platinum-specific). Cross-check PKHeX `Locations.cs` Gen-IV table. **WebFetch first, cite both sources in the YAML header comment.** This is a different enum from `maps.yml` (map-header IDs vs encounter-table met-location IDs) — explicit comment to prevent confusion.
    - Coverage target for v1: **all Platinum routes 201-230, every gym town, every notable dungeon (Eterna Forest, Mt Coronet, Stark Mountain, Distortion World, Spear Pillar) + every event/trade pseudo-location flagged with `event: true`.** Total ~80-100 entries. Missing IDs surface as "Met-Location #N" via the helper fallback — graceful degradation.
    - Extend `SoulLink::GameState`: add `MET_LOCATIONS_PATH` constant + `met_locations` (memoized YAML loader, returns `{}` on missing file) + `met_location_name(id)` (returns nil on unknown ID) + `event_met_location?(id)` (returns boolean). Add to `reload!`.
11. **Egg handling rule (locked).** `PartyParser` filters out eggs before returning. `is_egg`-true PKMs never enter `parsed_party_data` and never hit the diff. When the egg hatches in-game, the next parse sees a PID that wasn't in the prior set → fires PokemonCaughtEvent → CatchCoordinator creates the record at hatch time. **Net behavior:** an egg in the party is invisible to the auto-tracker; it materializes as a "caught" event the moment it hatches. Acceptable for Soul Link v1 (no egg semantics in scope per audit § 3 edge-case table).
12. **`ParseSaveDataJob` extension.**
    - Add `parsed_party_data` to the `update_columns` write (using `PartyParser.parse(slot.save_data)`'s output, JSON-serialized via Rails' default JSON column coder).
    - Extend `capture_state(slot)` to include `:party_data => slot.parsed_party_data`.
    - Extend `SaveDiffDispatcher.dispatch` to wire `prev_party` / `curr_party` into `SaveDiff.between(...)` and to fan out to `CatchCoordinator` when `diff.catch_events.any? || diff.removal_events.any?`.
    - **Failure path unchanged (KG-13 invariant):** parse failure stamps only `parsed_at`; `parsed_party_data` keeps its prior value.
    - **Baseline rule unchanged (Step 15):** dispatcher still gates on `prev[:parsed_at].present?` — first-ever parse with a 6-mon party does NOT fire 6 catch events.
13. **Dashboard surface — extend the PC BOX tab, NOT the existing group-based UI.**
    - `app/views/dashboard/_pc_box_content.html.erb` gets a new section near the top (above the existing `ON TEAM` section): **`AUTO-DETECTED CATCHES`** showing per-player auto-tracked SoulLinkPokemon (`pid IS NOT NULL`, `soul_link_pokemon_group_id IS NULL`, scoped to run + current_user_id, ordered `caught_at DESC`).
    - Per-row render: `"<species> — <route_name> — Lv <level>"` plus badges as needed. Mirror the visual style of the existing box-cell layout.
    - **First-encounter badge.** Compute `first_encounter_for_route?` live: a SoulLinkPokemon is the first encounter iff `SoulLinkPokemon.where(soul_link_run_id:, discord_user_id:, location:).order(:caught_at).first.id == self.id`. Render a small `1ST` badge next to qualifying catches.
    - **Trade-in flag.** Records with `trade_in: true` get a styled `TRADE-IN` pill (use one of the existing palette tokens — `--amber` works, mirrors the YOU badge styling).
    - **Real-time refresh.** `SoulLinkPokemon` already has `broadcasts_refreshes_to ->(record) { [ record.soul_link_run, :dashboard ] }` (see model line 25) — auto-detected catches surface live on dashboard pages with no extra wiring. Confirm in test, no model edits required.
14. **No partner-linking.** The existing `SoulLinkPokemonGroup` flow (manual Catch modal → group with 4 linked pokemon) is untouched. Auto-detected catches live as `soul_link_pokemon_group_id: nil` rows. A future Step 18+ will add the partner-pairing logic. **Reviewer should flag any code that auto-creates groups or auto-assigns to existing groups.**
15. **Out of scope (do NOT implement):**
    - Nature surface (even though derivable from PID alone — Step 18)
    - IVs / EVs / moveset surface (Step 18)
    - Held items
    - PC box parsing (only party block in Step 17)
    - Auto-mark-dead from PC-box "Released" detection
    - Discord notifications for new catches
    - Full Soul Link 4-player partner-linking, dupes-clause, party shenanigans
    - UI confirmation flow for `PokemonRemovedEvent` (just log it)

### Architecture summary

```
ParseSaveDataJob
 ├─ pre-snapshot (now includes :party_data)
 ├─ SaveParser.parse (unchanged Step-16 surface)
 ├─ PartyParser.parse(save_data) → Array<Pkm>          ← NEW Layer A
 │     └─ PkmDecoder.decrypt(record_bytes) → Pkm or nil  ← NEW Layer A
 ├─ update_columns(parsed_*, parsed_party_data: …)
 └─ SaveDiffDispatcher.dispatch(slot, prev:, curr:)
       └─ SaveDiff.between(prev_party:, curr_party:, …) returns Result with
          catch_events: + removal_events: (in addition to badge/tid/pokedex/hof)
          └─ CatchCoordinator.process(slot, events)    ← NEW Layer B
                ├─ skip eggs / dedupe by PID / detect trade-in
                ├─ resolve route via GameState.met_location_name
                └─ SoulLinkPokemon.create!(pid:, species:, location:, …, trade_in:, acquired_via:)
                    └─ existing broadcasts_refreshes_to fires Turbo refresh
```

### Diff scope

- **New files (8):**
  - `app/services/soul_link/pkm_decoder.rb`
  - `app/services/soul_link/party_parser.rb`
  - `app/services/soul_link/catch_coordinator.rb`
  - `config/soul_link/met_locations.yml`
  - `db/migrate/<ts>_add_step_17_columns_to_soul_link_pokemon.rb`
  - `db/migrate/<ts>_add_parsed_party_data_to_soul_link_emulator_save_slots.rb`
  - `test/services/soul_link/pkm_decoder_test.rb`
  - `test/services/soul_link/party_parser_test.rb`
  - `test/services/soul_link/catch_coordinator_test.rb`
- **Modified files (~7):**
  - `app/services/soul_link/save_diff.rb` — add `Pkm` struct, `PokemonCaughtEvent` / `PokemonRemovedEvent` structs, `catch_events:` / `removal_events:` Result fields, `between(... prev_party:, curr_party: …)` keyword args, `diff_party` helper, `Result#empty?` extension
  - `app/services/soul_link/save_diff_dispatcher.rb` — capture/wire party data, fan out to `CatchCoordinator`
  - `app/services/soul_link/game_state.rb` — `met_locations` loader + `met_location_name` + `event_met_location?` + `reload!` extension
  - `app/jobs/soul_link/parse_save_data_job.rb` — call `PartyParser`, persist `parsed_party_data`, extend `capture_state`
  - `app/models/soul_link_pokemon.rb` — new column accessors are auto-wired by AR; **only edit if validations need adjustment** (e.g. allow nil pid). Probably no edits needed.
  - `app/views/dashboard/_pc_box_content.html.erb` — new `AUTO-DETECTED CATCHES` section with first-encounter + trade-in badges
  - `app/controllers/dashboard_controller.rb` — load the new auto-detected catches collection alongside `@on_team_groups` / `@storage_groups` / `@fallen_groups`
- **Extended test files (~3):**
  - `test/services/soul_link/save_diff_test.rb` — catch_events/removal_events tests + `prev_party:` / `curr_party:` backward compat
  - `test/services/soul_link/save_diff_dispatcher_test.rb` — party fan-out, baseline rule for catches
  - `test/jobs/soul_link/parse_save_data_job_test.rb` — `parsed_party_data` persists; integration: simulate 1→2 party slots, assert SoulLinkPokemon row created with correct route name; CatchCoordinator de-dup on retry
  - `test/services/soul_link/save_parser_test.rb` — only if changes are needed there (probably not)
  - `test/services/soul_link/game_state_test.rb` — `met_locations` loader + `met_location_name` + `event_met_location?` (Step-12-style canary: assert key route IDs ship — Route 201, Twinleaf, Oreburgh, Eterna, Sunyshore, Pokemon League)

### Tests (per the brief — bake every edge case)

1. **`PkmDecoder`** — representative encrypted block round-trips to known-decoded values. Use a fixture from PKHeX's test vectors or a hand-crafted PID-shuffle test (cite the source in the test file). Cover: all 24 block orderings (parametrize on PID's bits 13-17); checksum mismatch returns nil; boundary error returns nil.
2. **`PartyParser`** — party block with 1, 6, and partial (e.g. 3) party members; corrupted block (bad CRC at general level → nil); empty party (count=0 → []); mixed eggs + pokémon (eggs filtered out); each PKM checksum invalid → that PKM dropped, others returned.
3. **`SaveDiff` `PokemonCaughtEvent` emit conditions** — empty prev + empty curr → no events; empty prev + 1 PKM curr → 1 catch event; 1 PKM prev + same 1 PKM curr → no events (PID stable); 1 PKM prev + different PID curr → 1 catch + 1 removal; 6 prev + 5 curr (same 5 PIDs survived) → 1 removal; both nil → no events (defensive); only one side nil → no events.
4. **`met_locations.yml`** — file loads, key gym towns + key routes ship (Step-12 canary): assert `Route 201`, `Oreburgh City`, `Eterna City`, `Sunyshore City`, `Pokemon League`, `Distortion World` are present; at least one `event: true` entry exists.
5. **`CatchCoordinator`** — egg event no-ops; PID-already-exists no-ops; new catch creates `SoulLinkPokemon` with correct fields; trade-in event creates with `trade_in: true` + `acquired_via: 'trade_in'`; event-met-location creates with `acquired_via: 'event_gift'` (but NOT a 'caught' record? PO call → re-read the brief: trade-ins create a record with the trade-in flag; mystery-gift / event-met IDs ALSO create with `event_gift` flag — surface them, don't drop them); transaction wraps create; PokemonRemovedEvent log-only no-op.
6. **Backward compatibility** — existing saves without party data parse cleanly (`parsed_party_data: nil` → diff dispatcher falls through cleanly, no events). Existing Step-15/16 SaveDiff callers untouched. Existing manual Catch flow unchanged (manually-created `SoulLinkPokemon` with `pid: nil` validates and renders correctly).
7. **Integration** — simulate a player's save going from 1 → 2 party slots; assert `SoulLinkPokemon` record created with correct route name, correct discord_user_id, correct level. Re-run the same job; assert NO duplicate (PID dedup).
8. **Coordinator retry idempotency** — same shape as Step 15's regression: `CatchCoordinator.process` raising on first run does not double-fire on retry (because `update_columns` writes `parsed_party_data` BEFORE dispatch — the retry sees `prev_party_data == curr_party_data`, diff is empty, no re-dispatch). **Bake this test.**

### Citation requirements (KG closures)

- **KG-11 closes** if and only if `PARTY_BLOCK_OFFSET` (or whatever the constant is named) is cited in `party_parser.rb` from a primary source (pret/pokeplatinum file + line OR PKHeX `SAV4Pt.cs` field). Both is better. If you can't pin it, KG-11 stays open and the brief is incomplete — escalate to Architect.
- **KG-12 closes** if and only if `met_locations.yml`'s header comment cites pret/pokeplatinum `include/constants/location.h` and PKHeX `Locations.cs` Gen-IV section as the sources, with at least the v1 coverage target satisfied (~80-100 entries spanning Sinnoh routes + gym towns + key dungeons + event-pseudo IDs).
- **PKM crypto offsets / table.** Cite the PID-shuffle 24-permutation table inline (or link to projectpokemon Gen-4 PKM-structure doc with a one-line summary in code). Cite the LCG constants from PKHeX `PK4.cs` or projectpokemon doc.

### Standing rules (PO confirmed)

- Commit + push freely. Only stop on truly destructive ops.
- `.claude/settings.json` already widened in this worktree at start-of-step.
- Architect-Brief is **session-active** — Bob and Richard read THIS file as the source of truth for Step 17.
- The user is on mobile — pause for input only when there's a real human-decision needed (no decisions are expected for this step; the brief is locked).

### Builder Plan section
*Bob (Builder) — 2026-05-03. No open questions: brief is fully specified, primary sources verified pre-plan. Proceeding directly per BUILDER.md rule for "literal-to-brief plans with no open questions."*

#### Primary sources verified (KG-11, KG-12 closures pinned)

Fetched from raw.githubusercontent.com BEFORE writing any code:

1. **Party block offset = 0xA0** within the general/small block.
   Source: PKHeX `PKHeX.Core/Saves/SAV4Pt.cs` `GetSAVOffsets()` → `Party = 0xA0`
   alongside `Trainer1 = 0x68` and `Extra = 0x2820`. **KG-11 closes.**

2. **PID-shuffle 24-permutation table** (canonical, indexed by `((pid >> 13) & 0x1F) % 24`):
   Source: pret/pokeplatinum `src/pokemon.c:4861-4924` `BoxPokemon_GetDataBlock`
   switch statement maps cases 0..23 (and 24..31 collapse to 0..7 via `% 24`)
   to one of 24 ABCD orderings. PKHeX `PokeCrypto.Shuffle45` table identical.
   The 24 orderings are the canonical Gen-IV permutation matrix
   (also documented at projectpokemon Gen-4 PKM-structure r65).

3. **LCG constants** (Gen-IV PKM crypt LCG):
   Source: pret/pokeplatinum `include/math_util.h:8-10`
   `LCRNG_MULTIPLIER = 1103515245` (= 0x41C64E6D)
   `LCRNG_INCREMENT  = 24691`      (= 0x6073)
   Algorithm: `seed = seed * mult + inc` (mod 2^32, u32 overflow), XOR uses
   `seed >> 16` (the high 16 bits) per `src/math_util.c:217-234` `EncodeData`
   + `LCRNG_NextFrom`. Confirmed in PKHeX `PokeCrypto.cs` `Decrypt45` →
   `CryptArray(data[8..136], chk)` for blocks A-D, then `CryptArray(data[136..], pv)`
   for the party-only stats block. **Two separate LCG keys: chk for blocks, pid for party stats.**

4. **PKM record field offsets** (block-relative, Platinum):
   Source: pret/pokeplatinum `include/struct_defs/pokemon.h:16-149`.
   - PID: record `0x00-0x03` (uint32 LE, never encrypted)
   - checksum: record `0x06-0x07` (uint16 LE, also encryption key)
   - Block A 0x00 species (uint16) → record `0x08-0x09`
   - Block A 0x04 otID (uint32 = TID low + SID high, 2x uint16) → record `0x0C-0x0F`
   - Block B 0x10 IV/Egg dword (`isEgg : 1` at bit 30) → record `0x38-0x3B`
   - Block B 0x1E `MetLocation_PtHGSS` (uint16) → record `0x46-0x47` (matches brief)
   - Block D 0x1C `metLevel : 7` → record `0x84` low 7 bits
   - PartyPokemon 0x08C `level` (uint8) → record absolute `0x8C` (party-only block)
   PartyPokemon block (`0x88-0xEB`) IS encrypted — second LCG keyed with PID,
   per `src/pokemon.c:328` `Pokemon_DecryptData(&mon->party, sizeof(PartyPokemon), mon->box.personality)`.

5. **Met-location enum (Platinum)**: PKHeX
   `PKHeX.Core/Resources/text/locations/gen4/text_hgss_00000_en.txt` — 235 entries,
   0-indexed (0 = "Mystery Zone", 1 = "Twinleaf Town", ..., 126 = "Rock Peak Ruins").
   Entries 127..235 are Johto/Kanto/HGSS — out of Platinum scope. Special IDs
   from PKHeX `Locations.cs`: 2000 = Daycare4 (egg), 2001 = LinkTrade4NPC, 2002 = LinkTrade4,
   3001 = Ranger4 (event), 3002 = Faraway4 (mystery gift). All five tagged `event: true`
   in `met_locations.yml`. **KG-12 closes.**

#### Build order (file-by-file, with line estimates)

1. **`config/soul_link/met_locations.yml`** (~150 lines) — full Platinum + special IDs from PKHeX text + Locations.cs, header comment cites both pret + PKHeX.
2. **`app/services/soul_link/game_state.rb`** (+15 lines) — `MET_LOCATIONS_PATH`, `met_locations`, `met_location_name(id)`, `event_met_location?(id)`, extend `reload!`.
3. **`app/services/soul_link/pkm_decoder.rb`** (~180 lines) — `Pkm` Struct + `decrypt(bytes, slot_index:)` static method. Pure, never raises, returns nil on any failure. PID-shuffle table inline as a frozen 2D constant; LCG inline; checksum verify post-decrypt. Cites pret + PKHeX in header.
4. **`app/services/soul_link/party_parser.rb`** (~80 lines) — `parse(save_data)` static method. Reads count + 6 records from `slot_offset + 0xA0`. Calls PkmDecoder per slot. Filters eggs + nils. Returns Array<Pkm>. Cites SAV4Pt.cs `Party = 0xA0` in header.
5. **`db/migrate/<ts1>_add_step_17_columns_to_soul_link_pokemon.rb`** (~25 lines) — additive: pid (bigint), met_location_id (integer), ot_id (integer), ot_sid (integer), trade_in (boolean default false null false), acquired_via (string). Compound non-unique index `(soul_link_run_id, discord_user_id, pid)` per brief decision 9 ("application-level uniqueness check is acceptable for v1").
6. **`db/migrate/<ts2>_add_parsed_party_data_to_soul_link_emulator_save_slots.rb`** (~12 lines) — additive: parsed_party_data (json, nullable).
7. **`app/services/soul_link/save_diff.rb`** (+90 lines) — add `Pkm` Struct, `PokemonCaughtEvent`/`PokemonRemovedEvent` Structs, `catch_events`/`removal_events` Result fields, `prev_party:`/`curr_party:` keyword args, `diff_party` helper, extend `Result#empty?`. Backward-compat for Step-15/16 callers preserved (defaults `[]`).
8. **`app/services/soul_link/save_diff_dispatcher.rb`** (+5 lines) — wire prev_party/curr_party kwargs into `between(...)` and fan out to `CatchCoordinator` when catch/removal events any.
9. **`app/services/soul_link/catch_coordinator.rb`** (~120 lines) — `process(slot, events)` symmetrical to `GymBeatenCoordinator`. Egg skip, PID dedup against existing rows, trade-in detection, route resolution via GameState, event-met filtering, transaction-wrapped `SoulLinkPokemon.create!`. PokemonRemovedEvent log-only.
10. **`app/jobs/soul_link/parse_save_data_job.rb`** (+10 lines) — capture `:party_data` in `capture_state`, call PartyParser.parse on success, persist `parsed_party_data` in update_columns. KG-13 invariant preserved (failure path: only stamp `parsed_at`).
11. **`app/controllers/dashboard_controller.rb`** (+5 lines) — load `@auto_detected_catches` for current_user.
12. **`app/views/dashboard/_pc_box_content.html.erb`** (+50 lines) — new "AUTO-DETECTED CATCHES" section above ON TEAM, per-row render, first-encounter + trade-in badges.
13. **Test files (~600-800 lines total)**:
    - `test/services/soul_link/pkm_decoder_test.rb` — round-trip via known-PID synthetic blocks; checksum-fail returns nil; all 24 PID-shuffle orderings exercised; boundary errors return nil; egg bit detected.
    - `test/services/soul_link/party_parser_test.rb` — partial party (1, 3, 6 mons), empty, mixed eggs, corrupt PKM dropped, all-corrupt returns [].
    - `test/services/soul_link/save_diff_test.rb` — extend with party diff: empty/empty, new PID, removed PID, stable PID, both-nil, one-nil; PartyParser-generated payload.
    - `test/services/soul_link/save_diff_dispatcher_test.rb` — extend with CatchCoordinator fan-out test + baseline rule.
    - `test/services/soul_link/catch_coordinator_test.rb` — egg no-op, PID dedup, new catch creation, trade-in flag, event-met-location flag, removal log-only, transaction wrap, missing run/session no-op.
    - `test/services/soul_link/game_state_test.rb` (or new met-loc-specific test) — Step-12-style canary on Route 201, gym towns, Distortion World; event_met_location? for 2000+; missing-id → nil.
    - `test/jobs/soul_link/parse_save_data_job_test.rb` — extend with parsed_party_data persistence + 1→2 party integration + retry idempotency on PartyParser results.
    - `test/factories/soul_link_pokemon.rb` — no changes likely (existing factory still satisfies; new columns are nullable).

#### Test plan summary (mapping brief test scenarios to files)

- Brief test 1 (PkmDecoder crypto correctness): `pkm_decoder_test.rb`. All 24 orderings via parametric build; checksum mismatch; boundary error; egg-bit; round-trip from a hand-crafted PID-encrypted block.
- Brief test 2 (PartyParser): `party_parser_test.rb`. count=0, count=1, count=3, count=6, mixed eggs (filtered), corrupt PKM dropped.
- Brief test 3 (SaveDiff catch/removal events): `save_diff_test.rb` extension. 7 scenarios from brief.
- Brief test 4 (met_locations.yml canary): `game_state_test.rb` (or new file). 7 known-IDs assertion + event flag assertion.
- Brief test 5 (CatchCoordinator): `catch_coordinator_test.rb`. 8 scenarios.
- Brief test 6 (back-compat): `save_diff_test.rb` + `parse_save_data_job_test.rb` regression checks.
- Brief test 7 (integration 1→2 party): `parse_save_data_job_test.rb`. New + idempotency.
- Brief test 8 (retry idempotency): `parse_save_data_job_test.rb`. Mirror Step-15 retry test shape.

#### Open questions

None. Proceeding to implementation.

