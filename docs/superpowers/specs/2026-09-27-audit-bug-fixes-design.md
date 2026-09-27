# Audit Bug Fixes (Cleanup Phase 1 of 4)

**Date:** 2026-09-27

## Context

A full audit of the codebase (baseline `e822ed9`, 964 tests passing) found
duplication and performance issues, plus a set of real bugs. The cleanup is
split into five phases, each with its own spec:

1. **Bug fixes** (this document)
2. Infrastructure: Solid Cable and Solid Queue on the existing MySQL database
3. Rails core cleanup: controllers, models, dead code, quick speed wins
4. Discord layer: shared REST base, services shared by bot and web, bot split
5. Frontend: shared JS helpers, calculator merge, page weight

Fixing bugs first keeps phases 3-5 purely structural, so any behaviour change
in a later phase is a regression by definition.

## Decisions (2026-09-27)

| Question | Decision |
|---|---|
| Deploys for this phase | One. Batches are held on the branch. |
| Live updates and background jobs | Solid Cable + Solid Queue, as phase 2 |
| Server-side read-only for wiped runs | Enforce (2.3) |
| Undoing a mistaken wipe | Revive stays allowed and clears the wipe (2.3) |
| Who may edit run data on the website | Any server member (unchanged) |
| Legacy "Add My Species" bot flow | Remove, in phase 4 |

## Rules

- Every fix starts with a test that fails on the current code.
- Fixes are minimal. No restructuring here, even where phase 2 or 3 will
  rewrite the surrounding code.
- Work is done in three batches, each committed on the worktree branch once
  the full suite passes. The batches are held on the branch and shipped
  together: one fast-forward merge to `main` and one push, which is one
  production deploy for the whole phase.

## Batch 1: user-facing

### 1.1 Redirect loop when the guild has no active run

`SessionsController#new` sends logged-in users to `team_path`;
`TeamsController#show` sends them to `login_path` when there is no active run.
After END RUN the app is unreachable and START NEW RUN cannot be shown.

Fix:

- `DashboardController#show` falls back to the guild's most recent run when
  there is no active one (`@all_runs.active.first || @all_runs.first`). This is
  the same page as `/?run_id=<latest>`, which already works, and its Runs tab
  already shows the NO ACTIVE RUN panel with START NEW RUN.
- An unknown `?run_id=` falls back the same way instead of redirecting.
- If the guild has no runs at all (only possible if runs were deleted, since
  login requires one), render a minimal `pixeldex` page pointing to
  `/start_new_run` in Discord, with a sign-out button.
- Every "no active run" redirect for a logged-in user goes to `root_path`
  instead of `login_path` (teams, map, gym_ready, species_assignments,
  gym_polls, gym_drafts, runs).
- The post-login landing page stays `/team`; `/login` → `/team` → `/` no
  longer loops, so it does not need to change.

Tests: logged-in user with only an inactive run gets 200 on `/` and sees the
no-run panel; `/team` and the other pages redirect to `/`; the chain from
`/login` ends on a 200.

### 1.2 Auto-detected catches saved as "Species #N"

`CatchCoordinator.species_name_by_id` checks `defined?(PokemonBaseStat)`. The
model is `Pokemon::BaseStat`, so the lookup is always empty.

Fix: use `Pokemon::BaseStat.pluck(:national_dex_number, :species).to_h` and
drop the `defined?` guard.

Backfill: add `rake soul_link:backfill_species_names`, which finds
`soul_link_pokemon` rows whose `species` matches `/\ASpecies #(\d+)\z/` and
rewrites `species` (and `name` where it holds the same placeholder) from
`Pokemon::BaseStat`. It supports `DRY_RUN=1` and prints each change. It is not
run against production without explicit confirmation.

Tests: a caught event for dex number 387 stores "Turtwig"; unknown ids keep
the placeholder; the rake task rewrites placeholders and leaves real names
alone.

### 1.3 `!next_gym` always shows gym 1

`discord_bot.rb:350` calls `GameState.next_gym_info` with no argument.

Fix: pass `run.gyms_defeated`; reply "All gyms beaten" when it returns nil.
Extract the lookup into a class method (`DiscordBot.next_gym_for(run)`) so it
can be tested without a gateway connection, following the existing `apply_*`
pattern.

### 1.4 Deaths marked from Discord skip wipe detection

`handle_move_to_deaths_final` never calls `SoulLink::WipeCoordinator.process`;
the web path does (`pokemon_groups_controller.rb:89`).

Fix: extract the DB part of the handler into `DiscordBot.apply_mark_dead(run,
group_id, location, eulogy:)`, which marks the group dead and calls
`WipeCoordinator.process(run)`. The handler keeps the Discord sync and the
response.

Tests: marking the last living group dead through `apply_mark_dead` stamps the
run as wiped.

## Batch 2: access control

### 2.1 Draft and poll channels are not scoped to the guild

`GymDraftChannel#subscribed` and `GymPollChannel#subscribed` use an unscoped
`find`. Any logged-in user can subscribe to, and act on, any id.

Fix: look the record up through the session's guild
(`GymDraft.joins(:soul_link_run).where(soul_link_runs: { guild_id: ... })`)
and `reject` when it is missing, as `RunChannel` does. Apply the same scoping
to the bot's gym-poll vote and reset handlers and to
`GymDraftsController#show`.

Tests: subscription from another guild's session is rejected; same-guild
subscription still works; `GET /gym_drafts/:id` for another guild's draft
returns 404.

### 2.2 CSRF verification is off for SaveSlotsController

