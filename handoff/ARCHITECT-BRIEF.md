# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 1 — SRAM Phase 1: Trainer Block Parsing

Context: emulator + roster sidebar are shipping. Tier 1 sidebar (model metadata) was deferred from showing in-game info because that requires parsing the SRAM blob — the opaque 512KB binary save file. This step implements **Phase 1 only**: the trainer block, which is plaintext (no encryption). Future phases (party data, PC boxes) require Pokemon's PRNG/XOR descrambling and are deferred.

**Phase 1 scope (THIS step):** parse trainer block, surface fields in the sidebar.
**NOT in scope:** Pokemon party data, PC boxes, character set quirks beyond ASCII letters/digits, multi-language support.

After this step, the sidebar will show: in-game character name, time played, money, badges count, current map ID. (Map name lookup is Phase 2.)

### Project Owner decisions (locked)

- **Phase 1 only first**, evaluate before Phase 2+.
- **Schema columns** (Option A) for caching, NOT on-demand parsing.
- **`:failed` parse paths** leave columns nil; sidebar renders "—". Document as expected.
- **English-only** save support. Multi-language is a Known Gap, not a v1 concern.

### Files to Create

- `app/services/soul_link/save_parser.rb` — pure parsing service
- `app/jobs/soul_link/parse_save_data_job.rb` — async parse + persist after save_data PATCH
- `db/migrate/<timestamp>_add_parsed_save_fields_to_soul_link_emulator_sessions.rb` — schema migration
- `test/services/soul_link/save_parser_test.rb`
- `test/jobs/soul_link/parse_save_data_job_test.rb`

### Files to Modify

- `app/models/soul_link_emulator_session.rb` — `after_update_commit :enqueue_parse_if_save_changed` callback
- `app/controllers/emulator_controller.rb` — pass parsed fields to view via existing `@run_sessions`
- `app/views/emulator/_run_sidebar.html.erb` — render new fields per session
- `test/models/soul_link_emulator_session_test.rb` — extend with parse-callback test
- `test/controllers/emulator_controller_test.rb` — extend with sidebar rendering test for new fields

---

### Migration Spec

Add five nullable columns to `soul_link_emulator_sessions`:

```ruby
class AddParsedSaveFieldsToSoulLinkEmulatorSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :soul_link_emulator_sessions, :parsed_trainer_name, :string,        limit: 16
    add_column :soul_link_emulator_sessions, :parsed_money,        :integer,       limit: 4
    add_column :soul_link_emulator_sessions, :parsed_play_seconds, :integer,       limit: 4
    add_column :soul_link_emulator_sessions, :parsed_badges,       :integer,       limit: 1, default: 0, null: false
    add_column :soul_link_emulator_sessions, :parsed_map_id,       :integer,       limit: 2
    add_column :soul_link_emulator_sessions, :parsed_at,           :datetime
  end
end
```

Notes on column choices:
- `parsed_trainer_name` is varchar(16) — Pokemon Platinum trainer name limit
- `parsed_money` is signed int — game caps at 999,999, fits easily
- `parsed_play_seconds` stores total seconds for easy sorting/formatting; convert to "12h 45m" in the view
- `parsed_badges` is a tinyint counting set bits in the badges bitfield (0-8); default 0 because we'll show "0 badges" rather than "—" when there's a save but no badges
- `parsed_map_id` is the raw Gen IV map ID (16-bit). Lookup → name happens in Phase 2.
- `parsed_at` is the timestamp of last successful parse — useful for sidebar "Parsed Xm ago" + skipping re-parse if save unchanged
- All other parsed_* are nullable: nil = "no save yet" or "parse failed"

---

### Service: `SoulLink::SaveParser`

Pure function. No AR, no I/O, no side effects.

