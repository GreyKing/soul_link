# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 16 — Non-decryption SRAM expansion: TID/SID + Pokédex counts + Hall of Fame

### Context

Step 15 shipped `SoulLink::SaveDiff` (pure diff layer) + `SoulLink::GymBeatenCoordinator` (all-4 AND-gate side-effect handler) + KG-13 fix. Categories 2 (gym battle teams) and 3 (catches+routes) of the SRAM auto-tracking audit (`handoff/2026-05-02-sram-auto-tracking-audit.md`) are deferred to Step 17/18 because they require Gen-IV PKM block decryption.

This step bundles the **three highest-ROI SRAM additions that don't pay decryption cost**, all on top of the Step-15 SaveDiff infra:

1. **TID/SID surfacing** (audit § 3.1 items 1+2) — save-mix-up detection across the 4 players. Offsets `0x0078` (TID) and `0x007A` (SID) are already documented constants in `save_parser.rb` — just unused.
2. **Pokédex caught/seen counter** (audit § 3.1 item 4) — closes **KG-14**. Offsets need pret/pokeplatinum validation.
3. **Hall of Fame detection** (audit § 3.1 item 5) — run-completion auto-detection. Separate save block + own CRC.

Source docs (already on main): `handoff/2026-05-02-sram-auto-tracking-audit.md`, `handoff/2026-05-02-yml-and-sram-expansion.md` § 3 + § Recommendations.

### Project Owner decisions (locked)

1. **Pattern adherence: SaveDiff emits events for all three categories.** New event structs `TidObserved`, `PokedexProgress`, `HallOfFameEntered` join the existing `BadgeGained`/`BadgeLost`. `Result` extends with `tid_events:`, `pokedex_events:`, `hof_events:` keyword fields (default `[]` — backward compat). Step 15 callers using only `prev_badges:`/`curr_badges:` continue working unchanged.
2. **TID and Pokédex coordinators are log-only.** The user-visible value comes from the parser persisting the values + the views reading them. No DB side effects beyond the slot row's parsed_* columns. The coordinators exist for symmetric pattern adherence and traceability — same shape as `GymBeatenCoordinator`'s `BadgeLost` no-op log handler.
3. **HoF coordinator is the side-effect-bearing one.** When all 4 sessions in a run report `parsed_hof_count >= 1`, set `run.completed_at = Time.current`. All-4 AND-gate, mirrors `GymBeatenCoordinator.all_players_have_badge?`. Idempotent: skip if `completed_at` is already set.
4. **No auto-deactivation of completed runs.** `active` flag stays as-is. PO follow-on call. Log to BUILD-LOG Known Gaps.
5. **Dispatcher extraction.** Per the brief: `ParseSaveDataJob` becomes "pure parser + persist". Diff + dispatch moves to a new `SoulLink::SaveDiffDispatcher.dispatch(slot, prev:, curr:)`. Job builds two state-snapshot hashes (pre/post) and hands them to the dispatcher; dispatcher computes the diff and fans out to the four coordinators. Step 15's existing dispatch logic relocates with no behavior change to badge handling.
6. **TID-mix-up detection is read-side.** A new `SoulLinkRun#tid_conflict_groups` returns groups of session-ids that share the same `(parsed_trainer_id, parsed_secret_id)` pair. The view renders a yellow "⚠ TID conflict" pill on each affected card. No coordinator action — the player resolves manually (it might be a legitimate save-reset, not a mix-up).
7. **Backward compat is non-negotiable.** Every new column nullable / default-zero. Every new SaveDiff dimension nil-safe. The first-ever-parse baseline rule (Step 15 architecture decision) still applies — no events fire on a slot's first successful parse.
8. **KG-14 closure rule.** Pokédex caught/seen offsets must be cited in code comments from a primary source (pret/pokeplatinum `include/pokedex.h` or `src/savedata/`). Defensive cap: count > `POKEDEX_BIT_LENGTH` (493 — Sinnoh dex max) returns nil for that field, mirroring `safe_map_id`'s graceful degradation. **KG-14 only closes if the offset is cited from a primary source.** If you can't pin it, ship the rest of the step (TID + HoF) and log Pokédex as deferred — KG-14 stays open.
9. **HoF block CRC.** Validate offset + size + CRC variant against pret/pokeplatinum (`SAVEDATA_PT_HALLOFFAME_BLOCK_SIZE` and adjacent `SaveData` block table). The general block uses CRC16-CCITT-FALSE (poly 0x1021, init 0xFFFF) — if HoF uses the same variant, reuse the existing `crc16_ccitt` helper. If it diverges, document and match. On CRC fail or any error → `parsed_hof_count = nil` (NEVER false-positive a "Run complete").

