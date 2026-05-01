# Review Request
*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

Ready for Review: YES

---

## Step 9 — UX Batch: Tier-A + KG-1/2/3/4

**Builder:** Bob
**Tests:** 310/310 passing (305 baseline + 5 new broadcast tests). 0 failures, 0 errors.
**Lint:** `bundle exec rubocop` clean on all 5 touched Ruby files (3 models, 2 tests).

---

## Files Changed

### Modified (12)

| Path | Change |
|------|--------|
| `app/javascript/controllers/save_slots_controller.js` | A.1 toasts on every error branch (5 sites) + A.4 button-disable in overwrite mode + new `_actionButtons()` helper |
| `app/javascript/controllers/gym_draft_controller.js` | A.2 `errorBanner` target + new `showError(message)` method with 8s auto-hide |
| `app/javascript/controllers/team_builder_controller.js` | A.3 replaced Tailwind classes with `team-builder-status--saving/saved/error` modifiers |
| `app/javascript/controllers/pixeldex_controller.js` | A.5 SAVE button disable in-flight + KG-3 EVOLVE loading state |
| `app/models/soul_link_emulator_save_slot.rb` | KG-1 broadcast callbacks (two distinct method names to dodge Rails callback dedup) |
| `app/models/soul_link_pokemon.rb` | KG-2 `broadcasts_refreshes_to ->(p) { [p.soul_link_run, :dashboard] }` |
| `app/models/soul_link_pokemon_group.rb` | KG-2 same pattern |
| `app/views/emulator/show.html.erb` | KG-1 `turbo_stream_from @run, :emulator if @run` |
| `app/views/emulator/_run_sidebar.html.erb` | KG-1 frame wrap + KG-4 amber token (also dropped YOU badge / 4px-border — Known Gap) |
| `app/views/dashboard/show.html.erb` | KG-2 `turbo_refreshes_with method: :morph` + `turbo_stream_from @run, :dashboard` |
| `app/views/gym_drafts/show.html.erb` | A.2 `errorBanner` target div |
| `app/assets/stylesheets/pixeldex.css` | KG-4 `--amber` token + A.3 `team-builder-status--*` classes |

### Created (1)

| Path | Purpose |
|------|---------|
| `app/views/emulator/_run_sidebar_card.html.erb` | Single-session card extracted from `_run_sidebar.html.erb`; renders cleanly with only `s` (the session) as a local — no controller context needed |

### Modified (test files)

- `test/models/soul_link_emulator_save_slot_test.rb` — added 5 broadcast tests + `Turbo::Broadcastable::TestHelper` include + explicit require
- `test/controllers/emulator_controller_test.rb` — renamed YOU-badge test, dropped `>YOU<` assertion (Known Gap)

### Modified (handoff)

- `handoff/ARCHITECT-BRIEF.md` — Step 9 brief
- `handoff/BUILD-LOG.md` — Step 9 history entry + Known Gaps section update (4 closed, 4 new from Step 9)
- `handoff/REVIEW-REQUEST.md` — this document
- `handoff/REVIEW-FEEDBACK.md` — Reviewer's verdict

### Untracked → committed in this batch

- `handoff/PROJECT-REVIEW-2026-04-30.md` — diagnostic report from the prior session that fed this step

### Untouched (per brief)

- All app/controllers
- All app/services
- All app/channels (existing channels — gym_draft, gym_schedule, run — untouched)
- `config/cable.yml` (still async; bot-process broadcasts deferred)
- All factories
- `test/test_helper.rb`

---

## Self-Review

### What would Reviewer most likely flag?

1. **Two-method-name workaround on `SoulLinkEmulatorSaveSlot`.** Rails dedupes callback registrations by method name across lifecycle events: `after_create_commit :foo` + `after_update_commit :foo` only keeps the second. I verified this empirically — the first attempt with a single method on both events fired ONLY on update. Split into `broadcast_roster_card_on_create` + `broadcast_roster_card_on_update`, both delegating to a shared private `broadcast_roster_card`. Documented inline.

2. **YOU badge / 4px-border removed from roster cards.** Preserving them across stream replacements would require either (a) passing `current_user_id` into a model callback (layer violation), (b) wrapping the marker outside the turbo_frame_tag (DOM fragility — frame replacement preserves the wrapper), or (c) a small Stimulus controller that decorates the matching frame post-render. (a) violates clean architecture, (b) breaks because the marker would need its own per-session id which means we already have that frame, (c) is a follow-up. Logged as Known Gap. Updated the failing emulator test to reflect.

3. **Tier-A toasts use `window.alert()`.** Brief explicitly endorsed this as the smallest viable change. A styled toast component (matching `gb-flash gb-flash-alert`) is a follow-up. The user has already seen 4 alerts during normal usage (delete confirm, restore confirm, slot-N-active info, network errors) — the added ones don't break the existing UX style.

