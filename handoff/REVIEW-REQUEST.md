# Review Request
*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

Ready for Review: YES

---

## Step 15 — SaveDiff Infrastructure + Category 1 (Gyms-Beaten Auto-Detection) + KG-13 fix

**Builder:** Bob
**Tests:** 370 → 396 (+26). 0 failures, 0 errors. Exactly hits the brief's mandatory ~26 count.
**Lint:** `bundle exec rubocop` — 0 offenses across 159 files (was 152; +7 from new files).
**Migration:** `db/migrate/20260502191439_create_gym_auto_mark_suppressions.rb` — additive, no backfill.

---

## Files Changed

### Created (5)

| Path | Lines | Purpose |
|------|-------|---------|
| `db/migrate/20260502191439_create_gym_auto_mark_suppressions.rb` | 1-9 | Creates `gym_auto_mark_suppressions` table with FK to `soul_link_runs` and a unique composite index on `(soul_link_run_id, gym_number)`. Additive — no data backfill. |
| `app/models/gym_auto_mark_suppression.rb` | 1-17 | AR model. `belongs_to :soul_link_run`. Validates `gym_number` presence + 1..8 + uniqueness scoped to run (matches the DB unique index). Doc comment names the lifecycle (created on manual UNMARK, cleared on manual MARK BEATEN or post-draft mark-beaten). |
| `app/services/soul_link/save_diff.rb` | 1-58 | Pure-function diff layer. `Result` struct + `BadgeGained`/`BadgeLost` event classes. `SaveDiff.between(prev_badges:, curr_badges:)` returns a Result of events, [] when either side is nil or values are equal. Multi-bit jumps emit one event per gym in sequential order. NO `Rails.logger`, NO AR, NO `Time.current`. |
| `app/services/soul_link/gym_beaten_coordinator.rb` | 1-72 | Static service. `.process(slot, events)` consumes `SaveDiff` events; BadgeGained → `attempt_auto_mark`, BadgeLost → info log + no-op. `.attempt_auto_mark(run, gym_number)` runs three guards in priority order (idempotency → suppression → all-4 gate) and wraps create+counter-bump in a single transaction. `.all_players_have_badge?(run, gym_number)` checks every session's `active_slot&.parsed_badges.to_i >= gym_number`, returns false on empty session set. |
| `test/factories/gym_auto_mark_suppressions.rb` | 1-12 | FactoryBot factory; sequence on `gym_number` cycles 1..8 to avoid the unique-index collision until the 9th call. |
| `test/services/soul_link/save_diff_test.rb` | 1-67 | 8 SaveDiff unit tests: nil prev, nil curr, equal values, +1 (1 BadgeGained), +2 (2 BadgeGained sequential), -1 (1 BadgeLost), full reset (8 BadgeLost), full claim (8 BadgeGained). |
| `test/services/soul_link/gym_beaten_coordinator_test.rb` | 1-138 | 10 coordinator tests covering 4/4 satisfy → create + counter bump, 3/4 satisfy → no-op, idempotency (gym_results exists → no-op), suppression respected → no-op, BadgeLost is a no-op, inactive run guard, 0-sessions guard, missing-active-slot branch (focus area #2 explicit), transaction wrapping (focus area #4), multi-event sequence (gym 1 then gym 2 in one process call). |

### Modified (5)

| Path | Lines | Change |
|------|-------|--------|
| `app/jobs/soul_link/parse_save_data_job.rb` | 1-71 | KG-13 fix: failure branch went from a 7-line "zero everything" hash to `slot.update_columns(parsed_at: Time.current); return`. Added: capture `prev_parsed_at` and `prev_badges` BEFORE the parse, then dispatch `SaveDiff.between` + `GymBeatenCoordinator.process` IFF `prev_parsed_at.present?` (baseline rule). Branch on `result` (the parser's nil-on-failure contract) — exactly per the brief's constraint flag. |
| `app/models/gym_result.rb` | 1-22 | Added `broadcasts_refreshes_to ->(record) { [ record.soul_link_run, :dashboard ] }`. Mirrors the Step 9 KG-2 pattern on `SoulLinkPokemon`. Covers manual mark/unmark, post-draft mark-beaten, and the auto-mark path uniformly. |
| `app/models/soul_link_run.rb` | 7-9 | Added `has_many :gym_auto_mark_suppressions, dependent: :destroy`. Cascades suppression rows when a run is deleted. |
| `app/controllers/gym_progress_controller.rb` | 14-37 | Unmark branch creates a suppression via `find_or_create_by!` (idempotent against double-clicks). Mark branch destroys any matching suppression after the create. |
| `app/controllers/gym_drafts_controller.rb` | 91-103 | `mark_beaten` action destroys any matching suppression after the `gym_results.create!` (completing a draft is an explicit re-engagement signal). |

### Test files modified (3)

| Path | Change |
|------|--------|
| `test/jobs/soul_link/parse_save_data_job_test.rb` | REPLACED stale "writes nil-attrs and parsed_at when parser returns nil" (asserted the OLD KG-13-bug behavior) with the new KG-13 contract. ADDED 5 new tests: KG-13 no-spurious-diff dispatch on failure, first-ever-parse skip (baseline rule), badges-unchanged → no auto-mark, badges-+1-with-4/4 → 1 gym_results row, end-to-end integration (4 player saves landing in sequence, 4th triggers exactly 1 auto-mark). |
| `test/controllers/gym_progress_controller_test.rb` | ADDED 2 tests: unmark creates suppression, mark clears matching suppression. |
| `test/controllers/gym_drafts_controller_test.rb` | ADDED 1 test: mark_beaten clears matching suppression after creating the gym_results row. |

### Schema dump

| Path | Change |
|------|--------|
| `db/schema.rb` | Auto-regenerated by `db:schema:dump`. Adds `create_table "gym_auto_mark_suppressions"` block with the unique composite index and FK to `soul_link_runs`. |

### Handoff (2)

| Path | Change |
|------|--------|
| `handoff/BUILD-LOG.md` | New Step 15 entry under Step History; `Active step` updated; KG-13 moved to closed list; new "SRAM auto-tracking (locked 2026-05-02)" durable Architecture Decisions section added. |
| `handoff/REVIEW-REQUEST.md` | Overwritten with this Step 15 review request. |

---

## Self-Review — Brief's Constraint Flags

1. **`parsed_badges` count semantics, not raw bits.** No `parsed_badge_bits` column added. `GymBeatenCoordinator.all_players_have_badge?` uses `>= gym_number`. Confirmed in `app/services/soul_link/gym_beaten_coordinator.rb:67`.

2. **`SaveDiff` stays pure.** Verified via grep — `app/services/soul_link/save_diff.rb` has zero hits for `Rails.`, `logger`, `Time`, `find`, `where`, `update`, `create` outside doc comments. Pure integer arithmetic.

3. **Coordinator is a static service.** No `belongs_to`, no `include ActiveRecord::Base`, no instance state. Class methods only. Mirrors `SoulLink::SaveParser`.

4. **Transaction wraps the auto-mark.** `attempt_auto_mark` body uses `run.transaction { run.gym_results.create!(...); run.update!(gyms_defeated: ...) }`. Test 16 stubs `update!` to raise `ActiveRecord::Rollback` and asserts no `gym_results` row persists.

5. **Suppression check is a `WHERE EXISTS` lookup.** Uses `run.gym_auto_mark_suppressions.exists?(gym_number: N)` — single-row existence check, doesn't load the relation. Confirmed `gym_beaten_coordinator.rb:55`.

6. **`prev_parsed_at` capture is BEFORE `update_columns`.** `parse_save_data_job.rb:34-35` captures both `prev_parsed_at = slot.parsed_at` and `prev_badges = slot.parsed_badges` before line 39's `result = SoulLink::SaveParser.parse(...)`. Test 18 (`first-ever parse → no diff dispatch`) covers this — if we captured AFTER `update_columns`, the test would fail because `parsed_at` would always be non-nil.

7. **KG-13 fix branches on `result.nil?`.** Code reads `if result ... else ...` — Ruby's truthiness on `result` is exactly the parser contract (Result on success, nil on failure). Not `attrs.values.any?(&:nil?)` or anything fragile.

8. **Idempotency:** `gym_results.exists?(gym_number: N)` is the FIRST guard in `attempt_auto_mark`. Without it, every save event after the gym is marked would re-fire `create!` and bomb on the unique index. Test 11 covers this.

9. **No new gems.** `Gemfile` and `Gemfile.lock` untouched.

10. **Rubocop stays clean.** 0 offenses across 159 files (was 152; +7 = 1 migration + 1 model + 1 factory + 2 services + 2 service-test files).

11. **`bundle exec rubocop` AND `bin/rails test` both clean.** 396/396 passing, 0 failures, 0 errors. Rubocop 0/159.

12. **Read the audit before coding.** `handoff/2026-05-02-sram-auto-tracking-audit.md` was read in full. The audit's § 1 "Gyms beaten" maps line-for-line to this implementation; the audit's § 4 "two-layer dispatch" call is the architectural shape (SaveDiff + Coordinator).

---

## Self-Review — Reviewer's 12 Focus Areas

1. **`SaveDiff` is genuinely pure.** Grep confirms `app/services/soul_link/save_diff.rb` has zero hits for `Time`, `logger`, `find`, `where`, `update`, `create` outside doc comments. The diff function operates only on integer + nil inputs and returns plain Ruby structs.

2. **All-4 check guards against both empty sessions and missing `active_slot`.** Two explicit tests cover both branches: `0 sessions → all_players_have_badge? returns false (no auto-mark)` and `session with no active_slot → all_players_have_badge? returns false`. The `nil&.parsed_badges.to_i` chain returns 0 for the missing-slot case, which fails `>= gym_number` for any gym_number ≥ 1.

3. **Idempotency guards execute in priority order.** Code reads top-to-bottom in `attempt_auto_mark`: (a) `gym_results.exists?` → early return; (b) `gym_auto_mark_suppressions.exists?` → early return; (c) `all_players_have_badge?` → early return on false. Tests 11 (existing → no-op), 12 (suppression → no-op), 9-10 (all-4 → conditional on N=4) cover each guard independently.

4. **Transaction wraps the create + update.** `run.transaction { run.gym_results.create!(...); run.update!(gyms_defeated: ...) }` in `attempt_auto_mark`. Test 16 stubs `update!` to raise `ActiveRecord::Rollback` and asserts the `gym_results` count doesn't change after the rescue.

5. **`parsed_at` baseline gate is BEFORE the parse runs.** Lines 34-35 of `parse_save_data_job.rb` capture `prev_parsed_at` and `prev_badges` BEFORE line 39's `SaveParser.parse(...)`. Test 18 (`first-ever parse (parsed_at was nil) does not dispatch the diff`) directly exercises this — if the capture were AFTER `update_columns`, `prev_parsed_at` would always be non-nil and the dispatch would always fire.

6. **KG-13 fix is precise.** On parse failure, `parse_save_data_job.rb` calls `slot.update_columns(parsed_at: Time.current)` and **returns immediately**. `parsed_badges` is NOT touched. Test `KG-13: parse failure leaves parsed_badges and other parsed_* alone, only updates parsed_at` sets up a slot with `parsed_badges=5`, stubs the parser to return nil, runs the job, asserts `parsed_badges == 5` post-job.

7. **No spurious `BadgeLost` events from the failure path.** The job's failure branch returns BEFORE the diff dispatch. Test `KG-13: parse failure does not dispatch the diff (no spurious BadgeLost)` stubs `GymBeatenCoordinator.process` and asserts it's never called when the parser returns nil.

8. **Suppression keyed on `(run_id, gym_number)`, unique index enforces it.** Migration creates `add_index :gym_auto_mark_suppressions, [:soul_link_run_id, :gym_number], unique: true`. Controller uses `find_or_create_by!` so double-clicks are idempotent. The test `unmark beaten creates a gym_auto_mark_suppression for that gym` exercises this (no second test needed for double-click — the `find_or_create_by!` primitive guarantees the behavior).

9. **`GymResult.broadcasts_refreshes_to` mirrors the Step 9 KG-2 pattern.** Confirmed: same callable-form lambda (`->(record) { [ record.soul_link_run, :dashboard ] }`), same `:dashboard` channel name. Manual MARK/UNMARK + post-draft mark-beaten + auto-mark all create through `gym_results.create!` (or destroy through `existing.destroy!`), so the broadcast covers all three paths uniformly. No explicit broadcast-test added because the existing `SoulLinkPokemon`/`SoulLinkPokemonGroup` Step 9 broadcasts also have no dedicated tests — pattern parity.

10. **The down-event log line is at `info` level.** `Rails.logger.info(...)` in `GymBeatenCoordinator.process` for the BadgeLost branch. Not `warn`, not `error`. Loading an older save state is normal user behavior and not surfaced to ops.

11. **Coordinator dispatch wrapped in the parse job's existing flow.** The parse-data write happens via `update_columns` (line 41-48) BEFORE the dispatch runs (line 60). If `GymBeatenCoordinator.process` raises (stale `gyms_defeated` race, etc.), the parse data is already persisted — the parse work is not lost or retried. The `process` method itself doesn't re-raise (it iterates events and dispatches per event; case-on-event is total over the two known struct types). Worst case: a coordinator-level raise bubbles to the job runner, the job is marked failed in ActiveJob's queue, but the parse data is intact for the next save event to diff against.

12. **Diff scope holds.** No category-2 or category-3 scaffolding. No `met_locations.yml`, no `PartyParser` stub, no PKM decryption. Verified via grep — only files touched are exactly the files listed in the brief's "Diff scope" enumeration.

---

## Self-Review — Brief's Out-of-Scope Items (NOT done)

- **Categories 2 and 3** — no PKM decryption, no party parser, no met-locations table, no `gym_results.team_snapshot` writes.
- **"3/4 players have it" UI indicator** — not added. Gym stays in current state until 4/4.
- **Auto-unmark.** BadgeLost is log-only; no `gym_results.destroy!` from any auto path.
- **Per-player auto-mark tracking** — no `discord_user_id` column on `gym_results`; the run-level row is unchanged.
- **Re-engaging via a button** — manual MARK BEATEN is the re-engagement signal; no separate "clear suppression" UI affordance.
- **Time-based suppression expiry** — suppression persists indefinitely until cleared by a manual MARK BEATEN.
- **`parsed_badges` migration to nullable** — schema unchanged. Diff baseline gated by `parsed_at` instead.
- **`parsed_badge_bits` raw-bitfield column** — not added.
- **Refactoring the success-branch attribute hash** — only the failure branch is touched (KG-13 fix). Success-branch hash is kept structurally identical to before, with `update_columns(...)` called inline rather than via a temporary `attrs` hash.
- **Race-condition tests for `parse_save_data_job`** — no new concurrency tests; staying within the existing test envelope.
- **New structured logging / telemetry / metric counters** — only the brief's `Rails.logger.info` for BadgeLost.
- **Bot integration of auto-mark events** — no Discord bot changes.
- **Backfill migration on existing data** — none. Per the brief's analysis, the next parse on an existing slot will run the diff against `prev_badges = 0`; the all-4 gate keeps this safe (a single late-saving player can't trigger anything until everyone catches up).

---

## Open Questions

None. The brief was unambiguous and complete — every decision was locked.

---

## Diff Scope Validation

Per the brief's "Diff scope":

- **1 migration:** `create_gym_auto_mark_suppressions`. ✓
- **1 new model:** `gym_auto_mark_suppression.rb`. ✓
- **1 new service:** `save_diff.rb`. ✓
- **1 new service:** `gym_beaten_coordinator.rb`. ✓
- **1 modified job:** `parse_save_data_job.rb`. ✓
- **1 modified model (broadcasts_refreshes_to):** `gym_result.rb`. ✓
- **1 modified model (has_many):** `soul_link_run.rb`. ✓
- **2 modified controllers:** `gym_progress_controller.rb`, `gym_drafts_controller.rb`. ✓
- **4 new test files / additions:** `save_diff_test.rb` (NEW), `gym_beaten_coordinator_test.rb` (NEW), additions to `parse_save_data_job_test.rb`, additions to `gym_progress_controller_test.rb` + `gym_drafts_controller_test.rb`. ✓
- **1 factory:** `gym_auto_mark_suppressions.rb`. ✓
- **4 handoff files:** `BUILD-LOG.md`, `REVIEW-REQUEST.md` (this file). ARCHITECT-BRIEF.md and SESSION-CHECKPOINT.md are not Builder-owned mid-cycle.
- **Schema dump:** `db/schema.rb` auto-regenerated to include the new table (incidental — Rails always regenerates on `db:migrate` / `db:schema:dump`).

Nothing outside the brief's listed files. Zero scope expansion.

---

## Verification Commands

```bash
# Schema confirmed — gym_auto_mark_suppressions exists with the unique index
RAILS_ENV=test bin/rails runner "puts ActiveRecord::Base.connection.indexes('gym_auto_mark_suppressions').map(&:name)"

# SaveDiff purity — should return zero hits outside comments
grep -nE "Rails\.|logger|Time\.|find|where|update|create" app/services/soul_link/save_diff.rb

# Tests — 396/396 passing
RAILS_ENV=test bin/rails test

# Lint — 0 offenses across 159 files
bundle exec rubocop
```
