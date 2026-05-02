# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 13 — Undo Affordances on the Gyms Tab: Unmark Beaten + Reset Draft

### Context

Two related "let me undo a mistake" affordances on the dashboard's Gyms tab. Project Owner's verbatim ask:

> "add a remove gym beaten button from the gyms tab on the dashboard? I can't go back if I've mistakenly marked a gym beaten"
>
> "can we also have a gym draft reset button added?"

Both bundled into Step 13.

**Pre-flight discovery (saves Bob a step):** the backend for unmark already exists. `GymProgressController#update` (`app/controllers/gym_progress_controller.rb:14-25`) toggles based on whether a `GymResult` exists for that `gym_number` — if it does, it destroys it and decrements `gyms_defeated`, with a guard that only allows unmark of the highest gym. So the unmark feature is purely a UI surface that's missing — **no controller change needed for unmark**.

The reset feature is greenfield. `GymDraftsController` has no `destroy` action and the route doesn't expose one (`config/routes.rb:36`). Bob adds both.

### Project Owner decisions (locked)

- **Auto-accept mode for this work.** Bob can act decisively; Reviewer + tests are the backstop.
- **Unmark = no confirm modal.** The Project Owner's pain is *that mistakes are unfixable*; don't replace one friction with another. A plain button. The action is recoverable (just re-mark beaten).
- **Reset = full confirm modal, mirroring `_mark_dead_modal.html.erb`.** Resetting destroys 4-6 rounds of player picks (held in `state_data` JSON on the draft); that's real data the user crafted across multiple players. Modal mirrors the Step 10 mark-dead pattern: gb-modal-styled overlay, CANCEL (default) + CONFIRM RESET (gb-btn-danger), Stimulus actions on the existing `dashboard` controller.
- **Both buttons live on the dashboard's Gyms tab.** Unmark goes on the most recent defeated gym row (the only gym you're allowed to unmark). Reset goes in the panel header, alongside the existing START GYM DRAFT button, only when an active draft exists.
- **Reset = destroy.** Wipe the draft entirely; the user starts a new one via the existing START GYM DRAFT button. No partial-reset, no "back to lobby" — destroy and create-fresh is cleaner and matches the user's mental model ("reset = start over").
- **Reset condition: status in `[lobby, voting, drafting, nominating]`.** This matches the `GymDraftsController#create` reuse logic at `app/controllers/gym_drafts_controller.rb:9` — same set of "active" states. A `complete` draft is intentionally NOT resettable from the dashboard; the user marks-beaten or accepts the result. (See Out-of-Scope below.)
- **No new turbo broadcasts on `GymDraft`.** Reset action redirects back to the dashboard root; the page reload picks up the new state. Same pattern as `GymDraftsController#mark_beaten`. Adding `broadcasts_refreshes_to` is a separate concern (logged as future work).
- **Unmark response mirrors mark-beaten.** Same endpoint (`PATCH /gym_progress`), same `data: { turbo: false }` form posting, same JSON response. Whatever Mark Beaten does today, Unmark does. No regression on existing flow; no new response format.

### Implementation

#### 1. View edit — `app/views/dashboard/_gyms_content.html.erb`

**Two changes:**

(a) **Panel header — add RESET DRAFT button next to START GYM DRAFT** (after line 5).

The header is currently:
```erb
<div class="panel-header">
  <span>GYMS</span>
  <span style="display: flex; align-items: center; gap: 8px;">
    <span class="panel-header-sub"><%= @gyms_defeated %>/8 BADGES</span>
    <%= button_to "START GYM DRAFT", gym_drafts_path, method: :post, class: "gb-btn-primary gb-btn-sm", style: "font-size: 9px; padding: 3px 8px;" %>
  </span>
</div>
```

Add directly after the START GYM DRAFT button, gated on `@active_draft.present?`:

