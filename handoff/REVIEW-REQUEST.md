# Review Request — Step 20

**Builder:** Bob
**Branch:** `claude/condescending-jones-2bf3c7` (worktree; rebased on `028643b` after Step 19 + post-audit FF-merge)
**Ready for Review: YES**
**Scope:** Step 20 — Phase 1 cross-cutting safety nets per § 5 of `handoff/2026-05-04-ui-audit.md`. Five buckets (A gb-grid media queries · B shared confirm-modal partial · C ARIA + focus trap on existing modals · D gym-schedule cancel proposer-only + channel authz · E `<NEXT` literal cleanup), all in one ship.

---

## Summary

Twenty-two modified files, eight new files. Full suite: **654 → 676 runs (+22); 2011 → 2095 assertions (+84)**. Rubocop clean (197 files, no offenses). Brakeman clean for Step 20 — the two pre-existing weak-confidence warnings (`emulator_controller.rb:79`, `gym_schedule_discord_update_job.rb:14`) are unchanged from Step 19.

The buckets land independently and in the brief's locked order (A → E → D → B → C). I committed nothing along the way — single-commit ship to keep `git log` readable, matching the Step 18/19 pattern.

---

## Per-bucket changes

### Bucket A — `gb-grid-N` 520px media query

- **`app/assets/stylesheets/pixeldex.css:1061-1064`** — added `@media (max-width: 520px) { .gb-grid-3 { grid-template-columns: 1fr; } .gb-grid-4 { grid-template-columns: 1fr; } }` immediately after the existing 900px breakpoint. `gb-grid-2` intentionally untouched.

### Bucket B — Shared confirm-modal partial + helper + Stimulus controller

**New files:**
- `app/views/shared/_confirm_modal.html.erb` — partial mirroring `_mark_dead_modal.html.erb` shape. Takes locals `id` / `title` / `body` / `confirm_label` / `confirm_class` (default `"gb-btn-danger gb-btn-sm"`) / `confirm_data` (hash spread onto the confirm button as data-* attributes) / `cancel_label` (default `"CANCEL"`). Outer wrapper carries `data-controller="confirm-modal"`; inner `.gb-modal` carries `role="dialog" aria-modal="true" aria-labelledby="<id>-title"`. Body is rendered via `raw(body)` to allow `<strong>` etc.
- `app/helpers/confirm_modal_helper.rb` — single method `confirm_modal(id:, title:, body:, confirm_label:, confirm_class:, confirm_data:, cancel_label:)`. Auto-loaded by Rails.
- `app/javascript/controllers/confirm_modal_controller.js` — one controller per modal. Static `id` value. `connect()` registers in `window.__confirmModals[id]`; `open(event)` reads `event.params.id`, matches by id-value, reveals, focuses Cancel target (safe default), saves prior focus, attaches Tab-trap keydown listener; `close()` hides, restores prior focus, detaches listener. ESC is handled globally by the existing `escape_close_controller` (which clicks the `.gb-modal-close` button).

**Six wire sites:**
1. `app/views/dashboard/_runs_content.html.erb` — END RUN trigger swapped to `confirm-modal#open` with id `end-run-dashboard-confirm`.
2. `app/views/runs/index.html.erb` — same trigger pattern with id `end-run-page-confirm` (distinct so the two surfaces can co-render in a future merged view).
3. `app/views/emulator/_save_slots_sidebar.html.erb` — DELETE per slot uses id `delete-slot-#{n}-confirm`. Confirm button's `confirm_data: { action: "click->save-slots#deleteSlot", slot_number: n }` carries the slot number; `data-slot-number` is spread onto the confirm button so `event.currentTarget.dataset.slotNumber` still resolves.
4. Same file — CLEAR ALL SLOTS uses id `clear-all-slots-confirm`. Confirm action is `click->clear-save#clear`.
5. `app/views/species_assignments/_group_card.html.erb` — DEL trigger per group uses id `delete-group-#{group.id}-confirm`. Confirm button carries `group_id: group.id`; the JS handler now reads `event.currentTarget.dataset.groupId` directly with a `.closest("[data-group-id]")` fallback.
6. `app/views/gym_schedules/show.html.erb` — Cancel schedule trigger uses id `cancel-schedule-confirm`. Confirm action is `click->gym-schedule#cancel`. Trigger lives inside the proposer-only `<% if @schedule.proposed_by == current_user_id %>` (Bucket D).

