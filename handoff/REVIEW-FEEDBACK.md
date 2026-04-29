# Review Feedback — Step 4: Run Roster Sidebar
*Written by Reviewer. Read by Builder and Architect.*

---

**Date:** 2026-04-29
**Ready for Builder:** YES

## Must Fix

*—*

## Should Fix

- `app/views/emulator/_run_sidebar.html.erb:29` — `pending`/`generating` status uses an invented hex `#d4b14a` (amber). No amber/yellow token exists in `pixeldex.css` (verified via grep). The brief allowed picking the closest existing color when one didn't exist; the runs-page "ROMs generating…" precedent is plain `var(--l1)` text-only, which Bob's note acknowledges. The choice complies with the "no new CSS in `pixeldex.css`" flag literally — it's inline-only, no class added — but it is the one place a brand-new color literal got introduced. Recommendation: leave as-is for this step (the badge is visually distinct and contained). If status badges get touched again, prefer a `var(--l1)` background + dark text variant, or escalate to Arch for a proper `--accent` / `--warn` var so the color stops being orphaned inline. Not blocking.

- `app/views/emulator/_run_sidebar.html.erb:27` — Bob's note describes the `ready` palette as "matches the ACTIVE label in runs/index", but `app/views/runs/index.html.erb:17` actually uses `background: var(--d2)` while the partial uses `background: var(--d1)`. Both are dark-on-light using existing vars — no invented colors — but the parity claim isn't quite literal. Cosmetic. Not blocking.

## Escalate to Architect

*—*

## Cleared

Reviewed all four touched files plus the new partial against the architect brief and Bob's report. Verified item-by-item against the scrutinize list:

### #1 — Canvas style preserved byte-for-byte

`app/views/emulator/show.html.erb:76` — `style="aspect-ratio: 2 / 3; max-width: min(100%, 60vh); max-height: 90vh; margin: 0 auto;"` matches commit `9b0bf29` exactly. Confirmed via `git show 9b0bf29 -- app/views/emulator/show.html.erb` — the only change around the `emulator-game` div is indentation (additional 4-space wrap from the new flex-item div). Bob's claim is accurate.

### #2 — `@run_sessions` scoping

`app/controllers/emulator_controller.rb:38` — `@run_sessions = @run.soul_link_emulator_sessions.order(:id) if @session&.ready?`. Identical guard as `@cheats` on line 32. Non-ready branches incur no extra DB query and the partial cannot accidentally render where the ivar is unset (the partial only loads from inside the `<% else %>` ready branch in `show.html.erb:80`).

### #3 — `read_attribute_before_type_cast` usage

`app/views/emulator/_run_sidebar.html.erb:16` — `s.read_attribute_before_type_cast("save_data")&.bytesize`. Skips the gzip coder, returns raw on-disk bytes, safe-navigates nil. Matches the brief's flag exactly. The `saved_bytes && saved_bytes > 0` check at line 52 also handles the empty-string edge case (the gzip coder normalizes empty saves to `""`).

### #4 — Player name fallback chain

`_run_sidebar.html.erb:17–21` — three branches: `if s.discord_user_id` then `SoulLink::GameState.player_name(uid).presence || s.discord_user_id.to_s`, else `"Unclaimed"`. The middle branch is effectively dead code — `GameState.player_name` returns `"Player #{uid}"` (never nil) for unknown uids per `app/services/soul_link/game_state.rb:80–83` — but the defensive chain is consistent with the brief and harmless.

### #5 — `current_user_id` comparison

`_run_sidebar.html.erb:12` — `s.discord_user_id == current_user_id`. No `.to_s` / `.to_i` coercion. `current_user_id` is set from `auth.uid.to_i` in `SessionsController#create:16,38` (Integer), and `discord_user_id` is `bigint` per `db/schema.rb:124`. Integer-to-Integer direct comparison, matching the locked architecture decision.

### #6 — Status badge color choices

- `failed`: `#4a1c1c / #e8a0a0 / #6b2c2c` — these are the literal `gb-flash-alert` palette at `pixeldex.css:140–143` (and re-used by `gb-btn-danger` at 758–765). Existing palette, no invented colors.
- `ready`: `var(--d1) / var(--l2)` — both vars defined at `pixeldex.css:6,9`. (The minor parity caveat with the actual ACTIVE label is in Should Fix.)
- `pending`/`generating`: flagged under Should Fix.

### #7 — YOU accent

Confirmed via `grep -n "accent" pixeldex.css` — zero matches. No `--accent` var exists. Bob's substitution: `border-width: 4px` on the gb-card (whose default border per `pixeldex.css:11` is `3px solid var(--d1)`). This thickens the existing `--d1`-colored border to 4px without inventing a new var. Mirrors the visual weight of `gb-modal`'s 4px border (`pixeldex.css:836`), which is the project's existing "this thing is special" pattern. Reasonable substitution given the constraint.

