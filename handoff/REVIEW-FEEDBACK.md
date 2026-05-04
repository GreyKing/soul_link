# Review Feedback — Step 18
Date: 2026-05-03
Ready for Builder: NO

## Verdict

**Step 18 needs fixes before ship.** One Must Fix on the storage-block CRC
range; the rest is solid work. Citations are honest, pure-function discipline
holds across the new layers, dedup logic is correct, KG-13 invariant is
preserved, and view backward-compat checks every field. The Must Fix is a
single constant change plus its test mirror; once that lands the step ships.

---

## Must Fix

### 1. `BoxParser::STORAGE_CRC_RANGE_END` covers the wrong byte range — CRC will fail on every real save

- **File:** `app/services/soul_link/box_parser.rb:73`
- **What is wrong:**
  - Bob set `STORAGE_CRC_RANGE_END = STORAGE_CRC_OFFSET = STORAGE_SIZE - 2 = 0x121E2`.
  - PKHeX `SAV4.cs:113` declares
    `private ushort CalcBlockChecksum(ReadOnlySpan<byte> data) => Checksums.CRC16_CCITT(data[..^FooterSize]);`
    and `SAV4Sinnoh.cs:12` overrides `protected override int FooterSize => 0x14;`
    — so the CRC range is `[0, length - 0x14)`, NOT `[0, length - 2)`.
  - For storage that is `[0, 0x121E4 - 0x14) = [0, 0x121D0)`, i.e. up to and
    not including the **footer start**, not up to the **CRC field** start.
    There are 18 bytes (the rest of the footer: counter / blockCounter / size /
    signature / blockID / reserved) that PKHeX explicitly EXCLUDES from the
    CRC-protected body. Bob's range INCLUDES them.
  - This is the same lesson `SaveParser` learned the hard way for the general
    block — see `save_parser.rb:46-49`:
    *"`0..0xCF18 init=0xFFFF MSB poly=0x1021` produced the matching stored CRC
    of `0x6C3C`; `0..0xCF2A` produced `0x533D` (off)."* Bob picked the form
    SaveParser empirically proved wrong.
  - The footer doc comment in `box_parser.rb:42-47` correctly states
    "Counter is at footer +0 (block size - 20), CRC at footer +0x12 (block
    size - 2)" — Bob knew the footer was 20 bytes. The constant just doesn't
    match the comment.
- **Why this matters:** every real Platinum save will fail
  `storage_block_valid?`, `pick_active_storage_block` returns nil for both
  partitions, and `BoxParser.parse` returns `[]`. The whole PC-box
  auto-tracking feature silently no-ops in production. Tests don't catch this
  because the synthetic builder in `box_parser_test.rb:105` mirrors the same
  wrong constant, so the CRC matches itself.
- **How to fix:**
  - In `box_parser.rb:73`, change
    `STORAGE_CRC_RANGE_END = STORAGE_CRC_OFFSET` (0x121E2)
    to
    `STORAGE_CRC_RANGE_END = STORAGE_FOOTER_OFFSET` (0x121D0).
  - The constants `STORAGE_FOOTER_OFFSET = STORAGE_SIZE - STORAGE_FOOTER_SIZE`
    are already declared on lines 69-70 — no new constant needed.
  - In `test/services/soul_link/box_parser_test.rb:105`: the synthetic builder
    will recompute the body via the new constant value automatically — verify
    all 14 BoxParser tests still pass after the constant change.
  - Add a citation comment near the new constant referencing
    `PKHeX SAV4.cs:113` (`Checksums.CRC16_CCITT(data[..^FooterSize])`) +
    `SAV4Sinnoh.cs:12` (`FooterSize => 0x14`) so the next reader sees why
    "block size - 20" not "block size - 2".

---

## Should Fix

### 2. No real-SRAM smoke test will catch a regression of Must Fix #1

- **File:** `test/services/soul_link/box_parser_test.rb` (whole file)
- **What is wrong:** The test suite uses a synthetic SRAM builder that
  recomputes the CRC using the same `STORAGE_CRC_RANGE_END` constant the
  production code uses. Tests stay green even with a typo in the CRC range —
  and in fact did, until I cross-checked PKHeX directly. Once the Must Fix
  lands, the only assurance that the storage block CRC matches a *real*
  Platinum save is the parity argument with `SaveParser`. That's strong but
  not proven.