```ruby
module SoulLink
  class SaveParser
    # Pokemon Platinum SRAM is 512KB total: two 256KB save slots.
    # Slot selection picks the higher save_counter; checksums verified per block.
    # Trainer block lives at a known offset within the active slot — plaintext,
    # so no PRNG/XOR descrambling needed (that's Phase 4 for party data).
    #
    # Returns a Result struct on success. Returns nil on any error (malformed
    # save, both slots invalid, unsupported game version). The caller writes nil
    # columns and the sidebar renders "—" — that's the documented :failed path.

    SLOT_SIZE = 0x40000          # 256KB per slot
    EXPECTED_TOTAL = 0x80000     # 512KB total

    # Trainer block offsets WITHIN the active slot (Pokemon Platinum, English).
    # Source: Project Pokemon save format docs + pret/pokeplatinum disassembly.
    # Bob: verify these against a real save file from Project Owner — if wrong,
    # the parser will return nil and the sidebar shows "—". Never crash.
    TRAINER_BLOCK_OFFSET = 0x0000  # adjust if testing reveals different
    NAME_OFFSET          = 0x0064  # 16 bytes, Gen IV char-encoded
    NAME_BYTES           = 16
    GENDER_OFFSET        = 0x0078
    MONEY_OFFSET         = 0x007C  # 4 bytes little-endian
    BADGES_OFFSET        = 0x0084  # 1 byte bitfield (8 badges)
    PLAY_HOURS_OFFSET    = 0x0088  # 2 bytes LE
    PLAY_MINUTES_OFFSET  = 0x008A  # 1 byte
    PLAY_SECONDS_OFFSET  = 0x008B  # 1 byte
    MAP_ID_OFFSET        = 0x1234  # placeholder — Bob: identify from disasm or pkhex

    # Gen IV character set: index → unicode codepoint. ~250 entries for
    # English. Build incrementally from Project Pokemon docs. Bob:
    # implement only the English subset (A-Z, a-z, 0-9, common punctuation,
    # space, and PK/MN ligatures). Anything outside the table renders as
    # the codepoint U+FFFD (REPLACEMENT CHARACTER) — the cleaner failure
    # mode than crashing or showing nothing.
    GEN4_CHAR_TABLE = {
      0x0001 => 0x0030, # '0'
      0x0002 => 0x0031, # '1'
      # ... build out the table from Project Pokemon docs
    }.freeze

    Result = Struct.new(
      :trainer_name, :money, :play_seconds, :badges_count, :map_id,
      keyword_init: true
    )

    class << self
      # @param bytes [String] raw decompressed save_data (binary encoding)
      # @return [Result, nil] Result on success, nil on parse failure
      def parse(bytes)
        return nil unless bytes.is_a?(String)
        return nil if bytes.bytesize != EXPECTED_TOTAL

        slot = active_slot(bytes)
        return nil if slot.nil?

        Result.new(
          trainer_name: decode_name(slot.byteslice(NAME_OFFSET, NAME_BYTES)),
          money:        slot.byteslice(MONEY_OFFSET, 4).unpack1("V"),
          play_seconds: total_play_seconds(slot),
          badges_count: count_set_bits(slot.getbyte(BADGES_OFFSET)),
          map_id:       slot.byteslice(MAP_ID_OFFSET, 2).unpack1("v"),
        )
      rescue StandardError
        nil
      end

      private

      # Returns the higher-counter slot, or nil if both slots fail checksum.
      # See Project Pokemon docs for the per-block CRC16-CCITT layout.
      def active_slot(bytes)
        # Bob: implement slot selection. Skeleton:
        #   slot_a = bytes.byteslice(0, SLOT_SIZE)
        #   slot_b = bytes.byteslice(SLOT_SIZE, SLOT_SIZE)
        #   counter_a = read_save_counter(slot_a)
        #   counter_b = read_save_counter(slot_b)
        #   pick the higher one, but only if its checksum verifies; else fall
        #   back to the other slot; nil if both fail.
      end

      def decode_name(bytes)
        # Bob: walk the bytes 2 at a time as little-endian 16-bit indices,
        # stop at terminator 0xFFFF, look up GEN4_CHAR_TABLE, build a UTF-8
        # string, fall back to U+FFFD for unknown indices.
      end

      def total_play_seconds(slot)
        h = slot.byteslice(PLAY_HOURS_OFFSET, 2).unpack1("v")
        m = slot.getbyte(PLAY_MINUTES_OFFSET)
        s = slot.getbyte(PLAY_SECONDS_OFFSET)
        h * 3600 + m * 60 + s
      end

      def count_set_bits(byte)
        byte.to_s(2).count("1")
      end
    end
  end
end
```

