# Review Feedback — Step 21
Date: 2026-05-04
Ready for Builder: YES

## Must Fix

None.

## Should Fix

- **`app/javascript/controllers/save_slots_controller.js:166-189` and `:191-209`** —
  `_enterOverwriteMode` and `_exitOverwriteMode` don't reconcile a slot whose
  inline DELETE confirm is already open. Sequence: user clicks DELETE on slot 3
  (action row hidden, `.confirm-inline` revealed, pill flipped to red CONFIRM);
  then triggers Save File in the emulator while five slots are full → 409 fires
  `_enterOverwriteMode`. Slot 3's `confirmRow` stays visible and its pill is
  overwritten to amber TARGET, so the slot reads as both "confirm delete?" AND
  "click to overwrite" simultaneously. On exit, the pill restores from the
  cached dataset (which captured the original SAVED text, not the in-flight
  CONFIRM text) and the confirm row is still visible. Recommendation: in
  `_enterOverwriteMode`'s `slotTargets.forEach`, also hide each slot's
  `confirmRow` (`slot.querySelector("[data-save-slots-target='confirmRow']")`)
  before swapping the pill. Symmetric reconciliation on `_exitOverwriteMode` is
  already covered by the dataset-cached pill class restoring to the rendered
  original. Edge case, not a daily flow — fix inline if quick, otherwise log to
  BUILD-LOG.
  Fixed inline at <commit-pending>.

## Escalate to Architect

None.

## Cleared

Reviewed Step 21 R3 save-slot redesign across the 7 modified files + 1 new file
(`app/javascript/controllers/roster_seed_controller.js`) at the line ranges
called out in REVIEW-REQUEST.md, plus the four extended test files and the
relevant cited sections of the architect brief and the locked mockup.

What passed:

- **Mockup parity.** All 5 state pills (EMPTY / SAVED / ACTIVE / TARGET /
  CONFIRM) render with the locked colour mapping. Banner replaces the old
  `gb-card` overwrite-pending banner. Per-slot `.confirm-inline` blocks render
  hidden server-side and reveal inline (NOT a modal) — confirmed via the
  inline-DELETE markup test at `test/controllers/emulator_controller_test.rb:193-208`
  and the `assert_no_match(/id="delete-slot-#{n}-confirm"/)` test at lines
  223-238. CLEAR ALL SLOTS uses the same inline pattern. Roster card has the
  3-tile stat strip + `<details>STATS</details>` + TID conflict warning band as
  a high-contrast amber-on-dark band (not a pill) + click-to-copy seed + no peso
  glyph (locked at `:240-257`). HOF pill kept on slot card per Ava answer #4.

- **Inline-confirm flow correctness.** `confirmDelete` reveals confirmRow,
  hides actionRow, swaps the pill class/text, and focuses the cancel button
  (annotation D, Screen 3 — `save_slots_controller.js:122-123`). `cancelDelete`
  reverses cleanly using the dataset-cached original pill class/text.
  `confirmClearAll`/`cancelClearAll` toggle the footer rows symmetrically and
  also focus the cancel button (`:153-154`). Overwrite-pending mode walks every
  filled slot via `slotTargets`, sets `.overwrite-target`, swaps the pill to
  TARGET, hides the per-slot action row, and wires `data-action` on the slot
  wrapper. `_actionButtons()` selector correctly retargets
  `[data-action*='save-slots#confirmDelete']` so Tab focus during overwrite
  mode still skips the (now hidden) DELETE triggers.

- **`window.confirm` removal.** Confirmed both the per-slot DELETE and the
  overwrite path no longer call `window.confirm`. The banner-as-announcement +
  click-as-consent contract holds.

- **Architectural locks honoured.** Inline confirm is genuinely inline (not
  the Step 20 modal). The Step 20 `confirm_modal(...)` calls were removed only
  from `_save_slots_sidebar.html.erb`; greppable consumers in
  `app/views/runs/index.html.erb`, `app/views/dashboard/_runs_content.html.erb`,
  `app/views/gym_schedules/show.html.erb`, and
  `app/views/species_assignments/_group_card.html.erb` remain wired correctly.
  `app/views/shared/_confirm_modal.html.erb`,
  `app/javascript/controllers/confirm_modal_controller.js`, and
  `ConfirmModalHelper` are untouched. Three new tokens (`--d0`, `--green-glow`,
  `--crimson`) declared exactly once each in `:root` (`pixeldex.css:13-17`),
  pinned by the responsive_grids_test at lines 44-48. No other tokens added.
  `_run_sidebar_card.html.erb` keeps the `s`-only locals contract — no
  `current_user_id` / `@run_sessions` references. YOU markers re-applied via
  `roster_you_marker_controller.js#apply()` after each
  `turbo:before-stream-render`. OFF-FEED stays out of scope (lives on PC BOX
  tab). Roster cards show trainer stats per the mockup, not party Pokémon.

- **Out-of-scope surfaces clean.** `git diff --stat HEAD` confirms only the 7
  listed files + 1 new file plus the three handoff docs. Parser pipeline,
  Discord notifier, R2/R4/R1 surfaces, the 6 "not ready" panels in
  `emulator/show.html.erb:15-58`, `_pc_box_content.html.erb`, and the entire
  Step 20 modal infrastructure are untouched.

- **KG-33 + KG-34 in BUILD-LOG.md** at lines 1166-1167. Both accurately scoped
  as mockup-driven UI omissions, not parser regressions; `slot.updated_at` and
  `save_data.bytesize` still persist server-side.

- **Tests.** 21 new test runs as claimed: 8 in
  `test/helpers/emulator_helper_test.rb` pin every `format_progress_phrase`
  boundary including singular/plural and integer truncation; 4 in
  `test/integration/responsive_grids_test.rb` lock the token declarations and
  the no-collapse contract; 5 in `test/controllers/emulator_controller_test.rb`
  cover EMPTY/SAVED state pills, empty-slot CTA, inline DELETE markup, inline
  CLEAR ALL markup, no Step 20 modal ids, and no peso glyph; 4 in
  `test/models/soul_link_emulator_save_slot_test.rb` lock the roster-card
  class, 3-tile strip, HOF inline regex, and the conflict-warning band on/off
  paths. I could not run the suite locally (mise still resolves a stale Ruby
  3.0.6 in this worktree shell for `bin/rails`), but the assertion shapes are
  correct and Bob reports 0 failures / 0 errors. Trusting the claim.

Bob's open questions, resolved:

1. **TID conflict partner-name ordering** — current id-order rendering is fine
   for v1. Mockup doesn't pin it and the only multi-partner case (3-player
   conflict) is rare. Accept as is. If alphabetical reads better in real use,
   future-step polish.
2. **`Seed: ` prefix retained in element textContent** — locked. Mockup line
   674 renders `<div class="seed">Seed: 0xAB12CD34EF567890</div>` verbatim;
   `roster_seed_controller.js#copy` strips the prefix before the clipboard
   write so users get just the hex. Implementation matches the mockup.
3. **`format_progress_phrase` for negative seconds** — only caller is the
   inline DELETE confirm body, fed by `parsed_play_seconds` from a real save
   where negative values are not reachable. Cosmetic divergence from
   `format_play_time`'s clamp-to-zero behaviour; locked test bench doesn't pin
   it. Accept as is.
4. **`.slot.empty .slot-meta` dimmed to `--d2`** — mockup-locked
   (`pixeldex.css:1084` matches mockup line 130). Visual judgment call; if real
   renders read too dim, future-step adjustment.

`Step 21 is clear.`
