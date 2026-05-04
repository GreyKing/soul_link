# Architect Brief — Step 20
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 20 — Phase 1 cross-cutting safety nets (post-audit follow-through)

The 2026-05-04 UI/UX audit (`handoff/2026-05-04-ui-audit.md`) shipped `028643b`. § 5 of that audit names a Phase 1 of cross-cutting fixes that need to land before any of the bigger redesigns (R3 Save Slots / R2 PC Box / R4 Map / R1 Dashboard) begin. This step ships **all five** Phase 1 buckets in one bundle. They are independent and small individually; bundling lets us pay one review tax and unblock the redesigns.

**Out of scope this step:** any of the four redesigns themselves; backend audit; Discord-bot decomposition. Those each get their own session.

---

## Five buckets — all in scope, ship as one step

### Bucket A — `gb-grid-N` media queries (CSS only)

**Problem the audit flagged.** `.gb-grid-3` / `.gb-grid-4` reflow to 2 columns at ≤900px (existing rule in `app/assets/stylesheets/pixeldex.css:1057-1058`) but never collapse below that. On a 360px phone, two-column with content like player cards or stat tiles is unusable.

**Locked decision.** Add a single new media-query block to `pixeldex.css` directly after the existing `@media (max-width: 900px)` block:

```css
@media (max-width: 520px) {
  .gb-grid-3 { grid-template-columns: 1fr; }
  .gb-grid-4 { grid-template-columns: 1fr; }
}
```

**Do NOT touch.** `.gb-grid-2` stays 2-column at all sizes — it's already mobile-friendly (label + value pairs). No ERB changes for bucket A; the existing `gb-grid-3` / `gb-grid-4` consumers (runs/index, dashboard runs tab, teams/index, gym_ready, map special encounters, gym_schedules show RSVP grid) inherit the new breakpoint automatically.

**Why 520px.** Below 520 we see consistent pain on phones; above 520 (small landscape, tablet portrait) two-column still works. Round number, easy to remember, halfway between 360 (phone portrait) and 900 (existing breakpoint).

---

### Bucket B — Shared `confirm_modal` partial + helper + Stimulus controller

**Problem the audit flagged.** Five destructive actions ship today with no confirmation: `END RUN` (×2 surfaces), save-slot `DELETE`, `CLEAR ALL SLOTS`, group `DEL`, schedule `Cancel`. The `MARK DEAD` modal already implements the right pattern; we factor it into a reusable partial and wire it into all six trigger sites.

