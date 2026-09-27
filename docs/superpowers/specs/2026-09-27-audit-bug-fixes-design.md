# Audit Bug Fixes (Cleanup Phase 1 of 4)

**Date:** 2026-09-27

## Context

A full audit of the codebase (baseline `e822ed9`, 964 tests passing) found
duplication and performance issues, plus a set of real bugs. The cleanup is
split into four phases, each with its own spec:

1. **Bug fixes** (this document)
2. Rails core cleanup: controllers, models, dead code, quick speed wins
3. Discord layer: shared REST base, services shared by bot and web, bot split
4. Frontend: shared JS helpers, calculator merge, page weight

Fixing bugs first keeps phases 2-4 purely structural, so any behaviour change
in a later phase is a regression by definition.

## Rules

- Every fix starts with a test that fails on the current code.
- Fixes are minimal. No restructuring here, even where phase 2 or 3 will
  rewrite the surrounding code.
- Work ships in three batches. Each batch is committed on the worktree branch,
  fast-forward merged to `main` and pushed once the full suite passes. A push
  to `main` deploys to production.

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
- If the guild has no runs at all, render a minimal page in the `pixeldex`
  layout with the same START NEW RUN panel.
- Every "no active run" redirect for a logged-in user goes to `root_path`
  instead of `login_path` (teams, map, gym_ready, species_assignments,
  gym_polls, gym_drafts).
- `SessionsController#new` and `#create` redirect to `root_path`.

Tests: logged-in user with only an inactive run gets 200 on `/` and sees the
no-run panel; `/team` redirects to `/`; `/login` while logged in redirects to
`/`; no request chain returns to `/login`.

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

Fix: build the node with `textContent`.

## Out of scope

| Item | Why | Where it goes |
|---|---|---|
| Bot changes do not reach open browsers (`async` cable adapter across two processes) | Infrastructure change (Solid Cable or Redis) | Separate decision |
| `async` job adapter loses jobs on restart | Same | Separate decision |
| Read-only mode is enforced in the UI only | Policy decision | Phase 2 |
| No registered-player check on web mutations | Policy decision | Phase 2 |
| Unique index on `(run, user, pid)` | Needs a duplicate check on production data first | Phase 2 |
| Bot interactions not deferred before REST calls | Touches every handler | Phase 3 |
| Legacy "Add My Species" flow skips species validation | Removed by the shared service | Phase 3 |

## Verification

After each batch: `bin/rails test` with output redirected to a file, and
`bundle exec rubocop` on changed files. The suite must stay at zero failures
with the test count going up.
