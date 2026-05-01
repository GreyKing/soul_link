# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 10 — UX Batch 2: Tier-B/C/D/E + YOU-badge follow-up + KG-5

### Context

Step 9 (commit `7513764`, on main) shipped the first real-time UX (KG-1 / KG-2) plus 5 Tier-A silent-failure fixes. Step 10 continues with the natural next tier.

`handoff/PROJECT-REVIEW-2026-04-30.md` lists 18 UI/UX items across Tiers A-E. Tier A is done. This step picks the highest-ROI Tier B-E items + a couple of small KGs.

**Architect-level scoping notes:** during pre-flight reads, several PROJECT-REVIEW items turned out to already be handled in the codebase (the review was based on an earlier scan). Items skipped:

- **B.6 (gym draft button disable):** all six action handlers (`ready`, `vote`, `pickPokemon`, `nominatePokemon`, `approveNomination`, `rejectNomination`) already disable the relevant buttons or set `pointer-events: none` on click. `disablePokemonCards` covers the clicked card. The "spam-clicks possible" diagnosis no longer holds. Skip.
- **B.8 (run_management auto-dismiss):** [run_management_controller.js:56](app/javascript/controllers/run_management_controller.js:56) already has `setTimeout(() => this.clearError(), 8000)`. Skip.
- **B.9 (no empty state for gym drafts):** there is no `index` action / route — `gym_drafts/show` is only reachable by ID after `START GYM DRAFT` button creates one. There's no "no draft" page that needs an empty state. Skip.
- **B.11 (no "no species assigned" placeholder):** [_group_card.html.erb](app/views/species_assignments/_group_card.html.erb) already shows per-player rows with placeholders ("Drop your species here" for the current user, "waiting..." for others), which is clearer than a single all-empty message. Skip.
- **C.12 (form `for=scheduled_at` not associated):** the input at [gym_schedules/index.html.erb:12](app/views/gym_schedules/index.html.erb:12) already has `id="scheduled_at"` matching the label's `for=`. Skip.
- **D.16 (save-slot operations hard-reload):** turning `window.location.reload()` into a targeted turbo_stream replace is meaningful work (server-side broadcast on slot create/update/destroy + frame wrapping per slot). Compounds with KG-1 plumbing but expands its surface; defer to a future step.

**Items in scope for Step 10 (9 total):**

1. **B.7** — Drop misleading `opacity: 0.6` on Cancel button
2. **B.10** — Add "schedule already active" hint when gym schedule form vanishes
3. **C.13** — Avatar alt text uses player name
4. **C.14** — `aria-label="Close modal"` on every `gb-modal-close` button
5. **D.15** — Emulator page mobile breakpoint (stack columns below 900px)
6. **E.17** — Mark Dead custom modal (replace native `confirm()`)
7. **E.18** — FALLEN section tooltip
8. **KG-Step9-followup** — YOU badge restoration via small Stimulus controller (the regression Step 9 logged)
9. **KG-5** — Run `rubocop -a` (safe autocorrect) sweep — 113 fixable offenses

### Project Owner decisions (locked)

- **Auto-accept mode for this work.** Bob can act decisively; Reviewer + tests are the backstop.
- **Tier-1 structural refactors NOT in this batch.** Save for a fresh main-checkout session per Project Owner's worktree preference.
- **`rubocop -a` (safe) only — NOT `-A` (unsafe).** The 113 fixable offenses are mostly whitespace + style (Layout/SpaceInsideArrayLiteralBrackets, Style/DefWithParentheses, etc.). `-A` would also run cops that change semantics ("CRITICAL", "Lint" categories). Keep this sweep purely cosmetic.
- **Mark Dead modal reuses the existing pixeldex-style modal pattern.** No new component library; same gb-modal/gb-card/gb-btn-* tokens that the pokemon modal uses.
- **Don't touch tests for items where the change is purely visual / aria-label / inline style.** The full suite must still pass; new tests are required only for the YOU-badge Stimulus controller (small unit shape) and any model-level changes (none here).

### Scope per item

