# Review Feedback — Step 20
Date: 2026-05-04
Ready for Builder: YES

## Must Fix

None. All five buckets land cleanly. The architect-locked decisions (six wire sites, two-layer schedule cancel, confirm_modal partial signature, coin-flip ARIA-only) are honored. The non-locked decisions Bob made under "Decisions made for ambiguities" are sound.

## Should Fix

None.

## Nice to Have

- `app/javascript/controllers/confirm_modal_controller.js:24-29` — the `window.__confirmModals` registry is populated in `connect()` and torn down in `disconnect()`, but no callsite **reads** from it. The `open()` action discriminates by `event.params?.id !== this.idValue` instead. The registry is dead code today and only earns its keep if a future external script wants to call `window.__confirmModals['some-id'].click()` programmatically (e.g. a Turbo-Stream payload that opens a modal server-side). Worth keeping for now per the brief's KG-32; if a future cleanup wants to drop it, the dependency on the registry is zero. Tracked in KG-32 already.

- `app/javascript/controllers/confirm_modal_controller.js:48-51` — `open()` falls back to `firstFocusable()` if `hasCancelTarget` is false. The partial always renders the cancel button with the right target attribute, so the `hasCancelTarget` branch is the only one that ever fires in production. Defense-in-depth comment is fine; the fallback is a no-cost belt-and-suspenders for any future caller that omits the cancel button (won't happen).

## Notes (observations, not blocking)

- **Bucket A — CSS media query placed correctly.** `pixeldex.css:1061-1064` sits immediately after the existing `@media (max-width: 900px)` block (1043-1059). Cascade is right: at 521-900px, gb-grid-3/4 → 2 cols (existing); at ≤520px, → 1 col (new); above 900px, original column counts (declared at the top-level rules at 975-985). gb-grid-2 is never overridden — confirmed by `ResponsiveGridsTest#test_gb-grid-2_stays_2-column`.

- **Bucket B — partial markup audit.** Walked `app/views/shared/_confirm_modal.html.erb` end-to-end:
  - Outer `<div id="<%= id %>">` carries `class="hidden"` + `data-controller="confirm-modal"` + `data-confirm-modal-id-value="<%= id %>"`.
  - Inner `<div class="gb-modal">` carries `role="dialog" aria-modal="true" aria-labelledby="<%= title_id %>"`.
  - Title `<span id="<%= title_id %>">` matches the labelledby pointer (id is `"#{id}-title"`).
  - Cancel button has `data-confirm-modal-target="cancel"` and `data-action="click->confirm-modal#close"`.
  - Confirm button class defaults to `"gb-btn-danger gb-btn-sm"`; `confirm_data` hash is spread via `.map { |k, v| %(data-#{k.to_s.dasherize}="#{ERB::Util.html_escape(v)}") }.join(" ").html_safe` — verified the `>` in `"click->run-management#endRun"` ends up as `&gt;` on the rendered confirm button (matches the test expectation).
  - Backdrop click closes (`data-action="click->confirm-modal#close"`).
  - The `.gb-modal-close` button (the `&times;` X) is present, so `escape_close_controller` finds and clicks it on ESC.

- **Bucket B — six wire sites verified.** For each of the six sites, the trigger's `data-action` is `click->confirm-modal#open` and `data-confirm-modal-id-param` matches the partial's `:id` local. The confirm button's `confirm_data` carries the **original** Stimulus action that used to live on the trigger. Site-by-site:
  | Site | Trigger id-param | Confirm action |
  |---|---|---|
  | dashboard runs tab END RUN | `end-run-dashboard-confirm` | `click->run-management#endRun` |
  | /runs page END RUN | `end-run-page-confirm` | `click->run-management#endRun` |
  | save-slot DELETE | `delete-slot-#{n}-confirm` | `click->save-slots#deleteSlot` + `slot_number: n` |
  | CLEAR ALL SLOTS | `clear-all-slots-confirm` | `click->clear-save#clear` |
  | group DEL | `delete-group-#{group.id}-confirm` | `click->species-assignment#deleteGroup` + `group_id: group.id` |
  | schedule Cancel | `cancel-schedule-confirm` | `click->gym-schedule#cancel` |

  Two distinct ids for END RUN (dashboard vs /runs) is intentional and defensive — if a future redesign hosts both surfaces in one DOM tree, they don't collide.

- **Bucket B — JS controller deferred-confirm cleanup.** All four JS controllers had their native `window.confirm()` removed correctly:
  - `save_slots_controller.js#deleteSlot` — `CONFIRM_DELETE` constant deleted (was unused after the removal — checked the file for any other reference).
  - `clear_save_controller.js#clear` — `CONFIRM_MESSAGE` constant deleted.
  - `run_management_controller.js#endRun` — only the `endRun` confirm removed; `startRun` and `regenerateEmulatorRoms` confirms left in place per Bob's note (out of brief scope).
  - `gym_schedule_controller.js#cancel` — confirm removed.

  The `species_assignment_controller.js#deleteGroup` change is more substantive: it now reads `groupId` from `event.currentTarget.dataset.groupId` (the confirm button's spread attribute) with a `.closest("[data-group-id]")` fallback. This dual-read keeps the `_group_card` partial's confirm-button wiring working AND keeps any future callsite that doesn't migrate to the modal pattern functional. Sensible.

- **Bucket B — `_actionButtons()` selector update is correct.** Verified `save_slots_controller.js:117-124` matches `[data-action*='save-slots#makeActive'], [data-confirm-modal-id-param^='delete-slot-']`. The make-active trigger still has its data-action (unchanged); the DELETE trigger now matches by id-param prefix. Overwrite-pending mode (`_enterOverwriteMode`) still disables both trigger types.

- **Bucket C — ARIA shape on every modal.** All seven existing modals have `role="dialog"` + `aria-modal="true"` + `aria-labelledby` pointing at a `<span id="...">` matching the labelledby value. Six attach `data-controller="modal-a11y"`; the coin-flip is ARIA-only as documented (no close button, auto-dismisses, focus trap on a 1-2s animation would be friction). Agree with Bob's call on the coin-flip — `aria-modal="true"` alone gives screen-reader users the announcement, and the lack of focus trap is correct for a dialog with no interactive controls.

- **Bucket C — `modal_a11y_controller` wrapper detection.** The `#findWrapper()` heuristic walks `parentElement` looking for either `.hidden` or `position: fixed` inline style. Spot-checked each modal:
  - `_catch_modal.html.erb:3-4` — outer wrapper has `class="hidden"` + `style="position: fixed; inset: 0; z-index: 50;"`. The walk hits it on the second hop (gb-modal → outer flex-center wrapper → `position: fixed` outer). ✓
  - `_pokemon_modal.html.erb` — same shape. ✓
  - `_mark_dead_modal.html.erb`, `_reset_draft_modal.html.erb` — same. ✓
  - `_quick_calc_modal.html.erb` — same. ✓
  - `species_assignments/show.html.erb` group modal at line 128 — outer div has `class="hidden"` + `position: fixed`. ✓
  - The shared `_confirm_modal.html.erb` outer is itself `position: fixed` and `class="hidden"` — but the partial uses `confirm-modal` controller, not `modal-a11y`. ✓

- **Bucket C — ESC propagation in pixeldex layout.** Confirmed `app/views/layouts/pixeldex.html.erb:28` has `<body data-controller="escape-close">`. Before this step, the dashboard layout had no global ESC handler — the catch / pokemon / mark-dead / reset-draft modals could only be closed by clicking the X or the backdrop. Now ESC works for them too. The bundle-in is documented in REVIEW-REQUEST §6 and is the right call.

- **Bucket D — view authz.** Confirmed `gym_schedules/show.html.erb:64` wraps the cancel button + accompanying confirm-modal partial in `<% if @schedule.proposed_by == current_user_id %>`. Both `proposed_by` (bigint Integer) and `current_user_id` (Integer from `auth.uid.to_i` at OAuth callback) are Ruby Integer — direct equality works.

- **Bucket D — channel authz.** Confirmed `gym_schedule_channel.rb:23-25` matches the brief exactly. The early return uses `transmit({ error: "Only the proposer can cancel this schedule." })` — same shape as the existing `rsvp` rescue path. The `unless ... return` reads cleanly. `current_user_id` on the channel comes from `Connection#identified_by`, which traces back to `session[:discord_user_id]` (set on OAuth callback as `auth.uid.to_i`). Same Integer comparison as the view.

- **Bucket D — channel authz tested.** `test/channels/gym_schedule_channel_test.rb` covers: subscribe + initial broadcast (1 test), proposer cancel succeeds (1), non-proposer cancel rejected with the error message + schedule stays proposed (1), non-proposer cancel does NOT trigger a second broadcast (1). The "no extra broadcast" test is a nice belt-and-suspenders verification — even though `transmit({ error: })` is a per-connection send, not a broadcast, asserting `broadcasts(@schedule).size` doesn't increase is the cleanest way to prove the channel didn't accidentally fan out the rejection.

- **Bucket E — `<NEXT` literal cleanup.** `_gyms_content.html.erb:52` now reads:
  ```erb
  <span class="type-text" style="border-color: var(--amber); color: var(--amber); margin-left: 4px;">NEXT</span>
  ```
  Reuses the existing `type-text` badge class with amber border + color. Visually consistent with the type-abbreviation badge that immediately precedes it on line 51. Cleaner than the original literal.

- **Tests.** 22 new tests, all using FactoryBot (no fixtures — verified `test/channels/gym_schedule_channel_test.rb` and `test/factories/gym_schedules.rb` are factory-only; the GymSchedule factory is new this step but follows the existing factory conventions). 0 failures, 0 errors. Suite count `654 → 676` matches the assertion increase from `2011 → 2095` (+84 assertions).

- **Test environment caveat.** Same as Step 19: the worktree's PATH resolves to Ruby 3.0.6's bundle by default, which can't load Rails 8.1.1 gems. Workaround invocation: `PATH="/Users/gferm/.local/share/mise/installs/ruby/3.4.5/bin:$PATH" /Users/gferm/.local/share/mise/installs/ruby/3.4.5/bin/bundle exec rails test`. Bob ran with this; I re-ran the new tests in isolation (`test/helpers/...`, `test/integration/confirm_modal_flow_test.rb`, `test/integration/responsive_grids_test.rb`, `test/channels/gym_schedule_channel_test.rb`) — all 22 pass in 0.36s.

- **Rubocop / Brakeman.** Rubocop clean (191 → 197 files, 0 offenses; +6 files = the 6 new Ruby/JS/ERB files). Brakeman clean — same two pre-existing weak warnings as Step 19 (`emulator_controller.rb:79` SendFile, `gym_schedule_discord_update_job.rb:14` FileAccess), no new warnings.

- **Hand-rolled vs helper-rendered attribute escaping.** Verified the asymmetry that initially failed Bob's test: the trigger button's `data-action="click->confirm-modal#open"` is hand-written ERB and preserves `>` literally; the confirm button's data-attributes go through `ERB::Util.html_escape` and become `click-&gt;run-management#endRun`. Both are functional (HTML attribute parsing decodes `&gt;` back to `>`), but a follow-up cleanup could normalize by using `tag_helper`-rendered buttons with `data:` hashes for consistency. Minor; not worth a follow-up KG.

- **Map-view NEW CATCH gating preserved.** Step 19 added `dashboard_read_only?(@run)` guard to `app/views/map/show.html.erb:228`. Step 20 didn't touch that file. Confirmed the guard is still there.

- **No regressions in the existing Step 18/19 tests.** All 654 pre-existing tests still pass (676 - 22 new = 654 from Step 19 baseline).

- **Frontend smoke not performed.** Same pattern as Steps 15-19: the changes are server-rendered ERB + Stimulus controller scaffolding. Existing `broadcasts_refreshes_to` infrastructure handles real-time updates. The user's standing instruction is integration test (not system test) — and integration tests verify markup, not interactive Stimulus behavior. The Selenium-driven "click END RUN, modal opens, ESC closes, run is still active" verification is a manual smoke step the Project Owner can run — or a future system-test cycle.

- **Coin-flip ARIA-only — concur with Bob.** Re-reviewed the architect brief: it locked "all 8 modals" but the coin-flip's no-close-button structure makes a focus trap actively harmful (1-2s animation lockup with no escape). Bob made the right architectural call to skip `modal-a11y` there while still adding ARIA. If Project Owner disagrees, the cost to add `modal-a11y` later is one line of markup.

## Summary

Five buckets, all clean. 22 new tests, full suite green. Rubocop clean. Brakeman clean. The architect-locked decisions hold up under code-walk. Two tiny "nice to have" notes about the controller's unused registry and unreachable fallback path; both are intentional defense-in-depth and acceptable as-is. **Ship it.**
