# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 18 — Per-Pokémon stats (Nature/IVs/EVs/moves) + PC box parsing

### Context

Step 17 (b0be7e4 / `eefcbbe`) shipped `SoulLink::PkmDecoder` (Layer A — pure 236-byte / 136-byte PKM decryptor, never raises) and `SoulLink::PartyParser` (Layer B — walks the SRAM party block at offset 0xA0, returns `Array<Pkm>`). The `Pkm` value Struct currently surfaces `pid / species / level / ot_id / ot_sid / met_location_id / met_level / is_egg / slot_index`. `SoulLink::CatchCoordinator` consumes `PokemonCaughtEvent` / `PokemonRemovedEvent` from `SaveDiff`, dedups by `(run, discord_user_id, pid)`, and writes `SoulLinkPokemon` rows with `pid IS NOT NULL` AND `soul_link_pokemon_group_id IS NULL`. The dashboard PC BOX tab renders an "AUTO-DETECTED CATCHES" section showing species + route + level + 1ST / TRADE-IN / EVENT pills.

This step extends the same `PkmDecoder` foundation with **per-Pokémon competitive-detail fields** (Nature, IVs, EVs, moveset) and adds a **PC box parser** that closes KG-21. Both new fields and the box parser sit on top of Step 17 — no algorithm changes to PID-shuffle or LCG XOR.

**Closes KG-21** (PC box parsing). KG-20 (species-id fallback) is **deferred** — orthogonal to PKM crypto; needs a numeric-id-keyed pokedex source we don't have.

### Project Owner decisions (locked)

1. **Extend the Step-17 `Pkm` Struct in place — eagerly populate the new fields.** The input brief floated lazy decryption; rejecting that — decrypt cost is fixed, structs are small, eager is simpler and matches the existing shape. Add `nature` (Integer 0..24, derived from `pid % 25`), `ivs` (Hash with keys `:hp/:atk/:def/:spe/:spa/:spd` → Integer 0..31 each), `evs` (Hash same keys → Integer 0..255 each), `moves` (Array of 4 Hashes `{ id:, pp:, pp_up: }`). Step 17 callers that don't read these fields are unaffected.

2. **Backward-compat is non-negotiable.** Step 17 catches landed BEFORE these fields existed; their `parsed_party_data` JSON has no `nature/ivs/evs/moves` keys, and their `SoulLinkPokemon` rows have nil/null `ivs/evs/moves`. The `Pkm` struct must tolerate `nil` for any field. The view must render cleanly when the columns are nil. **The `nature` column already exists on `soul_link_pokemon`** (legacy from earlier work — schema.rb line 180); reuse it.

3. **PC box parsing as a sibling layer (`SoulLink::BoxParser`), not a refactor of `PartyParser`.** Same shape — pure function, never raises, returns `Array<Pkm>`. Lives at `app/services/soul_link/box_parser.rb`. Re-uses `PkmDecoder.decrypt` per-record (decoder already accepts the 136-byte box record size).