**JS controller adjustments accompanying the wires:**
- `app/javascript/controllers/save_slots_controller.js` — removed the redundant `if (!window.confirm(CONFIRM_DELETE)) return` from `deleteSlot` (the modal asks now). Removed the unused `CONFIRM_DELETE` constant. Updated `_actionButtons()` selector to match the new `[data-confirm-modal-id-param^='delete-slot-']` triggers so overwrite-pending mode still disables them.
- `app/javascript/controllers/clear_save_controller.js` — removed the redundant native `confirm()` from `clear()`.
- `app/javascript/controllers/run_management_controller.js` — removed the native `confirm()` from `endRun()`. The two other native `confirm()` calls in this file (`startRun` and `regenerateEmulatorRoms`) are NOT in the brief's locked scope; left alone for a future step.
- `app/javascript/controllers/gym_schedule_controller.js` — removed the native `confirm()` from `cancel()`.
- `app/javascript/controllers/species_assignment_controller.js` — `deleteGroup` now reads `groupId` from the confirm-button's dataset directly, falling back to `.closest("[data-group-id]")` for legacy callers; removed the native `confirm()`; dropped the now-unused `nickname` lookup.

### Bucket C — ARIA + focus trap on the seven existing modals

**New file:**
- `app/javascript/controllers/modal_a11y_controller.js` — connects to a `[role="dialog"]` element, walks up to find the closest wrapper that toggles `.hidden` (the outer `position: fixed` div), uses a `MutationObserver` on the wrapper's `class` attribute to detect open/close transitions. On open: saves prior focus, focuses the first focusable element, attaches Tab-trap keydown listener. On close: restores prior focus, detaches listener.

**Per-modal patch (8 modals — 7 existing + 1 new shared partial covered by Bucket B):**
- `app/views/dashboard/_catch_modal.html.erb` — `gb-modal` div gets `role="dialog" aria-modal="true" aria-labelledby="catch-modal-title" data-controller="modal-a11y"`; title text wrapped in `<span id="catch-modal-title">`.
- `app/views/dashboard/_pokemon_modal.html.erb` — same pattern, id `pokemon-modal-title`.
- `app/views/dashboard/_mark_dead_modal.html.erb` — same, id `mark-dead-modal-title`.
- `app/views/dashboard/_reset_draft_modal.html.erb` — same, id `reset-draft-modal-title`.
- `app/views/species_assignments/show.html.erb` (group modal at line 133) — same, id `group-modal-title`. The title `<span>` already had `data-species-assignment-target="modalTitle"`; both attributes coexist.
- `app/views/gym_drafts/show.html.erb` (coin-flip modal at line 177) — **ARIA only, no `data-controller="modal-a11y"`.** The coin-flip has no close button and auto-dismisses post-animation; a focus trap during the animation would cause input weirdness. Documented inline.
- `app/views/teams/_quick_calc_modal.html.erb` — same as catch/pokemon, id `quick-calc-modal-title`.

**Layout change:**
- `app/views/layouts/pixeldex.html.erb:28` — `<body>` gets `data-controller="escape-close"`. The dashboard layout previously had no ESC handler at all (only `application.html.erb` did), so all four dashboard modals had no ESC support before this step. Brought to parity with the application layout. (This was implicit in Bucket C — the modal-a11y controller relies on the global escape-close handler clicking `.gb-modal-close` to actually close the modal.)

### Bucket D — Gym-schedule Cancel: proposer-only + channel authz

- **`app/views/gym_schedules/show.html.erb:62-81`** — wrapped the cancel-button `<div>` (and its accompanying confirm-modal partial) in `<% if @schedule.proposed_by == current_user_id %>`. Non-proposers no longer see the trigger.
- **`app/channels/gym_schedule_channel.rb:23-25`** — `cancel(_data)` now early-returns with `transmit({ error: "Only the proposer can cancel this schedule." })` when `current_user_id != @schedule.proposed_by`. Same `transmit({ error: })` shape as the `rsvp` rescue path, so the JS controller's existing error display path (if any) handles it.