**Locked file layout.**
- New directory: `app/views/shared/`
- New partial: `app/views/shared/_confirm_modal.html.erb`
- New helper: `app/helpers/confirm_modal_helper.rb` (`include`d via `ApplicationHelper`'s convention — Rails auto-loads helpers).
- New JS controller: `app/javascript/controllers/confirm_modal_controller.js` (registered through the Stimulus index).

**Locked partial signature.** Render via `<%= confirm_modal(id:, title:, body:, confirm_label:, confirm_class:, confirm_data:) %>` where:
- `id` — string, becomes the modal element's DOM id (e.g. `"end-run-confirm"`).
- `title` — uppercase short string (e.g. `"END THIS RUN?"`).
- `body` — paragraph copy explaining the consequence; safe HTML allowed (use `<strong>` for the irreversible-warning sentence).
- `confirm_label` — uppercase short string for the destructive button (e.g. `"END RUN"`).
- `confirm_class` — defaults to `"gb-btn-danger gb-btn-sm"`.
- `confirm_data` — hash of additional `data-*` attributes for the confirm button (this is where the original Stimulus action goes — e.g. `{ action: "click->run-management#endRun" }`).

**Locked partial markup.** Mirrors `_mark_dead_modal.html.erb` shape:
- Outer fixed `inset: 0; z-index: 50` div with `data-controller="confirm-modal" data-confirm-modal-id-value="<id>"`.
- Backdrop div with `data-action="click->confirm-modal#close"`.
- Inner `gb-modal` wrapper with `role="dialog" aria-modal="true" aria-labelledby="<id>-title"`.
- Title row with `<id>-title` id + close button (`aria-label="Close modal"`, `data-action="click->confirm-modal#close"`).
- Body paragraph rendered as `raw(body)` (caller responsible for safety — locked to trusted call sites).
- Action row: `CANCEL` button (`gb-btn gb-btn-sm`, `data-action="click->confirm-modal#close"`) + confirm button (`<%= confirm_class %>` + `<%= confirm_data %>` attributes spread).

**Locked Stimulus controller (`confirm_modal_controller.js`).**
- Static value `id: String`.
- `connect()` — registers the modal in a global `window.__confirmModals = {id: element}` map so trigger buttons can look it up by id without DOM-walking.
- `disconnect()` — removes from the map.
- `open(event)` — reads `event.params.id`, looks up the modal via the map, removes `.hidden`, saves `document.activeElement` as the prior-focus, focuses the cancel button (safe default).
- `close()` — adds `.hidden`, restores prior focus.
- ESC handler — bound on document while open, unbound on close. Hits `close()`.
- Tab/Shift-Tab focus trap — keeps focus inside the modal; on Tab from last focusable, wraps to first; on Shift-Tab from first, wraps to last.

**Locked trigger pattern.** Each destructive trigger button changes from a direct action to:
```erb
<button data-action="click->confirm-modal#open"
        data-confirm-modal-id-param="end-run-confirm"
        class="gb-btn-danger gb-btn-sm">END RUN</button>
```
and the existing action moves into the modal's confirm button (`confirm_data: { action: "click->run-management#endRun" }`).

**Six wire sites — locked copy.**

1. **`dashboard/_runs_content.html.erb:73-76` (END RUN, dashboard tab)** — id `"end-run-dashboard-confirm"`. Title `"END THIS RUN?"`. Body: `"This archives the current run and stops Soul Link tracking. <strong>Runs cannot be un-ended through the UI.</strong>"`. Confirm `"END RUN"`. Confirm data: `{ action: "click->run-management#endRun" }`.

2. **`runs/index.html.erb:44-47` (END RUN, /runs page)** — id `"end-run-page-confirm"` (must differ from the dashboard tab's id; the two surfaces can both render in the same page tree if a future redesign merges them). Same title/body/label/action as 1.

3. **`emulator/_save_slots_sidebar.html.erb:146-152` (DELETE slot)** — id `"delete-slot-#{n}-confirm"` (per-slot, since the slot number is part of the action context). Title `"DELETE THIS SLOT?"`. Body: `"This permanently removes the save data for slot <%= n %>. <strong>The save file is gone after this — there is no undo.</strong>"`. Confirm `"DELETE FOREVER"`. Confirm data: `{ action: "click->save-slots#deleteSlot", slot_number: n }`.

4. **`emulator/_save_slots_sidebar.html.erb:166-171` (CLEAR ALL SLOTS)** — id `"clear-all-slots-confirm"`. Title `"CLEAR EVERY SAVE?"`. Body: `"This wipes <strong>all <%= @save_slots.size %> save slots</strong> at once. There is no undo for any of them."`. Confirm `"CLEAR ALL SLOTS"`. Confirm data: `{ action: "click->clear-save#clear" }`.

5. **`species_assignments/_group_card.html.erb:28-32` (DEL group)** — id `"delete-group-#{group.id}-confirm"` (per-group). Title `"DELETE GROUP?"`. Body: `"Removes <strong><%= group.nickname %></strong> and every player's species assignment in this group."`. Confirm `"DELETE GROUP"`. Confirm data: `{ action: "click->species-assignment#deleteGroup", group_id: group.id }`.

6. **`gym_schedules/show.html.erb:62-69` (Cancel schedule)** — id `"cancel-schedule-confirm"`. Title `"CANCEL THIS SCHEDULE?"`. Body: `"This cancels the proposed gym battle for <strong><%= @schedule.scheduled_at.strftime("%A, %B %-d at %-I:%M %p") %></strong>. RSVPs are discarded."`. Confirm `"CANCEL SCHEDULE"`. Confirm data: `{ action: "click->gym-schedule#cancel" }`. **This trigger is also gated by Bucket D** — only the proposer sees it.

**Existing `_mark_dead_modal.html.erb` — leave alone this step.** It works, has its own copy, and converting it would touch Step-19-shipped guards. Future cleanup can fold it onto the shared partial; out of scope here. (Same for `_reset_draft_modal.html.erb`.)

---

### Bucket C — ARIA + focus trap on every modal

**Problem the audit flagged.** Every modal in the app is a `<div>` with `position: fixed`. Close buttons have `aria-label`, but the modal containers themselves are unannounced. Tab key escapes the modal into the page behind it. Screen readers see "row of buttons," not "dialog."

**Locked file change.**
- New JS controller: `app/javascript/controllers/modal_a11y_controller.js`. **Separate** from `confirm_modal_controller.js` because the existing seven modals already have parent controllers (dashboard, pixeldex, gym-draft, etc.) that own open/close — we attach `modal-a11y` as a **sibling** controller on the same element, additively.

**Locked controller behavior.**
- `connect()` — sets up a `MutationObserver` watching the `class` attribute of its element. Saves a reference to the existing parent close-button (`[data-modal-a11y-target="close"]`). Establishes the focus-trap and ESC handlers in a "disabled" state.
- On `class` mutation removing `hidden` — saves `document.activeElement` as prior focus, focuses first focusable element inside the modal, attaches `keydown` listener that handles Tab/Shift-Tab wrap + ESC (ESC simulates a click on the close button via `closeButtonTarget.click()` so the existing parent controller handles state).
- On `class` mutation adding `hidden` — detaches `keydown` listener, restores prior focus.
- `disconnect()` — tears down observer + listeners.

**Locked modal inventory and per-modal changes (8 total).**

| File | Outer wrapper | Title element | Close button |
|---|---|---|---|
| `dashboard/_catch_modal.html.erb` | gb-modal: add `role="dialog" aria-modal="true" aria-labelledby="catch-modal-title" data-controller="modal-a11y"` | gb-modal-title: add `id="catch-modal-title"` | `.gb-modal-close`: add `data-modal-a11y-target="close"` |
| `dashboard/_pokemon_modal.html.erb` | same pattern | id `pokemon-modal-title` | same |
| `dashboard/_mark_dead_modal.html.erb` | same | id `mark-dead-modal-title` | same |
| `dashboard/_reset_draft_modal.html.erb` | same | id `reset-draft-modal-title` | same |
| `species_assignments/show.html.erb` (group modal at line 133) | same (inline) | id `group-modal-title` | same |
| `gym_drafts/show.html.erb` (coin-flip modal at line 177) | same (inline) | id `coin-flip-modal-title` | same |
| `teams/_quick_calc_modal.html.erb` | same | id `quick-calc-modal-title` | same |
| `app/views/shared/_confirm_modal.html.erb` (NEW) | bake the same attrs in directly | dynamic id from partial locals | wired in partial |

**Already covered.** The new `_confirm_modal.html.erb` partial already includes all of these (Bucket B locks them in the partial markup). It does NOT additionally use `modal-a11y` because `confirm-modal` already handles ESC + focus management; piling on would double-bind ESC. Bucket B's controller is the focus-trap implementation for confirm modals; Bucket C's controller is for the seven existing modals.

---

### Bucket D — Gym-schedule Cancel: proposer-only visibility + channel authz

**Problem the audit flagged.** `gym_schedules/show.html.erb:63-69` shows the Cancel button to every viewer. The audit notes this isn't just UX — `app/channels/gym_schedule_channel.rb:21-27` accepts cancel from anyone too. Two-part fix.

**Locked decisions.**

1. **View change** — wrap the cancel-button div in `<% if @schedule.proposed_by == current_user_id %>`. The `@schedule` ivar is already exposed via the controller (`gym_schedules_controller.rb#show`); `current_user_id` is the existing helper. After Bucket B is in place, this also guards the trigger that opens the confirm modal.

2. **Channel change** — `gym_schedule_channel.rb#cancel(_data)` adds proposer authz at the top:
```ruby
def cancel(_data)
  @schedule.reload
  unless @schedule.proposed_by == current_user_id
    return transmit({ error: "Only the proposer can cancel this schedule." })
  end
  @schedule.cancel!
  broadcast_state
rescue => e
  transmit({ error: e.message })
end
```
Same `transmit({ error: ... })` shape as the existing `rsvp` rescue. No new error format. Server-side enforcement so a hand-crafted WebSocket message can't bypass.

**Why both layers.** UI hide is the v1 contract for read-only mode (KG-28), but for cancel-schedule we have a clear authz scope (proposer = owner) and the server check is a one-liner. Don't carry KG-28's pattern into a place where it doesn't fit. Per-action call: server-enforce when ownership is unambiguous.

---

### Bucket E — `<NEXT` literal cleanup

**Problem the audit flagged.** `_gyms_content.html.erb:52` reads `&lt;NEXT` after the gym leader name. The `&#9654;` (▶) at line 50 + `&lt;NEXT` after the type abbreviation produces visually confused `▶ ROARK [RCK] <NEXT`.

**Locked replacement.** Replace line 52 (`            &lt;NEXT`) with:
```erb
            <span class="type-text" style="border-color: var(--amber); color: var(--amber); margin-left: 4px;">NEXT</span>
```

The amber border + color signals "next gym" cleanly. Reuses the existing `type-text` badge styling. Single-line edit.

---

## Build order

Strict left-to-right, one bucket at a time, commit-as-you-go to keep diffs reviewable. Hold the final commit + push until everything is green.

1. **Bucket A** — Single CSS edit. ~5 minutes. No tests yet.
2. **Bucket E** — Single ERB edit. ~5 minutes. No tests yet.
3. **Bucket D** — Two-part view + channel edit. Add a controller test.
4. **Bucket B** — Build the partial + helper + Stimulus controller. Then wire each of the 6 sites. Each site is a small ERB diff. Add the helper unit test as you build the helper, the system test after wiring END RUN (the first site).
5. **Bucket C** — Add `modal-a11y` controller. Then bulk-edit the 7 existing modal partials. The 8th (the confirm-modal partial from Bucket B) already covers itself.
6. Add the responsive-CSS regression test.
7. Run `bin/rails test`, `bundle exec rubocop`, `bundle exec brakeman`. Green-or-bust.
8. Ship.

---

## Tests required

Per the user's standing instruction:

1. **System test for at least one destructive action behind the new confirm-modal.** New file `test/system/confirm_modal_flow_test.rb`. Uses the existing `ApplicationSystemTestCase` (`driven_by :selenium, using: :headless_chrome`). Two cases:
   - Visiting `/runs` with an active run, the END RUN button is visible. Clicking it does NOT immediately fire `endRun` — instead, the confirm modal opens with `role="dialog"`, focus moves to the Cancel button. Pressing ESC closes the modal and the run remains active.
   - Visiting `/runs` again, clicking END RUN, then clicking the modal's `END RUN` confirm button — the original `run-management#endRun` fires (verify by either a backend assertion that the run is now ended, or by asserting the post-action UI state).

2. **Unit test for `confirm_modal` helper.** New file `test/helpers/confirm_modal_helper_test.rb`. Asserts:
   - All required locals (`id`, `title`, `body`, `confirm_label`) render.
   - The outer container has `role="dialog"`, `aria-modal="true"`, `aria-labelledby="<id>-title"`.
   - The title element has `id="<id>-title"`.
   - The confirm button gets the `data-action` from `confirm_data`.
   - `confirm_class` defaults to `"gb-btn-danger gb-btn-sm"`.
   - `body` accepts safe HTML (e.g. `<strong>` survives).

3. **Layout regression test for gb-grid responsive cascade.** New file `test/integration/responsive_grids_test.rb` — opens `Rails.root.join("app/assets/stylesheets/pixeldex.css")`, asserts the file contains both the existing 900px rule AND the new 520px rule. CSS file content asserts are unusual but match the project's existing pattern of validating data files (move_names.yml, gym_info.yml, etc.) via Ruby readers — same idea, different file extension.

4. **Channel authz test.** New `test/channels/gym_schedule_channel_test.rb` (or extend if it exists). Cases: proposer can cancel; non-proposer gets the error transmit; non-proposer's `@schedule.cancel!` is NOT called.

---

## Known gaps logged this step

- **KG-31** — Existing `_mark_dead_modal.html.erb` and `_reset_draft_modal.html.erb` keep their bespoke implementations rather than folding onto the shared `confirm_modal` partial. Future cleanup can consolidate; out of scope this step because it would touch Step-19-shipped read-only guards and the gym-draft reset flow.
- **KG-32** — `confirm-modal` Stimulus controller's `window.__confirmModals` global registry is the simplest cross-controller lookup but uses a global. Acceptable for v1; a future cleanup can switch to Stimulus outlets or custom events if more cross-component plumbing emerges.

---

## Done definition

- All five buckets land.
- Tests pass (`bin/rails test`).
- Rubocop clean.
- Brakeman clean for new code (pre-existing weak warnings fine).
- All six confirm-modal trigger sites verified manually by Bob in markup output (no more direct destructive actions in the affected views).
- Richard verifies the system test runs and signs off on the accessibility shape (ARIA attributes correct, focus trap behavior holds).
- BUILD-LOG + SESSION-CHECKPOINT updated.
- One commit `ship Step 20: Phase 1 cross-cutting safety nets (post-audit)`.
- FF-merge to main + push.

---

## Resume prompts

**For Bob (Builder):**
> You are Bob (Builder) on Soul Link — Three Man Team.
> Read handoff/ARCHITECT-BRIEF.md, then handoff/SESSION-CHECKPOINT.md.
> Implement Step 20 in the locked build order. Write to handoff/REVIEW-REQUEST.md when ready for Richard.

**For Richard (Reviewer):**
> You are Richard (Reviewer) on Soul Link — Three Man Team.
> Read handoff/REVIEW-REQUEST.md, then handoff/ARCHITECT-BRIEF.md.
> Verify Step 20 with focus on accessibility (ARIA, focus trap, keyboard) and the destructive-action confirmation paths. Write to handoff/REVIEW-FEEDBACK.md.
