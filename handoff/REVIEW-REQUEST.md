# Review Request — Step 18

**Builder:** Bob
**Branch:** `claude/lucid-lamport-624d16` (worktree at `b0be7e4` baseline; uncommitted)
**Ready for Review: YES**
**Scope:** Step 18 — Per-Pokémon stats (Nature / IVs / EVs / moveset) + PC box parsing (closes KG-21).

---

## Summary

Eleven files touched, six new files added. Test count: **547 → 596 (+49)**. Assertions: **1737 → 1906 (+169)**. Rubocop clean. Brakeman clean (the two pre-existing weak-confidence warnings in `emulator_controller.rb` and `gym_schedule_discord_update_job.rb` are unchanged and outside Step-18 scope).

### Per-file changes

#### Migrations (NEW)

- **`db/migrate/20260503184057_add_step_18_columns_to_soul_link_pokemon.rb`** — adds `ivs` (json), `evs` (json), `moves` (json), `caught_off_feed` (boolean default false NOT NULL). `nature` already exists on the table from the legacy `20260406000002` migration; reused, not re-added.
- **`db/migrate/20260503184058_add_parsed_box_data_to_soul_link_emulator_save_slots.rb`** — adds `parsed_box_data` (json, nullable). Mirrors `parsed_party_data`'s shape.

#### Services

