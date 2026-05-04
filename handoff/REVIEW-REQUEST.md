# Review Request — Step 21

**Builder:** Bob
**Branch:** `claude/agitated-matsumoto-d48881` (worktree)
**Ready for Review: YES**
**Scope:** Step 21 — R3 Save Slots redesign per § 4 R3 of `handoff/2026-05-04-ui-audit.md` and the locked mockup `handoff/2026-05-04-ui-audit-mockup-save-slots.html` (5 screens). First Phase 2 redesign (R3 → R2 → R4 → R1 ship order locked by the audit).

---

## Summary

7 modified files, 1 new file. Full suite: **676 → 697 runs (+21); 0 failures, 0 errors**. Rubocop clean (197 files, 0 offenses). Brakeman clean for Step 21 — same 2 pre-existing weak-confidence warnings (`emulator_controller.rb:79`, `gym_schedule_discord_update_job.rb:14`) unchanged from Steps 18/19/20. 0 migrations. 0 new gem deps. 0 new design tokens beyond the three named in the brief (`--d0`, `--green-glow`, `--crimson`).

Built per Bob's plan B-1 → B-5 with Ava's approved answers folded in. No commits along the way — single-commit ship to keep `git log` readable, matching Step 18/19/20.

---

## Per-bucket changes

### B-1 — CSS tokens + scoped styles

- **`app/assets/stylesheets/pixeldex.css:5-19`** — three new tokens added inside the existing `:root` block, each tagged `/* Step 21 R3 — <role> */`:
  - `--d0: #0a1a0a;` — slot inner bezel + action-button bg + seed monospace bg.
  - `--green-glow: #5fd45f;` — ACTIVE state pill bg + active-slot 4px border.
  - `--crimson: #c75a5a;` — CONFIRM state pill + DELETE FOREVER bg + inline-confirm border.
- **`app/assets/stylesheets/pixeldex.css:1045-1257`** — new `/* ── R3 Save Slots ── */` section inserted immediately above the existing `RESPONSIVE` divider. Mockup CSS (`<style>` lines 85–322) copied verbatim except the kebab-case rename `.slot.overwrite-target` (mockup uses camelCase `.slot.overwriteTarget`; our codebase is kebab throughout). New rules: `.slot`/`.slot.active`/`.slot.overwrite-target`/`.slot.empty`, `.slot-head`/`.slot-num`/`.state-pill` + 5 modifiers (`empty`/`saved`/`active`/`target`/`confirm`), `.slot-meta` + nested `.row .lbl/.val/strong`, `.slot-actions` + button modifiers (`primary`/`danger`/`confirm`), `.confirm-inline` + `.q/.body/.actions`, `.pending-banner` + `.icon` + button, `.footer-actions` + button, `.roster-card` + `.you/.head/.name/.you-badge/.stats/.stat`, `.roster-card details/summary/.extra/.seed`, `.conflict-warning`, `.hof-pill`. Pure addition — no existing rule edited.
- **No removals or edits to existing CSS rules.** `gb-card`/`gb-grid-N`/`emulator-grid`/the existing 900px/520px/1200px media blocks all untouched.

### B-2 — Save-slot sidebar markup (`app/views/emulator/_save_slots_sidebar.html.erb`)

Full body rewrite per Screens 1, 2, 3 of the mockup. Outer `data-controller="save-slots"` wrapper preserved with all three `*-value`s.