### Architecture

#### Layer A — parser additions (`app/services/soul_link/save_parser.rb`)

Extend `Result` struct with new keyword fields (preserve existing field order):

```ruby
Result = Struct.new(
  :trainer_name, :money, :play_seconds, :badges_count, :map_id,
  :trainer_id, :secret_id,                # NEW — items 1+2
  :pokedex_caught, :pokedex_seen,         # NEW — item 4 (KG-14)
  :hof_count,                             # NEW — item 5
  keyword_init: true
)
```

Constants:
- `TRAINER_ID_OFFSET` and `SECRET_ID_OFFSET` are **already declared** at lines 60-61. Wire them into `parse(...)` via a new `read_uint16_le(slot, offset)` helper (or extend the existing `read_uint32_le` pattern).
- `POKEDEX_CAUGHT_OFFSET` + `POKEDEX_CAUGHT_BYTES` and `POKEDEX_SEEN_OFFSET` + `POKEDEX_SEEN_BYTES` — pin against pret/pokeplatinum primary source. Audit cites `~0x1328` for caught (84 bytes, bit-per-species, 493 species). The seen region is adjacent. Verify both before shipping.
- `POKEDEX_BIT_LIMIT = 493` — Sinnoh national dex cap. Defensive guard: if popcount > 493, return nil for that field.
- HoF block constants: `HOF_BLOCK_OFFSET` (within the 512KB file, NOT within a slot — the HoF block lives outside the two general-block slots), `HOF_BLOCK_SIZE`, `HOF_FOOTER_OFFSET`, `HOF_CRC_OFFSET`, `HOF_COUNT_OFFSET` (the entry-count field within the HoF block — verify what "count" means in pret; it may be a record count, not a "1 if HoF entered, 0 if not". For our purposes, **`hof_count >= 1` means "this player has entered HoF at least once"** which is the only thing the run-completion logic cares about).

New private methods on `SaveParser`:
- `read_uint16_le(bytes, offset)` — 2-byte little-endian read with nil-safe boundary check.
- `count_pokedex_bits(slot, offset, byte_length, bit_limit)` — popcount bytes; if total > bit_limit → return nil; else return total.
- `safe_hof_count(bytes)` — picks the active HoF block (CRC-validated), reads the entry count, returns Integer or nil. Use the same active-slot-picker shape as `active_slot` if HoF has dual-slot semantics, otherwise single-block-with-CRC. Verify against pret.

Parser purity contract (already documented in the file): no AR, no Rails.logger, no Time. Top-level `rescue StandardError → nil` already wraps the whole `parse(...)` — keep it.

#### Layer B — schema migrations

Two migrations, one per table (keep diffs reviewable):

**`db/migrate/<ts>_add_step_16_parsed_columns_to_soul_link_emulator_save_slots.rb`**
```ruby
class AddStep16ParsedColumnsToSoulLinkEmulatorSaveSlots < ActiveRecord::Migration[8.1]
  def change
    add_column :soul_link_emulator_save_slots, :parsed_trainer_id,    :integer
    add_column :soul_link_emulator_save_slots, :parsed_secret_id,     :integer
    add_column :soul_link_emulator_save_slots, :parsed_pokedex_caught, :integer
    add_column :soul_link_emulator_save_slots, :parsed_pokedex_seen,   :integer
    add_column :soul_link_emulator_save_slots, :parsed_hof_count,      :integer
  end
end
```

