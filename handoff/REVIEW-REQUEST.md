# Review Request — Step 19

**Builder:** Bob
**Branch:** `claude/pedantic-jemison-e7d667` (worktree at `12cdde4` baseline; uncommitted)
**Ready for Review: YES**
**Scope:** Step 19 — Move-name lookup + Discord notifier + Wipe check (three sub-features bundled per ARCHITECT-BRIEF.md).

---

## Summary

Twenty modified files, eight new files. Full suite: **597 → 654 runs (+57); 1925 → 2011 assertions (+86)**. Rubocop clean (191 files, no offenses). Brakeman clean for Step 19 — two pre-existing weak-confidence warnings outside Step-19 scope (`emulator_controller.rb:79`, `gym_schedule_discord_update_job.rb:14`) unchanged.

The three features ship side-by-side and were built strictly left-to-right per the brief's Build order:
1. Move-name layer (move_names.yml + GameState + helper + view edit, closes KG-24)
2. DiscordNotifier service (six fire-and-forget methods, full rescue chain)
3. Wipe migration + run extension + WipeCoordinator + read-only UI (closes KG-17 via `notify_run_complete`)

---

## Per-file changes

### New files

- `config/soul_link/move_names.yml` — 467-entry Platinum move table (PKHeX `text_Moves_en.txt` lines 1..467 after the leading sentinel; cross-checked against pret/pokeplatinum `MOVE_SHADOW_FORCE = 467`). Header documents source + KG-24 closure.
- `app/services/soul_link/discord_notifier.rb` — class-only outgoing-message service; six public methods (`notify_catch`, `notify_death`, `notify_gym_player_progress`, `notify_gym_team_beaten`, `notify_wipe`, `notify_run_complete`); routes to `catches_channel_id` / `deaths_channel_id` / `general_channel_id` per decision 5; full rescue chain (`RestClient::ExceptionWithResponse, RestClient::Exception, SocketError, Errno::*, JSON::ParserError, StandardError`) → `Rails.logger.warn` and return; never raises.
- `app/services/soul_link/wipe_coordinator.rb` — `process(run)` walks `SoulLink::GameState.player_ids`, finds the first player with caught Pokemon AND zero alive, sets `wiped_at` inside `with_lock` (idempotent: outer guard + inner double-check), fires `notify_wipe` with the most recent dead Pokemon's location.
- `db/migrate/20260504000001_add_wiped_at_to_soul_link_runs.rb` — `add_column :soul_link_runs, :wiped_at, :datetime` (nullable, no index).
- `test/services/soul_link/game_state_move_names_test.rb` — 10 tests; mirrors `game_state_met_locations_test.rb` shape; locks ID 1=Pound / 33=Tackle / 467=Shadow Force from production YAML + ID-0 absence guard.
- `test/services/soul_link/discord_notifier_test.rb` — 23 tests; nil-run/nil-channel guards × 6 methods, channel routing × 6, message formatting × 7 (including `[off-feed]` suffix), REST exception swallow + logger.warn capture, generic `StandardError` swallow, blank-token short-circuit.
- `test/services/soul_link/wipe_coordinator_test.rb` — 7 tests covering the brief's (a)..(e) scenarios + nil-run defense + most-recent-death route resolution.
- `test/integration/wipe_flow_test.rb` — 2 end-to-end tests (PATCH `/pokemon_groups/:id` with `status: dead` → wipe fires + dashboard renders RUN ENDED banner + `+ NEW CATCH` affordance is hidden; counter-test where every player still has alive catches → no wipe).

### Modified files