4. **`broadcasts_refreshes_to` on pokemon + group fires unconditionally on every save.** Brief acknowledges this — relevant fields for the dashboard are nearly all attributes (species, level, ability, nature, status, nickname). A few extra refreshes are cheap with morph mode. If the rate becomes problematic, gate via `if: -> { saved_change_to_relevant_field? }` later.

5. **Turbo test helper requires + tests use diff-style counts.** `Turbo::Broadcastable::TestHelper` isn't auto-loaded; explicit `require "turbo/broadcastable/test_helper"` + `include`. Tests that need to count broadcasts INSIDE a block (vs the entire test run) capture before+after with `capture_turbo_stream_broadcasts` and compare sizes — the helper's `assert_turbo_stream_broadcasts` count argument applies to total-during-test, not block-scoped, so the diff approach is the correct pattern for this Turbo version.

6. **YOU badge test renamed.** `"show roster renders player names, YOU badge, and Unclaimed entries"` → `"show roster renders player names and Unclaimed entries"`. The 3 surviving assertions still hold. Comment explains why.

### Did every item in the brief ship?

- [x] A.1 — save_slots_controller.js toasts
- [x] A.2 — gym_draft_controller.js error banner
- [x] A.3 — team_builder_controller.js pixeldex classes
- [x] A.4 — Save-slot buttons disabled during overwrite mode
- [x] A.5 — Pokemon modal SAVE in-flight disable
- [x] KG-1 — Real-time roster card replace
- [x] KG-2 — Real-time dashboard morph-refresh
- [x] KG-3 — EVOLVE loading state
- [x] KG-4 — `--amber` palette token
- [x] Full suite green: 310/310
- [x] Rubocop clean on touched files
- [x] No app/controllers or app/services changes
- [x] BUILD-LOG Known Gaps updated (4 closed, 4 new)

### What does the user see if data is empty or a request fails?

- **Save-slot delete/restore/overwrite failure:** `window.alert("Could not [action] slot N. Try again or contact the run creator.")` (was: silent console.error)
- **Gym draft action rejected:** red banner inside the page for 8s with the server's error message (was: silent console.error)
- **Pokemon modal save in-flight:** SAVE button greys out + "SAVING..." status; on error the button re-enables so the user can retry
- **EVOLVE click in-flight:** EVOLVE button greys out + "EVOLVING..." text; on error restores
- **Real-time tab open + another player edits a pokemon:** Turbo morphs the dashboard in place, scroll position preserved, modals stay open
- **Real-time + save slot parsed:** the matching session's roster card replaces in place, no full reload (so the running emulator iframe stays intact)

---

## Open Questions / Notes

1. **Does the manual smoke test cover the broadcast paths?** Bob did not run a two-tab manual test in this step (no live dev server up). The 5 unit tests for the broadcast callbacks cover that the broadcast fires + targets the right stream + renders the right partial. End-to-end real-time UX verification is a Project Owner / production smoke check. Expectation: open `/emulator` in two browsers logged in as different players; trigger a save in one; the other's roster card updates without page reload.

2. **`broadcasts_refreshes_to` macro on `SoulLinkPokemon` may double-fire.** When `assign_to_group!` updates pokemon AND triggers `mark_as_dead!` on the group (in `mark_as_dead!`), both broadcast a refresh. The dashboard receives 2 refreshes in quick succession. Turbo's morph engine deduplicates close-together refreshes (debounce); shouldn't be user-visible. Worth monitoring once real traffic flows through.

3. **No browser-level smoke test for the YOU badge regression.** The view test asserts `>YOU<` is gone; that's the contract. A Project Owner manual verification on the emulator page would confirm the visual loss is acceptable in practice.

4. **The `Turbo::StreamsChannel.broadcast_replace_to` call renders the partial in the broadcast callback's thread.** If the partial render raises, the after_commit callback raises and the calling controller / job sees the exception. Tested implicitly by the broadcast tests (they'd fail if the partial errored). For belt-and-suspenders, future iteration could wrap the broadcast call in `rescue StandardError => e; Rails.logger.error(...)` so a partial regression doesn't break model save flows.

5. **Pre-existing rubocop offenses outside touched files** — still 133-ish across the suite (unchanged). Step 9 touched only 5 Ruby files; rubocop clean on those. Outside the scope.

6. **The `_run_sidebar_card.html.erb` partial calls `SoulLink::GameState.player_name`.** That's a YAML-cached lookup, fine in production. In tests, the partial renders against a fresh GameState (or stubbed one); my smoke test renders cleanly so no concern.

---

**Ready for Review: YES**
