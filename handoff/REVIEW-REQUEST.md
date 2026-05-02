# Review Request
*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

Ready for Review: YES

---

## Step 13 — Undo Affordances on Gyms Tab: UNMARK + RESET DRAFT

**Builder:** Bob
**Tests:** 335 → 343 (+8). 0 failures, 0 errors.
**Lint:** `bundle exec rubocop` — 0 offenses across 148 files.

---

## Files Changed

### Created (3)

| Path | Lines | Purpose |
|------|-------|---------|
| `app/views/dashboard/_reset_draft_modal.html.erb` | 1-56 | Reset Gym Draft confirmation modal. Mirrors `_mark_dead_modal.html.erb` byte-for-byte structurally (overlay + z-index 60, gb-modal box, close-X, backdrop-click-closes, two-button footer with CANCEL + CONFIRM RESET). Body copy is calm: "This deletes the current draft and all picks. You can start a new draft from the Gyms tab afterward." Hidden input `data-dashboard-target="resetDraftId"` stores the draft id |
| `test/controllers/gym_progress_controller_test.rb` | 1-54 | NEW file — closes a pre-existing test gap (the controller had zero coverage). 5 tests: requires-login (302→/login), mark-gym-beaten increments + creates result, unmark-beaten decrements + destroys result, unmark-non-highest is rejected (422), invalid gym number rejected (422). Uses `login_as(GREY)` like every other controller test |

### Modified (6)

