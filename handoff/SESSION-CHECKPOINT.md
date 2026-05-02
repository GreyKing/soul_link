# Session Checkpoint
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*
*Session-scoped — archived to `handoff/archive/` at session end.*

---

## Where We Stopped

Step 13 (Undo Affordances on Gyms Tab — UNMARK + RESET DRAFT) shipped + FF-merged to `main` + pushed. Awaiting next brief from Project Owner.

---

## What Was Built

**Step 13 — UNMARK + RESET DRAFT.** Two "let me undo a mistake" affordances on the dashboard's Gyms tab:

- **UNMARK** button on the highest defeated gym row in `_gyms_content.html.erb`. Reuses the existing `GymProgressController#update` endpoint (which already toggles based on `GymResult` existence and guards "highest gym only"). No backend change. Lightweight, no confirm modal — Project Owner's pain was *that mistakes are unfixable*; reintroducing friction would defeat the point.
- **RESET DRAFT** button in the Gyms-tab panel header, alongside START GYM DRAFT, gated on `@active_draft.present?` (status in `lobby/voting/drafting/nominating`). Opens a confirm modal mirroring `_mark_dead_modal.html.erb` byte-for-byte (overlay, gb-modal, close-X, backdrop click). CONFIRM RESET fires DELETE /gym_drafts/:id; page reloads. New `GymDraftsController#destroy` has belt-and-suspenders status guard + auth scoping via `run.gym_drafts.find_by(id:)` to prevent cross-guild bypass.

New file: `_reset_draft_modal.html.erb`. Three new Stimulus actions on `dashboard_controller.js` (`openResetDraftModal`, `closeResetDraftModal`, `confirmResetDraft`) mirroring the Mark Dead pattern. Routes gain `:destroy` on gym_drafts.

Tests: 335 → 343 (+8). New `test/controllers/gym_progress_controller_test.rb` (closes pre-existing test gap — covers mark, unmark, reject-non-highest, reject-invalid-num). Extended `gym_drafts_controller_test.rb` with destroy / destroy-complete-rejected / destroy-cross-guild-404. Rubocop clean (0 offenses across 148 files).

---

## What Was Decided This Session

- **UNMARK gets no confirm modal.** The Project Owner explicitly chose lightweight — recovering from an accidental mark-beaten shouldn't require another step. Title attr is the only "are you sure?" hint.
- **RESET DRAFT gets the full Mark Dead modal pattern.** Resetting destroys 4-6 rounds of player picks (held in `state_data` JSON); that's real crafted data. Mirroring the existing Mark Dead UX keeps modal UX consistent across the dashboard.
- **Reset = destroy, not "back to lobby".** Matches the user's mental model ("reset = start over"). After destroy, the user clicks START GYM DRAFT again (the existing button creates fresh).
- **Reset condition is `status in [lobby, voting, drafting, nominating]`** — same set as `GymDraftsController#create`'s reuse logic. `complete` drafts are intentionally NOT resettable from the dashboard (out of scope; the user marks-beaten or accepts).
- **Belt-and-suspenders gating.** View gates via `@active_draft` (only loads non-complete); controller gates via `status.in?(...)`. Both must hold; direct-curl bypass returns 422.
- **No new turbo broadcasts on `GymDraft`.** Reset action returns JSON `{ ok: true }` and the JS reloads. Same model as `GymDraftsController#mark_beaten`. Real-time draft state already flows through the WebSocket channel for the draft show page; the dashboard's gyms tab doesn't need it.
- **No changes to `GymProgressController`.** The unmark path already works. The pre-existing JSON-response-on-HTML-form quirk stays — it's pre-Step-13 territory and the user has been using MARK BEATEN successfully despite it.

---

## Known Gaps / Future Work

*See `handoff/BUILD-LOG.md` Known Gaps — running list maintained there.*

Four new gaps logged in this step:
1. `test/controllers/dashboard_controller_test.rb` does not exist — render-condition tests for the Gyms tab partial were optional per the brief and deferred.
2. `broadcasts_refreshes_to` not added to `GymDraft` — page-reload after reset is sufficient for v1.
3. Pre-existing JSON-response-on-HTML-form quirk in `GymProgressController#update` — explicitly forbidden to fix in Step 13.
4. RESET DRAFT only on the dashboard's Gyms tab, not on `gym_drafts/show.html.erb` — out of scope per the brief; can be added if the user reports the in-draft-page absence as friction.

---

## Resume Prompt

Copy and paste this to resume:

---

You are Ava (Architect) on Soul Link — Three Man Team.
Read handoff/SESSION-CHECKPOINT.md, then handoff/BUILD-LOG.md.
Confirm status and next action. Then wait for direction.

---
