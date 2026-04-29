# Review Request
*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

Ready for Review: YES

---

## Step 1 — SRAM Phase 1: Trainer Block Parsing

### Files Changed

#### Created

- `app/services/soul_link/save_parser.rb` — pure parsing service. `SoulLink::SaveParser.parse(bytes)` returns a `Result` struct on success, `nil` on any error (never raises).
- `app/jobs/soul_link/parse_save_data_job.rb` — async job. Calls the parser and writes parsed_* columns via `update_columns` (skips the after_update_commit callback to avoid an enqueue loop).
- `app/helpers/emulator_helper.rb` — `format_play_time(seconds)` returns `"Xh Ym"` or `"—"`.
- `db/migrate/20260429215107_add_parsed_save_fields_to_soul_link_emulator_sessions.rb` — adds 6 nullable columns (parsed_trainer_name, parsed_money, parsed_play_seconds, parsed_badges (default 0), parsed_map_id, parsed_at) to `soul_link_emulator_sessions`.
- `test/services/soul_link/save_parser_test.rb` — 18 tests (synthetic SRAM fixtures, slot selection, char decoding, failure paths).
- `test/jobs/soul_link/parse_save_data_job_test.rb` — 8 tests (success, failure, nil/empty save_data short-circuit, idempotency, no-recurse).

#### Modified

- `app/models/soul_link_emulator_session.rb` — added `after_update_commit :enqueue_parse_if_save_changed` callback (line 61) and the corresponding private method (lines 105–109).
- `app/views/emulator/_run_sidebar.html.erb` — added 4 new rendered fields between the save-size block and the seed footer (lines 65–87), gated on column presence.
- `test/models/soul_link_emulator_session_test.rb` — added `include ActiveJob::TestHelper` (line 5–6) and 6 new callback tests at the bottom of the file.
- `test/controllers/emulator_controller_test.rb` — 3 new sidebar-rendering tests after the existing roster tests.

### Key Decisions