#### B.7 — Cancel button opacity

[app/views/gym_schedules/show.html.erb:66](app/views/gym_schedules/show.html.erb:66): `class="gb-btn-danger gb-btn-sm" style="opacity: 0.6;"`. Drop the inline `style="opacity: 0.6;"`. The `gb-btn-danger` already provides the visual "danger" cue — opacity makes it look disabled.

#### B.10 — Gym schedule form silent vanish

[app/views/gym_schedules/index.html.erb:7-18](app/views/gym_schedules/index.html.erb:7): the propose-schedule form is wrapped in `<% unless @schedules.any? %>`. When schedules exist, the form simply doesn't render — users think the UI is broken.

Add an `<% else %>` branch (or sibling `<% if @schedules.any? %>` block above the upcoming list) with copy like:

```erb
<% else %>
  <div class="gb-card" style="max-width: 500px; padding: 12px; margin-bottom: 16px;">
    <div style="font-size: 11px; color: var(--d2); line-height: 1.6;">
      A schedule is already active. Cancel the active one below before proposing a new time.
    </div>
  </div>
<% end %>
```

The semantic is: only one active schedule per run at a time. The hint explains why the form isn't there.

#### C.13 — Avatar alt text

[app/views/layouts/application.html.erb:46](app/views/layouts/application.html.erb:46): `alt="avatar"` → `alt="<%= current_username %>'s avatar"`. Single-line edit.

#### C.14 — Modal close aria-label

Four files use `class="gb-modal-close"`:
- `app/views/dashboard/_pokemon_modal.html.erb:13`
- `app/views/dashboard/_catch_modal.html.erb:13`
- `app/views/species_assignments/show.html.erb:137`
- `app/views/teams/_quick_calc_modal.html.erb:15`

Each renders `&times;` with no aria-label. Add `aria-label="Close modal"` to all four. Plus `app/views/map/show.html.erb:219` uses inline-styled `&times;` (same intent, no `gb-modal-close` class) — also add `aria-label`.

#### D.15 — Emulator mobile breakpoint

[app/views/emulator/show.html.erb:72](app/views/emulator/show.html.erb:72): inline `display: grid; grid-template-columns: 280px minmax(0, 1fr) 280px; gap: 16px; align-items: stretch;`. Below 900px viewport, the center column goes negative.

Move to a CSS class in `pixeldex.css`:

```css
.emulator-grid {
  display: grid;
  grid-template-columns: 1fr; /* mobile / narrow: stacked */
  gap: 16px;
  align-items: stretch;
}

@media (min-width: 900px) {
  .emulator-grid {
    grid-template-columns: 280px minmax(0, 1fr) 280px;
  }
}
```

Then in `emulator/show.html.erb`, replace the inline `style="..."` with `class="emulator-grid"`.

The `align-items: stretch` keeps the canvas full-height in the desktop layout; in stacked mobile layout it doesn't matter (single column).

#### E.17 — Mark Dead custom modal

Permadeath in a Nuzlocke is irreversible. The current `markDead` in [dashboard_controller.js:80-82](app/javascript/controllers/dashboard_controller.js:80) uses native `confirm()` — generic, ugly on mobile, doesn't show the Pokemon details.

**Plan:**
1. New partial `app/views/dashboard/_mark_dead_modal.html.erb` modeled on `_pokemon_modal.html.erb`'s structure (background overlay, gb-modal container, close button, header, content, action row).
2. Modal shows: pokemon sprite (using `pokemon_sprite_tag` if available, or a simple icon), group nickname, location, and a warning sentence: "This permanently removes <nickname> from all teams and marks every linked pokemon as dead."
3. Two action buttons: "CANCEL" (closes modal) and "CONFIRM DEATH" (fires the actual PATCH).
4. Wire via Stimulus targets on the dashboard controller:
   - `markDeadModal` (the modal container)
   - `markDeadNickname` (the displayed nickname)
   - `markDeadLocation` (location text)
   - `markDeadGroupId` (hidden field)