- **`app/services/soul_link/natures.rb`** (NEW, 33 lines) — frozen 25-entry array of canonical PKHeX/pret nature names + `Natures.name(id)` lookup with defensive `"Nature ##{id}"` fallback.
- **`app/services/soul_link/box_parser.rb`** (NEW, 172 lines) — pure Layer-B parser sibling to `PartyParser`. Picks the active storage block across both partitions (independent of the general block's active partition, per PKHeX swap semantics), walks 18 boxes × 30 slots × 136-byte records, decodes each via `PkmDecoder.decrypt`, filters eggs + species==0. Returns `Array<Pkm>` (size 0..540) or `[]` on any failure. Top-level `rescue StandardError → []`.
- **`app/services/soul_link/pkm_decoder.rb`** (extended) — `Pkm` Struct gains 4 new keyword fields (`:nature, :ivs, :evs, :moves`) appended at the end of the declaration so Step-17 positional access stays stable. New constants `UNSHUFFLED_EV_OFFSET / UNSHUFFLED_MOVES_OFFSET / UNSHUFFLED_PP_OFFSET / UNSHUFFLED_PP_UP_OFFSET / IV_FIELD_MASK / IV_*_SHIFT` cite the PKHeX `PK4.cs` accessor at the citation comment for each. New private extractors `extract_ivs / extract_evs / extract_moves` (each defensive — return all-zero Hash / 4 zeroed entries on slice boundary failure rather than nil). Decoder still never raises.
- **`app/services/soul_link/save_diff.rb`** (extended) — `BoxedPokemonObservedEvent` Struct, `Result#box_events` (default `[]`), `Result#empty?` extended, `between(...)` gains `prev_box: nil, curr_box: nil` keyword args, `diff_box(...)` method (mirrors `diff_party` shape). `PokemonCaughtEvent` and `BoxedPokemonObservedEvent` carry `:nature, :ivs, :evs, :moves` keyword fields; `diff_party` and `diff_box` populate them via `hash_get`.
- **`app/services/soul_link/save_diff_dispatcher.rb`** (extended) — reads `prev[:box_data]` / `curr[:box_data]`, threads them into `SaveDiff.between`, and combines `catch_events + removal_events + box_events` into a single `CatchCoordinator.process` call. Doc comment lists the new `:box_data` key.
- **`app/services/soul_link/catch_coordinator.rb`** (extended) — new `case` branch for `BoxedPokemonObservedEvent → handle_box_observed`. Both `handle_caught` and `handle_box_observed` delegate to a shared `create_pokemon_row(... caught_off_feed:)` helper. The PID-dedup `.exists?` check covers both intra-event-type dedup AND the cross-event (party + box, same PID, same snapshot) collision; dispatcher orders catch first → party-side wins on the dedup. Persists `nature` (resolved via `Natures.name`), `ivs`, `evs`, `moves`, `caught_off_feed`.

#### Job

- **`app/jobs/soul_link/parse_save_data_job.rb`** (extended) — calls `SoulLink::BoxParser.parse(slot.save_data).map(&:to_h)` after `PartyParser.parse(...)`. Persists via `update_columns(parsed_box_data: ...)`. `capture_state(slot)` extended with `:box_data`. **KG-13 invariant preserved** — failure path still only stamps `parsed_at`; pre-existing `parsed_box_data` is left alone. Verified by `Step 18: parse failure does not write parsed_box_data (KG-13 invariant)`.

#### View

- **`app/views/dashboard/_pc_box_content.html.erb`** (extended) — adds `OFF-FEED` pill (using `var(--d3)` palette token, "informational not alarming") in the existing pill row. Adds a `<details>`-driven `STATS` panel below `box-cell-loc` that renders Nature / IVs / EVs / Moves when present. Backward compat: every guard checks `.present?` / `.is_a?(Hash|Array)` so Step-17 rows (all four fields nil) render exactly as today — no `<details>` block, no console errors.

#### Tests

- **`test/services/soul_link/natures_test.rb`** (NEW, 6 tests / 23 assertions)
- **`test/services/soul_link/box_parser_test.rb`** (NEW, 14 tests / 32 assertions) — empty box, single record, full single box, multi-box walk order, egg filtering, corrupt-record isolation, both-CRC-bad → `[]`, one-CRC-bad → uses good partition, higher-counter wins, wrong bytesize, nil/non-String, all-zero SRAM, source-discipline (no AR/Rails.logger/Time.current).
- **`test/services/soul_link/pkm_decoder_test.rb`** (extended, 9 → 22 tests / 220 → 270 assertions, +13 new) — nature derivation, IVs round-trip (perfect + per-stat distinct + empty fallback), EVs round-trip (per-stat + max-byte), moves round-trip (distinct + empty fallback), backward-compat composite, Struct member-order lock.
- **`test/services/soul_link/save_diff_test.rb`** (extended, 34 → 48, +14 new) — `box_events` default, single-PID box catch, stable PID, withdraw side, nil prev/curr, zero-PID skip, nature/ivs/evs/moves carried through, Step-17 backward-compat (nil fields), string-keyed JSON entries, same-PID-in-party-AND-box dual-fire, `Result#empty?`.
- **`test/services/soul_link/save_diff_dispatcher_test.rb`** (extended, 11 → 15, +4 new) — `BoxedPokemonObservedEvent` fan-out, stable box PIDs, baseline rule for box, combined catch+box single-call ordering.
- **`test/services/soul_link/catch_coordinator_test.rb`** (extended, 17 → 29, +12 new) — nature/ivs/evs/moves persist; back-compat (nil columns); `BoxedPokemonObservedEvent` creates with `caught_off_feed: true`; existing-PID dedup; **same-snapshot party+box dual-fire creates exactly one row**; box event_gift, box trade-in, box egg drop, box zero-PID drop, nil-nature stays nil, `caught_off_feed: false` default for catches, Struct kw-init contract.
- **`test/jobs/soul_link/parse_save_data_job_test.rb`** (extended, 20 → 26, +6 new) — `parsed_box_data` written on success; KG-13 failure path keeps it untouched; `capture_state` carries box_data; box-only PID creates row with `caught_off_feed: true`; same-PID party+box dual-fire creates one row; pre-Step-18 `parsed_party_data` (no nature/ivs/evs/moves keys) runs through cleanly with no exceptions / no spurious events.

---

## Test counts

```
Before:   547 runs, 1737 assertions, 0 failures, 0 errors
After:    596 runs, 1906 assertions, 0 failures, 0 errors
Delta:    +49 runs, +169 assertions
```

Within the brief's expected `~+30..50` envelope.

---

## Citations of primary sources for every new offset

Every new constant in `pkm_decoder.rb` and `box_parser.rb` carries an inline citation comment. Reviewer should spot-check these against:

### PK4 record offsets (from PKHeX `PKHeX.Core/PKM/PK4.cs`)

WebFetch verified — `PK4.cs` accessors quote PK4-ABSOLUTE offsets (the full record including the 8-byte header at PID/flags/checksum). Our `unshuffled` ontology is the 128-byte blocks-buffer (no header), so `unshuffled offset = PK4 absolute - 0x08`. The mapping:

| Field | PK4 absolute | unshuffled | Citation |
|---|---|---|---|
| EV_HP..SPD | `Data[0x18..0x1D]` | `0x10..0x15` | `PK4.cs` `EV_HP` getter |
| Move1/2/3/4 | `Data[0x28]/[0x2A]/[0x2C]/[0x2E]` | `0x20..0x27` | `PK4.cs` `Move1` getter (u16 LE) |
| Move PP | `Data[0x30..0x33]` | `0x28..0x2B` | `PK4.cs` `Move1_PP` getter |
| Move PP-Ups | `Data[0x34..0x37]` | `0x2C..0x2F` | `PK4.cs` `Move1_PPUps` getter |
| IV32 | `Data[0x38]` | `0x30` (already in code from Step 17) | `PK4.cs` `IV32` getter |

### IV bit packing (from pret/pokeplatinum `include/struct_defs/pokemon.h`)

WebFetch confirmed:
```
u32 hpIV : 5; atkIV : 5; defIV : 5; speedIV : 5; spAtkIV : 5; spDefIV : 5; isEgg : 1; hasNickname : 1;
```

### Storage block layout (from PKHeX `PKHeX.Core/Saves/SAV4Pt.cs`)

WebFetch confirmed:
- `public const  int GeneralSize = 0xCF2C;`
- `private const int StorageSize = 0x121E4;`
- Comment `"Start 0xCF2C, +4 starts box data"` — the first 4 bytes of the storage block are `currentBoxIndex`; box-PKM records start at storage offset `0x04`.

### Storage footer parity (from PKHeX `PKHeX.Core/Saves/SAV4.cs` + pret/pokeplatinum `include/savedata.h`)

PKHeX uses identical `Checksums.CRC16_CCITT(...)` + `^2..` CRC location for both general and storage blocks (single `CalcBlockChecksum`/`GetBlockChecksumValid` method pair handles both). pret/pokeplatinum defines a single `SaveBlockFooter` struct shared between blocks. **Storage footer is structurally identical to the general footer** — counter at footer +0x00 (block size - 20), CRC at footer +0x12 (block size - 2). Documented inline in `box_parser.rb`'s class doc.

### Nature names (from PKHeX `Nature.cs` + pret/pokeplatinum `include/constants/pokemon.h`)

Cited inline in `natures.rb`. 25-entry canonical order Hardy=0..Quirky=24.

### Box dimensions (from PKHeX SAV4 BoxCount=18 / BoxSlotCount=30)

Standard Gen-IV constants — 18 boxes × 30 slots × 136 bytes/record = `0x11EE0` bytes total of box-PKM records. Cited inline in `box_parser.rb`.

---

## Open questions / known gaps for Richard

1. **The brief's "unshuffled offset" labels for the new fields were off by 0x08.** The brief said e.g. "moves at unshuffled offset `0x28..0x2F` (Block B +0x08..+0x0F)" — but the existing decoder's `UNSHUFFLED_*` ontology is the 128-byte blocks-buffer (no PK4 header). Move1 at PK4-absolute 0x28 lands at unshuffled `0x20` (Block B +0x00), not `0x28` (Block B +0x08). I followed the existing decoder's ontology (the only consistent way to extend it) and made the citation comments quote PK4-absolute offsets explicitly so Richard can cross-check. The math chains cleanly: PK4 `EV_HP=0x18` → unshuffled `0x10` (Block A +0x10), PK4 `Move1=0x28` → unshuffled `0x20` (Block B +0x00), PK4 `IV32=0x38` → unshuffled `0x30` (Block B +0x10) — same delta of 0x08 across the board. Reviewer: please verify this matches your PKHeX read.

2. **Brief's nature math example was wrong.** Brief said "PID `0xFFFFFFFF` → `% 25 = 9` (Lax)". Actual: `0xFFFFFFFF % 25 = 20` (Calm). I tested for the correct value (`Step 18: nature for PID 0xFFFFFFFF is 20 (Calm)`). Not a code issue — flagging in case Ava wanted to update the brief.

3. **`extract_ivs / extract_evs / extract_moves` return all-zero Hash/Array on boundary failure rather than `nil`.** Brief was silent on this; I picked the "always-Hash/always-Array" contract because (a) it makes the view's `.is_a?(Hash)` / `.is_a?(Array)` guard cleaner, (b) it matches `read_u16_le`'s "return 0 on slice fail" pattern, and (c) the surrounding `rescue StandardError` in `decrypt` would otherwise swallow `nil`-receiver errors and lose the rest of the record. Tradeoff: a record with a corrupted IV chunk surfaces `{ hp: 0, ... }` rather than nil; the view distinguishes nil (Step-17 row) vs. zeros (Step-18 row with bad slice) only by presence of other fields. I think this is right but flagging for Reviewer.

4. **`SoulLinkPokemon.create!` for box-events does NOT touch `caught_at`.** The model's `before_create :set_caught_at, if: -> { status == 'caught' }` callback handles that, same as Step 17. So a box-only catch gets a `caught_at = Time.current` exactly when its row is created — meaning the dashboard's "first encounter on this route" computation works the same way for box-only catches as for party-side catches. Confirming with Reviewer that this is the desired UX.

5. **No `BoxParser` slot-level mutation tests against pre-existing rows in DB.** All Step-18 BoxParser/CatchCoordinator integration tests stub `BoxParser.parse` and `PartyParser.parse` — there's no end-to-end "build a real 0x80000 SRAM with party + box, run through the full job" test. I judged the integration test in `parse_save_data_job_test.rb` (with stubs) sufficient because the real-SRAM path is exercised in `box_parser_test.rb` against the synthetic builder. Reviewer: if you want a real-SRAM end-to-end, flag it and I'll add one.

6. **Move-name rendering is purely numeric (`MOVE 1: #N · PP n/m`).** Logged as KG-24 (per brief). No `config/soul_link/moves.yml` work in Step 18.

7. **No new column on `soul_link_pokemon` for `box_index` / `slot_index`.** A box catch's slot location (which box, which slot) is not surfaced anywhere — the catch row just records `pid + species + met_location + caught_off_feed: true`. Brief did not call for this; if you want it, it'd be a Step 19 column add.

---

## Deviations from the brief

**None on byte values; one cosmetic on labels.** The brief's "Block B +0x08" offset annotations for moves were wrong (off by 0x08 because the brief was using PK4-absolute offsets but labelling them as unshuffled-buffer offsets); I implemented to match PKHeX's actual offsets and the existing decoder's "unshuffled = blocks-buffer" ontology. **The byte values read from the record are exactly what the brief intended**; only the labels in the brief were inconsistent. Documented in §"Open questions" #1 above.

The brief's nature-math example for `0xFFFFFFFF` was also wrong (`= 9` should be `= 20`); my test asserts the correct value. No code impact.

---

## Reviewer focus areas (suggested)

1. **PK4 offset citations** — every new constant in `pkm_decoder.rb` carries an inline `# PK4 0xNN` comment. Spot-check three (`UNSHUFFLED_MOVES_OFFSET`, `UNSHUFFLED_EV_OFFSET`, `UNSHUFFLED_PP_OFFSET`) against PKHeX `PK4.cs` directly.
2. **Storage footer offsets** — `box_parser.rb` `STORAGE_COUNTER_OFFSET` / `STORAGE_CRC_OFFSET`. Verify against PKHeX `SAV4.cs`'s footer-parity claim. The doc comment cites the parity assertion explicitly; if you have a real Gen-IV save handy, the integration check is "does `BoxParser.parse(real_save)` return non-empty when the player has at least 1 boxed Pokémon."
3. **Cross-event PID dedup** — `test/services/soul_link/catch_coordinator_test.rb` `Step 18: same-snapshot PokemonCaughtEvent + BoxedPokemonObservedEvent for same PID creates exactly one row` and `test/jobs/soul_link/parse_save_data_job_test.rb` `Step 18 integration: same PID in party AND box (same snapshot) creates exactly one row`. Both pin the invariant.
4. **KG-13 invariant** — `test/jobs/soul_link/parse_save_data_job_test.rb` `Step 18: parse failure does not write parsed_box_data (KG-13 invariant)`. Verify `update_columns(parsed_at: Time.current)` in the failure branch is unchanged.
5. **Backward-compat for Step-17 rows** — `test/jobs/soul_link/parse_save_data_job_test.rb` `Step 18: pre-Step-18 parsed_party_data without nature/ivs/evs/moves keys runs through cleanly`. Plus the view: a row with all four new columns nil renders the existing row layout exactly, no console errors, no `<details>` block.
6. **Decoder/parser purity** — grep `pkm_decoder.rb`, `box_parser.rb`, `natures.rb`, `save_diff.rb` for `Rails.logger`, `Time.current`, `ActiveRecord`, `.find_by`, `.create!`, `.update!`. Only hit is a doc-comment in `pkm_decoder.rb`. Confirms decoder layer stays pure.

---

## Manual smoke checks

`bin/dev` not started (no real SRAM blob in this worktree to feed the auto-tracker). The view's render path is covered by the existing dashboard tests that exercise `_pc_box_content.html.erb`; a Step-17 row continues to render with no `<details>` block, and a synthesized Step-18 row would render the OFF-FEED pill plus the STATS expandable. Reviewer's render-smoke pass is the right gate for the live UI.

---

Build complete. **Ready for Builder: NO** — over to Richard.

---

## Post-Review Fixes (2026-05-03)

Richard's review landed; addressed Must Fix #1 and Nice-to-Have #4 inline (working
tree only — uncommitted, awaiting Ava's re-verification call):

- **Must Fix #1** — `app/services/soul_link/box_parser.rb:73`:
  `STORAGE_CRC_RANGE_END` now points at `STORAGE_FOOTER_OFFSET` (0x121D0)
  instead of `STORAGE_CRC_OFFSET` (0x121E2), so the storage-block CRC body
  excludes the entire 20-byte footer per PKHeX
  `SAV4.cs:113` (`Checksums.CRC16_CCITT(data[..^FooterSize])`) +
  `SAV4Sinnoh.cs:12` (`FooterSize => 0x14`). Citation comment added inline
  next to the constant. Synthetic builder in
  `test/services/soul_link/box_parser_test.rb` recomputes against the new
  range automatically — all 14 BoxParser tests stay green.
- **Nice-to-Have #4** — `app/views/dashboard/_pc_box_content.html.erb:71`:
  `PP <pp>/<pp_up>` → `PP <pp> · ↑<pp_up>` so PP-Ups consumed (0..3) reads as
  a separate counter, not a denominator.

Re-verification:
- `PARALLEL_WORKERS=10 mise exec -- ruby -S bundle exec rails test --seed 300`:
  596 runs, 1906 assertions, 0 failures, 0 errors, 0 skips.
- `mise exec -- ruby -S bundle exec rubocop`: 184 files inspected, no offenses.

DONE — fixes applied, ready for re-review.