- `app/services/soul_link/game_state.rb` — adds `MOVE_NAMES_PATH` constant, `move_names` (memoized loader, returns `{}` when absent), `move_name(id)` (nil-safe + integer coercion), `@move_names` reset in `reload!`.
- `app/helpers/emulator_helper.rb` — adds `format_move_name(id)` mirroring `format_map_name`'s shape; nil/zero short-circuit + "Move #N" fallback.
- `app/helpers/application_helper.rb` — adds `dashboard_read_only?(run)` single-source-of-truth helper for v1 UI gating.
- `app/views/dashboard/_pc_box_content.html.erb` — `MOVE n: #<id>` → `MOVE n: <format_move_name(id)>`; wraps `+ NEW CATCH` button in `unless dashboard_read_only?(@run)`.
- `app/views/dashboard/_runs_content.html.erb` — adds wipe banner (`💀 RUN ENDED — WIPED <date>`) above the gb-grid-4 stats when `dashboard_read_only?(active_run)`.
- `app/views/dashboard/_pokemon_modal.html.erb` — wraps `MARK DEAD` button in `unless dashboard_read_only?(@run)`.
- `app/views/dashboard/_gyms_content.html.erb` — wraps `START GYM DRAFT` (panel header), `MARK BEATEN` (next-gym row), and `UNMARK` (defeated-gym row) in `unless dashboard_read_only?(@run)`. Existing-draft RESET DRAFT button left visible per brief decision 11.
- `app/models/soul_link_run.rb` — adds `wiped?`, `read_only?` (`wiped_at.present? && !completed?`); `broadcast_state` now includes `wiped_at: wiped_at&.iso8601`.
- `app/services/soul_link/catch_coordinator.rb` — `create_pokemon_row` ends with `SoulLink::DiscordNotifier.notify_catch(...)` AFTER `create!`, inside the existing `slot.transaction { }`.
- `app/services/soul_link/gym_beaten_coordinator.rb` — for each `BadgeGained`: fires `notify_gym_player_progress` BEFORE the gate, captures `was_marked` pre-state, calls `attempt_auto_mark`, fires `notify_gym_team_beaten` AFTER if and only if the gym flipped (`!was_marked && now_marked`). `BadgeLost` notification surface: none.
- `app/services/soul_link/hall_of_fame_coordinator.rb` — fires `notify_run_complete(run)` once after `update!(completed_at: ...)`; idempotency guarded by the existing `completed_at.present?` early return.
- `app/controllers/pokemon_groups_controller.rb` — `update` (status=dead branch): after `mark_as_dead!`, iterates `group.soul_link_pokemon.reload` and fires `notify_death` per linked Pokemon, then calls `SoulLink::WipeCoordinator.process(run)`.
- `app/controllers/gym_progress_controller.rb` — MARK BEATEN create branch fires `notify_gym_team_beaten(run, gym_number)`. UNMARK branch fires nothing.
- `db/schema.rb` — version bumped to 2026_05_04_000001 + `wiped_at` column. Pre-existing dev-DB drift on `add_foreign_key "gym_auto_mark_suppressions", "soul_link_runs"` was re-added by hand to keep the diff scoped.
- `test/models/soul_link_run_test.rb` — +6 tests for `wiped?` / `read_only?` matrix (wiped only / completed only / both / neither) + `broadcast_state[:wiped_at]` ISO8601 format.
- `test/services/soul_link/catch_coordinator_test.rb` — +2 tests; happy-path catch fires `notify_catch` with `off_feed: false`, box-observed fires with `off_feed: true`.
- `test/services/soul_link/gym_beaten_coordinator_test.rb` — +4 tests: `BadgeGained` always fires per-player progress; team-beaten fires only when gate flips; team-beaten skipped on idempotent re-run; `BadgeLost` fires nothing. Also amended the "0 sessions" stub-double to expose `discord_user_id` (notifier reads it).
- `test/services/soul_link/hall_of_fame_coordinator_test.rb` — +2 tests: `notify_run_complete` fires on nil→Time transition; does NOT re-fire on idempotent call.
- `test/controllers/gym_progress_controller_test.rb` — +2 tests: MARK BEATEN fires `notify_gym_team_beaten`; UNMARK fires nothing.

---

## Decisions made for ambiguities in the brief

1. **Brief said `dead: false` column on Pokemon**, but the codebase uses `status: 'caught' / 'dead'`. Used `status:` (brief decision 10 also called this out as a correction; documented in code comments).

2. **Move-name source line numbering.** PKHeX's `text_Moves_en.txt` line 1 is `———` (the move-ID-0 sentinel); brief said "lines 1..467 with line 1 = Pound = move ID 1". Resolved by extracting the file's lines 2..468 (which represent move IDs 1..467); the YAML body has IDs 1..467 with no gaps, and ID 0 is intentionally omitted per brief decision 2.

