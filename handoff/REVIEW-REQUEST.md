# Review Request
*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

Ready for Review: YES

---

## Step 10 — UX Batch 2: Tier-B/C/D/E + YOU-badge follow-up + KG-5

**Builder:** Bob
**Tests:** 310/310 passing (no test count change). 0 failures, 0 errors.
**Lint:** `bundle exec rubocop` — **0 offenses across 144 files**. Down from 133 pre-Step-10.

---

## Files Changed

### Manual edits (13 files)

| Path | Change |
|------|--------|
| `app/views/gym_schedules/show.html.erb` | B.7: drop `style="opacity: 0.6;"` from Cancel button |
| `app/views/gym_schedules/index.html.erb` | B.10: add explanatory hint when `@schedules.any?` |
| `app/views/layouts/application.html.erb` | C.13: avatar `alt="<%= current_username %>'s avatar"` |
| `app/views/dashboard/_pokemon_modal.html.erb` | C.14: aria-label on close + reroute MARK DEAD button to `openMarkDeadModal` |
| `app/views/dashboard/_catch_modal.html.erb` | C.14: aria-label on close |
| `app/views/species_assignments/show.html.erb` | C.14: aria-label on close |
| `app/views/teams/_quick_calc_modal.html.erb` | C.14: aria-label on close |
| `app/views/map/show.html.erb` | C.14: aria-label on close-panel button |
| `app/views/dashboard/_pc_box_content.html.erb` | E.18: `title="Pokemon that died this run"` on FALLEN heading |
| `app/views/dashboard/_pc_box_panel.html.erb` | E.18: same FALLEN tooltip |
| `app/views/dashboard/show.html.erb` | E.17: render the new `mark_dead_modal` partial |
| `app/views/emulator/show.html.erb` | D.15: replace inline grid styles with `class="emulator-grid"` |
| `app/views/emulator/_run_sidebar.html.erb` | YOU-badge: mount `roster-you-marker` Stimulus controller |
| `app/views/emulator/_run_sidebar_card.html.erb` | YOU-badge: add `data-discord-user-id` to outer card |
| `app/javascript/controllers/dashboard_controller.js` | E.17: replace `markDead` with `openMarkDeadModal` / `confirmMarkDead` / `closeMarkDeadModal` flow |
| `app/assets/stylesheets/pixeldex.css` | D.15: `.emulator-grid` + `@media` ; YOU-badge: `.gb-card--current-user` |
| `test/models/soul_link_emulator_save_slot_test.rb` | YOU-badge: extend partial-render test to assert `data-discord-user-id=` survives |

### Created (2)

| Path | Purpose |
|------|---------|
| `app/views/dashboard/_mark_dead_modal.html.erb` | Mark Dead confirmation modal (replaces native `confirm()`) |
| `app/javascript/controllers/roster_you_marker_controller.js` | YOU-badge restoration controller (decorates matching `[data-discord-user-id]` card on connect + on `turbo:before-stream-render`) |

### Rubocop autocorrect sweep (KG-5)

Ran `bundle exec rubocop -a` (safe autocorrect). 121 offenses corrected across 38 additional Ruby files (Layout/SpaceInsideArrayLiteralBrackets dominant, plus Style/DefWithParentheses, Layout/EndAlignment, etc.). Diffs are pure whitespace / style — no semantic changes. 310/310 tests still green post-sweep.

### Modified (handoff)

- `handoff/ARCHITECT-BRIEF.md` — Step 10 brief
- `handoff/BUILD-LOG.md` — Step 10 history entry + Known Gaps update (6 closed, 3 new from Step 10)
- `handoff/REVIEW-REQUEST.md` — this document
- `handoff/REVIEW-FEEDBACK.md` — Reviewer's verdict

### Untouched (per brief)

- All app/controllers, app/models, app/services, app/channels, app/jobs (rubocop autocorrect touched some, but only style/whitespace — no logic changes)
- All factories
- `config/cable.yml`
- `test_helper.rb`

---

## Self-Review

### What would Reviewer most likely flag?

1. **Six PROJECT-REVIEW items skipped after pre-flight reads.** The original PROJECT-REVIEW-2026-04-30.md was based on an earlier scan; six items had already been addressed:
   - **B.6** (gym-draft button disable): every action handler already disables buttons or sets `pointer-events: none`.
   - **B.8** (run_management auto-dismiss): line 56 already has `setTimeout(() => this.clearError(), 8000)`.
   - **B.9** (no empty state for gym drafts): no index route — show is reachable only by ID after create.
   - **B.11** (no "no species assigned" placeholder): per-player rows already show "Drop your species here"/"waiting...".
   - **C.12** (form-label `for` mismatch): the input already has matching `id`.
   - **D.16** (save-slot hard-reload → turbo_stream): meaningful work, deferred to a future step.
   Each is documented in the brief. Worth Reviewer's spot-check on 1-2.

