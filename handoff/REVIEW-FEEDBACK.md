# Review Feedback — Step 1 (SRAM Phase 1)
Date: 2026-04-29
Ready for Builder: YES

---

## Must Fix

*None.*

The code does what the brief asks. Failure paths are honest, the
no-recurse guarantee is enforced and tested, and the parser declines
to crash on adversarial input. Bob's open question on real-save
verification is for Arch and the Project Owner; it is not a code
defect.

---

## Should Fix

- `app/jobs/soul_link/parse_save_data_job.rb:39` — failure path writes
  `parsed_badges: 0` (column is `null: false, default: 0`), so the
  view's badge gate (`if s.parsed_at`) renders `Badges: 0 / 8` after a
  parse failure rather than the "—" the brief's :failed-path text
  describes. Bob's UX call is defensible (0/8 reads as "no badges"
  rather than as a parse error), and it follows directly from the
  schema decision Arch already made (badges is non-nullable). Flag
  for Arch awareness only — no code change required unless Arch
  wants the badges line gated more strictly (e.g.,
  `s.parsed_at && s.parsed_trainer_name.present?`).

- `handoff/REVIEW-REQUEST.md:57` — Bob writes "ParseSaveDataJob: 8"
  in the breakdown; the job test file actually contains 7 `test "..."`
  blocks. Total is still 34 (18 parser + 7 job + 6 callback + 3
  controller), and the suite reports 255 runs / 0 failures, so the
  baseline (221) + 34 = 255 arithmetic still holds. Just the line
  item is off by one — not a code issue, but the report should be
  corrected for the audit trail.

- `test/models/soul_link_emulator_session_test.rb:220, 258` — four
  pre-existing rubocop "Use space inside array brackets" offenses
  inside the `delete_rom_file` tests. **Not introduced by this step**
  (the lines were already there before Bob touched the file). Bob's
  added content is clean. If Arch wants the file fully clean post-
  step, autocorrect can fix all four with `rubocop -a` in under a
  minute. Otherwise leave for a separate cleanup.

---

## Escalate to Architect

1. **Real-save offset verification is outstanding.** Bob's open
   question is honest and well-scoped. The trainer-name / gender /
   money / badges / play-time offsets in `SoulLink::SaveParser` are
   cited from Project Pokemon docs, the pret/pokeplatinum disassembly,
   and a read-only reference to PKHeX SAV4Pt.cs. I tried to spot-check
   the public Project Pokemon save-structure / character-encoding URLs
   today; both URLs in the source citations now resolve to unrelated
   pages on the same domain (forum reorganisation, presumably) — I
   could not independently verify Bob's character-table indices or
   block offsets from the cited documents. That is what Bob asked Arch
   to decide: ship-as-is with a "—" sidebar on real saves that don't
   parse, or block on a real `.sav` from the Project Owner. Bob's DoD
   correctly flags the verification box as **NOT DONE**.

2. **`MAP_ID_OFFSET = 0x1234` is a placeholder.** Bob is up-front
   about it; `safe_map_id` returns nil on zero so the sidebar will
   simply omit the field rather than show garbage. If Arch is
   comfortable shipping a column that will likely be nil for the
   foreseeable future, this is fine — the cost of being wrong is
   zero rendered output, not corrupted data.

---

## Cleared

Reviewed:

- `app/services/soul_link/save_parser.rb`
  - `parse(bytes)` is hermetic: returns nil for non-String, wrong
    size, empty, garbage. The outer `rescue StandardError => nil`
    catches anything that slips past the structural guards. The
    "never raises on adversarial payloads" test exercises three
    distinct 0x80000-byte payloads (0xFF / 0x00 / 0xAA), which is
    real coverage of the contract.
  - `active_slot` reads both slots, computes CRC16-CCITT (poly
    0x1021, init 0xFFFF, MSB-first, no xorout — verified line-by-line
    in `crc16_ccitt`), and returns the higher save_counter slot whose
    CRC verifies. Falls back to the other slot if the higher one is
    corrupt; returns nil when both fail. The truth-table dispatch on
    `[a_ok, b_ok]` covers all four cases explicitly. Tested by
    "picks higher save_counter slot when both are valid", "falls back
    to the other slot when higher-counter slot has bad CRC", and
    "returns nil when both slots have invalid CRC".
  - Char decoding: 64 entries (space + 0–9 + A–Z + a–z + 6 punctuation),
    English-only as locked. 0xFFFF terminates, 0x0000 skips (no tail
    spam), unknown indices emit U+FFFD. The "Lyra" happy-path test
    decodes to the exact bytes "Lyra" with no padding leakage; the
    unknown-index test produces "A\u{FFFD}B" exactly.