5. Replace `markDead(event)` body: instead of `confirm(...)` then PATCH, set up the modal + show it. Add a new `confirmMarkDead()` action that fires the PATCH; add `closeMarkDeadModal()` to hide.

The existing pokemon modal's MARK DEAD button at [_pokemon_modal.html.erb:107-111](app/views/dashboard/_pokemon_modal.html.erb:107) currently calls `dashboard#markDead` and relies on `data-group-id` + `data-group-nickname`. The new flow:
- `dashboard#openMarkDeadModal(event)` — reads `groupId`, `groupNickname`, `groupLocation` from the dataset, populates the modal, shows it. Optionally closes the pokemon modal first.
- `dashboard#confirmMarkDead()` — fires the PATCH with `markDeadGroupIdTarget.value`.
- `dashboard#closeMarkDeadModal()` — hides without firing.

The data attributes already include `groupNickname`. Add `data-group-location="<%= group.location %>"` to the MARK DEAD button (button is currently set up by `pixeldex_controller#updateModalForGroup`, so the location needs to be passed through there too).

Actually simpler: read location from `modalGroupId` → look up the cell in the DOM. OR just skip the location for now; nickname is enough context. Keep modal copy simple for v1: nickname + warning text + actions.

The new partial gets rendered inline in `dashboard/show.html.erb` after the existing modal renders.

#### E.18 — FALLEN section tooltip

Two places: [app/views/dashboard/_pc_box_content.html.erb:72](app/views/dashboard/_pc_box_content.html.erb:72) and [app/views/dashboard/_pc_box_panel.html.erb:63](app/views/dashboard/_pc_box_panel.html.erb:63). Both render `<div class="box-section-label" style="margin-top: 14px;">FALLEN (<count>)</div>`.

Add `title="Pokemon that died this run"` to the div in both places. Trivial.

Optionally: also add `title` to `YOUR POKEMON` / `STORAGE` headings if it reads better — but PROJECT-REVIEW only flagged FALLEN as ambiguous, so just that.

#### KG-Step9-followup — YOU badge restoration via Stimulus

Step 9 dropped the YOU badge + 4px-border from run-roster cards because preserving them across Turbo broadcast frame replacements requires either passing `current_user_id` into a model callback (layer violation) or wrapping markers outside the frame (DOM fragility).

The clean solution per the BUILD-LOG Known Gap: a small Stimulus controller that decorates the matching `<turbo-frame>` post-render.

**Plan:**
1. New file `app/javascript/controllers/roster_you_marker_controller.js`. Simple Stimulus controller.
2. Stimulus value: `currentUserId: String` — set from a meta tag or data attr in the layout.
3. The controller's `connect()` (and a new method `apply()` triggered on Turbo stream events) iterates over `<turbo-frame id^="emulator_roster_session_">`. For each, if its inner card has `data-discord-user-id` matching the value, add a YOU badge and a "current-user" CSS class for the 4px border.
4. The roster card partial `_run_sidebar_card.html.erb` adds `data-discord-user-id="<%= s.discord_user_id %>"` to the outer card div so the Stimulus controller can find it.
5. The Stimulus controller listens for `turbo:before-stream-render` on the document so it re-applies the marker after broadcast replacements.
6. CSS: a new `.gb-card--current-user { border-width: 4px; }` rule in `pixeldex.css` for the 4px-border treatment.
7. Mount the controller on the run-sidebar wrapper in `_run_sidebar.html.erb` with `data-controller="roster-you-marker" data-roster-you-marker-current-user-id-value="<%= current_user_id %>"`.

**Why a separate Stimulus controller, not adding to an existing one:** the existing `save-slots` controller is scoped to the LEFT slot column; the run-roster sidebar on the RIGHT has no Stimulus controller of its own. A small dedicated controller keeps responsibilities clean.

**Test:** add a unit-shape JS test? The project doesn't run JS tests. Instead: a smoke render test in `_run_sidebar_card_test.rb` that confirms `data-discord-user-id` is present in the rendered partial (so the Stimulus selector won't break silently). One test addition.