### Bucket E — `<NEXT` literal cleanup

- **`app/views/dashboard/_gyms_content.html.erb:52`** — replaced the `&lt;NEXT` literal with a styled type-text badge: `<span class="type-text" style="border-color: var(--amber); color: var(--amber); margin-left: 4px;">NEXT</span>`. Reuses the existing badge styling alongside the type-abbreviation badge on the same row.

---

## Tests

Per the user's standing instruction (integration test, helper unit test, layout regression test), plus the channel-authz test added for Bucket D.

**New files:**
- `test/factories/gym_schedules.rb` — factory for `:gym_schedule` (no factory existed before; `proposed_by` defaults to GREY's discord_user_id, scheduled 1 day out, status `"proposed"`).
- `test/helpers/confirm_modal_helper_test.rb` — 11 tests. Asserts all required locals render, ARIA wiring (`role="dialog"`, `aria-modal="true"`, `aria-labelledby="<id>-title"`, `id="<id>-title"`), `data-controller="confirm-modal"`, that `confirm_data` spreads as data-* attributes (including the slot_number integer case), `confirm_class` default + override, `cancel_label` default + override, that the body accepts safe HTML (`<strong>` survives), that the modal starts `class="hidden"`.
- `test/integration/confirm_modal_flow_test.rb` — 4 tests. Logs in via the existing `LoginHelper`, fetches `/runs` and `/`, asserts (a) the END RUN trigger no longer carries the direct `run-management#endRun` action, (b) it now carries `confirm-modal#open` with the right id-param, (c) the confirm modal partial is rendered with correct ARIA and the correct title copy, (d) the dashboard runs tab uses a different id (`end-run-dashboard-confirm`) than the `/runs` page (`end-run-page-confirm`).
- `test/integration/responsive_grids_test.rb` — 3 tests. Reads `app/assets/stylesheets/pixeldex.css` and asserts: (a) the existing 900px block keeps `gb-grid-3` / `gb-grid-4` at 2 columns, (b) the new 520px block collapses them to 1 column, (c) `gb-grid-2` is not overridden in either breakpoint. Same shape as the YAML data tests.
- `test/channels/gym_schedule_channel_test.rb` — 4 tests. Subscribes as proposer (cancel succeeds, schedule transitions to `cancelled`), subscribes as non-proposer (cancel rejected with the proposer-only error message; schedule stays `proposed`; no extra broadcast triggered).

**Total new tests: 22** — 11 helper + 4 integration confirm-modal + 3 responsive-grids + 4 channel.
**Suite: 654 → 676 runs (+22). 2011 → 2095 assertions (+84). 0 failures, 0 errors.**

---

## Decisions made for ambiguities in the brief

1. **Where to register `confirm-modal` controllers** — the brief locked `window.__confirmModals = {id: element}` as the cross-controller lookup. Implemented exactly that. Brief KG-32 captures this as an acceptable v1 trade-off.

2. **`confirm_data` hash key serialization** — partial uses `k.to_s.dasherize` to convert `{ slot_number: 3 }` → `data-slot-number="3"`. Standard Rails convention.

3. **Body HTML safety** — the partial renders body via `raw(body)` because the brief explicitly required `<strong>` to survive. Trusted call sites only (no user input flows into a confirm-modal body in any of the six wire sites; the schedule's `scheduled_at.strftime` value is the only dynamic content in any body, and it goes through `strftime` before reaching the helper).

4. **Coin-flip modal — ARIA only, no `modal-a11y`.** The brief listed it among the eight modals to attach `modal-a11y` to. On second read, the coin-flip has no close button and auto-dismisses; a focus trap during the 3D coin animation would cause input weirdness on slow devices. Architect-call dependent — if Richard wants `modal-a11y` attached, I'll add it. Documented inline in the partial.

5. **Comment block in `_confirm_modal.html.erb`** — initial draft included an `<%# ... %>` multi-line example block with a nested `<%= confirm_modal(...) %>` example. ERB comments DON'T NEST: the inner `<%= %>` closed the outer `<%#` early, leaking text into the rendered output. Caught by integration test on first run; replaced with a pointer to `ConfirmModalHelper#confirm_modal` instead of an inline example. Tests pass on second run.

6. **Layout fix bundled in.** Adding `data-controller="escape-close"` to `pixeldex.html.erb`'s `<body>` wasn't explicitly in the brief, but the brief's Bucket C assumes ESC works for dashboard modals — it didn't, because the dashboard uses a different layout. Single-line edit. Documented above.

7. **`save_slots_controller.js#_actionButtons()` selector update.** Bucket B's wire-in changed the DELETE trigger's `data-action` from `save-slots#deleteSlot` to `confirm-modal#open`, breaking the `_actionButtons()` selector that drives overwrite-pending button-disabling. Updated the selector to match the new trigger by `[data-confirm-modal-id-param^='delete-slot-']`. Preserves the existing UX.

---

## Files

### New (8)
- `app/helpers/confirm_modal_helper.rb`
- `app/javascript/controllers/confirm_modal_controller.js`
- `app/javascript/controllers/modal_a11y_controller.js`
- `app/views/shared/_confirm_modal.html.erb`
- `test/channels/gym_schedule_channel_test.rb`
- `test/factories/gym_schedules.rb`
- `test/helpers/confirm_modal_helper_test.rb`
- `test/integration/confirm_modal_flow_test.rb`
- `test/integration/responsive_grids_test.rb` (9 — counted above)

### Modified (22)
- `app/assets/stylesheets/pixeldex.css`
- `app/channels/gym_schedule_channel.rb`
- `app/javascript/controllers/clear_save_controller.js`
- `app/javascript/controllers/gym_schedule_controller.js`
- `app/javascript/controllers/run_management_controller.js`
- `app/javascript/controllers/save_slots_controller.js`
- `app/javascript/controllers/species_assignment_controller.js`
- `app/views/dashboard/_catch_modal.html.erb`
- `app/views/dashboard/_gyms_content.html.erb`
- `app/views/dashboard/_mark_dead_modal.html.erb`
- `app/views/dashboard/_pokemon_modal.html.erb`
- `app/views/dashboard/_reset_draft_modal.html.erb`
- `app/views/dashboard/_runs_content.html.erb`
- `app/views/emulator/_save_slots_sidebar.html.erb`
- `app/views/gym_drafts/show.html.erb`
- `app/views/gym_schedules/show.html.erb`
- `app/views/layouts/pixeldex.html.erb`
- `app/views/runs/index.html.erb`
- `app/views/species_assignments/_group_card.html.erb`
- `app/views/species_assignments/show.html.erb`
- `app/views/teams/_quick_calc_modal.html.erb`
- `handoff/ARCHITECT-BRIEF.md`

---

## Things to verify (Richard, focus here)

1. **Accessibility shape on every modal.** ARIA attributes correct (`role="dialog"`, `aria-modal="true"`, `aria-labelledby` pointing at a real `id`). Focus trap holds — Tab from the last focusable wraps to the first, Shift-Tab from the first wraps to the last.
2. **ESC closes every modal in the dashboard layout** (it didn't before this step — the global escape-close was attached only to the `application` layout's body). Verify by inspecting the `pixeldex.html.erb` `data-controller` change.
3. **All six destructive trigger paths.** For each — END RUN ×2, save-slot DELETE, CLEAR ALL SLOTS, group DEL, schedule Cancel — the trigger no longer fires the action directly; it opens the modal whose confirm button carries the original Stimulus action.
4. **Channel authz.** Non-proposer trying to cancel a schedule via WebSocket gets the rejection transmit and the schedule does NOT transition. Test covers this.
5. **`save_slots_controller.js#_actionButtons()` selector update is correct** — overwrite-pending mode still disables the DELETE trigger.
6. **Coin-flip modal ARIA-only call.** Architect-call dependent; if you'd rather have `modal-a11y` attached, flag it and I'll add it.

Open the files, walk through them. Tests are dense but markup-only — the real Selenium-driven Tab/ESC interaction proof is a system test we deferred (out of brief scope; integration coverage was the user's explicit ask).