4. **Box block layout (cite from PKHeX `SAV4Pt.cs` + `SAV4.cs`):**
   - Each save partition (0x40000 bytes) contains a **general block** (`GeneralSize = 0xCF2C`) at partition offset 0 followed by a **storage block** (`StorageSize = 0x121E4`) at partition offset `0xCF2C`. Both blocks have their own footer (last 16 bytes of each block, with CRC-16-CCITT in the last 2 bytes — reuse `PartyParser`'s `crc16_ccitt` helper).
   - **Box data starts at offset `+4` within the storage block.** PKHeX `SAV4Pt.cs` declares `private const int StorageSize = 0x121E4; // Start 0xCF2C, +4 starts box data`. The first 4 bytes are the "current box index" pointer — informational, not load-bearing for parsing.
   - **Layout: 18 boxes × 30 slots × 136 bytes per slot = `0x11EE0` bytes total of box-PKM records.** After that comes box names, wallpapers, etc. (which we ignore).
   - Box-PKM records are 136-byte boxes (no party-stats block). `PkmDecoder.decrypt(record, slot_index: nil)` returns a `Pkm` with `level: nil` (correct — boxed Pokémon don't carry level in the box record). For UX-display purposes, that's acceptable for v1; we surface the box-level ("met level") as a fallback if level is nil.

5. **Storage block active-slot selection mirrors `PartyParser`'s logic.** Both partitions hold a storage block; the active one is the partition whose storage footer has the higher save_counter AND a valid CRC. Re-use the same picker shape as `PartyParser.pick_active_slot` but pointed at the storage block (offset `0xCF2C` within each partition, size `0x121E4`). The active general block and active storage block can live in DIFFERENT partitions (per PKHeX's `StorageBlockPosition` swap behavior). **Do not assume they live in the same partition** — `PartyParser` does not assume this either; the picker reads each block's own footer independently.

6. **`BoxedPokemonObservedEvent` is a new SaveDiff event type, distinct from `PokemonCaughtEvent`.** Why distinct: provenance matters for UX (the "CAUGHT OFF-FEED" badge surfaces that the catch arrived via box-only diff). Wiring:
   - `SaveDiff.between` gains `prev_box:` / `curr_box:` keyword args (default `nil`).
   - `SaveDiff::Result` gains `box_events:` (default `[]`).
   - `SaveDiff::BoxedPokemonObservedEvent` Struct: same fields as `PokemonCaughtEvent` (`pid, species_id, met_location_id, level, ot_id, ot_sid, is_egg`).
   - `diff_box(prev_box, curr_box)` returns events for PIDs present in `curr_box` but absent from `prev_box`. Same defensive nil-guard as `diff_party`.

7. **Cross-event de-dup: PID is the global key, party events processed first.** `CatchCoordinator.process` first iterates `PokemonCaughtEvent` (existing logic — creates row with `caught_off_feed: false`), then iterates `BoxedPokemonObservedEvent`. For box events, the existing `(run, discord_user_id, pid)` `.exists?` check no-ops the create when a row already exists from the party-side event. Net: a single catch produces exactly one `SoulLinkPokemon` row regardless of arrival path.

8. **`caught_off_feed: true` set on rows that arrive through the box path.** New boolean column on `soul_link_pokemon`, default `false`, NOT NULL. UI: dedicated "OFF-FEED" pill alongside the existing 1ST / TRADE-IN / EVENT pills.

9. **Move-name resolution is OUT of scope.** Numeric fallback "Move #N" is fine for v1. Adding a `config/soul_link/moves.yml` would mean ~467 Gen IV moves + a maintenance burden; log as new KG-24 instead. The IV/EV/Nature display IS in scope (no external lookup needed; nature is a 25-entry constant, IVs/EVs are integers).

10. **UI surface = inline expand row in the existing AUTO-DETECTED CATCHES section.** Click a row → expand a detail panel below it showing Nature, IVs (`H A D Sp SA SD = 31/31/31/31/31/31`), EVs (same shape), Moves (numbered 1-4 with "Move #N · PP n/m"). Do NOT touch the existing pixeldex modal flow (used by manual catches). Keep the auto-catch UX self-contained. The OFF-FEED pill renders alongside 1ST / TRADE-IN / EVENT, same styling pattern.

11. **Citation discipline (Step-17 pattern).** Every new offset / constant / field-position must be cited inline from a primary source: PKHeX (`PK4.cs`, `SAV4Pt.cs`, `SAV4.cs`, `PokeCrypto.cs`), pret/pokeplatinum (`include/struct_defs/pokemon.h`, `include/savedata/save_table.h`), or projectpokemon Gen-IV docs. **WebFetch before writing decoder code.** Reviewer will spot-check.

### What to build

#### A. PkmDecoder extension — `Pkm` struct gains 4 new fields

`app/services/soul_link/pkm_decoder.rb`:

1. Extend the `Pkm` Struct with `:nature, :ivs, :evs, :moves` keyword fields. Existing fields stay in their current order — append new fields at the end (Ruby Structs are positional under the hood; appending preserves existing positional access).
2. Populate during `decrypt`:
   - **Nature**: `nature = pid % 25` — derive from PID directly, no decryption needed. Surface as Integer 0..24 (the calling layer maps to a name via a separate constant — see C below).
   - **IVs**: re-use the existing IV dword read at `UNSHUFFLED_IV_DWORD_OFFSET` (Block B +0x10). The 32-bit dword packs HP/Atk/Def/Spe/SpA/SpD as 5 bits each (low 30 bits, in order), bit 30 = isEgg, bit 31 = isNicknamed. Extract: `hp = dword & 0x1F; atk = (dword >> 5) & 0x1F; def_ = (dword >> 10) & 0x1F; spe = (dword >> 15) & 0x1F; spa = (dword >> 20) & 0x1F; spd = (dword >> 25) & 0x1F`. Build the `ivs` Hash. Cite from PKHeX `PK4.cs` `IV_HP` / `IV_ATK` / etc. accessors and pret/pokeplatinum `include/struct_defs/pokemon.h`.
   - **EVs**: read 6 bytes at unshuffled offset `0x18..0x1D` (Block A +0x10..+0x15). Order: HP / Atk / Def / Spe / SpA / SpD (1 byte each, 0..255). Cite from PKHeX `PK4.cs` `EV_HP` at offset 0x18 etc.
   - **Moves**: read 4 × u16 LE at unshuffled offset `0x28..0x2F` (Block B +0x08..+0x0F → MoveID array). Read 4 × u8 at `0x30..0x33` (PP). Read 4 × u8 at `0x34..0x37` (PP-up). Build the `moves` Array of `{id:, pp:, pp_up:}` Hashes. Cite from PKHeX `PK4.cs` `Move1` (0x28) through `Move4_PPUps` (0x37). **Note: moves are in Block B, NOT Block C** (the input-brief said Block C — that was a typo; verify against PKHeX `PK4.cs` `Move1` accessor at offset 0x28).
3. Add `UNSHUFFLED_EV_OFFSET = 0x18` (block A +0x10), `UNSHUFFLED_MOVES_OFFSET = 0x28` (block B +0x08), `UNSHUFFLED_PP_OFFSET = 0x30`, `UNSHUFFLED_PP_UP_OFFSET = 0x34` constants. Document each with the PKHeX citation in a comment.
4. Tests in `test/services/soul_link/pkm_decoder_test.rb`:
   - Nature derivation: PID 0 → 0 (Hardy), PID 0xFFFFFFFF → `0xFFFFFFFF % 25 = 9` (Lax — verify the math), and a few in-between fixtures.
   - IVs round-trip: build a known IV dword (e.g. all 31s = `0x3FFFFFFF`), encrypt with a fake checksum, run through `decrypt`, assert the Hash.
   - EVs round-trip: same shape — known 6 bytes in encrypted block A → decoded Hash.
   - Moves round-trip: 4 IDs (e.g. 1/2/3/4), 4 PP values, 4 PP-ups → decoded Array.
   - Backward-compat: existing Step 17 pkm_decoder_test fixtures (which don't assert on the new fields) keep passing unchanged.

#### B. BoxParser — new file `app/services/soul_link/box_parser.rb`

1. Sibling to `PartyParser`. Same `module SoulLink` namespace, same pure-function shape, never raises, returns `Array<Pkm>` (size 0..540) or `[]` on any error.
2. `STORAGE_OFFSET_IN_PARTITION = 0xCF2C` (cited from PKHeX `SAV4Pt.cs` `GeneralSize` constant — storage starts where general ends). `STORAGE_SIZE = 0x121E4` (cited from PKHeX `SAV4Pt.cs` `StorageSize`). `BOX_DATA_OFFSET_IN_STORAGE = 4` (cited from PKHeX `SAV4Pt.cs` `// Start 0xCF2C, +4 starts box data` comment). `BOX_COUNT = 18`, `SLOTS_PER_BOX = 30`, `BOX_RECORD_SIZE = 136` (`SoulLink::PkmDecoder::BOX_SIZE`). Total box-data bytes = `BOX_COUNT * SLOTS_PER_BOX * BOX_RECORD_SIZE = 0x11EE0`.
3. **Active storage-block picker.** Read both partitions' storage blocks, CRC-validate each (re-use `crc16_ccitt`), pick the higher save_counter. Storage footer layout matches the general block's: counter at `STORAGE_SIZE - 0x14`, CRC at `STORAGE_SIZE - 2`. Verify these constants against PKHeX before writing — if PKHeX's storage footer offsets differ from the general-block footer offsets, surface that and cite. **Do not assume parity.**
4. Walk: for each `(box_idx, slot_idx)` pair, slice 136 bytes at `STORAGE_OFFSET + BOX_DATA_OFFSET_IN_STORAGE + ((box_idx * SLOTS_PER_BOX + slot_idx) * BOX_RECORD_SIZE)`. Decode via `PkmDecoder.decrypt(record, slot_index: nil)`. Filter nil / eggs / `species == 0`. Append to result.
5. Tests in `test/services/soul_link/box_parser_test.rb`:
   - Empty box (all 540 slots zeroed) → `[]`.
   - Single-record box (slot [0,0] populated) → 1 Pkm.
   - Full box (one whole 30-slot box populated) → 30 Pkm.
   - Mixed eggs + Pokémon → only non-eggs returned (defense-in-depth check that egg filter applies).
   - Bad CRC on both partitions → `[]`.
   - Bad CRC on one partition, good on the other → uses the good one.

#### C. Natures lookup module — new file `app/services/soul_link/natures.rb`

1. `module SoulLink::Natures` with a frozen 25-element array of nature names (canonical order from PKHeX `Nature.cs` / pret/pokeplatinum `include/constants/pokemon.h`):
   ```
   %w[Hardy Lonely Brave Adamant Naughty Bold Docile Relaxed Impish Lax
      Timid Hasty Serious Jolly Naive Modest Mild Quiet Bashful Rash
      Calm Gentle Sassy Careful Quirky].freeze
   ```
2. `Natures.name(id)` — returns the name for 0..24, `"Nature ##{id}"` for out-of-range (defensive — Bob shouldn't ever pass out-of-range, but nil-safety matches the rest of the codebase).
3. Citation comment with PKHeX `Nature.cs` reference.

#### D. SaveDiff extension

`app/services/soul_link/save_diff.rb`:

1. Add `BoxedPokemonObservedEvent = Struct.new(:pid, :species_id, :met_location_id, :level, :ot_id, :ot_sid, :is_egg, keyword_init: true)`.
2. Extend `Result` Struct with `:box_events` (default `[]`). Update `Result#empty?` to include it.
3. Extend `between(...)` with `prev_box: nil, curr_box: nil` keyword args. Pipe through `diff_box(prev_box, curr_box)` and assign to `box_events:` in the new `Result`.
4. `self.diff_box(prev_box, curr_box)` mirrors `diff_party` exactly: defensive nil-guard returns `[]`; index both arrays by PID; emit `BoxedPokemonObservedEvent` for PIDs in curr but not prev. Skip nil/zero PID entries (defense-in-depth, same as `diff_party`).
5. **No `BoxedPokemonRemovedEvent`** — boxes hold many Pokémon long-term; "removed from box" is not a meaningful event for a Soul Link tracker (could be a withdraw to party, which the party diff already covers, or a release/trade-out, which we already handle as no-op).
6. Tests in `test/services/soul_link/save_diff_test.rb`: empty box on both sides; new PID in curr_box → 1 event; PID in both → 0 events; PID in prev_box only → 0 events; nil prev_box → `[]`; nil curr_box → `[]`.

#### E. SaveDiffDispatcher wiring

`app/services/soul_link/save_diff_dispatcher.rb`:

1. Read `prev[:box_data]` / `curr[:box_data]` and pass to `SaveDiff.between(...)` as `prev_box:` / `curr_box:`.
2. Fan-out: `SoulLink::CatchCoordinator.process(slot, diff.catch_events + diff.removal_events + diff.box_events)` — combine all three into one call, ordering preserved (catch first, then removal, then box). The coordinator dispatches by event class.
3. Update the `:keys required` doc comment to add `:box_data`.

#### F. CatchCoordinator extension

`app/services/soul_link/catch_coordinator.rb`:

1. Add a `when SoulLink::SaveDiff::BoxedPokemonObservedEvent` branch in the `case event` block. Calls a new `handle_box_observed(slot, session, run, event)` method.
2. `handle_box_observed` mirrors `handle_caught` exactly EXCEPT it sets `caught_off_feed: true` on the create. The PID-dedup `.exists?` check no-ops the create when a party-side row already exists for the same PID.
3. Existing `handle_caught` adds `caught_off_feed: false` to its create call (explicit; column is NOT NULL).
4. Tests in `test/services/soul_link/catch_coordinator_test.rb`:
   - BoxedPokemonObservedEvent for a new PID → row created, `caught_off_feed: true`, `acquired_via: 'catch'`.
   - BoxedPokemonObservedEvent for a PID that already has a party-side row → no-op (existing dedup).
   - Same-snapshot dispatch with PokemonCaughtEvent + BoxedPokemonObservedEvent for the same PID → exactly one row created with `caught_off_feed: false` (party-side wins because it processes first).
   - BoxedPokemonObservedEvent for an event-met-location PID → `acquired_via: 'event_gift'` (precedence preserved).
   - BoxedPokemonObservedEvent for a trade-in PID → `acquired_via: 'trade_in'`.

#### G. ParseSaveDataJob — wire the box parser

`app/jobs/soul_link/parse_save_data_job.rb`:

1. After the existing `PartyParser.parse(...)` line, add a `BoxParser.parse(slot.save_data).map(&:to_h)` call.
2. Persist via `update_columns(parsed_box_data: ...)` — same pattern as `parsed_party_data`.
3. Extend `capture_state(slot)` with `:box_data` (mirrors `:party_data`).
4. **Failure path UNCHANGED.** KG-13 invariant: only stamps `parsed_at` on failure. Don't touch `parsed_box_data` on failure.
5. Test in `test/jobs/soul_link/parse_save_data_job_test.rb`: new test asserting `parsed_box_data` is populated on success and untouched on failure.

#### H. Migrations

1. `db/migrate/<TS>_add_step_18_columns_to_soul_link_pokemon.rb`:
   - `add_column :soul_link_pokemon, :ivs, :json` (nullable — Step-17 rows stay null)
   - `add_column :soul_link_pokemon, :evs, :json` (nullable)
   - `add_column :soul_link_pokemon, :moves, :json` (nullable)
   - `add_column :soul_link_pokemon, :caught_off_feed, :boolean, default: false, null: false`
   - `nature` column ALREADY EXISTS — do NOT re-add. The new code populates it.

2. `db/migrate/<TS+1>_add_parsed_box_data_to_soul_link_emulator_save_slots.rb`:
   - `add_column :soul_link_emulator_save_slots, :parsed_box_data, :json` (nullable)

#### I. CatchCoordinator — populate the new SoulLinkPokemon columns

In `handle_caught` (and by extension `handle_box_observed`):

1. Add to the `SoulLinkPokemon.create!` call: `nature: SoulLink::Natures.name(event.pid % 25)`, `ivs: event.ivs`, `evs: event.evs`, `moves: event.moves`.
2. To carry these through, **extend `SaveDiff::PokemonCaughtEvent` and `BoxedPokemonObservedEvent` Structs with `:nature, :ivs, :evs, :moves` keyword fields**. `SaveDiff.diff_party` and `diff_box` populate from `entry[:nature]` / etc. (same `hash_get` helper).
3. The `Pkm.to_h` call in `ParseSaveDataJob` must include the new fields (Struct's `to_h` does this automatically once the Struct is extended).

#### J. UI — `app/views/dashboard/_pc_box_content.html.erb`

1. Add `OFF-FEED` pill in the existing pill row, alongside 1ST / TRADE-IN / EVENT. Use the same styling primitive (`type-text` with `border-color` / `color` set to a new palette token — pick `--d3` or an existing dim color so it reads as informational, not alarming).
2. Below the existing `box-cell-loc` row, add a collapsible detail block (use `<details><summary>` for zero-Stimulus simplicity — it's read-only data, no UX dynamism needed):
   ```erb
   <% if p.nature.present? || p.ivs.present? || p.evs.present? || p.moves.present? %>
     <details class="box-cell-detail" style="margin-top: 4px; font-size: 9px; color: var(--d2);">
       <summary>STATS</summary>
       <% if p.nature.present? %><div>NATURE: <%= p.nature.upcase %></div><% end %>
       <% if p.ivs.is_a?(Hash) %>
         <div>IVS: <%= [ p.ivs['hp'], p.ivs['atk'], p.ivs['def'], p.ivs['spe'], p.ivs['spa'], p.ivs['spd'] ].compact.join('/') %></div>
       <% end %>
       <% if p.evs.is_a?(Hash) %>
         <div>EVS: <%= [ p.evs['hp'], p.evs['atk'], p.evs['def'], p.evs['spe'], p.evs['spa'], p.evs['spd'] ].compact.join('/') %></div>
       <% end %>
       <% if p.moves.is_a?(Array) %>
         <% p.moves.each_with_index do |m, i| %>
           <div>MOVE <%= i + 1 %>: #<%= m['id'] %> · PP <%= m['pp'] %>/<%= m['pp_up'] %></div>
         <% end %>
       <% end %>
     </details>
   <% end %>
   ```
   (Hash keys via JSON read-back are string-keyed — that's why the snippet uses `'hp'` not `:hp`. Match the same `hash_get`-style accommodation already in `SaveDiff`.)
3. Backward compat for Step-17 rows: when all four fields are nil, the `if` guards collapse the entire `<details>` block — Step-17 rows render exactly as they do today.

#### K. SoulLinkPokemon model

`app/models/soul_link_pokemon.rb`:

1. **No validation changes.** `ivs/evs/moves` columns are nullable JSON; `caught_off_feed` defaults to false at the DB level. The existing species + per-group uniqueness validations remain gated on `soul_link_pokemon_group_id.present?`, so Step-18 rows skip them just like Step-17 rows.
2. **No new scopes required for the controller** (the existing `@auto_detected_catches` controller scope already filters `pid IS NOT NULL` AND `soul_link_pokemon_group_id IS NULL`).

### Constraints (do not violate)

- **Decoder layer never raises.** Every new offset read goes through `byteslice + nil-guard + unpack1` — same boundary-safe pattern as the existing decoder. Top-level `rescue StandardError → nil` stays in place. Box parser likewise: top-level `rescue StandardError → []`.
- **Decoder layer has zero AR / logger / clock side effects.** Test by running the decoder unit tests with `DATABASE_URL` unset — they must pass.
- **Backward-compat the JSON keys.** `parsed_party_data` from Step 17 has no `nature/ivs/evs/moves` keys; the diff-side `hash_get` already returns `nil` for absent keys, and `BoxedPokemonObservedEvent` / `PokemonCaughtEvent` Structs initialize missing keyword args to `nil`. Verify with a test that loads a pre-Step-18 `parsed_party_data` JSON and runs it through `SaveDiff.between` — no exceptions, no spurious events.
- **Failure path stays one-line.** `ParseSaveDataJob` failure branch updates ONLY `parsed_at`. KG-13 invariant.
- **No partner-linking, no Discord notification, no auto-mark-dead, no PC-box UI for storage Pokémon.** Out of scope per audit + brief.
- **Move name lookup is OUT.** Render `Move #N` numerically. Log a Known Gap.

### Files to verify before writing code (WebFetch each)

- `https://raw.githubusercontent.com/kwsch/PKHeX/master/PKHeX.Core/PKM/PK4.cs` — verify Move1/Move2/Move3/Move4 offsets at 0x28/0x2A/0x2C/0x2E; Move1_PP at 0x30; Move1_PPUps at 0x34; EV_HP/ATK/DEF/SPE/SPA/SPD at 0x18..0x1D; IV32 at 0x38.
- `https://raw.githubusercontent.com/kwsch/PKHeX/master/PKHeX.Core/Saves/SAV4Pt.cs` — verify `GeneralSize = 0xCF2C`, `StorageSize = 0x121E4`, the `// Start 0xCF2C, +4 starts box data` comment.
- `https://raw.githubusercontent.com/kwsch/PKHeX/master/PKHeX.Core/Saves/SAV4.cs` — confirm storage-block footer offsets (counter / CRC) match the general-block footer layout.
- pret/pokeplatinum reference for the IV dword bit layout (HP at low 5 bits, ATK at next 5, ..., isEgg at bit 30, isNicknamed at bit 31) — `include/struct_defs/pokemon.h`.

### Acceptance — Reviewer's checklist

1. **Crypto correctness.** New IV/EV/move offsets cited verbatim in code comments from PKHeX `PK4.cs`. No magic numbers without a citation.
2. **Box block offset cited.** `STORAGE_OFFSET_IN_PARTITION = 0xCF2C` and `BOX_DATA_OFFSET_IN_STORAGE = 4` cited from PKHeX `SAV4Pt.cs`. Storage footer layout cited (or, if it differs from general-block, called out explicitly).
3. **Backward-compat.** Step-17 catches render in the auto-catches grid with no STATS expansion and no JS errors. Existing Step-17 tests (`pkm_decoder_test.rb`, `party_parser_test.rb`, `catch_coordinator_test.rb`, `save_diff_test.rb`, `save_diff_dispatcher_test.rb`, `parse_save_data_job_test.rb`) keep passing without modification — extend, don't rewrite.
4. **De-dup correctness.** A test exercises the same-snapshot party+box double-fire scenario and asserts exactly ONE `SoulLinkPokemon` row is created.
5. **Egg filtering at both layers.** PartyParser AND BoxParser filter eggs before return.
6. **Failure path untouched.** `ParseSaveDataJob` failure test asserts `parsed_box_data` is nil after failure (not zeroed, not stale-overwritten).
7. **Test counts.** Expect ~+30..50 new tests. All green. Rubocop clean. Brakeman clean.
8. **Migration.** `nature` column is NOT re-added (already exists). New columns (`ivs`, `evs`, `moves`, `caught_off_feed`, `parsed_box_data`) all migrate cleanly.
9. **UI render.** A Step-17 catch (no IVs/EVs/moves) and a Step-18 catch (full data) both render in the same auto-catches grid, no console errors. The OFF-FEED pill renders only on box-only catches.
10. **No scope creep.** No moves.yml, no pixeldex modal changes, no partner-linking, no Discord notification.

### Build order (suggested)

1. WebFetch the three PKHeX files; pin all offsets in a scratchpad.
2. Migration A (soul_link_pokemon columns) + migration B (save_slots column). Run `bin/rails db:migrate`.
3. `Natures` module + unit test.
4. `PkmDecoder` extension (Pkm Struct + decrypt populates new fields) + unit tests.
5. `BoxParser` + unit tests.
6. `SaveDiff` extension (`BoxedPokemonObservedEvent`, Result `box_events`, `between` keyword args, `diff_box`) + unit tests. **Also** extend `PokemonCaughtEvent` Struct with the new `:nature/:ivs/:evs/:moves` keyword fields.
7. `SaveDiffDispatcher` wiring + unit tests.
8. `CatchCoordinator.handle_box_observed` + unit tests (including the same-snapshot de-dup test).
9. `ParseSaveDataJob` box-parser call + capture_state extension + unit tests.
10. View extension + run a manual render smoke against a fixture.
11. Full test run (`PARALLEL_WORKERS=10 mise exec -- ruby -S bundle exec rails test --seed 300`) → 0 fail / 0 error. Rubocop clean. Brakeman clean.
12. Write `REVIEW-REQUEST.md` with focus areas + delta line counts + open questions.

Flag immediately if any of these block: (a) a PKHeX offset that disagrees with this brief, (b) the storage-block footer differs structurally from the general-block footer, (c) anything that would force a Step-17-side test rewrite.
