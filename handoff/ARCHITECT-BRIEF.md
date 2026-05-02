# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 15 — SaveDiff Infrastructure + Category 1 (Gyms-Beaten Auto-Detection)

### Context

Following the SRAM auto-tracking audit (`handoff/2026-05-02-sram-auto-tracking-audit.md`, committed to main as `b8a769e`), the Project Owner picked **option (b)**: a gym auto-marks beaten **only when all 4 players' active save slots show that badge**, with manual MARK BEATEN as the override and manual UNMARK creating a per-gym suppression so auto-detect doesn't re-fire.

This step builds the **shared `SaveDiff` infrastructure** the audit prescribed for all three SRAM auto-tracking categories, then ships **category 1 (gyms beaten)** on top of it. Categories 2 and 3 (gym battle teams, catches+routes) are out of scope for this step — they need the Gen-IV PKM decryption work, which is its own much larger surface and rolls under the future KG-11/KG-12 design phase.

The audit also called out **KG-13** (a pre-existing bug: parse-failure path zeros `parsed_badges`, which would cause spurious badge-loss events under the new diff system). KG-13 is folded into this step as a prerequisite — without it, the diff fires garbage events every time a CRC-failed save lands between two valid ones.

### Project Owner decisions (locked)

1. **All-4-players AND-gate.** Auto-mark fires only when every emulator session in the run has `parsed_badges >= gym_number`. While 1-3 players have it: gym stays in its current state. No partial UI signal in scope ("3/4 have it" indicator deferred).
2. **Manual MARK BEATEN bypasses the all-4 check.** It works exactly as today — direct create of `gym_results`. Bypass is implicit (it goes through a different controller, doesn't hit the coordinator).
3. **Manual UNMARK creates a suppression record.** Subsequent save-parses do NOT re-auto-mark a suppressed `(run, gym_number)`. Suppression persists until the user explicitly re-engages by manually MARK-BEATEN-ing that gym (which clears the suppression).
4. **Down events are no-ops.** A player loading an older save state produces a `BadgeLost` diff event; coordinator ignores it (logs at `info` level for traceability). No auto-unmark.
5. **Multi-bit jumps are processed sequentially.** A save that jumps 0→2 badges produces two `BadgeGained` events (gym 1, then gym 2); each runs through the all-4 check independently.
6. **`SaveDiff` is a pure function.** Operates on plain values (badge counts) — no AR coupling. The audit's architectural call. Future categories (catches, evolutions) extend the same Result struct without rewriting the consumers.
7. **Per-bit semantics use the count.** In legitimate Platinum play, `parsed_badges >= N` is equivalent to "has badge N" because the in-game badge bitfield is monotonically progressive. PKHeX edits that violate this assumption are out of scope. **No new column** for the raw bitfield byte.
8. **Baseline rule (audit Section 1).** A slot's first-ever successful parse triggers no events. Implementation: gate the diff dispatch on `slot.parsed_at` being non-nil **before** the current parse runs. If nil → record the parse, skip the diff.
9. **KG-13 fix.** On parse failure, only `parsed_at` updates. All other `parsed_*` fields are left at their prior value. Documented in the parser job + a regression test.

### Architecture

#### Layer A — pure diff (`app/services/soul_link/save_diff.rb`)

```ruby
module SoulLink
  module SaveDiff
    BadgeGained = Struct.new(:gym_number, keyword_init: true)
    BadgeLost   = Struct.new(:gym_number, keyword_init: true)

    Result = Struct.new(:badge_events, keyword_init: true) do
      def empty?
        badge_events.empty?
      end
    end

    # @param prev_badges [Integer, nil] previous parsed_badges count (nil = no prior baseline)
    # @param curr_badges [Integer, nil] current parsed_badges count (nil = parse failed)
    # @return [Result] always; badge_events is [] if either side is nil or if values are equal
    def self.between(prev_badges:, curr_badges:)
      events = []
      if !prev_badges.nil? && !curr_badges.nil? && prev_badges != curr_badges
        if curr_badges > prev_badges
          ((prev_badges + 1)..curr_badges).each { |n| events << BadgeGained.new(gym_number: n) }
        else
          ((curr_badges + 1)..prev_badges).each { |n| events << BadgeLost.new(gym_number: n) }
        end
      end
      Result.new(badge_events: events)
    end
  end
end
```

The `Result` struct is the extension point. Future categories add `catch_events:` / `evolution_events:` as new keyword fields. Existing call sites that only care about badges keep working.

#### Layer B — coordinator (`app/services/soul_link/gym_beaten_coordinator.rb`)

```ruby
module SoulLink
  class GymBeatenCoordinator
    # @param slot [SoulLinkEmulatorSaveSlot] the slot whose parse just produced events
    # @param events [Array<SaveDiff::BadgeGained, SaveDiff::BadgeLost>] from SaveDiff.between
    def self.process(slot, events)
      run = slot.soul_link_emulator_session&.soul_link_run
      return if run.nil? || !run.active?

      events.each do |event|
        case event
        when SoulLink::SaveDiff::BadgeGained
          attempt_auto_mark(run, event.gym_number)
        when SoulLink::SaveDiff::BadgeLost
          Rails.logger.info(
            "GymBeatenCoordinator: BadgeLost gym_number=#{event.gym_number} " \
            "run=#{run.id} session=#{slot.soul_link_emulator_session_id} — no auto-unmark"
          )
        end
      end
    end

    def self.attempt_auto_mark(run, gym_number)
      return if run.gym_results.exists?(gym_number: gym_number)            # already marked
      return if run.gym_auto_mark_suppressions.exists?(gym_number: gym_number)  # suppressed
      return unless all_players_have_badge?(run, gym_number)

      run.gym_results.create!(gym_number: gym_number, beaten_at: Time.current)
      run.update!(gyms_defeated: [run.gyms_defeated, gym_number].max)
    end

    def self.all_players_have_badge?(run, gym_number)
      sessions = run.soul_link_emulator_sessions.includes(:save_slots)
      return false if sessions.empty?
      sessions.all? { |s| s.active_slot&.parsed_badges.to_i >= gym_number }
    end
  end
end
```

**Design notes:**
- Pure-static service (no AR ancestry, no instance state). Same shape as `SoulLink::SaveParser`.
- `attempt_auto_mark` runs all three guards in priority order: idempotency → suppression → all-4 gate. Each early-returns silently.
- The all-4 check uses **all sessions in the run**, not just sessions belonging to a specific guild user. If a run has 3 sessions instead of 4 (e.g., player hasn't generated their ROM yet), the check returns false until the 4th joins and saves with the badge.
- `gyms_defeated` bump matches the manual `mark_beaten` controller's semantics (`[current, gym_number].max`) so auto-mark doesn't accidentally regress the counter if events arrive out of order.
- Wraps the `gym_results.create!` and `gyms_defeated` update in a single AR transaction — both succeed or both roll back. Use `run.transaction { ... }`. (Existing manual paths don't bother because they're sequential controller actions, but the coordinator's call is atomic by intent.)

#### Layer C — dispatch from the parse job

`app/jobs/soul_link/parse_save_data_job.rb` is the only call site. Modify `perform` to:

1. Capture `prev_parsed_at = slot.parsed_at` AND `prev_badges = slot.parsed_badges` BEFORE writing the new parse result.
2. Run `SaveParser.parse` as today.
3. Build `attrs`:
   - **On success:** all five `parsed_*` fields + `parsed_at: Time.current` (unchanged from today).
   - **On failure (KG-13 fix):** **only** `parsed_at: Time.current`. Do NOT zero or nil any other `parsed_*` field. Use `slot.update_columns(parsed_at: Time.current)` and skip the rest.
4. After `update_columns`, run the diff IFF `prev_parsed_at.present?`:
   ```ruby
   if prev_parsed_at.present?
     diff = SoulLink::SaveDiff.between(prev_badges: prev_badges, curr_badges: result&.badges_count)
     SoulLink::GymBeatenCoordinator.process(slot, diff.badge_events) unless diff.empty?
   end
   ```
5. Result struct accessor: today's `Result.badges_count` is the integer count — that's what `SaveDiff.between` consumes. No parser changes needed.

**Why dispatch lives in the job (not a separate job):** the job already owns the "after-parse" lifecycle and has both prev and curr values in scope. A separate job would need to re-fetch the slot and either capture prev via params (race-prone) or re-derive from previous_changes (which the job's own `update_columns` writes don't populate the way callbacks do). Keeping it in-job is simpler. The diff itself is pure and test-isolated; the coordinator is a separate service that's also unit-testable in isolation. The pattern is `(parse → write → dispatch)` mirroring the `(parse → return Result)` purity split the existing parser uses.

#### Layer D — suppression record

**New table:**
```ruby
class CreateGymAutoMarkSuppressions < ActiveRecord::Migration[8.1]
  def change
    create_table :gym_auto_mark_suppressions do |t|
      t.references :soul_link_run, null: false, foreign_key: true
      t.integer :gym_number, null: false
      t.timestamps
    end
    add_index :gym_auto_mark_suppressions, [:soul_link_run_id, :gym_number], unique: true
  end
end
```

**New model `app/models/gym_auto_mark_suppression.rb`:**
```ruby
class GymAutoMarkSuppression < ApplicationRecord
  belongs_to :soul_link_run

  validates :gym_number, presence: true,
            inclusion: { in: 1..8 },
            uniqueness: { scope: :soul_link_run_id }
end
```

**Wire `has_many` on `SoulLinkRun`:**
```ruby
has_many :gym_auto_mark_suppressions, dependent: :destroy
```

#### Layer E — UNMARK / MARK BEATEN integration

`GymProgressController#update` (`app/controllers/gym_progress_controller.rb`) is the existing dashboard mark/unmark toggle. Two integration points:

- **Unmark branch (line 23, the `existing.destroy!` path):** after destroy + `gyms_defeated` recompute, also create the suppression record:
  ```ruby
  run.gym_auto_mark_suppressions.find_or_create_by!(gym_number: gym_number)
  ```
  `find_or_create_by!` makes it idempotent against double-clicks.

- **Mark branch (line 28, the `gym_results.create!` path):** after the create, also clear any matching suppression:
  ```ruby
  run.gym_auto_mark_suppressions.where(gym_number: gym_number).destroy_all
  ```

**`GymDraftsController#mark_beaten` (line 92)** is the post-draft mark path. **Same change:** clear any matching suppression after `gym_results.create!`. (Future-proof: if the gym was somehow auto-suppressed before the draft completed, completing the draft is an explicit re-engagement signal.)

#### Layer F — real-time dashboard refresh

Today, `GymResult` does NOT broadcast. The dashboard re-renders from `@gym_results = run.gym_results.index_by(&:gym_number)` on each page render but doesn't auto-update. After this step, a player saves their game → coordinator creates a `gym_results` row in the background → other players' open dashboards must see the gym update without a full reload.

**Add to `GymResult` (mirrors the Step 9 KG-2 pattern on `SoulLinkPokemon`):**
```ruby
broadcasts_refreshes_to ->(record) { [record.soul_link_run, :dashboard] }
```

Manual mark/unmark via `GymProgressController` already triggers this (because the controller calls `create!`/`destroy!`). Auto-mark from the coordinator goes through the same `create!`, so the broadcast covers both paths.

### Out of Scope (do NOT expand)

- **Categories 2 (gym battle teams) and 3 (catches+routes).** Both require Gen-IV PKM decryption (PID-shuffle + LCG XOR). Not this step. Not even partial scaffolding.
- **A "3/4 players have it" UI indicator.** PO explicitly said "no UI flicker, no premature mark." Gym stays in current state until all-4 condition is met.
- **Auto-unmark.** `BadgeLost` events log only. The PO will design the un-detection flow later if it ever matters.
- **Per-player auto-mark tracking** (e.g., showing "Player A has the badge, Players B/C/D do not"). Decision was option (b), not option (c) — no per-player schema additions.
- **Re-engaging auto-tracking via a button.** Manual MARK BEATEN is the re-engagement signal. No separate "clear suppression" UI affordance.
- **Time-based suppression expiry.** Suppression persists indefinitely until a manual MARK BEATEN clears it.
- **Migration to make `parsed_badges` nullable.** Decision 7+9 means the existing `default: 0, null: false` schema stays. Diff baseline is gated by `parsed_at`.
- **Adding `parsed_badge_bits` raw-bitfield column.** Per decision 7, count semantics suffice for legitimate play.
- **Refactoring `parse_save_data_job.rb`'s failure-path attribute hash.** KG-13 fix is targeted: replace the failure branch with a one-line `update_columns(parsed_at: Time.current)`. Do not "improve" the success branch's hash structure while you're in there.
- **Tests for `parse_save_data_job` race conditions** (concurrent slot updates). The existing parse job has no concurrency tests; staying within that envelope. Document as a known concern in BUILD-LOG if you discover anything surprising in testing.
- **Logging infrastructure beyond `Rails.logger.info` for BadgeLost.** No new structured logging, no telemetry hooks, no metric counters.
- **Bot integration of auto-mark events.** The Discord bot doesn't surface auto-mark today; out of scope.
- **Backfill on existing data.** Existing slots have `parsed_at` set + `parsed_badges = 0` from prior runs. The `parsed_at.present?` gate means their NEXT parse will run the diff against `prev_badges = 0`. If a save with N>0 badges lands, that fires N events. **Acceptable**: any existing run is either (a) freshly imported with 0 badges, in which case 0 is correct, or (b) already mid-run with auto-detection wanted. The PO can RESET DRAFT or manually unmark if a spurious event lands. Document this as a one-time migration consideration in BUILD-LOG.

### Constraints / Flags

- **`parsed_badges` count semantics, not raw bits.** Bob: do not introduce a `parsed_badge_bits` column. Use `>= gym_number` for "has the badge" check.
- **`SaveDiff` stays pure.** No `Rails.logger`, no AR access, no `Time.current`. Pure function on integers + nils. The coordinator does the side effects.
- **Coordinator is a static service.** No instance state, no class instance vars. Mirrors `SaveParser`.
- **Transaction wraps the auto-mark.** `run.transaction { create! gym_results; update! gyms_defeated }`. Single atomic unit.
- **Suppression check is a `WHERE EXISTS` lookup, not loaded relation.** Use `run.gym_auto_mark_suppressions.exists?(gym_number: N)` to avoid loading the whole collection on every event.
- **`prev_parsed_at` capture is BEFORE `update_columns`.** Easy to get wrong — capture must read the DB-current value, not the about-to-be-written one.
- **KG-13 fix branches on `result.nil?`** in the parse job, not on `attrs.values.any?(&:nil?)` or anything fragile. The parser's contract is "Result on success, nil on failure" — branch on that exactly.
- **Idempotency:** `gym_results.exists?(gym_number: N)` check is the first guard in `attempt_auto_mark`. Critical — without it, every save event re-fires `create!` and bombs on the unique index.
- **No new gems.** All requirements satisfied by existing dependencies.
- **Rubocop must stay clean** (Step 14 ended at 152 files, 0 offenses).
- **`bundle exec rubocop` AND `bin/rails test`** must both be clean before signaling Ready for Review.
- **Bob: read the audit before coding.** `handoff/2026-05-02-sram-auto-tracking-audit.md` has the full architectural rationale; this brief is the spec for Step 15 specifically.

### Acceptance Criteria

- New migration: `create_gym_auto_mark_suppressions`.
- New model: `app/models/gym_auto_mark_suppression.rb`.
- New service: `app/services/soul_link/save_diff.rb` — pure function with `Result` struct + `BadgeGained` / `BadgeLost` event classes.
- New service: `app/services/soul_link/gym_beaten_coordinator.rb` — static class with `.process(slot, events)` + `.attempt_auto_mark(run, gym_number)` + `.all_players_have_badge?(run, gym_number)`.
- `app/jobs/soul_link/parse_save_data_job.rb`:
  - Captures `prev_parsed_at` and `prev_badges` before update.
  - Failure branch only updates `parsed_at` (KG-13 fix).
  - After update, calls `SaveDiff.between` and `GymBeatenCoordinator.process` if `prev_parsed_at.present?`.
- `app/models/gym_result.rb`: `broadcasts_refreshes_to ->(record) { [record.soul_link_run, :dashboard] }` added.
- `app/models/soul_link_run.rb`: `has_many :gym_auto_mark_suppressions, dependent: :destroy` added.
- `app/controllers/gym_progress_controller.rb`:
  - Unmark branch creates `find_or_create_by!` suppression after destroy.
  - Mark branch destroys matching suppression after create.
- `app/controllers/gym_drafts_controller.rb#mark_beaten`: destroys matching suppression after create.

**Tests (mandatory, not optional):**

1. **`SaveDiff.between` — nil prev → empty.** `SaveDiff.between(prev_badges: nil, curr_badges: 5).badge_events == []`.
2. **`SaveDiff.between` — nil curr → empty.** Same shape.
3. **`SaveDiff.between` — equal → empty.** `(prev: 3, curr: 3).badge_events == []`.
4. **`SaveDiff.between` — +1 badge → 1 BadgeGained.** `(prev: 3, curr: 4)` → `[BadgeGained(gym_number: 4)]`.
5. **`SaveDiff.between` — +2 badges → 2 BadgeGained, sequential.** `(prev: 3, curr: 5)` → `[BadgeGained(4), BadgeGained(5)]` in order.
6. **`SaveDiff.between` — -1 badge → 1 BadgeLost.** `(prev: 5, curr: 4)` → `[BadgeLost(5)]`.
7. **`SaveDiff.between` — full reset (prev: 8, curr: 0) → 8 BadgeLost events.** Sequential gyms 1..8 in BadgeLost order. (The order doesn't strictly matter for behavior but the test pins it.)
8. **`SaveDiff.between` — full claim (prev: 0, curr: 8) → 8 BadgeGained events.** Same shape, opposite direction.

9. **`GymBeatenCoordinator.process` — BadgeGained, 4/4 players have it, no suppression, no existing → creates `gym_results` and bumps `gyms_defeated`.** Use factories to set up the run with 4 sessions, each with a slot at `parsed_badges = 4`.
10. **`GymBeatenCoordinator.process` — 3/4 players have it → no `gym_results` created.** Assert count unchanged.
11. **`GymBeatenCoordinator.process` — 4/4 but `gym_results` already exists → no-op.** Idempotent.
12. **`GymBeatenCoordinator.process` — 4/4 but suppression exists → no-op.** Suppression respected.
13. **`GymBeatenCoordinator.process` — BadgeLost → no `gym_results` mutation.** Assert no create, no destroy. Optionally assert log line emitted (use `assert_logs` helper if present, else skip the log assertion).
14. **`GymBeatenCoordinator.process` — inactive run → no-op.** Defensive guard.
15. **`GymBeatenCoordinator.process` — 0 sessions → no-op (cannot satisfy all-4 with empty set).** Edge case from `sessions.empty?` guard.
16. **`GymBeatenCoordinator.attempt_auto_mark` — wraps create+update in a transaction.** Stub `gyms_defeated` update to raise; assert `gym_results` count unchanged after rescue.
17. **`GymBeatenCoordinator.process` — multi-event sequence (gym 1 then gym 2).** When the same player's save jumps 0→2, two events run; both are auto-marked if all-4 satisfy. Assert two `gym_results` rows.

18. **`ParseSaveDataJob` — first-ever parse (`parsed_at` was nil) → no diff dispatch.** Assert `GymBeatenCoordinator.process` is NOT called. Use mocha or assert_no_difference on `gym_results.count`.
19. **`ParseSaveDataJob` — subsequent successful parse, badges unchanged → diff dispatched but events empty → coordinator no-op.** Assert no `gym_results` change.
20. **`ParseSaveDataJob` — subsequent parse, badges +1, 4/4 satisfy → `gym_results` row created.** Integration test through the job.
21. **`ParseSaveDataJob` — KG-13: parse failure leaves `parsed_badges` and other parsed_* alone, only updates `parsed_at`.** Set up a slot with parsed_badges=5; stub `SaveParser.parse` to return nil; assert `parsed_badges` is still 5 after, but `parsed_at` is fresh.
22. **`ParseSaveDataJob` — KG-13: parse failure → no diff dispatch (because event would be spurious).** Or equivalently, the failure path skips the diff entirely. Test for no `gym_results` change.

23. **`GymProgressController#update` — unmark creates suppression.** Existing test should still pass for unmark behavior; add assertion that `gym_auto_mark_suppressions.count` increases by 1.
24. **`GymProgressController#update` — mark clears matching suppression.** Set up a suppression for gym N; mark gym N; assert suppression is gone.
25. **`GymDraftsController#mark_beaten` — clears matching suppression.** Same shape.

26. **Integration / system test — 4 player saves landing in sequence, 4th triggers the auto-mark.** Set up a run with 4 sessions + 4 slots all at `parsed_badges = 0` and `parsed_at = 1.minute.ago`. Update each slot's `save_data` with a fixture (or stub SaveParser to return badges_count=1) ONE AT A TIME, calling `ParseSaveDataJob.perform_now(slot)` after each. Assert: after slots 1, 2, 3 → no `gym_results`. After slot 4 → `gym_results.count == 1, gym_number: 1`.

**~26 new tests.** Step 14 ended at 370 tests. Step 15 should land somewhere in the 395-405 range. If lower, Bob is under-testing edge cases.

**Diff scope:**
- 1 migration (suppressions table)
- 1 new model (`gym_auto_mark_suppression.rb`)
- 1 new service (`save_diff.rb`)
- 1 new service (`gym_beaten_coordinator.rb`)
- 1 modified job (`parse_save_data_job.rb`)
- 1 modified model (`gym_result.rb` for broadcasts_refreshes_to)
- 1 modified model (`soul_link_run.rb` for has_many)
- 2 modified controllers (`gym_progress_controller.rb`, `gym_drafts_controller.rb`)
- 4 new test files: `save_diff_test.rb`, `gym_beaten_coordinator_test.rb`, additions to `parse_save_data_job_test.rb`, additions to `gym_progress_controller_test.rb` + `gym_drafts_controller_test.rb`
- 1 factory (`gym_auto_mark_suppressions.rb` for FactoryBot)
- 4 handoff files (REVIEW-REQUEST, BUILD-LOG, ARCHITECT-BRIEF stays this content, SESSION-CHECKPOINT)

Anything else is a Reviewer Condition.

### Files Bob Should Read

- `handoff/2026-05-02-sram-auto-tracking-audit.md` — full read; this is the architectural rationale.
- `app/services/soul_link/save_parser.rb` — full (the pattern to mirror for SaveDiff/coordinator purity).
- `app/jobs/soul_link/parse_save_data_job.rb` — full (will be modified).
- `app/models/soul_link_emulator_save_slot.rb` — full (the after_update_commit lifecycle).
- `app/models/soul_link_emulator_session.rb` — first 110 lines (`active_slot`, save_slots relation).
- `app/models/soul_link_run.rb` — full (has_many wiring + `current` scope + `active?`).
- `app/models/gym_result.rb` — full.
- `app/controllers/gym_progress_controller.rb` — full.
- `app/controllers/gym_drafts_controller.rb` — first 110 lines (the `mark_beaten` action + neighbors).
- `db/schema.rb` — grep the existing `gym_*` and `soul_link_emulator_*` tables; check the `parsed_*` columns on `soul_link_emulator_save_slots`.
- `test/jobs/soul_link/parse_save_data_job_test.rb` — full (existing patterns).
- `test/factories/soul_link_emulator_save_slots.rb` — full.
- `test/controllers/save_slots_controller_test.rb` — first 60 lines (factory usage patterns for slots).
- One existing service test like `test/services/soul_link/save_parser_test.rb` — first 80 lines (the static-method test pattern).

DO NOT load:
- The Gen-IV PKM decryption references — out of scope for this step.
- The gym-draft model/channel/views — out of scope this step.
- The Discord bot code.
- The dashboard view layouts beyond what `gym_results` rendering requires.
- The emulator/save-slot UPLOAD flow (controllers/save_slots_controller.rb beyond factory patterns).

### Files Bob Should Update at the End

- `handoff/REVIEW-REQUEST.md` — files-changed table, self-review answers covering EVERY constraint flag above plus the 12 reviewer focus areas in the Notes section, open questions if any, `Ready for Review: YES`.
- `handoff/BUILD-LOG.md` — Step 15 history entry following Step 12-14 structure. Note: `SaveDiff` + `GymBeatenCoordinator` + `GymAutoMarkSuppression` are NEW SURFACES introduced this step; call them out as architecture decisions in the durable section since they shape categories 2 and 3 down the road.

---

## Notes for Reviewer (Richard)

When this lands on your desk, focus on:

1. **`SaveDiff` is genuinely pure.** No `Rails.logger`, no AR queries, no `Time.current` calls. Single integer-arithmetic function. Grep `app/services/soul_link/save_diff.rb` for `Time`, `logger`, `find`, `where`, `update`, `create` — all should be ZERO hits.

2. **All-4 check guards against both empty sessions and missing `active_slot`.** `sessions.empty?` returns false from `all?`, but if a session has no `active_slot` (player generated ROM but never saved), `s.active_slot&.parsed_badges.to_i` is `0`, which fails the `>= gym_number` check correctly. Confirm this branch is tested.

3. **Idempotency guards execute in priority order.** The order is (a) gym already marked, (b) suppression exists, (c) all-4 satisfy. Reordering changes behavior — confirm the implementation matches the brief's listed order.

4. **Transaction wraps the create + update.** Look for `run.transaction do ... end` or equivalent in `attempt_auto_mark`. If `gyms_defeated` update fails for any reason, the `gym_results` row should NOT persist. Test 16 covers this.

5. **`parsed_at` baseline gate is BEFORE the parse runs, not after.** Easy mistake: capturing `prev_parsed_at` after the new parse has updated it would always make `prev_parsed_at` non-nil, defeating the first-parse skip. Test 18 covers this.

6. **KG-13 fix is precise.** On parse failure, `parse_save_data_job.rb` calls `slot.update_columns(parsed_at: Time.current)` and nothing else. Specifically, `parsed_badges` is NOT touched, NOT zeroed, NOT nil-ed. Test 21 covers this.

7. **No spurious `BadgeLost` events from the failure path.** Failure path skips the diff dispatch entirely (because there's no curr value to diff against). Alternatively, the diff is called but with `curr_badges: nil` which short-circuits to `[]`. Either implementation is acceptable; test 22 confirms behavior.

8. **Suppression is keyed on `(run_id, gym_number)`, unique index enforces it.** Test 23 should rely on this — `find_or_create_by!` is the right primitive; `create!` would raise on the second invocation.

9. **`GymResult.broadcasts_refreshes_to` mirrors the Step 9 KG-2 pattern.** Same callable-form lambda, same `:dashboard` channel. Confirm the auto-mark path actually triggers the broadcast — there's a Turbo::Streams test pattern for this in the existing codebase.

10. **The down-event log line is at `info` level, not `warn` or `error`.** This is normal user behavior (loading an older save state); not a problem to surface to ops.

11. **Coordinator dispatch is wrapped in the parse job's existing rescue/return-nil pattern.** If the coordinator raises (e.g., a stale `gyms_defeated` race), the parse job should still complete successfully — the parse data itself is already written via `update_columns` before the dispatch runs. Confirm the parse job doesn't bubble coordinator exceptions in a way that retries the parse work.

12. **Diff scope holds.** No category-2 or category-3 scaffolding sneaks in — no `met_locations.yml`, no PartyParser stub, no PKM decryption code. If Bob "while I'm here"-d any of those, flag it.

Out-of-scope items found during review → BUILD-LOG Known Gaps. Do not bundle.
