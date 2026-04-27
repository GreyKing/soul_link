# Review Feedback — Step 5
Date: 2026-04-26
Ready for Builder: YES

## Must Fix

None.

## Should Fix

None.

## Escalate to Architect

None.

## Cleared

Reviewed Step 5 (player-facing emulator) end to end. All twelve scrutiny items pass; full suite confirmed locally at `169 runs, 504 assertions, 0 failures, 0 errors, 0 skips`; the emulator-controller test file confirmed in isolation at `23 runs, 67 assertions, 0 failures`.

Detail by scrutiny item:

1. **Auto-claim race-retry is bounded** (`app/controllers/emulator_controller.rb:56-84`). First `claim!` is on line 66; on `AlreadyClaimedError` we issue a *new* `unclaimed.ready.first` query on line 72 (not the stale `unclaimed` reference) and try once more on line 75. The inner rescue on line 77 swallows the second error and sets `@session = nil`. No path can call `claim!` more than twice. Verified by the `assert_equal 2, call_count` assertion on `test/controllers/emulator_controller_test.rb:185`.

2. **CSRF bypass is properly scoped** (`app/controllers/emulator_controller.rb:19`). `protect_from_forgery with: :null_session, only: [:save_data], if: -> { request.patch? }` — both the action filter and the method filter are present. GET `save_data` does not get the bypass. The `with_forgery_protection` test (`test/controllers/emulator_controller_test.rb:302`) flips `ActionController::Base.allow_forgery_protection = true` and confirms PATCH still succeeds without an `X-CSRF-Token`. No blanket disable.

3. **`current_user_id` bigint flow is preserved end-to-end.** `app/controllers/sessions_controller.rb:16` stores `auth.uid.to_i` (Integer) in `session[:discord_user_id]`; `DiscordAuthentication#current_user_id` returns it raw; `EmulatorController#set_session` passes it to `find_by(discord_user_id: current_user_id)` (line 59) and `claim!(current_user_id)` (lines 66, 75). No `.to_i` / `.to_s` wrapping anywhere in the emulator controller.

4. **`rom` action covers all four branches** (`app/controllers/emulator_controller.rb:25-31`). `nil` session and not-ready collapse into the first guard (`@session&.ready?`), missing file is the second guard, happy path is `send_file`. Tests at lines 190, 200, 211, 222 cover each branch; the happy-path test uses a `Tempfile` and asserts byte equality.

5. **`save_data` GET 204 vs 200 is correct** (`app/controllers/emulator_controller.rb:40-42`). 204 for nil and empty (both via `data.blank?`) and 200 with the body otherwise. Tests at lines 246, 257, 268.

6. **`save_data` PATCH writes correctly** (`app/controllers/emulator_controller.rb:34-38`). Reads `request.body.read`, persists via `update!`, returns 204. Test at line 284 sends `"NEW_SAVE_BYTES_\x00\x01\x02".b` and asserts round-trip via `sess.reload.save_data.to_s.b`. Bob added a defensive `return head :not_found if @session.nil?` on line 35; the brief did not ask for it but it prevents a NoMethodError when a fifth player attempts to PATCH while all four ROMs are claimed elsewhere. Sensible defense, not drift.

7. **Six-state view, no silent fall-through** (`app/views/emulator/show.html.erb:9-64`). Branches in order: `@run.nil?` → NO ACTIVE RUN; `emulator_status == :none` → ROMS NOT GENERATED YET; `@session.nil?` → NO ROM AVAILABLE; `pending || generating` → ROM GENERATING; `failed` → ROM GENERATION FAILED with `error_message`; else → emulator stage with `data-controller="emulator"`. Each branch has distinct copy. Status validations in the model bound the else to "ready".

8. **Stimulus controller** (`app/javascript/controllers/emulator_controller.js`):
   - Globals set on lines 30-50, loader script injected on lines 52-55 — globals first, script second. Order correct.
   - Existing save fetched on line 28 *before* globals are set; injected on `EJS_ready` (line 49) via `_injectExistingSave` (lines 95-117) which writes into `gameManager.FS` and calls `loadSaveFiles()`.
   - `EJS_onSaveSave` registered on line 42 (the verified-correct callback for SRAM, per Architect ruling).
   - `_uploadSave` sends `"X-CSRF-Token": this.csrfValue` on line 128.
   - Both `_fetchSave` (line 80) and `_uploadSave` (line 130) use `credentials: "same-origin"`.

9. **"Play" nav link is well-placed** (`app/views/layouts/application.html.erb:42`). Sibling of the existing "Runs" link, same `class="gb-nav-link"`, lives inside the `<% if logged_in? %>` wrapper on line 29. No layout disturbance.

10. **Test coverage matches DoD.** 23 named tests; every brief-listed scenario has a corresponding test:
    - Auth (4): `show`, `rom`, `save_data` GET, `save_data` PATCH each redirect when not signed in.
    - Six show-states (4 message + generating + ready + idempotent revisit): no active run, emulator_status :none, all claimed, auto-claim happy path, idempotent re-visit, pending, generating, failed (with error_message), ready.
    - Claim race: monkey-patched `claim!` raises once, succeeds on retry, asserts `call_count == 2`.
    - `rom` four branches: not ready, no session, file missing, file present (Tempfile).
    - `save_data` GET three: nil, empty, present.
    - `save_data` PATCH two: writes bytes, succeeds without CSRF under enforced forgery protection.

11. **No scope creep.** No presence multiplayer, no cheat config, no cleanup polish. The only addition beyond the brief is the defensive PATCH nil-session guard mentioned in (6), which is a strict safety improvement.

12. **Hermetic tests.** `Tempfile` for ROM bytes; FactoryBot for `save_data`. No real EmulatorJS invocation, no fixtures on disk, no network. Race test's `class_eval` monkey-patch is restored in `ensure`; Rails forked-process parallelization isolates it from other workers.

The Architect-cleared deviations (`EMULATOR_CORE = "melonds"`, `EJS_onSaveSave` instead of `EJS_onSaveState`, no in-browser verification by Bob) are not re-litigated.

Step 5 is clear.

VERDICT: PASS