3. **Read-only affordance gating list.** Brief decision 11 lists "EVOLVE button on group cards" and "Mark Dead trigger in `_caught_pokemon` partial" — neither exists in this codebase. The MARK DEAD trigger lives on the JS-controlled `_pokemon_modal.html.erb`; gated there. No EVOLVE control exists anywhere; nothing to gate. Rest of the listed affordances (NEW CATCH / MARK BEATEN / UNMARK / START GYM DRAFT) gated as specified. Recorded as a deviation rather than an ambiguity — the spec describes a UI surface that's slightly different from what's currently shipped; v1 contract is "hide what exists matching the spec's intent."

4. **Wipe-route fallback test.** Brief's coordinator decision 10 has `last_route = ... || "Unknown"`. The DB layer's NOT NULL on `soul_link_pokemon.location` + the AR `presence: true` validation make this branch unreachable through normal AR paths; I dropped the test that tried to exercise it (would require bypassing both layers via `update_columns` + DB-level shenanigans). Kept the `||` fallback in code as defense-in-depth and documented the reasoning in the test file.

5. **Tailwind asset pre-build for integration tests.** The `wipe_flow_test.rb` integration test renders the dashboard layout, which references `tailwind.css`. Pre-built once via `bundle exec rails tailwindcss:build` (output lives in `app/assets/builds/tailwind.css`, which is `.gitignore`'d already). CI builds tailwind as part of asset compilation, so this works there. Worth flagging in case the assets:builds dir is wiped between test runs locally.

6. **Schema drift fix.** `bin/rails db:migrate` re-dumped `db/schema.rb` and removed `add_foreign_key "gym_auto_mark_suppressions", "soul_link_runs"` (the dev DB doesn't have that FK installed). Restored the line by hand so the schema diff is just the `wiped_at` add + version bump. Pre-existing dev-DB drift, not a Step-19 change.

---

## Final verification

- **Test suite:** `654 runs, 2011 assertions, 0 failures, 0 errors, 0 skips`
- **Rubocop:** `191 files inspected, no offenses detected`
- **Brakeman:** `Errors: 0; Security Warnings: 2` — both pre-existing, unchanged: `emulator_controller.rb:79` (Weak-confidence SendFile, ROM download endpoint) and `gym_schedule_discord_update_job.rb:14` (Weak-confidence FileAccess on Net::HTTP URL with model attribute). Neither in Step-19 scope.

---

## Out-of-scope guard rails respected

- Did NOT touch `app/services/soul_link/discord_bot.rb` (the 978-LOC god-object).
- Did NOT add server-side authz checks for read-only mode (UI-hide only is the v1 contract; server enforcement is logged as a future KG per brief decision 11).
- Did NOT alter dispatch ordering in `SaveDiffDispatcher`.
- Did NOT add `ActiveSupport::Notifications` or other pub/sub indirection.
- Did NOT add a Discord webhook URL alternative.
- No fixture changes (FactoryBot only, per project standing rule).

---

## Open questions / follow-ups (not in scope but worth flagging)

1. **`broadcast_state` consumer audit.** The new `wiped_at` key flows out via the Turbo Stream broadcast on every `SoulLinkRun` update. I did not survey downstream JS/Stimulus consumers — none of the existing dashboard JS reads `broadcast_state` keys directly today, so this is a forward-looking signal, but worth a confirmation pass before deploy.

2. **Test-env assets pipeline.** The integration test depends on `app/assets/builds/tailwind.css` existing. CI runs `bundle exec rails assets:precompile` (or similar) before tests; locally, devs need to remember to `bundle exec rails tailwindcss:build` once after a clean checkout. Could be wired into a `bin/setup` step if the pattern is uncomfortable.

3. **KG-17 closure language.** Brief calls out that `notify_run_complete` closes KG-17 ("per-team HoF notification"). I did NOT update BUILD-LOG / SESSION-CHECKPOINT (the brief's "When done" section in the kickoff message is silent on those). Architect to update at deploy time.

4. **`text_Moves_en.txt` real-SRAM canary.** Brief explicitly out-of-scopes this (parity with KG-25 for synthetic test data); logged here as a follow-up KG so a deploy reviewer can find it later.
