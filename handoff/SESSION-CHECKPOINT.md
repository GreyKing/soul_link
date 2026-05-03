# Session Checkpoint
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*
*Session-scoped — archived to `handoff/archive/` at session end.*

---

## Where We Stopped

Step 17 (PkmDecoder + PartyParser + catches+routes auto-detection) shipped at `eefcbbe`, FF-merged to `origin/main` and pushed. Worktree branch `claude/recursing-cori-8d3bfc` also pushed. Awaiting next brief from Project Owner.

---

## What Was Built

**Step 17 — Gen-IV PKM decryption infrastructure + category 3 (catches + routes) auto-tracking.**

Per the SRAM auto-tracking audit (`handoff/2026-05-02-sram-auto-tracking-audit.md` § 2-3), Step 17 ships the cryptographic infrastructure earmarked for categories 2 and 3 (Layer A — `PkmDecoder` + `PartyParser`, both pure functions that never raise) and ships category 3 (catches + routes) on top. Category 2 (gym battle teams) and Step 18 (Nature/IVs/EVs/movesets) reuse the same Layer A.

**Surfaces introduced:**
- `SoulLink::PkmDecoder` (`app/services/soul_link/pkm_decoder.rb`) — decrypts a single 236-byte (party) or 136-byte (box) Gen-IV PKM record. PID-shuffle (32-entry table cited verbatim from pret/pokeplatinum `src/pokemon.c:4861-4924`) + dual-key two-region LCG (checksum-keyed for blocks A-D, PID-keyed for party stats — pret `src/pokemon.c:328-329`) + checksum verify (sum-of-uint16-words mod 0x10000). Returns a `Pkm` Struct (pid/species/level/ot_id/ot_sid/met_location_id/met_level/is_egg/slot_index) or nil on any error.
- `SoulLink::PartyParser` (`app/services/soul_link/party_parser.rb`) — walks the party block at `PARTY_OFFSET_IN_GENERAL_BLOCK = 0xA0` (cited from PKHeX `SAV4Pt.cs` `GetSAVOffsets()` → closes KG-11). Replicates SaveParser's CRC-validated higher-counter slot picker (loose coupling rather than shared inheritance). Filters nils + eggs + zero-species; returns `Array<Pkm>` size 0..6.
- `SoulLink::CatchCoordinator` (`app/services/soul_link/catch_coordinator.rb`) — side-effect handler. `process(slot, events)` opens a `slot.transaction { }`, iterates events, dispatches PokemonCaughtEvent to `handle_caught` (egg / zero-PID / unclaimed guards → PID dedup against `(soul_link_run_id, discord_user_id, pid)` → resolve route via `GameState.met_location_name` → classify `acquired_via` (event_gift > trade_in > catch precedence) → `SoulLinkPokemon.create!` with `soul_link_pokemon_group_id: nil`). PokemonRemovedEvent is log-only (`Rails.logger.info` — no AR side effect, mirrors `BadgeLost` no-op).
- `config/soul_link/met_locations.yml` — 127 entries (Sentinel Mystery Zone + 15 cities + 30 routes 201-230 + 44 dungeons/overworld + 36 indoor/interior + 5 special pseudo-IDs `event: true` for Daycare4 / LinkTrade4NPC / LinkTrade4 / Ranger4 / Faraway4). Sourced from PKHeX `text_hgss_00000_en.txt` + `Locations.cs` (closes KG-12).
- `SaveDiff` extension — added `Pkm` value Struct, `PokemonCaughtEvent`, `PokemonRemovedEvent`. `Result` extends with `catch_events:` + `removal_events:` (default `[]`); `Result#empty?` checks all six event arrays. `between(...)` adds `prev_party:` + `curr_party:` keyword args (default `nil`); new `diff_party` helper indexes by PID and walks set difference. `hash_get(entry, key)` accepts both symbol-keyed and string-keyed entries (pre/post JSON roundtrip).
- `SaveDiffDispatcher` — wires `prev_party: prev[:party_data]` / `curr_party: curr[:party_data]` into the diff call; fans out to `CatchCoordinator.process(slot, diff.catch_events + diff.removal_events)` when either array is non-empty.
- `ParseSaveDataJob` — calls `PartyParser.parse(slot.save_data).map(&:to_h)` on success; persists via `update_columns(parsed_party_data: …)` (same write that already covered Step-16's parsed_*). Failure path UNCHANGED — KG-13 invariant preserved (only stamps `parsed_at`). `capture_state(slot)` extended with `:party_data`.
- `GameState` — added `MET_LOCATIONS_PATH`, `met_locations`, `met_location_name(id)`, `event_met_location?(id)`. `reload!` clears the new ivar.
- `dashboard_controller.rb` — loads `@auto_detected_catches` (current_user_id-scoped, `pid IS NOT NULL`, `soul_link_pokemon_group_id IS NULL`, ordered `caught_at: :desc`).
- `_pc_box_content.html.erb` — new "AUTO-DETECTED CATCHES" section above ON TEAM. Per-row render: species + route + level. First-encounter (`1ST`) badge computed live by location-group min-by-caught_at. Trade-in (`TRADE-IN`) and event (`EVENT`) pills. Real-time refresh via existing `SoulLinkPokemon` `broadcasts_refreshes_to`.

**Counts:** 461 → **527** tests (+66). 1682 assertions, 0 failures, 0 errors. Rubocop clean (169 → 178 files, 0 offenses). Brakeman clean. 2 migrations.

**Review:** 0 Must Fix, 0 Should Fix. Richard verified PID-shuffle table against PKHeX `PokeCrypto.cs` `BlockPosition`, `Party = 0xA0` against PKHeX `SAV4Pt.cs`, met-location IDs against PKHeX `text_hgss_00000_en.txt` — every primary-source citation real. Confirmed `SoulLinkPokemon` validations remain back-compat (`species` + per-group uniqueness gated on `soul_link_pokemon_group_id.present?`; Step-17 rows skip them). Confirmed retry-safety pattern (parsed_party_data persisted via `update_columns` BEFORE dispatch line — retry sees identical prev/curr, diff is empty).

---

## What Was Decided This Session

- **Two-layer decryption split.** `PkmDecoder` is the per-record crypto primitive (pure, never raises, returns Struct or nil); `PartyParser` is the SRAM walker (active-slot picker + party-block iterator). Step 18 (Nature/IVs/EVs/moveset) extends the `Pkm` Struct without touching either layer's algorithm.
- **PID is the diff key.** `SaveDiff.diff_party` indexes both prev and curr arrays by PID (uint32). New PIDs → catch event; PIDs in prev but not in curr → removal event; same PID present in both → no event. Covers deposit-and-re-catch round-trip via the box block (which Step 17 doesn't parse) AND covers party reorder.
- **Eggs filtered at PartyParser layer.** Eggs (`is_egg: true` per Block-B IV-dword bit 30 OR species==0) never enter `parsed_party_data`. When an egg hatches, the next parse sees a "new" PID → fires PokemonCaughtEvent → CatchCoordinator creates the row at hatch time. Net: eggs invisible until hatched. Acceptable for v1 per audit.
- **Trade-ins create records with `trade_in: true` + `acquired_via: 'trade_in'`.** PKMs whose `ot_id`/`ot_sid` differ from the slot's `parsed_trainer_id`/`parsed_secret_id` aren't filtered out; they're surfaced with a styled `TRADE-IN` pill. (Originally considered dropping them entirely; PO-locked decision in the brief was "flag, don't drop".) `acquired_via` precedence: `event_gift` > `trade_in` > `catch`.
- **Event-met-location PKMs (mystery gift, in-game trade NPC, distant land sentinel) flagged `event: true` in `met_locations.yml`.** CatchCoordinator surfaces them with `acquired_via: 'event_gift'` rather than dropping. Provides UI visibility into non-catch acquisitions without polluting first-encounter logic (route-name fallback prevents conflict with route-based Soul Link rules).
- **`PokemonRemovedEvent` is log-only.** No auto-mark-dead. The audit's edge-case table specifies that release-vs-trade-out-vs-bad-detection ambiguity makes auto-deletion unsafe; UI confirmation flow is downstream work.
- **Manual Catch flow untouched.** Step-17 auto-detected rows have `pid IS NOT NULL` AND `soul_link_pokemon_group_id IS NULL`. Manual catches (existing flow via the modal) keep `pid: nil` AND populate `soul_link_pokemon_group_id`. The `SoulLinkPokemon` `species` and per-group uniqueness validations are gated on `soul_link_pokemon_group_id.present?` so Step-17 rows skip them — no validation changes needed.
- **No partner-linking in Step 17.** Soul Link 4-player partner-pairing logic (linking the same-route catch across all 4 players, dupes-clause, etc.) is downstream Step 18+ work. Auto-detected rows live as standalone unpaired SoulLinkPokemon records for now.
- **First-encounter badge computed live.** `1ST` per `(location, discord_user_id)` group via min-by-caught_at — no schema column. Cheap because the controller already eager-loads.
- **Compound non-unique index on `(soul_link_run_id, discord_user_id, pid)`.** Application-level dedup via `where(...).exists?` in CatchCoordinator. Brief-locked decision (point 9) — partial unique index for `pid IS NOT NULL` rows would require either a virtual column trick (Step-11 pattern) or a stored generated column; non-unique compound index serves the lookup hot path equally well, and the uniqueness check happens in code before the create.
- **`parsed_party_data` is JSON, not a serialized binary blob.** AR's default JSON column coder roundtrips fine via `parsed_party_data: array_of_hashes`. The diff helper's `hash_get(entry, key)` accepts both symbol-keyed and string-keyed entries so pre-write (symbol keys from `Pkm.to_h`) and post-read (string keys from JSON deserialization) both work.
- **Replicated active-slot picker in PartyParser.** Cleaner than refactoring SaveParser to expose its picker as a public class method or extracting a shared `SlotPicker` mixin. Keeps SaveParser's contract narrow ("returns `Result` or nil") and gives PartyParser its own boundary-safe error path.

---

## Known Gaps / Future Work

*See `handoff/BUILD-LOG.md` Known Gaps — running list maintained there.*

Step 17 closed KG-11 (party block offset) and KG-12 (met-location enum). Logged four new gaps:
- **KG-20** — Species name resolution depends on `pokemon_base_stats` being seeded; "Species #N" fallback when empty. Production seeded as part of normal deploy; integration test tolerates fallback via regex.
- **KG-21** — PC box parsing not implemented. Catches that bypass party (auto-deposit on full party in some emulator contexts? trade NPC in Underground?) won't surface until box parsing ships. Step 17 deliberately scoped to party only.
- **KG-22** — No Discord notification on auto-catch. Could be a 1-liner in `CatchCoordinator` (post to run's `general_channel_id`). Deferred per brief.
- **KG-23** — No UI for "this auto-catch is wrong". A player who somehow gets a spurious auto-catch (PKHeX-edited PID collision? save-state shenanigan?) has no in-app delete; would need direct AR. Future affordance.

KG-7 (real-save offset verification for `MAP_ID_OFFSET`) still open from Step 12.

In-browser smoke deferred this step — same pattern as Step 15/16 (parse-job + service code + view extension; existing `SoulLinkPokemon` `broadcasts_refreshes_to` covers the new section's real-time path).

---

## Resume Prompt

Copy and paste this to resume:

---

You are Ava (Architect) on Soul Link — Three Man Team.
Read handoff/SESSION-CHECKPOINT.md, then handoff/BUILD-LOG.md.
Confirm status and next action. Then wait for direction.

---