```erb
<% if @active_draft %>
  <button type="button"
          class="gb-btn-danger gb-btn-sm"
          style="font-size: 9px; padding: 3px 8px;"
          data-action="click->dashboard#openResetDraftModal"
          data-draft-id="<%= @active_draft.id %>"
          data-draft-status="<%= @active_draft.status %>">
    RESET DRAFT
  </button>
<% end %>
```

`@active_draft` is loaded by the dashboard controller (see #2). `data-draft-status` is for the modal copy (so the user sees what state they're resetting from).

(b) **Defeated gym row — add UNMARK button on the most recent defeated gym only** (lines 48-89, the `elsif defeated` branch).

Inside the `<div class="gym-list-item">` (lines 49-54), only when `num == @gyms_defeated` (the highest defeated gym, the only one the controller permits unmarking), add a small UNMARK button. The current row layout:

```erb
<div class="gym-list-item">
  <span class="gym-check">&#9733;</span>
  <%= gym["leader"]&.upcase %>
  <span class="type-text">...</span>
  <span style="margin-left: auto; font-size: 9px; color: var(--d2);">Lv. <%= gym["max_level"] %></span>
</div>
```

Add the button before the `Lv.` span (so it sits right of the type-text), gated on `num == @gyms_defeated`:

```erb
<% if num == @gyms_defeated %>
  <%= button_to "UNMARK", gym_progress_path(gym_number: num),
      method: :patch, class: "gb-btn gb-btn-sm",
      style: "font-size: 8px; padding: 2px 6px; margin-left: auto;",
      data: { turbo: false },
      title: "Removes the star and decrements the badge count" %>
<% end %>
```

Then put the `Lv.` span back, with `margin-left: 6px` instead of `auto` (since the unmark button now eats the auto-margin slot when present). Keep `margin-left: auto` for the `Lv.` span on rows where unmark isn't shown — i.e., make the layout conditional. Cleanest:

```erb
<% if num == @gyms_defeated %>
  <%= button_to "UNMARK", gym_progress_path(gym_number: num),
      method: :patch, class: "gb-btn gb-btn-sm",
      style: "font-size: 8px; padding: 2px 6px; margin-left: auto;",
      data: { turbo: false },
      title: "Removes the star and decrements the badge count" %>
  <span style="margin-left: 6px; font-size: 9px; color: var(--d2);">Lv. <%= gym["max_level"] %></span>
<% else %>
  <span style="margin-left: auto; font-size: 9px; color: var(--d2);">Lv. <%= gym["max_level"] %></span>
<% end %>
```

The button uses `gb-btn` (default styling, NOT danger) — unmark is recoverable; we're not signaling permadeath here. Title attr is the only "are you sure?" hint, intentionally light.

#### 2. Controller edit — `app/controllers/dashboard_controller.rb`

Load `@active_draft` for the gyms tab. Find the existing `show` action (or wherever the gyms tab data is set up — `@gyms_defeated`, `@gym_results`, etc. are loaded around line 50/63 per Architect's earlier read). Add:

```ruby
@active_draft = run.gym_drafts.where(status: %w[lobby voting drafting nominating]).first
```

Place it next to the existing gym data loaders (`@gym_info`, `@gyms_defeated`, `@gym_results`). Same query shape as `GymDraftsController#create:9`.

#### 3. New file — `app/views/dashboard/_reset_draft_modal.html.erb`

Mirror `_mark_dead_modal.html.erb` exactly. Same overlay, gb-modal box, close button, two-button footer (CANCEL + CONFIRM RESET). Body copy:

- Title: `RESET GYM DRAFT`
- Body: a span with the current draft's status pre-filled (e.g., "DRAFTING"), then warning copy: "This deletes the current draft and all picks. You can start a new draft from the Gyms tab afterward."
- Buttons: CANCEL (`gb-btn gb-btn-sm`) + CONFIRM RESET (`gb-btn-danger gb-btn-sm`)
- Hidden input `data-dashboard-target="resetDraftId"` stores draft id for the Stimulus action

Stimulus targets needed (declare in step 4): `resetDraftModal`, `resetDraftStatus`, `resetDraftId`.

Mirror the file scaffold of `_mark_dead_modal.html.erb`. Don't reinvent the structure — the `position: fixed; inset: 0; z-index: 60` overlay, the `gb-modal` inner box, the close-X in the title, the backdrop click → close — all of that comes verbatim. Only the body copy + button labels + Stimulus action names change.

#### 4. View edit — `app/views/dashboard/show.html.erb`

Currently lines 57-59 render the existing modals:
```erb
<%= render "catch_modal" %>
<%= render "pokemon_modal" %>
<%= render "mark_dead_modal" %>
```

Add a fourth line:
```erb
<%= render "reset_draft_modal" %>
```

#### 5. JS edit — `app/javascript/controllers/dashboard_controller.js`

Mirror the `// ── Mark Dead ──` block (lines 76-125). Add three new methods AT THE END of the class:

```javascript
// ── Reset Gym Draft ──
//
// Mirrors the Mark Dead pattern: open with pre-filled status, CONFIRM
// RESET fires a DELETE to /gym_drafts/:id, CANCEL hides without firing.
// Resetting destroys all picks made during the draft — the modal makes
// the action explicit, mirroring the mark-dead UX for permadeath.

openResetDraftModal(event) {
  const draftId = event.currentTarget.dataset.draftId
  const status = event.currentTarget.dataset.draftStatus || "active"
  if (!draftId) return

  this.resetDraftIdTarget.value = draftId
  this.resetDraftStatusTarget.textContent = status.toUpperCase()
  this.resetDraftModalTarget.classList.remove("hidden")
}

closeResetDraftModal() {
  if (!this.hasResetDraftModalTarget) return
  this.resetDraftModalTarget.classList.add("hidden")
  this.resetDraftIdTarget.value = ""
}

async confirmResetDraft() {
  const draftId = this.resetDraftIdTarget.value
  if (!draftId) return

  try {
    const response = await fetch(`/gym_drafts/${draftId}`, {
      method: "DELETE",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfValue
      }
    })

    if (response.ok) {
      window.location.reload()
    } else {
      const data = await response.json().catch(() => ({}))
      alert(data.error || "Failed to reset draft")
      this.closeResetDraftModal()
    }
  } catch (error) {
    alert("Network error")
    this.closeResetDraftModal()
  }
}
```

Update the `static targets` array (line 4-7) to include the three new targets:
```javascript
static targets = [
  "catchModal", "catchNickname", "catchLocation", "catchSpecies", "catchStatus",
  "markDeadModal", "markDeadNickname", "markDeadGroupId",
  "resetDraftModal", "resetDraftStatus", "resetDraftId"
]
```

Hardcoded `/gym_drafts/${draftId}` URL is consistent with how `confirmMarkDead` constructs `${this.groupsUrlValue}/${groupId}` — but groupsUrl is a Stimulus value because there's a Rails-supplied path helper involved. For the draft destroy URL, we don't have a groups-url-style value pre-wired, and adding one for a single endpoint is overkill. Hardcoded path matches the Rails convention (`DELETE /gym_drafts/:id` is stable).

#### 6. Controller edit — `app/controllers/gym_drafts_controller.rb`

Add a `destroy` action at the end of the public methods (after `mark_beaten`, before `private`):

```ruby
def destroy
  run = current_run
  return render(json: { error: "No active run" }, status: :not_found) unless run

  draft = run.gym_drafts.find_by(id: params[:id])
  return render(json: { error: "Draft not found" }, status: :not_found) unless draft

  unless draft.status.in?(%w[lobby voting drafting nominating])
    return render(json: { error: "Draft is no longer active and cannot be reset" }, status: :unprocessable_entity)
  end

  draft.destroy!
  render json: { ok: true }
end
```

**Auth + scoping:** finding via `run.gym_drafts.find_by(id: ...)` (NOT `GymDraft.find`) is the auth boundary — a draft from another guild's run returns 404 to the requester. Mirrors `mark_beaten`'s `run.gym_drafts.find_by(id: ...)` at line 73.

**Status guard:** prevents destroying a `complete` draft (which may have an associated `GymResult` via `gym_results, dependent: :nullify`). Bob: confirm via the Gyms-tab render condition (`@active_draft` only loads non-complete drafts) that the button never appears for complete drafts; the controller guard is belt-and-suspenders for direct-curl bypass.

**Response:** JSON `{ ok: true }` for the Stimulus fetch; the JS reloads on success. No turbo_stream — the page reload picks up `@active_draft = nil` cleanly.

#### 7. Route edit — `config/routes.rb`

Existing line 36: `resources :gym_drafts, only: [ :create, :show ] do`

Change to: `resources :gym_drafts, only: [ :create, :show, :destroy ] do`

That's it. The `member { post :mark_beaten }` block stays; no change to the nested route.

#### 8. Tests

Add three test files / sections:

**(a) `test/controllers/gym_progress_controller_test.rb`** (NEW FILE — none exists today).

```ruby
require "test_helper"

class GymProgressControllerTest < ActionDispatch::IntegrationTest
  setup do
    @run = create(:soul_link_run, guild_id: "g1")
    Capybara.app_host = nil if defined?(Capybara) # no-op safety
    post "/auth/discord/callback", params: { /* mirror existing controller-test login pattern */ }
    # OR use whatever session-stub helper other controller tests use — see existing
    # tests in test/controllers/ for the exact pattern
  end

  test "mark gym beaten creates result and increments gyms_defeated" do
    patch gym_progress_path(gym_number: 1)
    assert_response :success
    assert_equal 1, @run.reload.gyms_defeated
    assert @run.gym_results.exists?(gym_number: 1)
  end

  test "unmark beaten destroys result and decrements gyms_defeated" do
    @run.gym_results.create!(gym_number: 1, beaten_at: Time.current)
    @run.update!(gyms_defeated: 1)

    patch gym_progress_path(gym_number: 1)
    assert_response :success
    assert_equal 0, @run.reload.gyms_defeated
    assert_not @run.gym_results.exists?(gym_number: 1)
  end

  test "unmark non-highest gym is rejected" do
    @run.gym_results.create!(gym_number: 1, beaten_at: Time.current)
    @run.gym_results.create!(gym_number: 2, beaten_at: Time.current)
    @run.update!(gyms_defeated: 2)

    patch gym_progress_path(gym_number: 1)
    assert_response :unprocessable_entity
    assert_equal 2, @run.reload.gyms_defeated
    assert @run.gym_results.exists?(gym_number: 1)
  end

  test "invalid gym number is rejected" do
    patch gym_progress_path(gym_number: 99)
    assert_response :unprocessable_entity
  end
end
```

**Bob: do NOT guess the login/session-stub pattern.** Read one existing controller test (e.g., `test/controllers/dashboard_controller_test.rb` if it exists, or `test/controllers/gym_drafts_controller_test.rb`) and copy the exact session-setup helper. The above is structural, not literal.

**(b) `test/controllers/gym_drafts_controller_test.rb`** (extend existing).

Add a `destroy` test block:

```ruby
test "destroy active draft removes it" do
  draft = create(:gym_draft, :lobby, soul_link_run: @run)
  delete gym_draft_path(draft)
  assert_response :success
  assert_not GymDraft.exists?(draft.id)
end

test "destroy complete draft is rejected (status guard)" do
  draft = create(:gym_draft, :lobby, soul_link_run: @run)
  draft.update!(status: "complete")
  delete gym_draft_path(draft)
  assert_response :unprocessable_entity
  assert GymDraft.exists?(draft.id)
end

test "destroy returns 404 for cross-guild access" do
  other_run = create(:soul_link_run, guild_id: "g2")
  draft = create(:gym_draft, :lobby, soul_link_run: other_run)
  delete gym_draft_path(draft)
  assert_response :not_found
  assert GymDraft.exists?(draft.id)
end
```

The `:lobby` factory trait exists per `test/factories/gym_drafts.rb:16-22` (Architect verified via the Explore agent's initial recon).

**(c) Render-condition tests for the Gyms tab.** If `test/controllers/dashboard_controller_test.rb` exists, add:

```ruby
test "gyms tab renders UNMARK button only on the highest defeated gym" do
  # seed run with 2 gyms defeated
  # GET dashboard, parse body
  # assert UNMARK button present once (or however the test framework asserts)
  # assert it's on gym 2's row, not gym 1
end

test "gyms tab renders RESET DRAFT only when active draft exists" do
  # without draft: assert no RESET DRAFT button
  # with lobby draft: assert button present
  # with complete draft: assert no RESET DRAFT button
end
```

Bob: write these as `assert_select` against the response body, or `assert_match` on response.body — whatever pattern other dashboard tests use. Don't overengineer.

If `test/controllers/dashboard_controller_test.rb` does NOT exist, log it as a Known Gap (the Step 13 changes ARE worth a smoke test, but creating the whole controller test file from scratch is scope expansion). The model + controller-action tests above carry the bulk of the coverage either way.

### Out of Scope (do NOT expand)

- **Resetting a `complete` draft.** Once a draft is complete, the user marks-beaten or accepts. Adding a "redo" affordance for complete drafts opens questions about associated `GymResult` cleanup (foreign-key nullify vs. cascade) and isn't worth bundling here. If the user later reports it as missing, fresh step.
- **Reset button on `gym_drafts/show.html.erb`.** The user described this as a Gyms-tab feature. Putting reset on the draft show page too would be redundant and adds wiring (different Stimulus controller scope). Future polish.
- **Adding `broadcasts_refreshes_to` to `GymDraft` for real-time gyms-tab updates.** Reset is a one-shot user action; full page reload is sufficient. Cross-player real-time draft state already flows through `GymDraftChannel` (the WebSocket). Out of scope.
- **Confirm modal for UNMARK.** Project Owner explicitly said no — pain is *that mistakes are unfixable*; don't replace it with a "are you sure" wall. Keep light.
- **Fixing the existing JSON-response-on-HTML-form behavior of `gym_progress#update`.** Pre-existing; the user has been using MARK BEATEN successfully despite it. UNMARK mirrors the same wiring. If Bob notices the JSON-response renders as a page in the browser (i.e., the user sees `{"gyms_defeated":N}` and presses back), log as Known Gap, do NOT fix in this step.
- **Refactoring the `_gyms_content.html.erb` partial.** Touch only the lines specified.
- **Tests beyond the three groups above.** No integration tests, no system tests, no JS tests. The controller + render-condition coverage is sufficient.
- **Adding `gym_drafts#destroy` test for non-existent draft id.** The `find_by` + 404 path is symmetric with `mark_beaten` and not worth a dedicated test.

### Constraints / Flags

- **Status guard belt-and-suspenders.** The render condition (`@active_draft` only includes non-complete) AND the controller guard (`status.in?(...)`) MUST both gate. Don't rely on UI alone — direct curl bypass must be rejected.
- **Auth scoping via `run.gym_drafts`, not `GymDraft.find`.** Do NOT use `GymDraft.find(params[:id])` in destroy — that bypasses guild scoping. Mirror `mark_beaten`'s pattern.
- **318/318 must still pass + new tests.** New count likely 322-330 depending on test coverage Bob writes.
- **Rubocop must stay clean** (Step 11/12 end state: 0 offenses across 147 files).
- **Don't introduce new modal scaffolding patterns.** Mirror `_mark_dead_modal.html.erb` byte-for-byte where structurally identical (overlay, gb-modal, close button, backdrop-click handler). Only body copy + Stimulus action names change.
- **Don't change `gym_progress_controller.rb` even slightly.** The unmark backend is already correct. Touching it (e.g., to "improve" the JSON response) is scope creep and will be flagged as drift.
- **Stimulus action names follow existing camelCase + verb-noun-noun.** `openResetDraftModal`, `closeResetDraftModal`, `confirmResetDraft` — symmetric with `openMarkDeadModal` etc.
- **The CSRF token on the DELETE fetch must be sent**, mirroring `confirmMarkDead`. Use `this.csrfValue`.
- **Modal copy must NOT use exclamation points or scream-case** beyond the title (which is consistent with mark-dead). Body copy is calm: "This deletes the current draft and all picks." — not "WARNING! YOU WILL LOSE EVERYTHING!".

### Acceptance Criteria

- New file `app/views/dashboard/_reset_draft_modal.html.erb`, structurally identical to `_mark_dead_modal.html.erb` with reset-specific copy.
- `app/views/dashboard/show.html.erb`: one-line addition rendering the new modal.
- `app/views/dashboard/_gyms_content.html.erb`: RESET DRAFT button in panel header (gated on `@active_draft`); UNMARK button on the highest defeated gym row (gated on `num == @gyms_defeated`).
- `app/controllers/dashboard_controller.rb`: loads `@active_draft` for the gyms tab.
- `app/controllers/gym_drafts_controller.rb`: new `destroy` action with status guard + auth scoping.
- `config/routes.rb`: `:destroy` added to gym_drafts resource.
- `app/javascript/controllers/dashboard_controller.js`: three new Stimulus actions + three new targets in the `static targets` array.
- New `test/controllers/gym_progress_controller_test.rb` covering mark/unmark/reject-non-highest/reject-invalid-num (4 tests minimum).
- Extended `test/controllers/gym_drafts_controller_test.rb` with destroy/destroy-complete-rejected/destroy-cross-guild-404 tests (3 tests).
- Optional: render-condition tests in `test/controllers/dashboard_controller_test.rb` IF that file already exists. Otherwise log as Known Gap.
- Manual smoke (Bob, in `bin/dev`):
  1. Mark gym 1 beaten via dashboard. Refresh. UNMARK appears on gym 1 row.
  2. Click UNMARK. Refresh. Star is gone, badge count back to 0, UNMARK button gone, MARK BEATEN re-appears on gym 1 as the next gym.
  3. Click START GYM DRAFT. Confirm RESET DRAFT button appears in panel header.
  4. Click RESET DRAFT. Confirm modal opens with status. Click CANCEL → modal closes, draft intact. Re-open. Click CONFIRM RESET → page reloads, draft gone, RESET DRAFT button gone, START GYM DRAFT remains.
- Full suite green. Rubocop clean.
- Diff scope: 4 view files (1 new, 3 modified), 2 controllers, 1 routes, 1 JS, 2 tests (1 new, 1 extended) [+ optional 3rd test file], 4 handoff files. Anything else is a Reviewer Condition.

### Files Bob Should Read

- `app/views/dashboard/_gyms_content.html.erb` (full — small)
- `app/views/dashboard/show.html.erb` (full — small; just need to know where to add the render line)
- `app/views/dashboard/_mark_dead_modal.html.erb` (full — the scaffold to mirror)
- `app/javascript/controllers/dashboard_controller.js` (full — the Stimulus pattern to mirror)
- `app/controllers/gym_drafts_controller.rb` (full — small)
- `app/controllers/gym_progress_controller.rb` (full — confirm unmark already works; do NOT modify)
- `app/controllers/dashboard_controller.rb` (the `show` action; find where `@gyms_defeated` etc. load)
- `config/routes.rb` (line 36)
- `test/controllers/gym_drafts_controller_test.rb` (full — small; the existing setup pattern is what new tests mirror for login/session)
- `test/factories/gym_drafts.rb` (full — small; confirm `:lobby` trait shape)

DO NOT load:
- The full `GymDraft` model (no model changes; status helpers already exist).
- `GymDraftChannel` or the WebSocket layer (no real-time changes).
- The other dashboard tabs/partials (`_runs_content.html.erb`, `_pc_box_*`, etc.).
- `gym_results_controller.rb` (the backfill flow is separate).
- The map / strategy / type-chart code.

### Files Bob Should Update at the End

- `handoff/REVIEW-REQUEST.md` — files-changed table, self-review answers covering all eight constraint flags above, open questions, `Ready for Review: YES`.
- `handoff/BUILD-LOG.md` — Step 13 history entry. Note: the `gym_progress_controller_test.rb` file is NEW (closes a pre-existing test gap).

---

## Notes for Reviewer (Richard)

When this lands on your desk, focus on:

1. **Auth scoping in `gym_drafts#destroy`**. Confirm `run.gym_drafts.find_by(id:)` is used, not `GymDraft.find`. A cross-guild draft id MUST return 404, not destroy the other guild's draft.

2. **Status guard on destroy is belt-and-suspenders.** The view gates via `@active_draft` (non-complete only); the controller gates via `status.in?(...)`. Both must be present. Removing either leaves the system one direct-curl bypass away from data loss.

3. **UNMARK button only on the highest defeated gym.** The render condition `num == @gyms_defeated` is the only gate. Confirm it's not on gym 1 when 3 gyms are defeated. The controller already enforces this (returns 422 on non-highest unmark) — UI consistency is a render-correctness check.

4. **No confirm modal on UNMARK.** That's the spec. If Bob added `confirm: "..."` or wired a modal flow, that's drift — flag it. Project Owner explicitly chose lightweight.

5. **Reset modal mirrors mark-dead structurally.** Compare `_reset_draft_modal.html.erb` to `_mark_dead_modal.html.erb` side-by-side: same overlay, same z-index 60, same gb-modal box, same close-X behavior, same backdrop-click handler. Only copy + action names + targets differ.

6. **Stimulus targets array updated.** All three new targets (`resetDraftModal`, `resetDraftStatus`, `resetDraftId`) must appear in the `static targets` array on `dashboard_controller.js`. If Bob references a target that's not in the array, Stimulus throws at runtime.

7. **CSRF token on the DELETE fetch.** The destroy fetch must send `X-CSRF-Token: this.csrfValue`, mirroring `confirmMarkDead`. Without it, Rails returns 422 InvalidAuthenticityToken.

8. **No changes to `gym_progress_controller.rb`.** Bob is told explicitly not to touch this. If the diff shows ANY edit there, flag it (could be a "tidy fix" that breaks the existing JSON contract).

9. **No new turbo broadcasts.** The brief explicitly opts for page-reload after the Stimulus fetch, NOT `broadcast_replace_to` or `broadcasts_refreshes_to`. If Bob adds either, flag — it expands scope and changes the dashboard's update model.

10. **Test count delta.** Step 12 ended at 335 tests. Step 13 adds 4 (gym_progress) + 3 (gym_drafts destroy) = 7 minimum, more if Bob writes the optional render-condition tests. Confirm the delta is in the 7-12 range, not 1-2 (under-tested) or 25+ (over-tested).

11. **Modal copy is calm.** Mark-dead uses "permanently marks... irreversible" — appropriate for permadeath. Reset is recoverable (start new draft afterward), so the copy MUST be matter-of-fact, not alarming. "This deletes the current draft and all picks." — not "WARNING".

12. **Manual smoke must be done by Bob.** The four-step flow in Acceptance Criteria. If REVIEW-REQUEST doesn't confirm Bob ran through it, that's a Should Fix.

Out-of-scope items found during review → BUILD-LOG Known Gaps. Do not bundle.
