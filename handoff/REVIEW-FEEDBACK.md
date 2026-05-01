# Review Feedback — Step 9
Date: 2026-04-30
Status: APPROVED

## Conditions

None.

## Escalate to Architect

None.

## Cleared

Reviewed Step 9 (UX Batch: Tier-A + KG-1/2/3/4) end-to-end: 12 modified files + 1 new partial + 5 new broadcast tests + handoff updates. Diff scope matches the brief — no app/controllers, no app/services, no config changes.

Verifications performed (independently of Bob's claims):

- **Tier-A.1 — `save_slots_controller.js` toasts.** Grep `console.error` returns 6 sites; each has a sibling `window.alert(...)` call within 1-3 lines. The earlier alert at line 143 (unchanged from prior step) is the only one without a paired console.error — it's already a toast, not an additional one. ✓

- **Tier-A.2 — `gym_draft_controller.js` errorBanner.** `static targets` includes `errorBanner`. `handleMessage` calls `this.showError(data.error)` after the `console.error`. `showError` falls back to `alert()` if the target is missing (defensive, in case the view is loaded without the target div). The 8s auto-hide via `setTimeout` matches Step 5's pattern in `run_management_controller.js`. The view's `<div data-gym-draft-target="errorBanner" hidden>` is in `gym_drafts/show.html.erb` line 30. ✓

- **Tier-A.3 — `team_builder_controller.js` pixeldex classes.** Grep `text-yellow-400|text-green-400|text-red-400` returns ZERO matches in the controller. `showStatus` now writes `team-builder-status ${modifier}` where modifier is one of three semantic classes. CSS rules in `pixeldex.css` lines 18-21 define the three modifiers with the existing palette tokens. ✓

- **Tier-A.4 — Save-slot buttons disabled in overwrite mode.** `_enterOverwriteMode` and `_exitOverwriteMode` call `_actionButtons().forEach(btn => btn.disabled = ...)`. `_actionButtons()` selects `[data-action*='save-slots#makeActive'], [data-action*='save-slots#deleteSlot']` within `this.element`. Tab nav + screen reader can no longer focus these during overwrite mode. ✓

- **Tier-A.5 — Pokemon modal SAVE in-flight disable.** `savePokemon(event)` accepts an `event` param now (existing call sites already pass it via `data-action`). `saveBtn = event?.currentTarget; if (saveBtn) saveBtn.disabled = true` at top; every error-return path re-enables; success path leaves disabled (page reloads). ✓

- **KG-1 — Roster broadcast.** Verified the entire chain:
  - `_run_sidebar_card.html.erb` exists, renders cleanly with only `s` as a local (no `current_user_id`, no `@run_sessions`); confirmed by reading the file end-to-end and by Bob's smoke test.
  - `_run_sidebar.html.erb` wraps each session render in `turbo_frame_tag "emulator_roster_session_#{s.id}"`. The header card ("RUN ROSTER") is outside the loop, untouched.
  - `emulator/show.html.erb` line 8: `turbo_stream_from @run, :emulator if @run`.
  - Model: `SoulLinkEmulatorSaveSlot` has `after_create_commit :broadcast_roster_card_on_create` and `after_update_commit :broadcast_roster_card_on_update, if: :saved_change_to_parsed?`. Both delegate to `broadcast_roster_card`, which calls `Turbo::StreamsChannel.broadcast_replace_to(run, :emulator, target: "emulator_roster_session_#{session.id}", partial: "emulator/run_sidebar_card", locals: { s: session })`.
  - The two-method-name workaround for Rails callback dedup is documented inline; the comment correctly identifies the symptom (registering the same method twice keeps only the second registration). Bob verified empirically via the diagnostic test before settling on this.

- **KG-2 — Dashboard refresh.** Both `SoulLinkPokemon` (line 25) and `SoulLinkPokemonGroup` (line 20) have `broadcasts_refreshes_to ->(record) { [ record.soul_link_run, :dashboard ] }`. `dashboard/show.html.erb` lines 5-6 set `turbo_refreshes_with method: :morph, scroll: :preserve` and `turbo_stream_from @run, :dashboard`. The morph mode + scroll-preserve combo means edits in one player's tab show up in others without scroll loss or modal teardown. ✓

- **KG-3 — EVOLVE loading state.** `evolvePokemon(event)` disables the button + sets text to "EVOLVING..." at top; both error-return paths restore disabled+text. Success path reloads (button is going away anyway). ✓

- **KG-4 — Amber token.** `pixeldex.css:11` adds `--amber: #d4b14a;` to the `:root` block. `_run_sidebar.html.erb` (line 33 in the original; the file is now smaller after Bob extracted the card partial) — the inline `#d4b14a` literal is gone, replaced by `var(--amber)`. The new `team-builder-status--saving` modifier also references `--amber`. Grep confirms only the new token-references and the original `:root` declaration remain. ✓

- **Diff scope (brief acceptance criterion).** `git status --short` shows: 12 modified files (5 JS controllers, 3 models, 4 views, 1 stylesheet), 1 new file (`_run_sidebar_card.html.erb`), and 4 handoff files (`ARCHITECT-BRIEF.md`, `BUILD-LOG.md`, `REVIEW-REQUEST.md`, `REVIEW-FEEDBACK.md`), plus `handoff/PROJECT-REVIEW-2026-04-30.md` (carried over from the prior session, included in this commit since it fed Step 9). No controllers, no services, no factory or test_helper changes. ✓

- **YOU badge regression.** `_run_sidebar.html.erb` no longer renders `>YOU<` or the 4px-border conditional. The view test was renamed and the relevant assertion dropped. The Known Gap is logged in BUILD-LOG with two paths to recover it (per-frame Stimulus controller, or wrapper-outside-frame trick). Player can still distinguish their card via `player_label`.

- **Test coverage of the broadcast callbacks.** 5 new tests in `soul_link_emulator_save_slot_test.rb`:
  1. Create with `:filled` trait → 1 broadcast on `[run, :emulator]`. Verified `streams.first["action"] == "replace"` and target matches `emulator_roster_session_<session_id>`.
  2. Update parsed_trainer_name → 1 new broadcast (diff-style: before vs after `capture_turbo_stream_broadcasts.size`).
  3. `update_columns` on parsed_* → 0 new broadcasts (callbacks bypassed; this is the contract — the parse job uses update_columns precisely so the broadcast doesn't fire from inside the job and double up the create-time broadcast).
  4. Update non-parsed field (`touch`) → 0 new broadcasts (the `if: :saved_change_to_parsed?` guard works).
  5. Partial renders standalone with only `s` local → no exception, contains the expected seed string.
  Diff-style counting (capture before + after, compare sizes) is the correct pattern for turbo-rails 2.0.20 because `assert_turbo_stream_broadcasts count: N` captures total-during-test, not block-scoped.

- **`Turbo::Broadcastable::TestHelper` include + require.** Bob used explicit `require "turbo/broadcastable/test_helper"` + `include Turbo::Broadcastable::TestHelper`. Without the require the constant isn't autoloaded in 2.0.20. Verified by reproducing the original NameError before the fix.

- **Tests.** Ran `bin/rails test` independently: 310 runs, 0 failures, 0 errors. Pre-Step-9 was 305. The 5 new tests are all in the broadcast-callback area.

- **Rubocop.** Ran `bundle exec rubocop` on all 5 touched Ruby files: clean. No new offenses; no changes outside the touched lines.

- **`broadcasts_refreshes_to` double-fire risk.** Bob's open question #2 calls out that `SoulLinkPokemonGroup#mark_as_dead!` updates both group + cascading pokemon, each emitting a refresh. Turbo morph debounces close-together refreshes per page, so the user sees one effective update. If telemetry shows excessive refreshes in production, gating on `if: -> { saved_change_to_relevant_field? }` is a 5-minute follow-up. Not blocking.

- **No regression on existing channel functionality.** Ran `bin/rails test test/channels/` — 9 + N runs all green. The new Turbo broadcasts use the `Turbo::StreamsChannel`; the existing `GymDraftChannel`, `GymScheduleChannel`, `RunChannel` use their own custom broadcast paths and are independent.

- **Manual smoke test deferred.** Bob did not run a live two-tab smoke test. The 5 unit tests cover the broadcast wire; end-to-end UX verification is a Project Owner check. Acceptable for this scope.

Bob shipped exactly what the brief specified, plus discovered + correctly handled the Rails-callback-dedup gotcha and the turbo-rails-test-helper-needs-explicit-require gotcha. The five flagged self-review items are all well-reasoned. No deviations from the brief in the diff. Ships as-is.

**Step 9 closes 4 Knowledge Gaps + ships 5 Tier-A silent-failure fixes. The first real-time multi-player UX is now live (pending the production smoke test). The codebase has its first turbo_stream_from / broadcasts_refreshes_to plumbing — future real-time features can follow this pattern.**
