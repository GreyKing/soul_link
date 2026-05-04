# Session Checkpoint
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*
*Session-scoped — archived to `handoff/archive/` at session end.*

---

## Where We Stopped

Step 18 (Per-Pokémon stats — Nature/IVs/EVs/moves — and PC box parsing) shipped at `132fb34`, FF-merged to `origin/main` and pushed. Worktree branch `claude/lucid-lamport-624d16` also pushed. Awaiting next brief from Project Owner.

---

## What Was Built

**Step 18 — Per-Pokémon stats + PC box parsing.**

Extends Step 17's `PkmDecoder` + `PartyParser` foundation with the four per-Pokémon detail fields the Soul Link UX needs and adds a sibling `BoxParser` so catches that arrive via box-only diff (caught + deposited between snapshots) surface alongside party catches. Decryption algorithm unchanged — only new field offsets within the existing 128-byte unshuffled payload, plus a new walker over the storage block.

**Surfaces introduced:**
- `SoulLink::PkmDecoder` (extended) — `Pkm` Struct gains `nature` (Integer 0..24, `pid % 25`), `ivs` (Hash with `:hp/:atk/:def/:spe/:spa/:spd`, 0..31 each, unpacked from IV dword's low 30 bits), `evs` (Hash same keys, 0..255 each, 6 bytes at unshuffled 0x10..0x15), `moves` (Array of 4 `{id:, pp:, pp_up:}` Hashes from unshuffled 0x20..0x2F). Eager-decoded — lazy was rejected as needless state. New fields appended at the end of the Struct so Step-17 positional-access callers stay stable.
- `SoulLink::BoxParser` (`app/services/soul_link/box_parser.rb`) — sibling to `PartyParser`, pure function, never raises, returns `Array<Pkm>` (size 0..540) or `[]`. Storage block at partition offset `0xCF2C` size `0x121E4`, box data at `+4`. Independent active-block picker per partition (storage and general blocks can swap partitions independently per PKHeX `StorageBlockPosition`). CRC body excludes the 20-byte footer (PKHeX `SAV4.cs:113` + `SAV4Sinnoh.cs:12` `FooterSize => 0x14`).
- `SoulLink::Natures` (`app/services/soul_link/natures.rb`) — 25-element frozen array of nature names + `name(id)` lookup with `"Nature ##{id}"` fallback. Cites PKHeX `Nature.cs` + pret enum order.
- `SoulLink::SaveDiff` extension — `BoxedPokemonObservedEvent` Struct, `box_events:` keyword field on `Result`, `prev_box:` / `curr_box:` keyword args on `between(...)`, `diff_box(prev, curr)` mirroring `diff_party` shape. `PokemonCaughtEvent` Struct extended with `:nature, :ivs, :evs, :moves` keyword fields populated from the entry hash.
- `SoulLink::SaveDiffDispatcher` — passes `prev[:box_data]` / `curr[:box_data]` through; combined fan-out: `CatchCoordinator.process(slot, catch + removal + box events)`.
- `SoulLink::CatchCoordinator` — new `when BoxedPokemonObservedEvent` branch dispatches to `handle_box_observed`, mirrors `handle_caught` exactly except sets `caught_off_feed: true` on the create. PID dedup `.exists?` covers cross-event collision — single transaction, party events processed first.
- `ParseSaveDataJob` — calls `BoxParser.parse(slot.save_data).map(&:to_h)` on success; persists via `update_columns(parsed_box_data: ...)`. Failure path UNCHANGED (KG-13 invariant: only stamps `parsed_at`); test stubs `BoxParser.parse` to flunk if called on failure path.
- `_pc_box_content.html.erb` — new OFF-FEED pill alongside 1ST / TRADE-IN / EVENT (renders only when `caught_off_feed: true`). Below the location row, a `<details><summary>STATS</summary>` collapsible block shows Nature / IVs / EVs / Moves for Step-18 catches. Step-17 catches (all-nil for the new fields) collapse the entire `<details>` block — render unchanged.

**Counts:** 547 → 596 tests (+49). 1737 → 1906 assertions, 0 failures, 0 errors. Rubocop clean (178 → 184 files, 0 offenses). Brakeman clean. 2 migrations.

**Review:** 1 Must Fix (storage CRC range covered only the 2-byte CRC field instead of the full 20-byte footer — would have silently failed every real Platinum save; fixed inline by pointing `STORAGE_CRC_RANGE_END` at the existing `STORAGE_FOOTER_OFFSET` constant + citation comment). 1 Nice-to-Have (PP rendering label `PP X · ↑Y` to disambiguate from a denominator; fixed inline). 2 Should Fixes accepted as-is — no real-SRAM smoke test (synthetic builder uses the same constants the production code does; logged as KG-25), and `caught_off_feed: false` for Step-17 rows (correct semantic — they were party-side detections by definition).

---

## What Was Decided This Session

- **Eager-decode the new Pkm fields, not lazy.** Brief floated lazy decryption; rejected. Decrypt cost is fixed-per-record, structs are small, eager is simpler and matches the existing Pkm shape.
- **`Pkm` Struct extended in place.** New keyword fields appended at the end so Step-17 positional-access callers stay stable. Member-name assertion in tests locks the order.
- **`BoxParser` is a sibling to `PartyParser`, not a refactor.** Same pure-function shape; reuses `PkmDecoder.decrypt` per-record (decoder already accepts the 136-byte box record size; box-only records have `level: nil`).
- **Storage block has its own active-block picker.** Per PKHeX `StorageBlockPosition`, storage and general blocks can swap partitions independently. Picker reads each partition's storage footer, CRC-validates each, picks higher save_counter. Does NOT delegate to or assume parity with the general block's picker.
- **CRC body excludes the entire footer, not just the CRC field.** PKHeX `SAV4.cs:113` `data[..^FooterSize]` + `SAV4Sinnoh.cs:12` `FooterSize => 0x14`. The Step-18 build initially used `STORAGE_SIZE - 2` (CRC field only); review caught the bug; fixed to `STORAGE_FOOTER_OFFSET = STORAGE_SIZE - 0x14` with citation comment. Same lesson `SaveParser` learned for the general block.
- **`BoxedPokemonObservedEvent` is a distinct event class, not a subtype of `PokemonCaughtEvent`.** Distinction surfaces via `caught_off_feed: true` + the OFF-FEED pill. **No `BoxedPokemonRemovedEvent`** — boxes hold Pokémon long-term; not a meaningful Soul Link signal.
- **Cross-event PID dedup: party first, box second, single transaction.** Locked by a same-snapshot dual-fire test that asserts exactly one row created with `caught_off_feed: false`.
- **Move-name lookup is OUT.** Numeric "Move #N" fallback. Logged as KG-24, adjacent to KG-20.
- **Brief had a typo: moves are in Block B, not Block C.** Corrected against PKHeX `PK4.cs` `Move1` accessor at PK4-absolute 0x28 (unshuffled 0x20 = Block B +0x00). Bob shipped Block B per PKHeX, correctly.
- **`caught_off_feed: false` is the correct semantic for Step-17 rows.** They WERE detected via the party diff path; the column just makes the provenance explicit going forward.

---

## Known Gaps / Future Work

*See `handoff/BUILD-LOG.md` Known Gaps — running list maintained there.*

Step 18 closed KG-21 (PC box parsing). Logged two new gaps:
- **KG-24** — No Move ID → Move name lookup. STATS expander renders `MOVE n: #N · PP n · ↑n`. Adding `config/soul_link/moves.yml` with all ~467 Gen IV moves (sourced from PKHeX `text_moves_en.txt`) would lift this to readable names. Adjacent to KG-20 (species lookup).
- **KG-25** — No real-SRAM smoke test for `BoxParser` and extended `PkmDecoder` field reads. All Step-18 tests use synthetic SRAM/PKM builders that recompute CRCs and LCG-encrypt payloads using the same constants the production code does. A regression of the storage-CRC fix would only be caught by running `BoxParser.parse` against a known-good Platinum dump. Same shape as Step 16/17's open audit task.

KG-7 (real-save offset verification for `MAP_ID_OFFSET`) still open from Step 12. KG-20 (species ID fallback), KG-22 (no Discord notification on auto-catch), KG-23 (no UI for "this auto-catch is wrong") still open from Step 17.

In-browser smoke deferred this step — same pattern as Steps 15/16/17 (parse-job + service code + view extension; existing `SoulLinkPokemon` `broadcasts_refreshes_to` covers the new section's real-time path).

---

## Resume Prompt

Copy and paste this to resume:

---

You are Ava (Architect) on Soul Link — Three Man Team.
Read handoff/SESSION-CHECKPOINT.md, then handoff/BUILD-LOG.md.
Confirm status and next action. Then wait for direction.

---
