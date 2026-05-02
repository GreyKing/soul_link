# Review Feedback — Step 13
Date: 2026-05-01
Ready for Builder: YES

## Must Fix

None.

## Should Fix

None blocking. One observation logged for the record:

- `app/javascript/controllers/dashboard_controller.js:151-175` — The full Stimulus modal click-through (open → CONFIRM RESET fetch → `window.location.reload()`) was not exercised in a real browser this cycle because `bin/dev` did not start cleanly in the sandbox (foreman/tailwind v4 quirk). Acceptable for shipping because (a) the three new methods mirror the production `openMarkDeadModal` / `closeMarkDeadModal` / `confirmMarkDead` block line-for-line, including the `try/catch`, the headers, and the `response.ok` branch; (b) target wiring is verified by the render-condition smoke (the `data-dashboard-target` attributes are present in the rendered DOM); (c) the controller-side DELETE path is covered by three new tests (200, 422, 404). Recommendation: when the next dashboard-touching step gets `bin/dev` running, click through this flow once and note it in BUILD-LOG. Already captured under the Step 13 Known Gap entry — no separate follow-up needed.

## Escalate to Architect

None.

## Cleared

All twelve focus areas pass.

1. **Auth scoping** — `gym_drafts_controller.rb:109` uses `run.gym_drafts.find_by(id: params[:id])`, scoped via `current_run = SoulLinkRun.current(session[:guild_id])`. The `destroy returns 404 for cross-guild access` test creates a draft on a different `guild_id` (with `active: false` to avoid the one-active-run-per-guild constraint) and proves GREY's session gets 404 with the draft surviving.

2. **Status guard belt-and-suspenders** — View gate at `dashboard_controller.rb:64` (`@active_draft = run.gym_drafts.where(status: %w[lobby voting drafting nominating]).first`) and at `_gyms_content.html.erb:6` (`<% if @active_draft %>` wraps the button). Controller gate at `gym_drafts_controller.rb:112-114` returns 422 with a clear error. Both gates needed; both present.

3. **UNMARK button only on highest defeated gym** — `_gyms_content.html.erb:63` gates with `<% if num == @gyms_defeated %>`. Render-condition smoke [B] confirmed the button appears once on gym 2's row when 2 gyms are defeated, not on gym 1.

4. **No confirm modal on UNMARK** — `_gyms_content.html.erb:64-68` is plain `button_to` with `data: { turbo: false }` and a `title:` attribute only. No `confirm:` data, no Stimulus open call. Light affordance, exactly as the brief specified.

5. **Reset modal mirrors mark-dead structurally** — Side-by-side comparison: same `position: fixed; inset: 0; z-index: 60`, same `rgba(15, 56, 15, 0.85)` backdrop, same `gb-modal` with `max-width: 440px`, same `gb-modal-title` + close-X with `aria-label="Close modal"`, same `padding: 12px 4px 4px` body, same `#e8a0a0` status color, same flex-row CANCEL (`gb-btn gb-btn-sm`) + danger button (`gb-btn-danger gb-btn-sm`), hidden input target at the bottom. Differences are exactly the labels/IDs/copy needed.

6. **Stimulus targets array** — `dashboard_controller.js:7` includes all three new targets: `"resetDraftModal", "resetDraftStatus", "resetDraftId"`. `this.resetDraftIdTarget` etc. won't throw at runtime.

7. **CSRF token on the DELETE fetch** — `dashboard_controller.js:160` sends `"X-CSRF-Token": this.csrfValue`. `show.html.erb:10` provides `data-dashboard-csrf-value="<%= form_authenticity_token %>"`.

8. **No changes to `gym_progress_controller.rb`** — File not in `git status`, content unchanged.

9. **No new turbo broadcasts on `GymDraft`** — Grep for `broadcast` in the controller and model: zero matches.

10. **Test count delta** — 335 → 343 = +8, in the brief's 7-12 range. Five of those land in a new `gym_progress_controller_test.rb` (closing a pre-existing gap), three extend `gym_drafts_controller_test.rb`.

11. **Modal copy is calm** — "This deletes the current draft and all picks. You can start a new draft from the Gyms tab afterward." No `<strong>` warning, no "WARNING" or "irreversible," no exclamation. Title "RESET GYM DRAFT" is matter-of-fact. Compare to mark-dead: `<strong>Nuzlocke runs are irreversible.</strong>`. Recoverable action gets recoverable copy.

12. **Manual smoke documented** — REVIEW-REQUEST and BUILD-LOG both walk through all four data states ([A] 1 defeated, [B] 2 defeated, [C] lobby draft, [D] complete draft) with the render-condition harness. The `bin/dev` constraint is named explicitly and the unrun JS click-through is logged as a known gap with the matching production-mirror argument.

Step 13 is clear.