### #8 — Tests cover all listed assertions

`test/controllers/emulator_controller_test.rb:147–222`:

| Brief assertion | Test location | Status |
|---|---|---|
| Body contains `RUN ROSTER` on ready | line 215 (`assert_match`) | ✔ |
| Body absent `RUN ROSTER` on non-ready | lines 179, 187, 199 (no-run, generating, failed) | ✔ |
| Body contains current player's display name (`Grey`) | line 217 | ✔ |
| Body contains `>YOU<` for current player's row | line 219 | ✔ |
| Body contains `Unclaimed` when other sessions are unclaimed | line 221 | ✔ |
| Body absent `>YOU<` on non-ready (defensive) | line 201 (failed branch explicitly) | ✔ |

The `>YOU<` negative is asserted explicitly only on `failed`, but generating and no-run states implicitly cover it via the `RUN ROSTER` absent assertion (the partial doesn't render at all in those branches). Test 1 (lines 149–172) additionally asserts all 4 sessions render in id-ascending order via unique seeds — the brief's substitute for `assigns(:run_sessions)`, which Rails 8 extracts to `rails-controller-testing` (not in this Gemfile). Body-based assertions are real coverage of the rendered output, more meaningful than ivar inspection.

### #9 — Responsive layout

`show.html.erb:59–80`:
- Container: `display: flex; gap: 16px; align-items: flex-start; flex-wrap: wrap;` ✔
- Canvas wrapper: `flex: 1 1 auto; min-width: 0;` (the standard flexbox shrink unlock) ✔
- Sidebar: `width: 280px; flex-shrink: 0;` ✔
- No media queries.

Layout will wrap below the canvas on narrow viewports as specified.

### #10 — Tier 1 strictly observed

- `git diff Gemfile Gemfile.lock` — no changes. No new gems.
- `git diff app/views/runs/` — no changes. Runs page untouched.
- No SRAM parsing logic in the diff. The two SRAM mentions in `emulator_controller.rb` (lines 3 and 11) are pre-existing comments documenting the save_data round-trip and size cap, not new logic.
- `_run_sidebar.html.erb:5` explicitly notes "No SRAM parsing — that's Tier 2 and lives in a future step."
- No changes to other emulator state branches in `show.html.erb` — only the ready `<% else %>` branch wraps existing markup in a flex container plus the new sidebar.

### #11 — DoD all checked

- [x] `EmulatorController#show` sets `@run_sessions` on ready state, ordered by id (line 38)
- [x] `app/views/emulator/_run_sidebar.html.erb` exists (66 lines, new file)
- [x] Ready-state view renders canvas + sidebar in flex layout, sidebar on right (`show.html.erb:59–82`)
- [x] Each session card shows: player name (or fallback), status, last-played time (or "Not started"), save size (or "—"), seed (`_run_sidebar.html.erb:36–67`)
- [x] Current player's card: visible YOU badge (line 42) + 4px accent border (line 36)
- [x] Non-ready states render unchanged — sidebar absent, no `@run_sessions` access (controller line 38 guards on `ready?`; partial only rendered in `<% else %>` branch)
- [x] Canvas style preserved exactly as in `9b0bf29` (verified)
- [x] Tests cover ivar set on ready + view contains player name + YOU + RUN ROSTER + Unclaimed (verified)
- [x] Full suite passes (verified locally)
- [x] 3+ consecutive runs without flakes (verified locally — see Stability)

### #12 — Suite stability

Ran `bundle exec rails test` three times sequentially using mise Ruby 3.4.5 (per Bob's note about `bin/rails` falling through to system Ruby 3.0.6):

```
Run 1: 221 runs, 660 assertions, 0 failures, 0 errors, 0 skips
Run 2: 221 runs, 660 assertions, 0 failures, 0 errors, 0 skips
Run 3: 221 runs, 660 assertions, 0 failures, 0 errors, 0 skips
```

Targeted: `bundle exec rails test test/controllers/emulator_controller_test.rb` → 36 runs, 0 failures.

Each invocation already exercises the parallel path via `parallelize(workers: :number_of_processors)` per `test_helper.rb:12`. Note: launching three `rails test` invocations *concurrently against the same `soul_link_test` DB* produces DB-contention errors — that is a test-infrastructure artifact of running multiple processes against a shared schema, not a flake in this code. The authoritative parallel path is the in-process worker pool, which is exercised every single run.

Rubocop on the two touched `.rb` files (`emulator_controller.rb`, `emulator_controller_test.rb`): clean. ERB files raise `Lint/Syntax` against rubocop-rails-omakase as expected (no ERB lint configured); not a real failure. Bob's report only claimed clean on `.rb` files, which matches.

---

Step 4 is clear.

VERDICT: PASS_WITH_OBSERVATIONS