- **Slot selection** — implemented per the brief: read the 20-byte general-block footer, verify CRC16-CCITT (poly 0x1021, init 0xFFFF, MSB-first) over the block payload, pick the higher save_counter slot whose CRC verifies, fall back if needed, return nil if both fail.
- **Char table** — English only (space, 0–9, A–Z, a–z, ! ? , . ' " — 64 entries). Unknown indices map to U+FFFD. 0xFFFF terminator stops decoding. 0x0000 padding bytes are skipped (not rendered as replacement chars) so a short trainer name doesn't tail-spam glyphs.
- **`update_columns` in the job** — explicit, with a test (`"job does not enqueue another ParseSaveDataJob on completion"`) that proves the no-recurse contract.
- **`safe_map_id` returns nil on 0** — the map id offset is the least-confidently-documented field; treating 0 as "unknown" lets the sidebar omit it cleanly when (a) the offset is wrong or (b) the player hasn't entered a mapped area yet.
- **Sidebar gating** — Badges line is gated on `parsed_at` (not `parsed_badges`), because parsed_badges has a 0 default — without the gate, the line would always render "0 / 8" even when no save has been parsed yet.

### Open Questions for Architect / Project Owner

1. **Real-save offset verification has NOT happened in this session.** The offsets in `app/services/soul_link/save_parser.rb` come from cross-referencing Project Pokemon docs + pret/pokeplatinum disassembly + (read-only) PKHeX SAV4Pt.cs. The trainer-name / gender / money / badges / play-time offsets within the general block are well-documented and consistent across all three sources. The map-id offset (0x1234) is a placeholder; on real-save data it may decode to something other than the current map. The parser's `safe_map_id` defensive nil-on-zero check means a wrong offset typically produces "no field" rather than "wrong number," but the column should be considered **unverified until first real save lands.**
   - Project Owner: a `.sav` from a brief test session (5–10 min into a randomized Platinum run, after at least one badge if possible) would let us verify all five fields decode to known values. Once we have one, I'll fix any wrong offset and update the comment to "verified against real save on YYYY-MM-DD."
   - If real-save verification is impossible: ship as-is with the sidebar honestly omitting fields that don't decode. The infrastructure is correct; only the offset constants are at risk.

2. **Map-id offset specifically.** If verification reveals the wrong offset, the fix is a single-constant change — `MAP_ID_OFFSET` in the parser. No structural rework needed.

### Source citations

- Project Pokemon save-file structure: https://projectpokemon.org/home/docs/gen-4/save-file-structure-r113/
- Project Pokemon Gen IV character encoding: https://projectpokemon.org/home/docs/gen-4/character-encoding-r68/
- pret/pokeplatinum disassembly: https://github.com/pret/pokeplatinum (`include/savedata.h`, `src/savedata` — referenced for general-block size and footer layout)
- PKHeX `SAV4Pt.cs` / `SAV4DP.cs`: https://github.com/kwsch/PKHeX/blob/master/PKHeX.Core/Saves/SAV4DP.cs — read-only cross-reference for offset constants. **No code copied** (license).

### Test Counts

- Baseline before this step: **221 runs, 0 failures**
- After this step: **255 runs, 0 failures** (+34 new tests)
  - SaveParser: 18
  - ParseSaveDataJob: 8
  - Model callback: 6
  - Controller sidebar: 3 (one per: rendered fields, omitted-when-nil, zero-badges-with-parsed_at)

### Flake Check

- 4 consecutive `bin/rails test` runs, all 255/255 green. (Default parallel workers via `parallelize(workers: :number_of_processors)`.) No flakes observed.

### Lint

- `bundle exec rubocop` clean across all changed Ruby files (8 files, 0 offenses). The `_run_sidebar.html.erb` view is not parseable by rubocop (ERB) and was not lint-checked, but it's pure markup + helper calls; no Ruby logic beyond `<%= %>` tags.

### Definition of Done

- [x] Migration adds 6 columns to `soul_link_emulator_sessions`; `db/schema.rb` reflects it
- [x] `SoulLink::SaveParser.parse(bytes)` returns Result on valid SRAM, nil on any error, never raises (test: `"never raises on adversarial payloads"` exercises 3 garbage payloads)
- [ ] All 5 trainer fields verified against a real Pokemon Platinum save — **NOT DONE this session** (no real save available). Offsets cited from Project Pokemon + pret/pokeplatinum + PKHeX. See Open Question #1.
- [x] `SoulLink::ParseSaveDataJob` updates parsed_* columns via `update_columns`, sets `parsed_at` on both success and failure paths
- [x] Model `after_update_commit` enqueues the job ONLY when save_data changed and is non-nil (covered by 6 model tests)
- [x] Sidebar renders new fields when present, gracefully degrades to "—" or skip when nil
- [x] Service tests cover success + failure paths with synthetic SRAM (no real ROM data in CI)
- [x] Job tests cover both branches (success → real attrs, failure → nil attrs)
- [x] Model test covers callback enqueue / no-enqueue cases
- [x] Full suite passes: 221 baseline + 34 new = 255 tests, 0 failures
- [x] 4 consecutive parallel runs without flakes

### Known Gaps (deferred, NOT in scope of this step)

- **Phase 2** — map-id → map-name lookup (config/soul_link/maps.yml or similar) so the sidebar can show "Eterna City" instead of `426`
- **Phase 3** — multi-language char tables (Japanese, Korean, etc.); current parser is English-only and unknown indices fall back to U+FFFD
- **Phase 4** — Pokemon party data (encrypted/PRNG-scrambled blocks A–D, requires Pokemon-internal descrambling)
- **Phase 5** — PC boxes (same scrambling as party + box-level layout)
- **Real-save offset verification** — see Open Question #1
- **Live-update sidebar** — currently page-load refresh only; could broadcast on save_data PATCH if "X just saved" UX is desired (already in BUILD-LOG Known Gaps)
