# Review Feedback — Step 15
Date: 2026-05-02
Ready for Builder: YES

## Must Fix

None.

## Should Fix

- `app/jobs/soul_link/parse_save_data_job.rb:70` — There is no rescue
  around `SoulLink::GymBeatenCoordinator.process(...)`. If the
  coordinator raises (e.g., a stale-`gyms_defeated` race causes
  `update!` to fail validation rather than rolling back inside the
  transaction), the exception bubbles to ActiveJob and the job is
  retried by the queue. Bob's self-review #11 argues retry is safe
  because `prev_parsed_at` and `prev_badges` are already at the
  written values on retry, so `SaveDiff.between(prev: N, curr: N)`
  short-circuits to an empty Result and the coordinator is never
  invoked again. This is correct as long as the parse `result` is
  identical (deterministic for the same `save_data`). It also means
  `update_columns` re-runs idempotently against unchanged columns.
  Recommendation: either pin this property with a regression test
  (`assert_no_difference "@run.gym_results.count" do; 2.times { ... }
  end` after a coordinator stub raises once and then succeeds), or
  wrap the dispatch in a small `rescue StandardError => e;
  Rails.logger.error(...); end` so a coordinator-level bug never gets
  re-driven by ActiveJob retries. Either makes the brief's focus area
  #11 ("doesn't bubble in a way that retries the parse") explicit
  rather than implicit. Inline-fix scale; not blocking.

- `test/services/soul_link/gym_beaten_coordinator_test.rb:111-125` —
  The transaction-rollback test stubs `update!` to raise
  `ActiveRecord::Rollback`, which is silently swallowed by
  `run.transaction { ... }`. The wrapping `begin/rescue
  ActiveRecord::Rollback` in the test is dead code — `transaction`
  catches `Rollback` itself and returns `nil`. The test still
  exercises the right behavior (the `gym_results.count` assertion
  passes because the row was rolled back), but a future maintainer
  reading it might think `Rollback` propagates. Stronger test:
  stub `update!` to raise something that's NOT a Rollback (e.g.
  `ActiveRecord::RecordInvalid` or even `RuntimeError`), then assert
  the transaction still rolls the create back. That proves the
  transaction actually wraps both writes rather than only succeeding
  because Rails happens to swallow `Rollback`. Inline-fix scale.

- `test/services/soul_link/gym_beaten_coordinator_test.rb:67-73` —
  `BadgeLost is a no-op` creates a pre-existing `gym_results` row
  (line 68) and asserts `assert_no_difference` on the count. That
  pins "no destroy", but it doesn't pin "no log line lost / no log
  level wrong" (focus area #10). The brief at item 13 explicitly
  flags `Optionally assert log line emitted (use assert_logs helper
  if present, else skip)`. Bob skipped both. Recommendation: assert
  the `info` log line gets emitted via
  `assert_logs(:info, /BadgeLost/) { ... }` or an `ActiveSupport::TaggedLogging`
  capture. If no helper exists, leave it — the focus-area requirement
  is met by code inspection of `gym_beaten_coordinator.rb:36`. Nit-y,
  not blocking.

## Escalate to Architect

None.

## Cleared

All 12 reviewer focus areas pass. Independent verification:

- **Tests:** `bundle exec rails test` → 396 runs, 0 failures, 0
  errors, 0 skips. Matches Bob's claim of 370 → 396 (+26 net).
  Cross-referenced the brief's numbered acceptance-criteria tests
  1-26 against the test files: SaveDiff #1-8 in `save_diff_test.rb`,
  Coordinator #9-17 in `gym_beaten_coordinator_test.rb` (plus one
  bonus "missing active_slot" test for focus area #2),
  ParseSaveDataJob #18-22 in `parse_save_data_job_test.rb`,
  controller #23-25 in `gym_progress_controller_test.rb` and
  `gym_drafts_controller_test.rb`, and the integration test #26 in
  `parse_save_data_job_test.rb:209`. Every numbered item has a
  corresponding test.

- **Lint:** `bundle exec rubocop` → 0 offenses across 159 files.
  Matches Bob's claim. The 7-file delta over Step 14's 152 lines up
  with: 1 migration + 1 model + 1 factory + 2 services + 2 service
  test files = 7.

Focus areas:

1. `app/services/soul_link/save_diff.rb` — pure. Grep against
   `Rails\.|Time\.|logger|find|where|update|create` returns only the
   doc-comment hits at lines 6-7. The `between` function is integer
   arithmetic with nil short-circuits and a `Result` struct return.
   No AR, no clock, no logger.

2. `app/services/soul_link/gym_beaten_coordinator.rb:68-72` — the
   all-4 check guards both branches: explicit `return false if
   sessions.empty?` (line 70) blocks vacuous `all? -> true` on an
   empty relation, and `s.active_slot&.parsed_badges.to_i >=
   gym_number` returns `0 >= N` (false) when `active_slot` is nil.
   Tests at `gym_beaten_coordinator_test.rb:86-99` (0 sessions) and
   `:101-107` (no active_slot) exercise both paths.