- **Recommendation:** This was Bob's open question #5 (no real-SRAM
  end-to-end). Either:
  - (a) Punt — log as a follow-up audit task ("verify `BoxParser.parse`
    returns non-empty against a known-good Platinum dump with ≥1 boxed mon"),
    and run that audit manually before the next deploy. This is what Step 16 /
    17 did.
  - (b) Drop a real-save fixture into `test/fixtures/files/` (compressed if
    necessary) and wire one integration test through `BoxParser.parse`.
    Heavier but durable.
  - I lean toward (a) given the brief said "no real-SRAM blob in this
    worktree". If Ava agrees, capture the audit task in BUILD-LOG so it
    doesn't slip.

### 3. Migration backfill semantics for `caught_off_feed` should be acknowledged

- **File:** `db/migrate/20260503184057_add_step_18_columns_to_soul_link_pokemon.rb:29`
- **What is wrong:** The migration adds `caught_off_feed` with
  `default: false, null: false`. Existing Step-17 rows (which were detected
  via the party diff path, so `caught_off_feed: false` is technically the
  correct semantic) will all read as `false` and never display the OFF-FEED
  pill. That is the correct behavior for those rows.
- **Recommendation:** No code change. Confirm with Ava that the brief
  intended Step-17 rows to never show OFF-FEED (because they are by definition
  party-side detections). I read the brief that way; flagging only because
  it's a one-way data state that can't be cleanly distinguished from
  "actually came from the party diff" later.

---

## Nice-to-Have

### 4. `MOVE n: #N · PP n/m` is misleading without a label

- **File:** `app/views/dashboard/_pc_box_content.html.erb:71`
- **What:** The view renders `PP <%= m["pp"] %>/<%= m["pp_up"] %>`. `pp_up`
  is the count of PP-Ups consumed (0..3), not the move's max PP. A user
  reading "PP 35/0" will read it as "35 of 0", which is nonsensical.
- **Recommendation:** Either label it (e.g.
  `PP <%= m["pp"] %> · ↑<%= m["pp_up"] %>`) or drop the PP-up count from v1
  (Bob already logged move-name lookup as KG-24; this could ride along with
  that). Strictly cosmetic — the data is correct, just visually ambiguous.
  Bob can take it inline or punt.

### 5. Doc-only — brief had an offset label and a nature math error

- Bob flagged both in REVIEW-REQUEST.md §"Open questions / known gaps" #1 and
  #2. Neither is a code issue; both are corrections to the upstream brief Ava
  authored. Acknowledged — Ava should update the brief so the next reviewer
  doesn't re-derive what Bob already proved (PK4-absolute vs unshuffled-buffer
  ontology delta of 0x08; `0xFFFFFFFF % 25 = 20` not 9). The shipped code is
  correct against PKHeX.

### 6. `extract_ivs` / `extract_evs` / `extract_moves` zeros-vs-nil tradeoff

- Bob's open question #3. The contract he picked — "always return a
  Hash/Array, fall back to zeros on slice failure" — is defensible (cleaner
  view guards, matches `read_u16_le`'s "return 0 on slice fail" pattern). The
  view's `.present?` / `.is_a?(Hash)` guards collapse cleanly for both nil
  (Step-17 row) and all-zeros (Step-18 row with bad slice). Bob's call, no
  fix needed.

---

## Escalate to Architect

None. The Must Fix is a code-level correctness issue I can spec without a
product call.

---

## What I verified (passes)

- **PK4 offset citations** (focus area 1): every new `UNSHUFFLED_*_OFFSET`
  constant in `pkm_decoder.rb:124-127` cites the correct PK4-absolute offset
  from `PK4.cs`. Cross-checked: `EV_HP @ PK4 0x18 → unshuffled 0x10`,
  `Move1 @ PK4 0x28 → unshuffled 0x20 (Block B +0x00)`, `Move1_PP @ PK4 0x30
  → unshuffled 0x28`, `Move1_PPUps @ PK4 0x34 → unshuffled 0x2C`,
  `IV32 @ PK4 0x38 → unshuffled 0x30`. All consistent — delta of 0x08 from
  PK4-absolute, matching the existing Step-17 ontology. Bob's deviation from
  the brief's labels is the right call.
- **Block B for moves** (focus area 1, follow-up): brief said Block C, Bob
  shipped Block B (correctly). PKHeX `PK4.cs` confirms moves are at
  `Data[0x28..0x37]` which is Block B (PK4 absolute 0x28..0x47 covers the
  entire Block B range).
- **IV bit packing** (focus area 1): `pret/pokeplatinum struct_defs/pokemon.h`
  order is `hpIV / atkIV / defIV / speedIV / spAtkIV / spDefIV` — Bob's
  shifts (HP=0, ATK=5, DEF=10, SPE=15, SPA=20, SPD=25) match exactly.
- **Active storage partition pick** (focus area 2):
  `pick_active_storage_block` in `box_parser.rb:119-138` reads each partition's
  storage block independently, CRCs each, and picks higher save_counter among
  valid candidates. Does NOT reuse `PartyParser`/`SaveParser`'s general-block
  selection — independent swap behavior preserved.