(Default integer = 4 bytes signed. uint16 max 65535 fits cleanly. Avoid `limit: 2` — smallint risks overflow on uint16 upper half. No defaults — nil = "never parsed this field" matches `parsed_map_id`'s pattern.)

**`db/migrate/<ts>_add_completed_at_to_soul_link_runs.rb`**
```ruby
class AddCompletedAtToSoulLinkRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :soul_link_runs, :completed_at, :datetime
    add_index  :soul_link_runs, :completed_at
  end
end
```

#### Layer C — SaveDiff extension (`app/services/soul_link/save_diff.rb`)

Add new event structs alongside the existing `BadgeGained`/`BadgeLost`:
```ruby
TidObserved       = Struct.new(:trainer_id, :secret_id, keyword_init: true)
PokedexProgress   = Struct.new(:caught_delta, :seen_delta, :curr_caught, :curr_seen, keyword_init: true)
HallOfFameEntered = Struct.new(:hof_count, keyword_init: true)
```

Extend `Result`:
```ruby
Result = Struct.new(:badge_events, :tid_events, :pokedex_events, :hof_events, keyword_init: true) do
  def empty?
    badge_events.empty? && tid_events.empty? && pokedex_events.empty? && hof_events.empty?
  end
end
```

Extend `SaveDiff.between`:
```ruby
def self.between(prev_badges:, curr_badges:,
                 prev_tid: nil, curr_tid: nil,
                 prev_sid: nil, curr_sid: nil,
                 prev_pokedex_caught: nil, curr_pokedex_caught: nil,
                 prev_pokedex_seen: nil,   curr_pokedex_seen: nil,
                 prev_hof_count: nil,      curr_hof_count: nil)
```

Emission rules:
- **Badge events** — unchanged from Step 15. Same nil-safety, same `>` / `<` pair-iteration.
- **TidObserved** — emit a single event when `[prev_tid, prev_sid]` ≠ `[curr_tid, curr_sid]` AND `curr_tid` is present-and-nonzero. Skip emission when curr is nil/zero (the slot just hasn't been parsed yet) or when prev == curr (no transition).
- **PokedexProgress** — emit one event when caught OR seen changed. Compute `caught_delta = curr - prev` (allow negative — older save load). Skip if both unchanged. Skip if either side is nil (first parse / parse-failure path — those skip dispatch entirely upstream anyway, but be defensive in the diff).
- **HallOfFameEntered** — emit only on the prev-was-nil-or-zero → curr-≥-1 transition. Subsequent increments (1 → 2 → 3) are not interesting at the diff level. Skip if curr is nil.

Backward-compat check: a Step-15-style call `SaveDiff.between(prev_badges: 0, curr_badges: 1)` must return `Result.new(badge_events: [BadgeGained.new(gym_number: 1)], tid_events: [], pokedex_events: [], hof_events: [])` and existing tests must pass unchanged.

#### Layer D — dispatcher (`app/services/soul_link/save_diff_dispatcher.rb` — NEW)

```ruby
module SoulLink
  # Side-effect handler for SaveDiff results. Called from ParseSaveDataJob
  # after parsed_* columns are written. Builds the SaveDiff and fans out
  # to the per-category coordinators.
  #
  # Owns the baseline rule (skip dispatch on first-ever parse) and the
  # empty-diff short-circuit. ParseSaveDataJob stays a "pure parser +
  # persist" job — no per-category branching lives in it.
  class SaveDiffDispatcher
    # @param slot [SoulLinkEmulatorSaveSlot]
    # @param prev [Hash] pre-parse snapshot — keys: :parsed_at, :badges,
    #   :trainer_id, :secret_id, :pokedex_caught, :pokedex_seen, :hof_count
    # @param curr [Hash] post-parse snapshot — same shape
    def self.dispatch(slot, prev:, curr:)
      return if prev[:parsed_at].nil?  # baseline rule

      diff = SoulLink::SaveDiff.between(
        prev_badges: prev[:badges],                 curr_badges: curr[:badges],
        prev_tid:    prev[:trainer_id],             curr_tid:    curr[:trainer_id],
        prev_sid:    prev[:secret_id],              curr_sid:    curr[:secret_id],
        prev_pokedex_caught: prev[:pokedex_caught], curr_pokedex_caught: curr[:pokedex_caught],
        prev_pokedex_seen:   prev[:pokedex_seen],   curr_pokedex_seen:   curr[:pokedex_seen],
        prev_hof_count:      prev[:hof_count],      curr_hof_count:      curr[:hof_count]
      )
      return if diff.empty?

      SoulLink::GymBeatenCoordinator.process(slot, diff.badge_events)         if diff.badge_events.any?
      SoulLink::TidObservationCoordinator.process(slot, diff.tid_events)      if diff.tid_events.any?
      SoulLink::PokedexProgressCoordinator.process(slot, diff.pokedex_events) if diff.pokedex_events.any?
      SoulLink::HallOfFameCoordinator.process(slot, diff.hof_events)          if diff.hof_events.any?
    end
  end
end
```

#### Layer E — coordinators

**`app/services/soul_link/tid_observation_coordinator.rb`** — log-only:
```ruby
module SoulLink
  class TidObservationCoordinator
    def self.process(slot, events)
      run = slot.soul_link_emulator_session&.soul_link_run
      return if run.nil?
      events.each do |event|
        Rails.logger.info(
          "TidObservationCoordinator: TID=#{event.trainer_id} SID=#{event.secret_id} " \
          "run=#{run.id} session=#{slot.soul_link_emulator_session_id} slot=#{slot.id}"
        )
      end
    end
  end
end
```

**`app/services/soul_link/pokedex_progress_coordinator.rb`** — log-only, same shape (log caught/seen deltas + curr counts).

**`app/services/soul_link/hall_of_fame_coordinator.rb`**:
```ruby
module SoulLink
  class HallOfFameCoordinator
    def self.process(slot, events)
      return if events.empty?
      run = slot.soul_link_emulator_session&.soul_link_run
      return if run.nil? || !run.active? || run.completed_at.present?
      return unless all_players_in_hall_of_fame?(run)

      run.update!(completed_at: Time.current)
      Rails.logger.info("HallOfFameCoordinator: run=#{run.id} marked complete (4/4 HoF)")
    end

    def self.all_players_in_hall_of_fame?(run)
      sessions = run.soul_link_emulator_sessions.includes(:save_slots)
      return false if sessions.empty?
      sessions.all? { |s| s.active_slot&.parsed_hof_count.to_i >= 1 }
    end
  end
end
```

(No suppression table for HoF — once `completed_at` is set, idempotency is enforced by the `run.completed_at.present?` guard. Direct AR write to `completed_at = nil` is the un-completion path if PO ever wants one. KG follow-on if needed.)

#### Layer F — model additions

**`app/models/soul_link_run.rb`**:

```ruby
broadcasts_refreshes_to ->(record) { [ record, :dashboard ] }

def completed?
  completed_at.present?
end

# Returns Array<Array<Integer>> — each inner array is a list of session
# ids whose active slots share the same (TID, SID) pair. Empty when
# every session has a unique or unset TID. Used by the dashboard to
# surface a "⚠ TID conflict" pill on each affected save-slot card.
# Sessions with nil/zero TID are excluded (unparsed, not a conflict).
def tid_conflict_groups
  pairs = soul_link_emulator_sessions
    .includes(:save_slots)
    .filter_map do |s|
      slot = s.active_slot
      next if slot.nil?
      next if slot.parsed_trainer_id.to_i.zero?
      [ slot.parsed_trainer_id, slot.parsed_secret_id, s.id ]
    end

  pairs
    .group_by { |tid, sid, _| [ tid, sid ] }
    .values
    .select { |group| group.size >= 2 }
    .map    { |group| group.map { |_, _, sid| sid } }
end
```

The new `broadcasts_refreshes_to` mirrors the Step 15 `GymResult` pattern. Verified absent today (`grep broadcasts_refreshes_to app/models/` — only `gym_result.rb`, `soul_link_pokemon.rb`, `soul_link_pokemon_group.rb` have it). When `HallOfFameCoordinator` updates `completed_at`, this broadcast fires the dashboard refresh and the "Run complete" banner appears in real time.

#### Layer G — `ParseSaveDataJob` rewire

```ruby
def perform(slot)
  return if slot.nil?
  return if slot.save_data.blank?

  prev = capture_state(slot)

  result = SoulLink::SaveParser.parse(slot.save_data)
  if result
    slot.update_columns(
      parsed_trainer_name:   result.trainer_name,
      parsed_money:          result.money,
      parsed_play_seconds:   result.play_seconds,
      parsed_badges:         result.badges_count.to_i,
      parsed_map_id:         result.map_id,
      parsed_trainer_id:     result.trainer_id,
      parsed_secret_id:      result.secret_id,
      parsed_pokedex_caught: result.pokedex_caught,
      parsed_pokedex_seen:   result.pokedex_seen,
      parsed_hof_count:      result.hof_count,
      parsed_at:             Time.current
    )
    SoulLink::SaveDiffDispatcher.dispatch(slot, prev: prev, curr: capture_state(slot))
  else
    # KG-13 contract: parse failure stamps only parsed_at. No dispatch.
    slot.update_columns(parsed_at: Time.current)
  end
end

private

def capture_state(slot)
  {
    parsed_at:      slot.parsed_at,
    badges:         slot.parsed_badges,
    trainer_id:     slot.parsed_trainer_id,
    secret_id:      slot.parsed_secret_id,
    pokedex_caught: slot.parsed_pokedex_caught,
    pokedex_seen:   slot.parsed_pokedex_seen,
    hof_count:      slot.parsed_hof_count
  }
end
```

The two `capture_state(slot)` calls bracket the `update_columns`, so prev and curr are taken from AR state before/after the write — consistent with how Step 15 captured `prev_parsed_at` and `prev_badges` directly.

#### Layer H — UI surfaces

**`app/views/emulator/_run_sidebar_card.html.erb`** (per-other-player card on the emulator-page sidebar — broadcasts on parsed_* updates per Step 9 KG-2):

After the existing `Badges: N / 8` block (lines 89-93), append (gated on each value being present):

1. **TID/SID line** — when `active_slot&.parsed_trainer_id.to_i > 0`:
   ```erb
   TID <%= active_slot.parsed_trainer_id %> / SID <%= active_slot.parsed_secret_id %>
   ```
2. **Pokédex line** — when `active_slot&.parsed_pokedex_caught` OR `active_slot&.parsed_pokedex_seen` present:
   ```erb
   Pokédex <%= active_slot.parsed_pokedex_caught || 0 %> caught / <%= active_slot.parsed_pokedex_seen || 0 %> seen
   ```
3. **HoF pill** — when `active_slot&.parsed_hof_count.to_i >= 1`:
   ```erb
   <span class="type-text" style="border-color: var(--amber); background: var(--amber); color: var(--d1); font-size: 9px;">🏆 HALL OF FAME</span>
   ```
4. **TID conflict pill** — compute inside the partial: `conflict_session_ids = s.soul_link_run.tid_conflict_groups.flatten`. When `conflict_session_ids.include?(s.id)`:
   ```erb
   <span class="type-text" style="border-color: #6b5a2c; background: #4a3a1c; color: #e8d6a0; font-size: 9px;">⚠ TID CONFLICT</span>
   ```

The conflict computation runs once per card render — accept the small N+1 (4 sessions × 1 query = 4 queries, all eager-loaded by `includes(:save_slots)`). Don't extract it to a controller-level memo — the broadcast partial has no controller context (per the partial's existing doc comment, lines 4-12).

**`app/views/emulator/_save_slots_sidebar.html.erb`** (per-slot column on the player's own emulator page):

Mirror the same TID/SID + Pokédex + HoF lines per slot, after the existing "Badges: N / 8" line (line 95-99). Skip the TID conflict pill here (the player's own slots can't conflict with themselves — only cross-player conflicts matter).

**`app/views/dashboard/_runs_content.html.erb`** (the run management panel, dashboard's "RUNS" tab):

In the Active Run panel header area (around line 26 — next to the existing "ACTIVE" pill), conditionally render a "🏆 RUN COMPLETE" pill when `active_run&.completed?`:
```erb
<% if active_run&.completed? %>
  <span class="type-text" style="border-color: var(--amber); background: var(--amber); color: var(--d1);">🏆 COMPLETE</span>
<% end %>
```

Also add a fifth tile to the gb-grid-4 stats (or convert to gb-grid-5 if the CSS supports it; otherwise add a row below) showing the completion timestamp:
```erb
<% if active_run&.completed_at %>
  <div class="gb-card-dark" style="text-align: center; padding: 8px;">
    <div style="font-size: 10px; color: var(--l2);"><%= active_run.completed_at.strftime("%b %-d, %Y") %></div>
    <div style="font-size: 9px; color: var(--l1); margin-top: 2px;">COMPLETED</div>
  </div>
<% end %>
```

Bob: pick the cleaner of the two layouts. If gb-grid-4 → gb-grid-5 isn't a one-line CSS adjust, do the row-below option. The pill alone is the must-have; the timestamp tile is a nice-to-have within the same partial.

### Tests required

**Parser** (`test/services/soul_link/save_parser_test.rb` — extend):
- TID parse: synthetic 512KB save with TID=0x1234 at slot offset 0x78 → `result.trainer_id == 0x1234`.
- SID parse: SID=0x5678 at slot offset 0x7A → `result.secret_id == 0x5678`.
- Pokédex caught: synthetic save with N bits set in caught region → `result.pokedex_caught == N`.
- Pokédex seen: same shape.
- Pokédex defensive cap: bit count > 493 → `result.pokedex_caught == nil`.
- HoF: synthetic save with valid HoF block + count=1 → `result.hof_count == 1`.
- HoF CRC fail: corrupted HoF block → `result.hof_count == nil`.
- HoF count=0 (player hasn't entered yet) → `result.hof_count == 0` (NOT nil — zero is meaningful, distinct from "couldn't parse").
- Backward compat: existing all-fields-populated test still passes; new fields populate alongside the existing five.

**SaveDiff** (`test/services/soul_link/save_diff_test.rb` — extend):
- TidObserved: prev `[nil, nil]` → curr `[1234, 5678]` → 1 event.
- TidObserved: prev `[1234, 5678]` → curr `[1234, 5678]` → 0 events.
- TidObserved: prev `[1234, 5678]` → curr `[9999, 5678]` → 1 event (TID changed).
- TidObserved: curr `[0, 0]` → 0 events (zero treated as unset).
- PokedexProgress: caught 47 → 47 + seen 89 → 89 → 0 events.
- PokedexProgress: caught 47 → 52 + seen 89 → 89 → 1 event with caught_delta 5, seen_delta 0.
- PokedexProgress: caught 50 → 48 → 1 event with caught_delta -2 (older save load).
- PokedexProgress: prev nil + curr present → 0 events (defensive — first parse handled upstream).
- HallOfFameEntered: prev nil → curr 1 → 1 event.
- HallOfFameEntered: prev 0 → curr 1 → 1 event.
- HallOfFameEntered: prev 1 → curr 2 → 0 events.
- HallOfFameEntered: prev 1 → curr 1 → 0 events.
- Backward-compat: Step-15 call signature `SaveDiff.between(prev_badges: 0, curr_badges: 1)` returns Result with all 4 event arrays populated correctly (1 BadgeGained, [], [], []).

**Dispatcher** (`test/services/soul_link/save_diff_dispatcher_test.rb` — NEW):
- Baseline rule: `prev[:parsed_at] = nil` → no coordinator called (mock all 4, assert call counts == 0).
- Empty diff (all values equal) → no coordinator called.
- BadgeGained event only → only `GymBeatenCoordinator.process` invoked.
- All four event types → all four coordinators invoked exactly once each.
- Mocha or Minitest stub — same harness Step 15's coordinator tests use.

**HoF coordinator** (`test/services/soul_link/hall_of_fame_coordinator_test.rb` — NEW):
- 4/4 sessions with `parsed_hof_count >= 1` → run.completed_at set to ~Time.current.
- 3/4 sessions → completed_at stays nil.
- Run already completed (`completed_at` non-nil) → no-op (idempotency).
- Run inactive → no-op.
- 0 sessions → all_players_in_hall_of_fame returns false (don't false-positive an empty run).
- Session with no active slot → `active_slot&.parsed_hof_count.to_i` returns 0 → all_players_in_hall_of_fame false.

**TID coordinator** (`test/services/soul_link/tid_observation_coordinator_test.rb` — NEW):
- TidObserved → log line emitted (you can use a `Rails.logger.expects(:info)` or just assert the method runs without raising). No AR side effects (assert no row counts changed).
- Run nil (orphan slot) → no-op.

**Pokédex coordinator** (`test/services/soul_link/pokedex_progress_coordinator_test.rb` — NEW):
- Same shape as TID coordinator.

**ParseSaveDataJob** (`test/jobs/soul_link/parse_save_data_job_test.rb` — extend):
- New columns populate from parser Result (extend the existing happy-path test).
- Dispatcher called with prev: + curr: snapshots after successful parse (mock dispatcher, assert call args).
- Parse failure path → dispatcher NOT called (KG-13 contract preserved — extends Step 15's existing failure test).
- HoF integration: stub `SaveParser.parse` to return progressively HoF-entered results across 4 sessions; only the 4th save sets `run.completed_at`.

**Run model** (`test/models/soul_link_run_test.rb` — extend):
- `completed?` true when `completed_at` set, false when nil.
- `tid_conflict_groups` empty when all sessions have unique TIDs.
- `tid_conflict_groups` returns 1 group of 2 ids when 2 sessions share `[TID, SID]`.
- `tid_conflict_groups` returns 1 group of 4 ids when all 4 sessions share `[TID, SID]`.
- `tid_conflict_groups` ignores sessions with nil/zero TID.
- `tid_conflict_groups` distinguishes the pair: same TID, different SID → no conflict.

### Out of scope (log to BUILD-LOG Known Gaps)

- **Auto-deactivation of completed runs.** PO follow-on. `active` flag stays as-is.
- **Discord notification on HoF.** Could be a 1-liner inside `HallOfFameCoordinator`. Defer to PO ask.
- **PKM decryption.** Step 17/18.
- **Item bag / HM detection (KG-15).** Future step.
- **Held items, nature, IVs.** Decryption-gated.
- **TID conflict resolution flow.** Pill is informational only; no UI to resolve.
- **HoF "uncomplete" path.** Direct AR edit only; no UI.

### Diff scope

- 2 migrations (slot columns + run completed_at)
- 1 modified parser
- 1 modified service (`save_diff.rb` — extension)
- 1 new dispatcher
- 3 new coordinators (TID, Pokédex, HoF)
- 1 modified model (`soul_link_run.rb` — broadcasts_refreshes_to + completed? + tid_conflict_groups)
- 1 modified job (`parse_save_data_job.rb` — refactor through dispatcher)
- 3 modified views (emulator/_run_sidebar_card, emulator/_save_slots_sidebar, dashboard/_runs_content)
- 4 new test files (dispatcher + 3 coordinators)
- 4 extended test files (save_parser, save_diff, parse_save_data_job, soul_link_run)

### Build order

1. **Schema first.** Both migrations. `bin/rails db:migrate`. Schema.rb diff committed.
2. **TID/SID parser** (smallest, offsets already declared). Parser test. Wire through `Result`.
3. **Pokédex parser** — pin offsets against pret. If can't pin confidently, escalate to Arch. Parser tests with synthetic byte payloads.
4. **HoF parser** — pin offsets + CRC against pret. Parser tests.
5. **SaveDiff extension** — new event structs, extended Result, extended `between(...)`. Tests.
6. **Dispatcher** (new file). Tests.
7. **Coordinators** — TID, Pokédex, HoF. Tests for each.
8. **`ParseSaveDataJob` rewire** through dispatcher. Update existing tests + add new integration tests.
9. **Run model** — `broadcasts_refreshes_to`, `completed?`, `tid_conflict_groups`. Tests.
10. **Views** — slot card additions, dashboard run-complete pill. No new tests (consistent with Step 15's view-broadcast pattern; manual smoke is the harness).
11. **Full suite + rubocop.** Commit, FF-merge to main, push.

### Flag: things Bob must NOT guess at

- **Pokédex offsets.** Validate against pret/pokeplatinum primary source (`include/pokedex.h` and `src/savedata/`). Cite the source link/struct in the constant's code comment. **If you can't pin it, escalate** — don't ship a guess. The defensive cap (>493 → nil) catches the case where the offset is wrong, but it's belt-and-suspenders, not the contract. KG-14 only closes if the offset is cited from primary source.
- **HoF block layout.** Validate against pret/pokeplatinum (`SAVEDATA_PT_HALLOFFAME_BLOCK_SIZE` + the surrounding `SaveData` block table). The general block lives at offsets 0..0xCF2C within each slot; HoF is a separate block with its own location and footer. Match the CRC algorithm the existing parser uses (CRC16-CCITT-FALSE) only if pret confirms HoF uses the same — otherwise document the divergence and match what pret says.
- **HoF count semantics.** Verify whether `hof_count` in pret means "number of HoF entries recorded" or "boolean entered/not". Either works for our `>= 1` check, but document which one in the constant's comment.
- **Migration column types.** Use default `:integer` (4 bytes signed), NOT `limit: 2` (smallint risks overflow on uint16 upper half). uint16 max 65535 fits cleanly.
- **`SoulLinkRun` broadcast wiring.** Verified absent today. Add `broadcasts_refreshes_to ->(record) { [ record, :dashboard ] }` per the Step-15 GymResult pattern. The dashboard `show.html.erb` already has `<%= turbo_stream_from @run, :dashboard %>` — the broadcast lands there.
- **Don't extract anything from `_run_sidebar_card.html.erb`.** Just append the new lines after the existing "Badges: N / 8" line. The partial-broadcast contract from Step 9 KG-2 is load-bearing — no helpers, no controller context, all data lookups happen on the local `s` (session).
- **Conflict computation lives inside the partial.** `s.soul_link_run.tid_conflict_groups.flatten` runs per card render. `includes(:save_slots)` keeps it cheap. Don't pass conflict data via locals — it complicates the broadcast renderer and there's no controller context to compute it from in the broadcast path.
- **Step 14.1's `respond_with_error` / `json_request?` patterns are unrelated** to this step. Don't accidentally touch `gym_progress_controller.rb` or any UNMARK/MARK paths.
- **Don't touch `GymBeatenCoordinator`.** The dispatcher relocates the *call* to it, not its body. Preserve all Step-15 behavior exactly.
- **Step 15's existing `parse_save_data_job_test.rb` retry-safety regression test** must keep passing. The dispatcher refactor changes call sites but not invariants — `prev_badges == curr_badges` after the first job's write still produces an empty diff and short-circuits before the coordinator.

### KG closure

- **KG-14 closes** if Pokédex offsets ship with primary-source citations.
- **No new KGs expected.** HoF block has high-confidence pret citation per the audit. TID/SID offsets are already constants in the parser.

— Ava