3. `gym_beaten_coordinator.rb:51-54` — guards execute in priority
   order top-to-bottom: (a) `gym_results.exists?`, (b)
   `gym_auto_mark_suppressions.exists?`, (c)
   `all_players_have_badge?`. Each early-returns silently. Tests at
   coordinator test lines 47, 56, 35-43 cover each guard
   independently.

4. `gym_beaten_coordinator.rb:56-59` — `run.transaction do
   create!; update!; end` wraps both writes. Test at coordinator
   test lines 111-125 confirms a failed `update!` rolls the
   `gym_results.create!` back (see Should Fix above for a
   suggestion to make the test stronger).

5. `app/jobs/soul_link/parse_save_data_job.rb:35-36` — `prev_parsed_at`
   and `prev_badges` are captured BEFORE the `SaveParser.parse` call
   on line 38 and the subsequent `update_columns` on line 41. Test
   at `parse_save_data_job_test.rb:139-156` (`first-ever parse`)
   asserts the diff is NOT dispatched on the first parse — if the
   capture were after `update_columns`, this would fail because
   `parsed_at` would always be non-nil.

6. `parse_save_data_job.rb:50-56` — KG-13 failure branch reads
   `slot.update_columns(parsed_at: Time.current); return`. Only
   `parsed_at` is touched; every other `parsed_*` column keeps its
   prior value. Test at `parse_save_data_job_test.rb:45-68`
   (`KG-13: parse failure leaves parsed_badges and other parsed_*
   alone`) sets `parsed_badges=5`, runs the failing parse, and
   asserts `parsed_badges == 5` post-job.

7. `parse_save_data_job.rb:56` — failure branch returns immediately
   BEFORE the diff dispatch on line 62. Test at
   `parse_save_data_job_test.rb:70-82` stubs
   `GymBeatenCoordinator.process` and asserts `assert_not called`
   when the parser returns nil.

8. `db/migrate/20260502191439_create_gym_auto_mark_suppressions.rb:8`
   — `add_index ... unique: true` on `[soul_link_run_id,
   gym_number]`. `gym_progress_controller.rb:29` uses
   `find_or_create_by!` against the index, so double-clicks
   (controller race) collapse to a single row. The
   `GymAutoMarkSuppression` model also validates `uniqueness:
   { scope: :soul_link_run_id }` for app-level enforcement.

9. `app/models/gym_result.rb:18` —
   `broadcasts_refreshes_to ->(record) { [ record.soul_link_run,
   :dashboard ] }`. Same callable-form lambda, same `:dashboard`
   channel, same overall shape as `app/models/soul_link_pokemon.rb:25`
   and `app/models/soul_link_pokemon_group.rb:20` (the Step 9 KG-2
   pattern). Manual MARK/UNMARK, post-draft mark-beaten, and
   coordinator auto-mark all create or destroy through this model,
   so the broadcast covers all three paths uniformly. Pattern parity
   on the missing dedicated test mirrors KG-2's missing dedicated
   test — accepted.

10. `gym_beaten_coordinator.rb:36-39` — `Rails.logger.info(...)` for
    BadgeLost. Not `warn`, not `error`. Loading an older save state
    is normal user behavior and shouldn't surface to ops dashboards.

11. `parse_save_data_job.rb:60-70` — The dispatch is fire-and-forget
    after `update_columns`. The parse data is already persisted
    BEFORE the dispatch runs, so a coordinator-level raise can't
    lose the parse work. On retry, the diff would be empty (curr ==
    prev) and the coordinator would not re-fire. See Should Fix
    above for a recommendation to make this property explicit (test
    or rescue).

12. Diff scope holds. Grep across `app/` and `test/` for
    `PartyParser`, `met_locations`, `PKM` returns zero hits. No
    category-2 or category-3 scaffolding sneaked in. The diff
    enumeration in REVIEW-REQUEST § "Diff Scope Validation"
    matches what's actually changed (verified against `git status`
    + `git diff --stat`):
    - 1 migration, 1 new model, 2 new services, 1 new factory,
      2 new test files
    - 1 modified job, 2 modified models, 2 modified controllers,
      3 extended test files, 1 schema dump
    - 2 handoff files (BUILD-LOG, REVIEW-REQUEST)
    Nothing outside the brief's listed surfaces.

Out-of-scope items the brief deferred (categories 2/3, "3/4 have it"
indicator, auto-unmark, per-player tracking, time-based suppression
expiry, `parsed_badge_bits` raw-bitfield column, refactor of the
parse-job success-branch hash, race-condition tests, structured
logging, bot integration, backfill migration) — all genuinely absent
from the diff. Bob's self-review § "Brief's Out-of-Scope Items (NOT
done)" lines up with the actual code changes.

Step 15 is clear.