The controller's `protect_from_forgery ... only: [:create, :update]` replaces
the inherited callback, so `destroy` and `restore` are unverified, and
`null_session` has no effect on create/update because authentication runs
first.

Fix: delete the override and rely on the default from `ApplicationController`.
All six client call sites already send `X-CSRF-Token`, and nothing uses
`sendBeacon` or `keepalive`. Replace the test "create succeeds without CSRF
token" with tests that tokenless create, update, destroy and restore are
rejected when forgery protection is on.

Risk: a browser tab opened before the deploy keeps a valid token, so no
in-progress save is lost.

### 2.3 Read-only mode is enforced in the UI only

`SoulLinkRun#read_only?` (wiped and not completed) hides buttons, but every
endpoint still accepts writes. The definition is unchanged: completed runs
stay editable.

Fix:

- A `RunWriteGuard` controller concern with `require_writable_run!`. For a
  read-only run it responds 403 with `{ error: "This run has wiped and is
  read-only." }` for JSON, or redirects to `root_path` with an alert for HTML.
- Applied to the mutating actions of `pokemon_groups`, `pokemon`,
  `species_assignments`, `teams`, `gym_progress`, `gym_drafts`, `gym_results`
  and `gym_polls`.
- `GymDraftChannel` and `GymPollChannel` actions transmit the same error.
- Bot handlers that write run data (catch, species, death, poll vote/reset)
  reply with the same message.
- `CatchCoordinator`, `GymBeatenCoordinator` and `HallOfFameCoordinator`
  return early for a read-only run, so an uploaded save cannot change it.

Not blocked: ending the run, starting a new run, emulator saves and save
slots, ROM downloads, the schedule template.

Undoing a wipe:

- Revive (`PATCH /pokemon_groups/:id` with `status=caught` on a dead group) is
  exempt from the guard.
- After a revive, `WipeCoordinator.reconsider(run)` clears `wiped_at` under
  `with_lock` when `wiping_player_and_route` no longer finds a wiped player.
  If another player is still wiped, the run stays read-only.
- The web UI has no revive control today (the drag-to-revive grid was
  removed; its JS is dead code). Add a REVIVE button to the Pokemon modal,
  shown for dead groups in any run, wired to the existing `PATCH` revive
  path. Every other affordance stays hidden on a read-only run.
- Guard the modal's MARK DEAD target in JS: on a read-only run the button is
  not rendered and opening the modal currently throws.
- No Discord message is sent when a wipe is cleared.

Tests: each guarded endpoint returns 403 on a wiped run and still works on a
live and on a completed run; revive on a wiped run succeeds and clears
`wiped_at`; revive that leaves another player wiped keeps `wiped_at`; a parsed
save on a wiped run creates no catches; end run and start run still work.

## Batch 3: concurrency and jobs

### 3.1 Lost updates on draft and poll state

Every `GymDraft` and `GymPoll` action reads the JSON column, changes it in
Ruby and writes it back, with no lock.

Fix: wrap each public mutating method in `with_lock`, which reloads the row
under `SELECT ... FOR UPDATE` inside a transaction. This also makes the
two-write paths (`mark_ready!`, `nominate!`) atomic. No API change.

Tests: a stale instance (loaded before another instance wrote) calling
`vote!` / `mark_ready!` preserves the other write.

### 3.2 Duplicate emulator sessions on double enqueue

`GenerateRunRomsJob` checks `count >= 4` and then creates four sessions.

Fix: run the check and the creates inside `run.with_lock`.

### 3.3 Roster card does not update after a save is parsed

The broadcast is an `after_update_commit` callback, but `ParseSaveDataJob`
writes with `update_columns`, which skips callbacks.

Fix: call the slot's broadcast method explicitly at the end of the job. Keep
`update_columns` (it avoids re-triggering the parse callback).

### 3.4 Job robustness

- Enable `retry_on ActiveRecord::Deadlocked` and
  `discard_on ActiveJob::DeserializationError` in `ApplicationJob`.
- `GymPollLockJob`: return early when `locked_slot_index` matches no slot.
- Poll jobs: return early with a log line when the bot token is missing.

### 3.5 New run never reuses the general channel

`DiscordBot#create_new_run` deactivates the current run and then asks for the
current run, which is always nil by then.

Fix: capture the previous run before deactivating it.

### 3.6 Unescaped species name in species assignment

`species_assignment_controller.js` interpolates text into `outerHTML`.

Fix: build the node with `textContent`. Look the group card up before
replacing the drop zone; today the lookup runs on the detached node, so the
card's "N missing" / "Complete" label never updates.

Note: section 3.1 (locking) is implemented before 2.3 (read-only), because
the read-only check sits inside the lock. Batches are internal groupings and
ship together, so the order has no user-visible effect.

## Out of scope

| Item | Why | Where it goes |
|---|---|---|
| Bot changes do not reach open browsers (`async` cable adapter across two processes) | Infrastructure change | Phase 2 |
| `async` job adapter loses jobs on restart | Infrastructure change | Phase 2 |
| Registered-player check on web mutations | Decided: any server member may edit | Not planned |
| Unique index on `(run, user, pid)` | Needs a duplicate check on production data first | Phase 3 |
| Bot interactions not deferred before REST calls | Touches every handler | Phase 4 |
| Legacy "Add My Species" bot flow | Decided: remove | Phase 4 |
| Client-side HTML building in draft and timeline pages | Not behaviour-preserving | Not planned |

## Verification

After each batch: `bin/rails test` with output redirected to a file, and
`bundle exec rubocop` on changed files. The suite must stay at zero failures
with the test count going up.