- **Header:** plain `<h2 style="font-family: 'Press Start 2P'…">SAVE SLOTS</h2>` replaces the inline-styled `gb-card` row. Uses the new mockup CSS for typography.
- **Pending banner** (`pixeldex.css` `.pending-banner`): the `data-save-slots-target="banner"` div now carries the mockup markup (`<span class="icon">⚠</span> SAVE FULL — PICK A SLOT TO OVERWRITE` + a CANCEL button wired to `save-slots#cancelOverwrite`). Hidden by default; revealed by the controller after a 409.
- **Per slot loop** (`MIN_SLOT..MAX_SLOT`):
  - Wrapper `<div class="slot[ active][ empty]" data-save-slots-target="slot" data-slot-number data-filled>`. Inline `style="…"` blocks dropped — the new CSS owns it.
  - `.slot-head` with `.slot-num` (`SLOT N`) + `.state-pill.<empty|saved|active>` carrying `data-save-slots-target="slotPill"`. Pill ALWAYS rendered (was previously gated on `is_active`).
  - Empty slot: `.slot-meta` body is the literal CTA copy `— drop a save here from the emulator —` (em-dash U+2014, mockup-verbatim).
  - Filled slot: `.slot-meta` with `<strong>` trainer name (gated on `parsed_trainer_name.present?`) + label/value rows. PLAY + BADGES share one row (mockup line 392 stacks both); MAP, DEX (`X caught · Y seen`), TID/SID render only when their underlying parsed_* field is present (existing nil-gating preserved). The slot-card MONEY row is dropped (mockup omits it from the slot column entirely; Money survives in the roster card's `<details>`). The `time_ago_in_words` "saved … ago" footer + the `number_to_human_size` byte count are dropped — logged as KG-33 per Ava answer #3.
  - HOF pill: when `parsed_hof_count >= 1`, renders `<span class="hof-pill">🏆 HOF</span>` after the body rows, before `.slot-actions` (Ava answer #4).
  - `.slot-actions` (filled only) carries `data-save-slots-target="actionRow"`. Children: DOWNLOAD `<a>` (existing href), MAKE ACTIVE `<button class="primary">` (only when not active, existing `save-slots#makeActive` wiring), DELETE `<button class="danger">` wired to the **new** `save-slots#confirmDelete` action.
  - `.confirm-inline` block (filled only, rendered with `hidden` attribute, `data-save-slots-target="confirmRow"`, `data-slot-number=N`): `.q` "DELETE THIS SLOT?", `.body` with `format_progress_phrase(parsed_play_seconds) + ". There's no undo — the save file is gone after this."`, `.actions` with CANCEL (`save-slots#cancelDelete`) + `class="confirm"` DELETE FOREVER (`save-slots#deleteSlot`).
- **Footer:** `data-controller="clear-save"` wrapper carries the new `.footer-actions` row (CLEAR ALL SLOTS button → `save-slots#confirmClearAll`) + a sibling `.confirm-inline` rendered hidden with CANCEL (`save-slots#cancelClearAll`) + CLEAR ALL SLOTS confirm button (`clear-save#clear`). Same nesting as before so the inline confirm's button still reads the controller's URL/CSRF values.
- **Removed:** the two `confirm_modal(...)` partial calls (per-slot DELETE and CLEAR ALL SLOTS) + their trigger buttons' `data-action="click->confirm-modal#open"` wiring + the per-slot `<button data-save-slots-target="overwriteOverlay">` overlay markup.

### B-3 — `save_slots_controller.js`

Additive overhaul — every existing public action signature preserved (`makeActive`, `deleteSlot`, `overwriteSlot`); the markup wiring just changes which trigger fires them.

- **`app/javascript/controllers/save_slots_controller.js:21-39`** — new static `targets` set: `["banner", "slot", "slotPill", "actionRow", "confirmRow", "clearAllAction", "clearAllConfirm"]`. Dropped `overwriteOverlay` (the per-slot overlay button is gone).
- **`connect()`:42-58** — caches each slot pill's original class + text on the pill's dataset (`data-original-pill-class` / `data-original-pill-text`). Survives broadcast replacements better than a JS-side WeakMap because the value travels with the rendered DOM. Used by `_exitOverwriteMode` and `cancelDelete` to restore the pill state.
- **`confirmDelete(event)`:108-127** — locates the matching slot via `data-slot-number`, hides its `.slot-actions` (`actionRow.hidden = true`), reveals the sibling `.confirm-inline` (`confirmRow.hidden = false`), swaps the slot pill to `state-pill confirm` with text `CONFIRM`, focuses the cancel button (safe-default keyboard behavior the mockup annotation calls out).
- **`cancelDelete(event)`:129-141** — reverses the above. Restores the pill's original class + text from the dataset cache.
- **`confirmClearAll(event)`:145-153** / **`cancelClearAll(event)`:155-159** — toggle the two footer rows. No pill swap (the footer button has no pill).
- **`_enterOverwriteMode(_event)`:163-186** — replaces the overlay-reveal logic. Walks each filled `.slot`, adds `.overwrite-target` class (amber border via the new CSS), sets `data-action="click->save-slots#overwriteSlot"` on the wrapper (the slot itself is now the click target), hides its `actionRow`, swaps the pill class to `target` + text to `TARGET`. Disables `_actionButtons()` for keyboard safety.
- **`_exitOverwriteMode()`:188-205** — undoes the above. Restores pill class + text from the dataset cache.
- **`cancelOverwrite(event)`:207-210** — wired to the banner's CANCEL button. Calls `_exitOverwriteMode()`.
- **`_actionButtons()`:212-220** — selector retargeted: replaces the `[data-confirm-modal-id-param^='delete-slot-']` clause (Step 20) with `[data-action*='save-slots#confirmDelete']` (Step 21). Keeps the `save-slots#makeActive` clause.
- **`overwriteSlot(event)`:222-265** — `window.confirm(CONFIRM_OVERWRITE)` line and the `CONFIRM_OVERWRITE` constant removed. Banner + amber slot border + visible TARGET pill is the announcement; the click on a TARGET slot is the explicit consent. Step 20 already removed the native confirm from DELETE; this is the last `window.confirm` in the file. Rest of the flow (byte-grab via `EJS_emulator.gameManager.getSaveFile()` + PATCH + reload) unchanged.

### B-4 — Roster card (`app/views/emulator/_run_sidebar_card.html.erb`)

Full body rewrite per Screen 4. **`s`-only locals contract preserved** (Step-9 lock).

- **Wrapper:** `<div class="roster-card" data-discord-user-id="…">`. Drops `gb-card` so the new `.roster-card` rules apply cleanly. The `.you` class + `.you-badge` are injected client-side by the updated `roster_you_marker_controller.js` (B-4b).
- **`.head` row:** `<span class="name roster-card-name">PLAYER<span class="hof-pill">🏆 HOF</span></span>` (HOF only when `active_slot&.parsed_hof_count.to_i >= 1`) + `<span class="state-pill <class>"><STATUS></span>`. Status → pill-class mapping: `ready` → `saved`, `pending`/`generating` → `target`, `failed` → `confirm`, fallback → `saved` (Ava answer #1: single colour vocabulary across slots and roster).
- **`.stats` 3-tile grid:** BADGES / DEX / PLAY. Renders `—` for nil values via `active_slot&.parsed_badges.nil? ? "—" : …`. The grid stays rectangular — all 3 tiles ALWAYS render even when partial.
- **TID conflict warning band:** placed _outside_ `<details>`, between `.stats` and `<details>`, only when the session is in a conflict group. Computed inline from `s.soul_link_run.tid_conflict_groups` — the model returns arrays of session ids (verified at `soul_link_run.rb:98-113`); the partial finds the group containing `s.id`, drops `s.id`, maps remaining ids → `SoulLinkEmulatorSession.find_by(id:)&.discord_user_id` → `SoulLink::GameState.player_name(...)`. Copy: `⚠ TID CONFLICT WITH <names joined by ', '> · re-roll the seed`. **Fallback:** if `tid_conflict_groups` matches but no usable partner labels surface (all partner names nil), renders `⚠ TID CONFLICT · re-roll the seed` without partner names. **N+1 acknowledged** (Ava OK'd): max 3 `find_by` per render, only fires on the conflict path, primary-key lookups, broadcast partial has no preload context.
- **`<details><summary>STATS</summary>` block:** TRAINER (`parsed_trainer_name`, no "In-game:" prefix), MAP (`format_map_name(parsed_map_id)`), MONEY (`number_with_delimiter(parsed_money)` only — no peso glyph), TID/SID, DEX SEEN (`parsed_pokedex_seen`). Each row is `<div class="row"><span class="lbl">LABEL</span><span>value</span></div>`. Skips rows whose underlying field is nil. **Dropped:** the existing "Active … ago" + "Save: bytes" rows entirely (KG-34 per Ava answer #3).
- **Seed:** `<div class="seed" data-controller="roster-seed" data-action="click->roster-seed#copy">Seed: …</div>` inside the `<div class="extra">` block, after the row list. The `cursor: copy` + the CSS-only `:hover::after` "click to copy" hint live in the new CSS; the controller does the actual copy.

### B-4b — `roster_you_marker_controller.js` (selector + injection update)

- **`apply()`:34-62** — when a card matches: adds `you` class (was `gb-card--current-user`) to the wrapper to match `.roster-card.you` in the new CSS, and injects the `.you-badge` span inside the `.roster-card-name` element (was appended to `card.querySelector("div")`). Keeps the data attribute `data-roster-you-marker-badge="true"` and the dedupe guard.
- When a card doesn't match: strips `you` class and removes any prior badge.
- Dropped the inline `style.cssText` on the badge — the new `.you-badge` CSS owns the styling.
- Stimulus controller name + registration unchanged. Broader contract not touched (per brief).

### B-4c — `roster_seed_controller.js` (new file, ~25 lines)

- **`app/javascript/controllers/roster_seed_controller.js:1-22`** — new Stimulus controller. On click: strips `Seed: ` prefix, `await navigator.clipboard.writeText(seed)`, swaps `element.textContent` to `Copied!` for 1s then reverts. Catches failures → `window.alert("Could not copy seed — copy it manually.")` (project's friendly-error pattern).
- **Auto-registered** by the existing `eagerLoadControllersFrom("controllers", application)` in `app/javascript/controllers/index.js`. No registration edit needed.

### B-5 — Helper + tests

- **`app/helpers/emulator_helper.rb:46-68`** — new `format_progress_phrase(seconds)` method. Locked rule documented inline:
  - `nil` or `seconds < 60` → `"less than a minute of progress"`
  - `60 ≤ seconds < 120` → `"1 minute of progress"` (singular special-case)
  - `120 ≤ seconds < 3600` → `"N minutes of progress"` (N = `seconds / 60`, integer div)
  - `3600 ≤ seconds < 7200` → `"1 hour of progress"` (singular special-case)
  - `seconds ≥ 7200` → `"N hours of progress"` (N = `seconds / 3600`, integer div, truncating)
- **Test additions (12 buckets per the brief, 21 new test runs total):**
  - `test/helpers/emulator_helper_test.rb` — 8 new tests for `format_progress_phrase` covering the 5 boundaries plus singular/plural pinning + truncation edge case (3h59m).
  - `test/integration/responsive_grids_test.rb` — 4 new tests: tokens declared exactly once each in `:root`, no `display: none` collapse on `.slot` or `.roster-card` inside the existing 520px/900px breakpoints, `.emulator-grid` shape (1fr default + 280px/1fr/280px at 900px).
  - `test/controllers/emulator_controller_test.rb` — 5 new tests: extended `>ACTIVE<` to also assert `>SAVED<` and `>EMPTY<`, empty-slot CTA copy, inline DELETE confirm markup with `data-action="click->save-slots#confirmDelete"` + `class="confirm-inline" hidden` + `DELETE FOREVER`, inline CLEAR ALL SLOTS confirm, no `confirm_modal` ids 1..5 + no `clear-all-slots-confirm`, no peso glyph anywhere.
  - `test/models/soul_link_emulator_save_slot_test.rb` — 4 new tests: `roster-card` class + 3 stat tiles + `<details>STATS</details>` + `data-controller="roster-seed"`, HOF inline pill anchored inside the name span via regex, TID conflict band rendered when 2 sessions share TID/SID, conflict band absent when there's no conflict.

---

## Files

### New (1)
- `app/javascript/controllers/roster_seed_controller.js`

### Modified (7)
- `app/assets/stylesheets/pixeldex.css` — 3 tokens in `:root` + new R3 section (~245 lines added).
- `app/views/emulator/_save_slots_sidebar.html.erb` — full body rewrite.
- `app/views/emulator/_run_sidebar_card.html.erb` — full body rewrite.
- `app/javascript/controllers/save_slots_controller.js` — overhaul (additive on top of existing public actions).
- `app/javascript/controllers/roster_you_marker_controller.js` — selector + injection point update.
- `app/helpers/emulator_helper.rb` — added `format_progress_phrase`.
- `app/views/emulator/_run_sidebar.html.erb` — **untouched** (turbo_frame_tag wrapper preserved per the brief; only the inner card partial changed).

### Test files extended (4)
- `test/controllers/emulator_controller_test.rb`
- `test/helpers/emulator_helper_test.rb`
- `test/integration/responsive_grids_test.rb`
- `test/models/soul_link_emulator_save_slot_test.rb`

### Handoff (2)
- `handoff/ARCHITECT-BRIEF.md` (Ava's "Architect response" section appended before the build).
- `handoff/BUILD-LOG.md` (Current Status + new Step 21 entry + KG-33/34).

---

## Things to verify (Richard, focus here)

1. **Mockup parity on the three core screens.** Visit `/emulator` and walk Screens 1 (default — every slot has a state pill), 2 (overwrite-pending — banner appears, filled slots get amber TARGET pill + amber border, action rows hide, whole slot is the click target), 3 (inline DELETE confirm — slot pill flips to red CONFIRM, action row swaps for `.confirm-inline`, CANCEL restores). Compare against `handoff/2026-05-04-ui-audit-mockup-save-slots.html`.
2. **Roster card structure (Screen 4).** name + state pill on top, 3-tile stat strip, TID conflict warning band as a high-contrast amber-on-dark band (NOT a tiny pill), `<details>STATS</details>` collapse, click-to-copy seed. Money rendered with `number_with_delimiter` and **no peso glyph anywhere in the body** — locked test #6 enforces this.
3. **YOU markers across broadcast replacement.** With 2 browsers logged in as different players, watch one player's emulator session render — the YOU badge + 4px amber border should land on the correct card and survive a Turbo Stream replacement (parsed_* update). The controller listens for `turbo:before-stream-render` and re-applies in `requestAnimationFrame`.
4. **`format_progress_phrase` rule.** The body of the inline DELETE confirm should read:
   - empty slot's confirm copy never fires (no DELETE button on empty slots).
   - <60s: "less than a minute of progress."
   - 60s exactly: "1 minute of progress."
   - 30 minutes: "30 minutes of progress."
   - 1h00m exactly: "1 hour of progress."
   - 4h23m: "4 hours of progress." (no zero-pad)
5. **TID conflict band partner-name lookup.** Force a TID conflict (two sessions with matching `parsed_trainer_id` + `parsed_secret_id`); verify the band reads `⚠ TID CONFLICT WITH <other player name> · re-roll the seed`. Then null out one partner's discord_user_id and verify the fallback `⚠ TID CONFLICT · re-roll the seed` (no partner name) renders. The N+1 (max 3 `find_by` per render) is Ava-approved on a cold path.
6. **`save_slots_controller.js#_actionButtons()` selector update.** Overwrite-pending mode should still disable the DELETE trigger (now an inline-confirm trigger). `[data-action*='save-slots#confirmDelete']` is the new selector clause.
7. **No `window.confirm` in `overwriteSlot`.** The banner is the announcement; the click on a TARGET slot is the explicit consent. Step 20 already removed the native confirm from DELETE; this is the last one in the file.

---

## Open questions for Richard

1. **TID conflict partner-name lookup ordering.** I haven't sorted `partner_labels` — they come out in `tid_conflict_groups`'s natural id order (which is session creation order). For a 2-player conflict that's fine; for a 3-player conflict the names render in the order the slots were created. If you'd prefer alphabetical, I can `.sort` before the join — flag it.
2. **`.seed` element retains the "Seed: " prefix in its `textContent`.** The controller strips it before writing to clipboard, but the displayed text reads "Seed: 0xABC…". Mockup line 674 shows the same `Seed: 0xAB12CD34EF567890`. If the brief intended the seed value alone (no prefix), I'll drop the prefix in the partial — but I read mockup-locked.
3. **`format_progress_phrase` for negative seconds.** I treat it via `seconds.to_i < 60` — `-100` returns "less than a minute of progress". `format_play_time` (the sibling helper) clamps negative to zero and returns `"0h 0m"`. Either is defensible; if you'd prefer parity, I can clamp negative to zero in `format_progress_phrase` too. Locked test bench doesn't pin this corner.
4. **`empty` class on slot wrapper carries `.slot.empty` styling that dims `.slot-meta` to `--d2`.** The empty slot CTA copy renders correctly but reads as fairly dim. Mockup line 130 (`.slot.empty .slot-meta { color: var(--d2); }`) intentional — the empty state is meant to be muted. If real renders look too dim, lift to `--l1`. Flagging.

---

`Ready for Review: YES`. No commits — single-commit ship after review-pass.