**Critical:** Bob, the offsets above are **placeholders** taken from rough community references. They may be wrong for Pokemon Platinum specifically. Your job during build:
1. Get a real save file from Project Owner (or use the in-conversation Tempfile-from-fixture approach)
2. Verify trainer_name decodes to a readable string
3. Verify money matches what the player sees in-game
4. Verify play_seconds matches in-game time
5. If any offset is wrong, **fix the offset in the constant** and document the verified value in a comment with source

**Reference sources (consult during build):**
- Project Pokemon save format spec: https://projectpokemon.org/home/docs/
- pret/pokeplatinum disassembly: https://github.com/pret/pokeplatinum (scan for `SaveData_*` symbols)
- PKHeX C# offsets: https://github.com/kwsch/PKHeX/blob/master/PKHeX.Core/Saves/SAV4DP.cs and SAV4Pt.cs (read-only reference; do NOT copy code — license)

If you cannot verify all 5 fields against a real save, **return nil for the unverifiable ones rather than guessing**. A "—" in the sidebar is better than a wrong number.

---

### Job: `SoulLink::ParseSaveDataJob`

```ruby
module SoulLink
  class ParseSaveDataJob < ApplicationJob
    queue_as :default

    def perform(session)
      return unless session.save_data.present?

      result = SoulLink::SaveParser.parse(session.save_data)

      attrs = if result
        {
          parsed_trainer_name: result.trainer_name,
          parsed_money:        result.money,
          parsed_play_seconds: result.play_seconds,
          parsed_badges:       result.badges_count,
          parsed_map_id:       result.map_id,
          parsed_at:           Time.current,
        }
      else
        # Parse failed — write nils + parsed_at so we don't loop. Sidebar shows "—".
        {
          parsed_trainer_name: nil,
          parsed_money:        nil,
          parsed_play_seconds: nil,
          parsed_badges:       0,
          parsed_map_id:       nil,
          parsed_at:           Time.current,
        }
      end

      session.update_columns(attrs)  # skip callbacks to avoid the after_update_commit loop
    end
  end
end
```

**`update_columns` is critical** — using `update!` would re-fire the `after_update_commit` callback that enqueued this job, infinite loop. The DB columns reflect the parse result; no callbacks needed for them.

---

### Model Hook: `SoulLinkEmulatorSession`

```ruby
after_update_commit :enqueue_parse_if_save_changed

private

def enqueue_parse_if_save_changed
  return unless saved_change_to_attribute?("save_data")
  return if save_data.blank?
  SoulLink::ParseSaveDataJob.perform_later(self)
end
```

`saved_change_to_attribute?("save_data")` is the AR 8 way to check if a column changed in the just-committed save. The job only runs when save_data was actually updated.

---

### Controller / View Updates

**`EmulatorController#show`** — no change needed. `@run_sessions` already loaded; the new parsed_* columns travel with the model.

**`_run_sidebar.html.erb`** — extend each card to render new fields when present. Skeleton:

```erb
<% if s.parsed_trainer_name.present? %>
  <div style="font-size: 11px; color: var(--d1); margin-bottom: 2px;">
    In-game name: <%= s.parsed_trainer_name %>
  </div>
<% end %>

<% if s.parsed_play_seconds %>
  <div style="font-size: 10px; color: var(--d2); margin-bottom: 2px;">
    Time played: <%= format_play_time(s.parsed_play_seconds) %>
  </div>
<% end %>

<% if s.parsed_money %>
  <div style="font-size: 10px; color: var(--d2); margin-bottom: 2px;">
    Money: ₽<%= number_with_delimiter(s.parsed_money) %>
  </div>
<% end %>

<div style="font-size: 10px; color: var(--d2); margin-bottom: 2px;">
  Badges: <%= s.parsed_badges %> / 8
</div>
```

Add a `format_play_time(seconds)` helper somewhere reasonable (`app/helpers/emulator_helper.rb` is fine if it doesn't exist; create it). Returns "12h 45m" for total seconds, "—" for nil.

**Sidebar order:** existing fields first (player name, status, last activity, save size), then new parsed fields, then seed footer. Don't reorder existing fields.

---

### Tests

#### `SaveParser` (`test/services/soul_link/save_parser_test.rb`)

Most important. Hermetic — no real save files in test/fixtures. Use:
- A small known-good fixture byte array hard-coded in the test (e.g., 0x80000 zero-padded with a synthetic trainer block at the right offset). Build it with `String.new(encoding: Encoding::BINARY)` and assemble the bytes you want at known offsets.
- Test the success path with 3-4 different name/money/time combinations
- Test failure paths: nil input, wrong size, garbage bytes
- Test edge cases: trainer name shorter than 16 chars (terminator), money at zero, play_time at zero, all 8 badges set

Don't test against a real Pokemon Platinum save in CI — that ROM data isn't redistributable.

If Bob can construct a synthetic SRAM-shaped binary and round-trip it through the parser successfully, that's sufficient coverage even if real-save verification happens manually outside CI.

#### `ParseSaveDataJob` (`test/jobs/soul_link/parse_save_data_job_test.rb`)

- Job stubs `SaveParser.parse` to return a Result; assert `update_columns` was called with the expected attrs
- Job stubs `SaveParser.parse` to return nil; assert nil-attrs were written + parsed_at set
- Job called for session with no save_data → no-op (no parser invocation)
- Idempotency: running the job twice on the same session leaves the same final state

#### Model callback (`test/models/soul_link_emulator_session_test.rb`)

- Updating save_data enqueues the job (use `assert_enqueued_with`)
- Updating other columns does NOT enqueue
- Updating save_data to nil does NOT enqueue

#### Controller / view (`test/controllers/emulator_controller_test.rb`)

- Render with a session that has `parsed_trainer_name = "Lyra"`, assert response body includes "Lyra"
- Render with parsed fields all nil, assert sidebar still renders ("—" or skipped)

---

### Build Order

1. Migration first. `bin/rails db:migrate`. Verify schema.
2. Service skeleton with placeholders. Run unit tests against synthetic SRAM.
3. **Verify offsets against a real Pokemon Platinum save.** Bob: ask Project Owner for a sample `.sav` from their actual emulator session (or generate one by playing for ~5 min and saving). Read it; confirm the trainer block parses to known values. Adjust offsets if needed and document the verified hex.
4. Job + tests.
5. Model callback + tests.
6. View update.
7. Controller test extensions.
8. Full suite. 3+ parallel runs for flake check.

If step 3 fails (offsets unverifiable), STOP and escalate. Do not ship offsets that haven't been validated against real game data.

---

### Flags

- Flag: **Phase 1 only.** Do NOT implement Pokemon party decryption (Phase 4) or PC boxes (Phase 5). Document them as deferred Known Gaps in REVIEW-REQUEST.
- Flag: **`update_columns`, not `update!`** in the job — must skip the `after_update_commit` callback or you'll get an infinite loop.
- Flag: **Parser returns nil on any error.** Never raise. The job catches nothing because it has nothing to catch.
- Flag: **Offsets must be verified against a real save** (Bob asks Project Owner). If Bob can't get one, ship the parser returning nil ("—" sidebar) and flag it as outstanding.
- Flag: **English-only character table.** Multi-language is a deferred Known Gap.
- Flag: **Don't copy PKHeX code** (license). Reference its constants and reimplement.
- Flag: **`add_column` with `:integer, limit: 1`** is a tinyint in MySQL — small but signed. badges fits 0..8, so signed tinyint is fine.
- Flag: **No new gems** — pure stdlib (`String#unpack`, bitwise ops).
- Flag: **`saved_change_to_attribute?`** not `saved_change_to_save_data?` — the magic-method form for symbol-keyed attribute names. Either works.
- Flag: **`parsed_at` is set even on parse failure** — prevents endless re-parse loops if the save is permanently malformed.
- Flag: Rails commands use `bin/rails ...`. Fall back to `mise exec -- bundle exec rails ...` if `bin/rails` fails.
- Flag: Do NOT commit. Architect commits.

### Definition of Done

- [ ] Migration adds 6 columns to `soul_link_emulator_sessions`; `db/schema.rb` reflects it
- [ ] `SoulLink::SaveParser.parse(bytes)` returns Result on valid SRAM, nil on any error, never raises
- [ ] All 5 trainer fields verified against a real Pokemon Platinum save (Bob documents offsets in code comment with source)
- [ ] `SoulLink::ParseSaveDataJob` updates parsed_* columns via `update_columns`, sets `parsed_at` on both success and failure paths
- [ ] Model `after_update_commit` enqueues the job ONLY when save_data changed and is non-nil
- [ ] Sidebar renders new fields when present, gracefully degrades to "—" or skip when nil
- [ ] Service tests cover success + failure paths with synthetic SRAM (no real ROM data in CI)
- [ ] Job tests cover both branches (success → real attrs, failure → nil attrs)
- [ ] Model test covers callback enqueue / no-enqueue cases
- [ ] Full suite passes: 221 baseline + new tests, 0 failures
- [ ] 3+ consecutive parallel runs without flakes

---

## Builder Plan
*Builder adds their plan here before building. Architect reviews and approves.*

### Plan (Bob)

1. **Migration + service skeleton with verified offsets from research**: I'll use the pret/pokeplatinum disassembly + Project Pokemon docs as primary sources to locate the correct offsets for Pt (general blockA layout). PKHeX read-only. No real save available, so I'll cite sources in the code comment, document offsets as "research-verified, awaiting real-save validation," and flag this loud in REVIEW-REQUEST. Will request a real save from Project Owner via REVIEW-REQUEST open question.
2. **Slot selection**: implement CRC16-CCITT (poly 0x1021, init 0xFFFF) over each block per pret. Pick the slot whose general-block save_counter is higher AND whose checksum verifies; fallback to other slot; nil if both fail.
3. **Gen IV English char table**: hand-build the English subset (space, 0-9, A-Z, a-z, common punctuation `! ? . , ' "`) from Project Pokemon. Unknown indices map to U+FFFD. Terminator 0xFFFF stops decoding.
4. **Synthetic test fixtures**: build a 0x80000-byte SRAM template in test setup — zero-padded, with known trainer block bytes and CRC computed at the right offset. Round-trip 4-5 scenarios (full name, short name with terminator, zero money, max badges, malformed garbage). This is load-bearing in lieu of real-save proof.
5. **Job + model hook + view**: per spec. `update_columns` to skip the callback loop. Helper `format_play_time` in `EmulatorHelper` (new file).
6. **Test discipline**: extend existing model + controller tests; new tests for service + job. Run 3+ parallel suites and confirm zero flakes.

Uncertainties / risks:
- Specific block-A layout & checksum endpoints in Pt. Will document the chosen offsets with exact source citations and ship returning-nil-on-failure as the safety net.
- Map ID location: deferred-flag if I can't pin it down with high confidence; field returns nil and sidebar omits it.

No new gems. English-only. Phase 1 only.