Actually the project doesn't have a `_run_sidebar_card_test.rb` either — partial render is exercised in the model broadcast tests from Step 9. Add a small assertion to one of those: `assert_includes rendered, "data-discord-user-id="`.

#### KG-5 — Rubocop autocorrect sweep

113 auto-fixable offenses. Run `bundle exec rubocop -a` (safe autocorrect ONLY — not `-A` which includes unsafe corrections). Commit the result as a single logical change.

After the sweep:
- Re-run full test suite — must stay green
- Re-run `bundle exec rubocop` — should report many fewer offenses (only the unsafe-correctable + non-correctable remain)
- Spot-check a few changed files for sanity (mostly Layout/SpaceInsideArrayLiteralBrackets and similar style changes)

Bob has discretion to revert specific edits if rubocop's autocorrect makes a code worse-looking change.

### Out of Scope (do NOT expand)

- Tier-1 structural refactors (god-object decomp, presenter extraction, GzipCoder concern move) — fresh session
- D.16 save-slot turbo_stream replace (compounds with KG-1, separate scope)
- KG-6 (Map ID → name lookup) — needs Gen IV map ID research, defer
- KG-7 (real-save offset verification) — needs a real `.sav` file from Project Owner
- KG-8/9/10 (channel authz, error_message column, destructive regenerate) — defer
- Adding a global toast component (still using `window.alert()` from Step 9; cleanup is a follow-up)
- Bot-process broadcasts (still requires redis cable adapter)
- B.6 / B.8 / B.9 / B.11 / C.12 / D.16 (already handled or deferred per Architect notes)
- Refactoring the dashboard controller's view-model setup (Tier-1)

### Constraints / Flags

- **Sequence the work**: B.7/B.10/C.13/C.14/E.18 first (trivial — verify visually, no test impact), then D.15 (CSS class extraction), then E.17 (Mark Dead modal — bigger), then YOU-badge controller (new file + partial edits), then KG-5 last (autocorrect sweep — runs after all manual edits).
- **305/310 tests must still pass** (310 from Step 9 with the broadcast tests). KG-5 autocorrect can break tests if it changes semantics — the safe `-a` flag should keep tests green; if it breaks, investigate per-cop.
- **`bundle exec rubocop` clean on touched files at the end** — KG-5 should make this trivially true.
- **No new `window.alert()` calls.** Step 9 added them as a stopgap; Step 10's Mark Dead modal supersedes the worst offender (the dashboard's `confirm()` was the most jarring native dialog). Don't ADD more alerts.
- **YOU badge controller doesn't violate the model-callback layer**. The Stimulus controller is purely client-side; it reads `current_user_id` from a meta tag/data attr set in the layout (where controller context exists). Models stay clean.
- **All 4 modal close buttons get the same `aria-label="Close modal"`** — don't customize per modal (they all close their respective modal, semantic is identical).
- **Mark Dead modal's "CONFIRM DEATH" button is the danger action.** Use `gb-btn-danger` class. The CANCEL button uses default `gb-btn` styling.
- **Don't add new CSS variables.** The amber token from Step 9 is the latest addition; further palette additions should be deliberate.

### Acceptance Criteria

- All 9 items shipped (B.7, B.10, C.13, C.14, D.15, E.17, E.18, YOU-badge, KG-5).
- Full suite green: 310/310 (or +N if YOU-badge test added).
- `bundle exec rubocop` reports 113 fewer offenses (or close to it — autocorrect may surface chain reactions).
- Manual smoke test (Bob): open `/dashboard`, click a Pokemon cell, click MARK DEAD — see the new modal, verify CANCEL closes without firing, verify CONFIRM DEATH fires the PATCH.
- Manual smoke test: open `/emulator` in a narrow window (< 900px) — sidebars stack vertically; in a wide window — they sit side-by-side.
- Manual smoke test: open `/emulator` as the current user — see the YOU badge + 4px-border on your roster card; trigger a save (which broadcasts a frame replace) — YOU badge re-applies post-broadcast.
- Diff scope: 5+ JS controllers, 6+ views, 1 stylesheet, 1 new view partial, 1 new JS controller, ~80+ files touched by KG-5 autocorrect, 4 handoff files. Plus any test files Bob touches for the YOU-badge follow-up.