- **Storage footer offsets** (focus area 2): `STORAGE_FOOTER_OFFSET = 0x121D0`
  and `STORAGE_CRC_OFFSET = 0x121E2` are correct (counter at footer +0, CRC
  at footer +0x12 = block_size - 2). Only the CRC RANGE is wrong (Must Fix
  #1).
- **Cross-event PID dedup** (focus area 3):
  `catch_coordinator_test.rb:251-266` exercises the same-snapshot dual-fire
  by passing both events in a single `process` call (single transaction). The
  `.exists?` check on `catch_coordinator.rb:107-109` catches the second event
  because the party-side row was inserted earlier in the same transaction
  (same DB connection → INSERT visible to subsequent SELECT). Test asserts
  `count == 1` AND `caught_off_feed == false` (party-side wins). Dispatcher
  orders catch_events first at `save_diff_dispatcher.rb:55`.
- **KG-13 invariant** (focus area 5): `parse_save_data_job_test.rb:601-613`
  writes a pre-existing `parsed_box_data: [{"pid" => 0x9999}]`, sets
  `parsed_at`, runs parse with `SaveParser.stub(:parse, nil)`, and asserts
  `parsed_box_data == [{"pid" => 0x9999}]` after the failure path. Job's
  failure branch at `parse_save_data_job.rb:76` only stamps `parsed_at`. Test
  also stubs BoxParser to flunk if called, asserting it never runs on the
  failure path.
- **Egg filtering at both layers** (focus area 6): `box_parser.rb:100`
  filters `pkm.is_egg`. PartyParser already filters eggs (Step 17).
- **Pure-function contract** (focus area 7): grep across `box_parser.rb`,
  `natures.rb`, `pkm_decoder.rb`, `save_diff.rb` for `Rails.logger`,
  `Time.current`, `ActiveRecord`, `.find_by`, `.create!`, `.update!` — zero
  matches. Top-level `rescue StandardError → []` (BoxParser line 107) and
  `→ nil` (PkmDecoder line 290) in place.
- **Citations** (focus area 8): spot-checked
  - `pkm_decoder.rb:113-127` cites PKHeX `PK4.cs` offsets verbatim ✓
  - `box_parser.rb:21-22` cites SAV4Pt
    `GeneralSize = 0xCF2C / StorageSize = 0x121E4 / "Start 0xCF2C, +4 starts box data"` verbatim ✓
  - `natures.rb:11-15` cites PKHeX `Nature.cs` + pret `enum Nature` order
    verbatim ✓
  - `box_parser.rb:43-47` cites `SaveBlockFooter` parity — but the constant
    derived from this citation doesn't match the citation (Must Fix #1).
- **Backward-compat for Step-17 rows** (focus area 4):
  - View at `_pc_box_content.html.erb:58` guards every Step-18 field with
    `.present?` — all-nil rows render no `<details>` block.
  - `SaveDiff.between` accepts `prev_box: nil, curr_box: nil` and `diff_box`
    short-circuits to `[]` on nil.
  - Step-17 tests in `pkm_decoder_test.rb` (lines 158-281),
    `party_parser_test.rb` (all 10 tests), `save_diff_test.rb` (Step 17
    section), and `catch_coordinator_test.rb` (Step 17 section) are all
    UNCHANGED — Bob extended each test file with new Step-18 tests appended,
    no rewrites.
  - `parse_save_data_job_test.rb:721-751` ("pre-Step-18 parsed_party_data
    without nature/ivs/evs/moves keys runs through cleanly") explicitly
    exercises the legacy-row path with string-keyed JSON missing the new
    fields — runs without exception, no spurious events.
- **Test coverage of failure modes** (focus area 10): `box_parser_test.rb`
  covers: empty box (line 135), single record (140), full box of 30 (159),
  multi-box walk (170), egg filtering (183), corrupt-record isolation (195),
  both-CRC-bad → `[]` (208), one-CRC-bad → use good (217), higher-counter
  wins (229), wrong bytesize (241), nil/non-String (245), all-zero SRAM
  (252), source discipline (256). 13 distinct failure modes covered.
- **Nature lookup**: PID `0xFFFFFFFF % 25 = 20 = Calm`. Bob's test asserts
  this exactly. The 25-entry `NAMES` array order matches PKHeX `Nature.cs`
  Hardy=0..Quirky=24.
- **`Pkm` Struct field order**: `nature/ivs/evs/moves` appended at the end of
  the declaration so Step-17 positional-access callers stay stable.
  `pkm_decoder_test.rb:446` locks the declaration order with an explicit
  member-name assertion.
- **Anti-scope drift check**: no `config/soul_link/moves.yml` shipped. No
  Discord notification for box-only catches. No held items / abilities /
  friendship / contest stats / ribbons / partner-linking. No `box_index` /
  `slot_index` columns. Bob stayed inside the brief's box.

---

DONE — REVIEW-FEEDBACK.md ready for Ava