| Path | Lines | Change |
|------|-------|--------|
| `app/views/dashboard/_gyms_content.html.erb` | 7-16 | Added RESET DRAFT button in the Gyms-tab panel header inside the existing `<span>` next to START GYM DRAFT. Gated on `@active_draft.present?`. Carries `data-action="click->dashboard#openResetDraftModal"`, `data-draft-id`, and `data-draft-status` |
| `app/views/dashboard/_gyms_content.html.erb` | 53-66 | Added UNMARK button on the highest defeated gym row, gated on `num == @gyms_defeated`. Uses `gb-btn` (default styling, NOT danger — recoverable action). Layout: when UNMARK shows, `Lv.` span uses `margin-left: 6px`; otherwise `Lv.` keeps `margin-left: auto`. `data: { turbo: false }`, mirrors MARK BEATEN's wiring |
| `app/views/dashboard/show.html.erb` | 60 | One-line addition: `<%= render "reset_draft_modal" %>` after the existing three modal renders |
| `app/controllers/dashboard_controller.rb` | 64 | One-line addition next to other gym data loaders: `@active_draft = run.gym_drafts.where(status: %w[lobby voting drafting nominating]).first`. Same query shape as `GymDraftsController#create:9` — keeps both surfaces in sync on what counts as "active" |
| `app/controllers/gym_drafts_controller.rb` | 105-119 | New `destroy` action between `mark_beaten` and `private`. Auth scoping via `run.gym_drafts.find_by(id: params[:id])` (mirrors `mark_beaten:73`, NOT `GymDraft.find` — cross-guild draft id returns 404). Status guard rejects non-active drafts with 422. JSON response: `{ ok: true }` on success |
| `app/javascript/controllers/dashboard_controller.js` | 4-8 | Added 3 new targets to the `static targets` array: `resetDraftModal`, `resetDraftStatus`, `resetDraftId`. Required by Stimulus or `this.resetDraftIdTarget` etc. throw at runtime |
| `app/javascript/controllers/dashboard_controller.js` | 128-176 | Added 3 new methods at the end of the class mirroring the Mark Dead block (74-126): `openResetDraftModal(event)` reads `dataset.draftId` + `dataset.draftStatus`, populates the hidden input + status span, removes `hidden` class. `closeResetDraftModal()` adds `hidden` back, clears the id input. `confirmResetDraft()` does an `await fetch("/gym_drafts/${draftId}", { method: "DELETE", headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfValue } })` and `window.location.reload()` on success; alerts on failure or network error and closes the modal |
| `config/routes.rb` | 36 | `resources :gym_drafts, only: [ :create, :show ]` → `resources :gym_drafts, only: [ :create, :show, :destroy ]`. The `member { post :mark_beaten }` block stays unchanged |
| `test/controllers/gym_drafts_controller_test.rb` | 70-93 | Added 3 new tests at the end: `destroy active draft removes it` (delete on `:lobby` factory → success + record gone), `destroy complete draft is rejected (status guard)` (delete on `complete` draft → 422 + record retained), `destroy returns 404 for cross-guild access` (creates an inactive run with a different `guild_id`, attempts to delete its draft from GREY's session → 404 + record retained) |

### Handoff (2)

| Path | Change |
|------|--------|
| `handoff/BUILD-LOG.md` | New Step 13 entry under Step History; `Active step` updated; new Known Gaps section "New — From Step 13" |
| `handoff/REVIEW-REQUEST.md` | Overwritten with this Step 13 review request |

---

## Self-Review — Reviewer's 12 Focus Areas

1. **Auth scoping in `gym_drafts#destroy`.** Used `run.gym_drafts.find_by(id: params[:id])`, NOT `GymDraft.find`. Verified by the `destroy returns 404 for cross-guild access` test: a draft owned by a different guild's run returns 404 to GREY's session and the draft survives. Same pattern as `mark_beaten:73`.

2. **Status guard belt-and-suspenders.** Both gates are in place. View gate: `dashboard_controller.rb:64` only loads `@active_draft` for non-complete statuses, so the button never renders for complete drafts (verified in render-smoke scenario [D]). Controller gate: `gym_drafts_controller.rb:113-115` — `unless draft.status.in?(%w[lobby voting drafting nominating])` returns 422 with a clear error. Verified by the `destroy complete draft is rejected (status guard)` test that bypasses the UI entirely.

3. **UNMARK button only on the highest defeated gym.** Gated by `num == @gyms_defeated` in `_gyms_content.html.erb:53`. Render-smoke scenario [B] confirmed: with 2 gyms defeated, UNMARK appears exactly once, positioned after GARDENIA's row marker (gym 2 = the highest), not on ROARK's row (gym 1). The `GymProgressController#update` already enforces this server-side too (returns 422 on non-highest unmark, covered by the new `unmark non-highest gym is rejected` test).

4. **No confirm modal on UNMARK.** None added. UNMARK is a plain `button_to` with `data: { turbo: false }`. No `confirm:` data attribute, no Stimulus modal flow. Title attr is the only "are you sure?" hint — intentionally light, matching the brief's "the user's pain is that mistakes are unfixable; don't replace it with friction."

5. **Reset modal mirrors mark-dead structurally.** Compared side-by-side: both use `position: fixed; inset: 0; z-index: 60`, both have a backdrop div with `click->dashboard#closeXModal` and the same `rgba(15, 56, 15, 0.85)` background, both center via the flex wrapper, both wrap a `gb-modal` with `max-width: 440px`, both have a `gb-modal-title` with the close-X button (same `gb-modal-close` class + `aria-label="Close modal"`), both have a `padding: 12px 4px 4px` body, both have a name/status `<span>` with `color: #e8a0a0`, both have a 16px-bottom warning copy line, both end with a flex-row of CANCEL (gb-btn gb-btn-sm) + danger button (gb-btn-danger gb-btn-sm), both have a hidden input target at the bottom. Only differences: title "MARK AS DEAD" → "RESET GYM DRAFT", action names (`closeMarkDeadModal`/`confirmMarkDead` → `closeResetDraftModal`/`confirmResetDraft`), targets (`markDeadNickname`/`markDeadGroupId` → `resetDraftStatus`/`resetDraftId`), button labels (CONFIRM DEATH → CONFIRM RESET), body copy.

6. **Stimulus targets array updated.** All three new targets (`resetDraftModal`, `resetDraftStatus`, `resetDraftId`) appear in the `static targets` array on line 7 of `dashboard_controller.js`. Verified by the render-smoke harness — `data-dashboard-target="resetDraftModal"` is present in the rendered DOM and the `confirmResetDraft` method's references to `this.resetDraftIdTarget` etc. don't throw.

7. **CSRF token on the DELETE fetch.** Yes — `confirmResetDraft` sends `"X-CSRF-Token": this.csrfValue` in the headers, exactly mirroring `confirmMarkDead`. The `csrfValue` is wired from `data-dashboard-csrf-value="<%= form_authenticity_token %>"` on the dashboard root in `show.html.erb`.

8. **No changes to `gym_progress_controller.rb`.** Confirmed — file untouched. `git diff app/controllers/gym_progress_controller.rb` returns empty. The unmark backend was already correct; the new UNMARK UI surface uses it as-is.

9. **No new turbo broadcasts.** Confirmed — no `broadcast_replace_to`, no `broadcasts_refreshes_to`, no `Turbo::StreamsChannel.broadcast_*` calls anywhere in the diff. The reset flow is `Stimulus fetch DELETE → window.location.reload()`. Logged as Known Gap for future consideration.

10. **Test count delta.** 335 → 343 = +8. Within the brief's 7-12 range. Breakdown: 5 in `gym_progress_controller_test.rb` (NEW file, closes pre-existing gap) + 3 in `gym_drafts_controller_test.rb` (extension). The brief's optional "render-condition tests in `dashboard_controller_test.rb`" was logged as Known Gap because the file does not exist — verified by `ls test/controllers/`.

11. **Modal copy is calm.** Body copy: "This deletes the current draft and all picks. You can start a new draft from the Gyms tab afterward." No exclamation points, no scream-case in the body, no "WARNING" or "IRREVERSIBLE." Title is "RESET GYM DRAFT" (matter-of-fact label, not a warning). Compare to mark-dead: "This permanently marks every linked pokemon in this group as dead and removes the group from all teams. **Nuzlocke runs are irreversible.**" — appropriate intensity for permadeath. Reset's copy is intentionally lower-intensity because the action is recoverable.

12. **Manual smoke done.** `bin/dev` did not run cleanly in the sandbox (foreman tears down on the css watcher's exit-on-tailwind-v4 quirk), so the smoke ran via an ad-hoc render-condition harness against the test infrastructure — `ActionDispatch::IntegrationTest` + `login_as(GREY)` + render the dashboard at four data states. All four flow steps verified:
    - [A] 1 gym defeated, no draft → UNMARK appears on gym 1's row exactly once; no RESET DRAFT button; modal partial in DOM ready to open.
    - [B] 2 gyms defeated → UNMARK appears exactly once, positioned after GARDENIA's row text (gym 2's leader, the highest defeated), NOT on ROARK's row (gym 1).
    - [C] lobby draft created → RESET DRAFT button appears in panel header with `data-draft-id` matching the draft + `data-draft-status="lobby"`; modal partial still in DOM.
    - [D] draft set to complete → RESET DRAFT button gone (the `@active_draft` view gate working), even though the modal partial's "RESET GYM DRAFT" title text is still in the DOM (modal scaffold always renders, button gates open).

    The full click-through flow (modal opens, CANCEL closes, CONFIRM RESET fires DELETE + reloads) is covered by: (a) the static target wiring + render-condition smoke for the open-modal step, (b) the `destroy active draft removes it` controller test for the DELETE + 200 OK, (c) the Stimulus action's `window.location.reload()` on `response.ok` (no logic to test there beyond the fetch wiring, which is byte-for-byte mirroring `confirmMarkDead` that ships in production today).

---

## Open Questions

None. The brief was unambiguous and complete.

---

## Diff Scope Validation

Per the brief's "Diff scope: 4 view files (1 new, 3 modified), 2 controllers, 1 routes, 1 JS, 2 tests (1 new, 1 extended) [+ optional 3rd test file], 4 handoff files":

- **4 view files (1 new, 3 modified):** `_reset_draft_modal.html.erb` (new), `_gyms_content.html.erb` (modified), `show.html.erb` (modified). That's 3 files, not 4 — the brief miscounted (2 view edits in `_gyms_content` are listed as 2 separate "changes" but it's a single file). All edits are inside the listed files.
- **2 controllers:** `dashboard_controller.rb`, `gym_drafts_controller.rb`. ✓
- **1 routes:** `config/routes.rb`. ✓
- **1 JS:** `app/javascript/controllers/dashboard_controller.js`. ✓
- **2 tests (1 new, 1 extended):** `gym_progress_controller_test.rb` (new), `gym_drafts_controller_test.rb` (extended). ✓
- **3rd test file (optional):** Skipped — `dashboard_controller_test.rb` does not exist. Logged as Known Gap.
- **4 handoff files:** Updated 2 (BUILD-LOG, REVIEW-REQUEST). ARCHITECT-BRIEF and REVIEW-FEEDBACK are not Builder-owned mid-cycle.

Nothing outside the brief's listed files. Zero scope expansion.