### Files Bob Should Read

For B.7: `app/views/gym_schedules/show.html.erb` line 66
For B.10: `app/views/gym_schedules/index.html.erb` lines 7-18
For C.13: `app/views/layouts/application.html.erb` line 46
For C.14: `app/views/dashboard/_pokemon_modal.html.erb`, `_catch_modal.html.erb`, `app/views/species_assignments/show.html.erb`, `app/views/teams/_quick_calc_modal.html.erb`, `app/views/map/show.html.erb` (close button)
For D.15: `app/views/emulator/show.html.erb` line 72, `app/assets/stylesheets/pixeldex.css` (`:root` block + appendable area for new class)
For E.17: `app/javascript/controllers/dashboard_controller.js` (markDead at 77), `app/views/dashboard/_pokemon_modal.html.erb` (where MARK DEAD button lives), `app/views/dashboard/_catch_modal.html.erb` (modal pattern reference)
For E.18: `app/views/dashboard/_pc_box_content.html.erb` line 72, `app/views/dashboard/_pc_box_panel.html.erb` line 63
For YOU-badge: `app/views/emulator/_run_sidebar.html.erb`, `_run_sidebar_card.html.erb`, `app/javascript/controllers/` directory listing for similar small Stimulus controllers (e.g. `clear_save_controller.js` for shape reference)
For KG-5: just run `bundle exec rubocop -a` and review the diff before committing

DO NOT load app/controllers, app/services, or any model code (no business-logic changes in this step).

### Files Bob Should Update at the End

- `handoff/REVIEW-REQUEST.md` — files-changed table, self-review answers, open questions, `Ready for Review: YES`
- `handoff/BUILD-LOG.md` — Step 10 history entry. **Update Known Gaps:** close the YOU-badge follow-up (added in Step 9, closed here).

---

## Notes for Reviewer

When this lands on your desk, focus on:

1. **The skipped items (B.6, B.8, B.9, B.11, C.12, D.16) are correctly diagnosed.** Spot-check 1-2 to verify they're already handled. Bob's notes in REVIEW-REQUEST should explain.

2. **Mark Dead modal flow.** Open dashboard, click a Pokemon, click MARK DEAD button — the new modal opens with the right pokemon's nickname + warning text. CANCEL closes without firing. CONFIRM DEATH fires the PATCH and reloads the page (current behavior). No regression to the existing markDead → server flow.

3. **YOU-badge Stimulus controller.** Open `/emulator` as a logged-in player. The session card for THAT player should have the YOU badge + 4px-border re-applied by the controller. After a save (which broadcasts a frame replace), the YOU badge should re-apply on the next render. Open dev tools and watch the controller's `apply()` method run on `turbo:before-stream-render`.

4. **D.15 mobile breakpoint.** Resize the emulator page below 900px — sidebars stack. Above 900px — three-column layout returns. CSS class is in pixeldex.css; inline style is gone.

5. **KG-5 sweep.** Verify the autocorrect didn't introduce semantic changes — spot-check 5-10 randomly modified files. Look for: behavior-preserving whitespace tweaks (Layout/SpaceInsideArrayLiteralBrackets), parens-on-no-arg-defs, etc. If any look semantically suspect, flag.

6. **Tests still pass post-autocorrect.** 310/310 (+N if YOU-badge test added). If KG-5 broke a test, it's a Reviewer Condition (rubocop -a should be safe).

7. **No app/controllers, app/services, or app/models changes.** Step 10 is view + JS + CSS + Stimulus + lint. Models from Step 9 stay clean.

8. **Diff scope.** `git diff --stat HEAD~1 main` should show many files (KG-5 sweeps the whole tree) but ZERO logic changes. Sanity-check a few samples.

Out-of-scope items found during review → BUILD-LOG Known Gaps. Do not bundle.