- `app/jobs/soul_link/parse_save_data_job.rb`
  - Uses `update_columns` (NOT `update!`) — verified against the
    "job does not enqueue another ParseSaveDataJob on completion"
    test, which is a real `assert_no_enqueued_jobs` block, not
    theatrical.
  - Sets `parsed_at: Time.current` on **both** success and failure
    paths. The failure path writes nils for nullable columns and 0
    for `parsed_badges` (the column is non-nullable per Arch's
    Option-A schema choice). Idempotency tested by running the job
    twice with a stubbed parser and asserting the resulting
    `parsed_*` slice is byte-equal between runs.
  - Defensive guards: `return if session.nil?` and `return if
    session.save_data.blank?` short-circuit cleanly. Both have
    explicit no-op tests.

- `app/models/soul_link_emulator_session.rb`
  - `after_update_commit :enqueue_parse_if_save_changed` only fires
    when `saved_change_to_attribute?("save_data")` is true AND
    `save_data` is non-blank. The 6 callback tests cover: enqueue on
    save_data change, enqueue on save_data → different value,
    no-enqueue on status / rom_path / discord_user_id updates,
    no-enqueue on save_data → nil, no-enqueue on save_data → empty
    string, and no-enqueue when the parsed_* fields are written via
    `update_columns` (the job's path).

- `app/views/emulator/_run_sidebar.html.erb`
  - Trainer name, time played, money are gated on the per-field
    column being present. Badges line is gated on `parsed_at` (not
    `parsed_badges`) — Bob's note in REVIEW-REQUEST is correct: with
    `default: 0`, gating on `parsed_badges` would render "0 / 8"
    forever. Confirmed by the controller test
    "show roster omits parsed_* lines when fields are nil" which
    asserts `assert_no_match(/Badges:/, response.body)`.
  - Existing fields (player name, status, last activity, save size,
    seed footer) render in the same order as before; new fields slot
    between save-size and seed.

- `app/helpers/emulator_helper.rb`
  - `format_play_time(nil)` returns "—". `format_play_time(0)`
    returns "0h 0m". Negative seconds are clamped to 0. Single-helper
    file, no overreach.

- `db/migrate/20260429215107_add_parsed_save_fields_to_soul_link_emulator_sessions.rb`
  - Six columns: `parsed_trainer_name` (string, limit 16),
    `parsed_money` (integer, limit 4), `parsed_play_seconds`
    (integer, limit 4), `parsed_badges` (integer, limit 1, default 0,
    null: false), `parsed_map_id` (integer, limit 2), `parsed_at`
    (datetime). Matches the brief shape exactly.
  - `db/schema.rb` reflects the migration (lines 126–131).

- **Test counts:** 18 parser + 7 job + 6 callback + 3 controller = 34
  new tests. Suite total 255 runs / 767 assertions / 0 failures /
  0 errors. I re-ran the suite twice locally on top of Bob's 4 — both
  green, no flakes observed.

- **No scope creep:** No party / PC box decryption, no Japanese or
  multi-language tables, no Phase 2 map-id → name lookup, no
  EmulatorController#show changes, no new gems. Confirmed via
  `git diff --stat HEAD` and a Gemfile scan.

- **Source citation honesty:** Bob cites three sources (Project
  Pokemon, pret/pokeplatinum, PKHeX SAV4Pt.cs) and is explicit that
  no PKHeX code was copied (license). The DoD checklist correctly
  marks the real-save verification box as NOT DONE. Open Question #1
  in REVIEW-REQUEST frames the offset risk honestly.

---

VERDICT: PASS_WITH_OBSERVATIONS

(The two observations above — the failure-path badges-as-0 UX nit and
the off-by-one job test count in the report — are notes for Arch, not
blockers. The real-save verification gap is escalated to Arch as
flagged in REVIEW-REQUEST. Step 1 is clear for the next move.)