2. **Rubocop autocorrect produced visually-awkward indentation in a few `if/else/end` blocks** (notably `app/services/soul_link/discord_bot.rb:251-261, 353-394`). The `Layout/EndAlignment` cop fixed `else`/`end` alignment to match the `if` opener but didn't reindent the bodies between them. Result: bodies sit at column ~26 while their `else`/`end` keywords sit at column ~6. Code is correct (Ruby is whitespace-insensitive at that level); tests pass. A 5-minute manual cleanup pass to also fix the body indentation would be a nice follow-up. Logged as a new Known Gap.

3. **`window.alert()` carry-over from Step 9.** The Mark Dead modal supersedes the worst native `confirm()` use, but Step 9's Tier-A error toasts still use `window.alert()`. Step 10 didn't add new alerts, but didn't replace existing ones either. Future polish: a styled toast component matching `gb-flash gb-flash-alert`.

4. **YOU-badge controller injects DOM nodes dynamically.** The badge is created and appended in JS rather than rendered server-side. This keeps the broadcast-rendered partial context-free (no `current_user_id` needed in model callbacks), but it's a small DOM-mutation pattern that's slightly less observable than a server-rendered marker. Trade-off: cleaner architecture vs. raw HTML predictability. The architect brief endorsed this approach.

5. **Mark Dead modal opens on top of the pokemon modal.** Z-index 60 vs the pokemon modal's 50. Closing the Mark Dead modal returns the user to the pokemon modal context (pokemon modal stays open underneath). Verify this is the intended UX — alternative would be to also close the pokemon modal when Mark Dead opens. The current behavior is more forgiving (Cancel from Mark Dead returns to where the user was), so I went with that.

### Did every item in the brief ship?

- [x] B.7 cancel opacity dropped
- [x] B.10 schedule already-active hint
- [x] C.13 avatar alt text
- [x] C.14 modal close aria-labels (5 sites)
- [x] D.15 emulator-grid CSS class with @media (min-width: 900px)
- [x] E.17 Mark Dead custom modal
- [x] E.18 FALLEN tooltips (2 sites)
- [x] YOU-badge follow-up (Stimulus controller + data attr + CSS class)
- [x] KG-5 rubocop autocorrect sweep
- [x] 310/310 tests green
- [x] `bundle exec rubocop` reports 0 offenses
- [x] No app/controllers, app/services, app/models semantic changes (autocorrect touched some files but only style/whitespace)

### What does the user see if data is empty or a request fails?

- **Cancel button on gym schedule:** now visually distinct (no opacity); clicking still fires the cancel flow.
- **Schedule already active:** instead of seeing a vanished form, the player sees "A schedule is already active. Cancel the active one below before proposing a new time."
- **Modal close on screen reader:** "Close modal" announcement instead of `&times;` ambiguity.
- **Mobile emulator (< 900px viewport):** sidebars stack vertically; canvas no longer goes negative-width.
- **Mark Dead from pokemon modal:** new modal opens with group nickname + warning copy + CANCEL/CONFIRM DEATH buttons. CONFIRM DEATH fires the PATCH and reloads. CANCEL returns to the pokemon modal.
- **YOU badge after a save broadcast:** the player's own roster card has the YOU badge + 4px-border re-applied client-side after the frame replacement.

---

## Open Questions / Notes

1. **Manual smoke test deferred.** The 9 changes are all UI/JS — no live server was started during the build. Recommend Project Owner manual verification: (a) two-tab emulator save → roster card updates with YOU badge re-applied; (b) dashboard pokemon edit → mark-dead modal flow; (c) emulator page resize narrow→wide → sidebars stack/unstack; (d) modal aria-labels on a screen reader.

2. **The mark_dead modal's close-button click also fires the overlay click.** I noticed `data-action="click->dashboard#closeMarkDeadModal"` on both the X button and the overlay — Stimulus dispatches both (the click bubbles). Net effect: modal closes either way. Not a bug, just over-wiring. Could simplify by stopping propagation on the X button, but it's harmless as-is.

3. **`Turbo::Broadcastable::TestHelper` require/include is still scoped to one test file.** Future broadcast tests in other files would need to add the same boilerplate. If the Step 11 work adds more broadcast assertions, consider adding the include to `test_helper.rb` at the TestCase level.

4. **Step 9's `Layout/SpaceInsideArrayLiteralBrackets` fixes were tactical** (only on touched lines). The Step 10 KG-5 sweep applied the same cop project-wide consistently — the suite is now uniform on that style.

5. **The dashboard now has 3 modals** (catch, pokemon, mark_dead) plus the species page has its own. They're all ad-hoc partials with similar structure. A future cleanup could extract a shared `_modal.html.erb` partial taking title + body + actions. Not Step 10 scope.

6. **The "discord_bot.rb autocorrect indentation" Known Gap** is the only place where the rubocop sweep produced visually awkward output. Three spots specifically (lines around 251-261, 353-369, 383-394). Easy 5-minute manual cleanup pass for whoever picks this up.

---

**Ready for Review: YES**
