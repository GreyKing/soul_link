# Review Feedback — Step 19
Date: 2026-05-04
Ready for Builder: YES

## Must Fix

None. Each of the architect's ten focus areas was traced and the implementation
holds up.

## Should Fix

None.

## Nice to Have

- `app/services/soul_link/discord_notifier.rb:125-127` — the rescue list
  enumerates `RestClient::ExceptionWithResponse, RestClient::Exception,
  SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::EHOSTUNREACH,
  JSON::ParserError, StandardError`. Since `StandardError` is the superclass
  of every other entry, the explicit list is documentation, not behaviour.
  Bob comments this as "belt-and-suspenders." Fine as-is. If a future cleanup
  pass wants the comment without the redundancy, drop the specific classes
  and keep only `StandardError` plus a doc comment listing the expected
  failure modes.

- `app/views/dashboard/_runs_content.html.erb:40` uses `active_run` for the
  read-only check while `_pc_box_content`, `_pokemon_modal`, and
  `_gyms_content` use `@run`. When the user is viewing a *past* wiped run
  via `?run_id=N`, `@run` is the past run and the buttons hide on the
  dashboard — but those buttons would have operated on the active run
  server-side anyway (controllers all resolve
  `current_run = SoulLinkRun.current(guild_id)`). Cosmetic inconsistency
  only; v1 contract is "UI hide only" so server still enforces correctness.

## Notes (observations, not blocking)

- **Move-name YAML cross-check passed.** I pulled
  `kwsch/PKHeX/master/PKHeX.Core/Resources/text/other/en/text_Moves_en.txt`
  directly and compared rows 2, 34, 166, 258, 468 (move IDs 1, 33, 165, 257,
  467) against `config/soul_link/move_names.yml`. All five boundary samples
  match: 1=Pound, 33=Tackle, 165=Struggle, 257=Heat Wave, 467=Shadow Force.
  Three Gen-IV-only spot-checks (354=Psycho Boost, 400=Night Slash,
  428=Zen Headbutt) also match. The file has 467 entries, no gaps, no
  duplicates, IDs 1..467 contiguous. Bob's off-by-one resolution (extracting
  source lines 2..468 because line 1 is the "no move" sentinel) is correct.

- **WipeCoordinator idempotency is sound.** The
  `return if run.wiped_at.present?` inside the `with_lock` block returns
  from the enclosing `process` method (Ruby `do/end` block return semantics
  — confirmed). The notifier call is unreachable when the inner double-check
  fires. The transaction commits an empty changeset before the method
  unwinds, which is harmless. Race between two concurrent Mark Dead
  requests is correctly handled.

- **Wipe path notification fan-out verified.** In
  `pokemon_groups_controller.rb:79-85`: `notify_death` fires once per linked
  Pokemon (via `group.soul_link_pokemon.reload.each`), then
  `WipeCoordinator.process(run)` is called exactly once after the loop. The
  coordinator itself fires `notify_wipe` exactly once per nil→Time
  transition. So a 4-player linked group going dead produces 4
  deaths-channel messages + 1 general-channel wipe message. Correct per
  the brief.

- **Schema diff is clean.** `git diff origin/main -- db/schema.rb` shows
  only the version bump (2026_05_03_184058 → 2026_05_04_000001) and the
  new `t.datetime "wiped_at"` column on `soul_link_runs`. The pre-existing
  `add_foreign_key "gym_auto_mark_suppressions", "soul_link_runs"` line
  that Bob flagged in REVIEW-REQUEST §6 is preserved.

- **broadcast_state new key is harmless for now.**
  `run_management_controller.js` only reads
  `run_number / gyms_defeated / caught_count / dead_count / started_at /
  has_discord_channels / emulator_status`. The new `wiped_at` ride-along
  is unused client-side; the wipe banner is server-rendered via the
  `broadcasts_refreshes_to` Turbo refresh. Forward-looking key, minor
  payload bloat on every run mutation. Bob already flagged this in
  REVIEW-REQUEST §1.

- **Brakeman warnings are pre-existing.** `git diff origin/main` shows zero
  changes to `app/controllers/emulator_controller.rb` and
  `app/jobs/gym_schedule_discord_update_job.rb`. The two weak-confidence
  warnings (`emulator_controller.rb:79` SendFile,
  `gym_schedule_discord_update_job.rb:14` FileAccess) are not Step-19
  introductions.

- **Map-view "NEW CATCH" form is not gated.**
  `app/views/map/show.html.erb:228` has its own NEW CATCH form
  (timeline_controller#submitCatch) that isn't wrapped in
  `dashboard_read_only?`. The brief's affordance list named the dashboard
  surfaces explicitly; the map-view path is arguably a separate surface.
  Out of spec scope as written. Worth flagging to Ava for a
  product-decision call: do we want read-only mode to apply to the
  map-view catch form too? If yes, that's a follow-on KG, not a Step-19
  blocker.

- **All new tests use FactoryBot.** Verified across
  `wipe_coordinator_test.rb`, `discord_notifier_test.rb`,
  `game_state_move_names_test.rb`, `wipe_flow_test.rb`,
  `gym_beaten_coordinator_test.rb` (Step 19 additions),
  `catch_coordinator_test.rb` (Step 19 additions),
  `hall_of_fame_coordinator_test.rb` (Step 19 additions),
  `gym_progress_controller_test.rb` (Step 19 additions),
  `soul_link_run_test.rb` (Step 19 additions). No fixture references.

- **All five wipe scenarios (a)..(e) have dedicated tests.** Each named
  comment block in `wipe_coordinator_test.rb` ties to a brief scenario:
  (a) brand-new run no-wipe, (b) one-zero-alive triggers, (c) all-alive
  no-wipe, (d) idempotent re-run, (e) cleared-then-re-fired. Plus nil-run
  defense + most-recent-death route resolution.

- **`was_marked` precondition for gym team-beaten** is covered by the
  "fires only when the all-4 gate flips the gym" test (when not previously
  marked → fires) and "does NOT fire on idempotent re-run" test (when
  already marked → no fire). The latter is the precise precondition the
  architect called out.

- **Test environment caveat.** I could not run the test suite locally —
  the worktree's mise/bundler config resolves to Ruby 3.0.6 while the
  Gemfile.lock targets 3.4.5, producing a `Bundler::GemNotFound`.
  Reviewed the code structurally and trust Bob's reported
  `654 runs, 2011 assertions, 0 failures`. CI will be the canonical
  verification.

## Cleared

Reviewed: move_names.yml (boundary + spot-check + structural), DiscordNotifier
class + tests, WipeCoordinator class + tests, HallOfFameCoordinator
notify_run_complete wiring, GymBeatenCoordinator per-player + team-beaten
notification placement, GymProgressController manual MARK BEATEN/UNMARK
notification placement, CatchCoordinator notify_catch placement (party + box
paths), PokemonGroupsController death + wipe firing, SoulLinkRun model
additions (`wiped?`, `read_only?`, `broadcast_state[:wiped_at]`),
ApplicationHelper `dashboard_read_only?`, EmulatorHelper `format_move_name`,
the four dashboard view edits, `db/schema.rb` diff, the migration.

Step 19 is clear.
