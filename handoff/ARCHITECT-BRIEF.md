# Architect Brief

> Locked instructions for the current step. Bob, this is your only source of truth.
> If anything below contradicts the mockup HTML, **the mockup wins**. Tell Arch.

---

## Step 21 — R3 Save Slots redesign (Phase 2 R3 of the 2026-05-04 audit)

### Reference files (read in this order, then stop)

1. `handoff/2026-05-04-ui-audit-mockup-save-slots.html` — **locked design**, 5 screens. Read end-to-end before touching code.
2. `handoff/2026-05-04-ui-audit.md` § 4 R3 (lines 229–235) and § 2 Workflow 4 (lines 64–76) — rationale for what the redesign is fixing.
3. Current implementation, before you change anything:
   - `app/views/emulator/_save_slots_sidebar.html.erb` — server-rendered, 193 lines, this is the main file you're rewriting.
   - `app/views/emulator/_run_sidebar.html.erb` + `_run_sidebar_card.html.erb` — broadcast-rendered roster card; Screen 4 of the mockup.
   - `app/javascript/controllers/save_slots_controller.js` — overwrite-pending mode + per-slot actions.
   - `app/javascript/controllers/roster_you_marker_controller.js` — already injects the YOU badge into the roster card after broadcast replacement; the mockup's `.you-badge` lives here.
4. Step 20 surfaces you'll touch / coexist with:
   - `app/views/shared/_confirm_modal.html.erb` + `app/javascript/controllers/confirm_modal_controller.js` — **stays as-is**. You will _stop using it_ for the per-slot DELETE and CLEAR ALL SLOTS (replaced by inline confirm per mockup), but other consumers (END RUN, group DEL, schedule cancel) keep using it untouched.
   - `app/assets/stylesheets/pixeldex.css` lines 1043–1064 — Step 20 added `@media (max-width: 900px)` and `@media (max-width: 520px)` blocks for `gb-grid-N`. Layout regression test pattern lives in `test/integration/responsive_grids_test.rb`.

---

### Scope

Redesign the save-slot column on `/emulator` (left sidebar) AND the run-roster card on the right sidebar to match the mockup. Five locked screens:

- **Screen 1 — Default state.** Every slot has a visible STATE PILL (`EMPTY` / `SAVED` / `ACTIVE`). Active slot gets a 4px green-glow border. Empty slot copy is the call-to-action `— drop a save here from the emulator —` (not the word `Empty`). `CLEAR ALL SLOTS` lives at the bottom with a dashed-border treatment.
- **Screen 2 — Overwrite-pending mode.** Sticky banner at the top of the column: `⚠ SAVE FULL — PICK A SLOT TO OVERWRITE` + a `CANCEL` button. Filled slots get the amber `TARGET` pill + amber border + the whole slot becomes a click target. Per-slot action buttons hide while in TARGET mode.
- **Screen 3 — Inline DELETE confirmation.** Click DELETE → the slot's actions row swaps in-place into a `.confirm-inline` block with the question, a stakes line ("Xh of progress. There's no undo — the save file is gone after this."), `CANCEL`, and `DELETE FOREVER`. The slot's state pill flips to red `CONFIRM`. Same pattern for `CLEAR ALL SLOTS`.
- **Screen 4 — Roster card restructured.** Name + state pill on top → 3-tile stat strip (`BADGES` / `DEX` / `PLAY`) → everything else collapsed inside `<details><summary>STATS</summary>` (TRAINER, MAP, MONEY, TID/SID, DEX SEEN, seed). HOF as inline pill next to the name. TID conflict as a high-contrast warning band ("⚠ TID CONFLICT WITH X · re-roll the seed"), not a tiny pill. Seed is click-to-copy with a hover hint. Money symbol removed.
- **Screen 5 — Mobile.** At <520px the emulator-grid is already single-column (Step 20). The save-slot column itself just needs to render legibly inside that. Same patterns, narrower.

---

### Resolved ambiguity #1 (Arch decision)

The Project Owner's prompt said _"Inline DELETE confirmation — use the shared confirm-modal partial from Step 20."_ The mockup shows literal **inline** confirmation (the slot row swaps in place; no modal overlay). The mockup is locked design.

**Decision:** match the mockup. Replace the existing Step 20 `confirm_modal` wiring on the per-slot DELETE button AND on CLEAR ALL SLOTS with inline confirmation. Remove their two `confirm_modal(...)` partial calls + the trigger buttons' `data-action="click->confirm-modal#open"` wiring. The Step 20 partial itself stays. Update `save_slots_controller.js#_actionButtons()` selector to target the new inline-confirm trigger instead of the old `[data-confirm-modal-id-param^='delete-slot-']`.

If you disagree on review, escalate before building.

---

### Resolved ambiguity #2 (Arch decision)

The Project Owner's prompt mentioned `OFF-FEED` and `alive/dead` status pills "inline with the species." The mockup roster cards do not show party Pokémon — they show per-trainer stats. **OFF-FEED is a per-Pokémon pill on the PC BOX tab (Step 18), not on save-slot or roster cards.**

**Decision:** mockup is authoritative — no party-Pokémon list and no OFF-FEED on the save-slot view this step. The roster-card state pill is the trainer's session status (`READY` / `PENDING` / `GENERATING` / `FAILED`), styled per `state-pill.saved` in the mockup. Don't reinvent that.

---

### Build order

Land in this order. Each item should leave the test suite green before you move on.

#### B-1 — CSS tokens + scoped styles (no behavior yet)

**File:** `app/assets/stylesheets/pixeldex.css`

- Add three new design tokens to `:root` at the top of the file. Comment-tag them as Step 21 R3 additions and explain the role:
  - `--d0: #0a1a0a;` — darker background, used for slot inner bezels, action-button bg, seed monospace bg. Mockup line 12.
  - `--green-glow: #5fd45f;` — ACTIVE state pill bg + active-slot 4px border. Mockup line 21.
  - `--crimson: #c75a5a;` — CONFIRM state pill + DELETE FOREVER button + inline-confirm border. Mockup line 19.
- Add a new `/* ── R3 Save Slots ── */` section near the bottom of the file (above the existing `RESPONSIVE` block) with the styles you'll need: `.slot`, `.slot.active`, `.slot.overwrite-target`, `.slot-head`, `.slot-num`, `.state-pill` + `.state-pill.empty/saved/active/target/confirm`, `.slot-meta` + `.slot-meta .row .lbl/.val`, `.slot-actions`, `.slot-actions button` + `.primary/.danger/.confirm`, `.confirm-inline` + nested children, `.pending-banner` + button, `.footer-actions` + button, `.roster-card` + `.you/.head/.name/.you-badge/.stats/.stat`, `.roster-card details/summary/.extra/.seed`, `.conflict-warning`, `.hof-pill`. **Copy the mockup CSS verbatim** from `<style>` lines 85–322, then adjust to use Soul Link's existing tokens where they match (the mockup's `--d1`/`--d2`/`--l1`/`--l2`/`--white`/`--amber` are already identical to ours; only `--d0`, `--green-glow`, `--crimson` are new).
- Do **not** introduce any other new tokens. The audit explicitly forbade it.

Expected file delta: ~140 lines added to `pixeldex.css`. No removals, no edits to existing rules.

#### B-2 — Save-slot sidebar markup (`_save_slots_sidebar.html.erb`)

Replace the body of this partial with the mockup-aligned structure. Per-slot:

- Wrapper: `<div class="slot[ active][ empty]" data-save-slots-target="slot" data-slot-number="N" data-filled="true|false">`. Drop the heavy inline `style="..."` blocks; use the new CSS classes.
- `.slot-head` containing `.slot-num` (`SLOT N`) + `.state-pill.empty/saved/active`. State pill must be **always present** (not gated on `is_active`).
- For empty slots: `.slot-meta` body is the call-to-action copy `— drop a save here from the emulator —` (use an em-dash, not two hyphens).
- For filled slots: `.slot-meta` with the trainer name as `<strong>` (16px), then label/value rows. Render only the rows where the parsed field is present (existing gating rules — keep them). **Drop the peso-sign `&#8369;` from the money row** — the mockup's slot-meta money is `<span class="lbl">MONEY</span> <span class="val">4,231</span>`. Drop the `time_ago_in_words` "saved … ago" footer (the mockup omits it; recover it later via Project Owner ask if anyone misses it — log as a Known Gap if it survives Richard).
- `.slot-actions` (only when filled): `DOWNLOAD` (still an `<a>` to `download_emulator_save_slot_path`), `MAKE ACTIVE` button (only when not active), `DELETE` button. Buttons use the mockup `.slot-actions button` styling (no inline `style="..."`).
- For DELETE, do **not** wire to `confirm-modal#open`. Instead, wire it to a new Stimulus action `save-slots#confirmDelete` that hides the slot's `.slot-actions` and reveals a sibling `.confirm-inline` block (rendered server-side as `hidden` per slot). The CONFIRM state pill replaces the SAVED pill while in confirm mode (toggle via class swap or re-render).
- Each filled slot also renders, server-side and `hidden` by default, the `.confirm-inline` block: `<div class="q">DELETE THIS SLOT?</div>`, `<div class="body">[Xh of progress | "30 minutes of progress" | "less than a minute of progress" depending on `parsed_play_seconds`]. There's no undo — the save file is gone after this.</div>`, two buttons: `CANCEL` (fires `save-slots#cancelDelete`) and `DELETE FOREVER` (fires the existing `save-slots#deleteSlot`, with `data-slot-number="N"`).
  - Helper for the body copy: add a small private helper `format_progress_phrase(seconds)` to `app/helpers/emulator_helper.rb`. Returns `"#{n} hours of progress"` for `seconds >= 3600`, `"30 minutes of progress"` style for `seconds >= 60`, `"less than a minute of progress"` for tiny/nil. Test it.
- For overwrite-pending mode: drop the per-slot absolutely-positioned `<button data-save-slots-target="overwriteOverlay">` overlay markup. Replace with: the slot itself becomes the click target (via `.slot.overwrite-target` class toggled by the Stimulus controller). The whole `<div>` slot wrapper picks up `data-action="click->save-slots#overwriteSlot"` only while in TARGET mode (controller-applied attribute, see B-3). The TARGET state pill (`.state-pill.target`) replaces the SAVED/ACTIVE pill while in TARGET mode (controller-applied class swap on the existing `[data-save-slots-target='slotPill']`).
- Banner: replace the existing `<div data-save-slots-target="banner" hidden class="gb-card" style="...">` with the mockup's `.pending-banner` structure including the `⚠` icon span, the copy `SAVE FULL — PICK A SLOT TO OVERWRITE`, and a `CANCEL` button (`data-action="click->save-slots#cancelOverwrite"`).
- CLEAR ALL SLOTS at the bottom: `.footer-actions` wrapper containing a single button styled per the mockup. Wire it to inline confirm too: `data-action="click->save-slots#confirmClearAll"` reveals a sibling `.confirm-inline` block (rendered server-side as `hidden`) with a CANCEL + a confirm button that fires the existing `clear-save#clear` action.
- Remove the two existing `confirm_modal(...)` partial calls (per-slot DELETE and CLEAR ALL SLOTS).

Constraints to preserve:
- The page-level `data-controller="save-slots"` wrapper, `data-save-slots-slots-url-value`, `data-save-slots-csrf-value`, `data-save-slots-active-value` — all unchanged.
- The DOWNLOAD link's URL, the MAKE ACTIVE PATCH path, the DELETE DELETE path — all unchanged. You're rewriting only the markup + styling + the gate that fires before DELETE/CLEAR-ALL is called.
- Keep server-side conditional rendering for parsed_* fields (don't force a row when the field is `nil`).
- HOF pill stays on the slot card (mockup line 116–120 shows it on the run-roster card; keep it on the slot card too where it currently lives — the mockup doesn't depict the HOF state on a slot card but the audit doesn't say to remove it. If in doubt, keep functionality, restyle only.)

#### B-3 — `save_slots_controller.js` updates

Update the existing controller. Don't replace — extend.

- Add new targets: `slotPill` (one per slot, the `.state-pill` element), `actionRow` (one per slot, the `.slot-actions` div), `confirmRow` (one per slot, the `.confirm-inline` div), `clearAllAction` (the `.footer-actions` button row), `clearAllConfirm` (the inline-confirm block under it). Targets only — no values.
- Replace `_enterOverwriteMode` body: instead of revealing per-slot `overwriteOverlay` buttons, walk each filled `.slot`, add `.overwrite-target` class, swap the slot pill's class from `saved`/`active` to `target` (and update its text content to `TARGET`), set `data-action="click->save-slots#overwriteSlot"` on the slot wrapper, and hide the action rows (`actionRow.hidden = true`). Keep the disabling of the action buttons (Tab/Enter safety) as-is.
- Replace `_exitOverwriteMode`: undo the above — strip `.overwrite-target`, restore the pill's original class + text (cache them on `connect()`), remove the wrapper-level `data-action`, unhide action rows. Also called by the new `cancelOverwrite()` action wired to the banner's CANCEL button.
- New action `confirmDelete(event)`: reads `slotNumber` from the trigger's dataset, finds the matching slot (`this.slotTargets.find(s => s.dataset.slotNumber === n)`), hides its `.slot-actions`, reveals its `.confirm-inline`, swaps its state pill to CONFIRM. Focus the cancel button inside the confirm-inline (safe-default).
- New action `cancelDelete(event)`: reverses the above. Restores SAVED/ACTIVE pill (whichever it was — read from the original cached value).
- New action `confirmClearAll`: hides the clear-all action button row, reveals the clear-all-confirm row.
- New action `cancelClearAll`: reverses.
- Existing `deleteSlot(event)` action: unchanged signature, still PATCHes — the only change is the trigger now lives inside `.confirm-inline` rather than being routed via the modal.
- `_actionButtons()` selector: change the `[data-confirm-modal-id-param^='delete-slot-']` clause to match the new inline-confirm trigger (`[data-action*='save-slots#confirmDelete']`). Keep the `save-slots#makeActive` clause.
- Remove the `CONFIRM_OVERWRITE` `window.confirm(...)` call from `overwriteSlot` — Step 20 already removed `window.confirm` from DELETE; the overwrite flow is the last `window.confirm` in the file. The banner's presence is the announcement; clicking a slot is the explicit consent. Confirm with Arch if you disagree.

#### B-4 — Roster card (`_run_sidebar_card.html.erb`)

Rewrite the card body to match Screen 4 of the mockup. Constraints:

- The partial must continue to render with **only** the `s` local — no controller context. (Same constraint Step 9 locked in.)
- Wrapper: `<div class="roster-card" data-discord-user-id="<%= s.discord_user_id %>">`. The `.you` class + `.you-badge` are still injected by `roster_you_marker_controller.js` after broadcast — extend that controller: when adding the YOU badge, also add `.you` to the wrapper, and inject the `.you-badge` span inside the `.name` element (not appended to the first `<div>`). Update the controller's selector so it knows where to put the badge (e.g. add a marker class like `.roster-card-name` on the name span and target it).
- `.head` row: `.name` (`<span class="name">PLAYER<span class="hof-pill" if hof>🏆 HOF</span></span>`) + `.state-pill.saved` showing the session status (uppercased — `READY` / `PENDING` / `GENERATING` / `FAILED`; use a `.state-pill.confirm` style for failed, `.state-pill.target` style for pending/generating, `.state-pill.saved` style for ready).
- `.stats` 3-tile grid: `BADGES` / `DEX` / `PLAY`. Show `—` for nil values. Always render all three tiles even when partial — the grid stays rectangular. Match `format_play_time` for PLAY (already exists).
- TID conflict warning band — placed _outside_ the `<details>` block, above it, only when conflict applies. Copy: `⚠ TID CONFLICT WITH <other player names joined by ', '> · re-roll the seed`. Compute the conflict-partner labels inline from `s.soul_link_run.tid_conflict_groups` (the existing computation) — find the group containing `s.id`, filter out `s.id`, map to `SoulLink::GameState.player_name(other_session.discord_user_id)`. If `tid_conflict_groups` doesn't surface partner session ids in a usable shape, log a Known Gap and fall back to the existing single-line text "⚠ TID CONFLICT" (don't block the step).
- `<details><summary>STATS</summary>` block: TRAINER (in-game name), MAP, MONEY (`number_with_delimiter` only, no symbol — drop `&#8369;`), TID/SID, DEX SEEN — each as `<div class="row"><span class="lbl">LABEL</span><span>value</span></div>`. Skip rows whose underlying field is nil.
- Seed: `.seed` element with click-to-copy. Implementation: a tiny new Stimulus controller `roster_seed_controller.js` (~25 lines). On click, write the seed to clipboard via `navigator.clipboard.writeText`, briefly swap the text/style to `Copied!` then revert after 1s. Wire as `data-controller="roster-seed" data-action="click->roster-seed#copy"` on the `.seed` div. (Keep the `cursor: copy` + the CSS-only `:hover::after` "click to copy" hint from the mockup; the controller is the actual copy.)
- Drop the `In-game:` prefix on the trainer name and the standalone "Active … ago" + "Save: …" rows. The mockup hides those — move "save bytes / saved-ago" out of the redesigned card. (If lost data is a problem, log a Known Gap.)
- The existing turbo_frame_tag wrapper in `_run_sidebar.html.erb` stays. The broadcast contract on the model is unchanged.

#### B-5 — Tests

Layer new tests on top of existing ones; do not regress any existing assertion. New tests live in either `test/integration/`, `test/helpers/emulator_helper_test.rb`, or `test/models/soul_link_emulator_save_slot_test.rb` — pick whichever shape minimises factory churn. Use FactoryBot per project convention.

Required coverage:

1. **State pills always render.** Update the existing `emulator_controller_test.rb#show renders ACTIVE badge on the slot matching active_save_slot` to also assert `>SAVED<` on the non-active filled slots and `>EMPTY<` on the unfilled ones in the same render. Existing assertion `assert_match(/>ACTIVE</, response.body)` must continue to pass.
2. **Empty-slot CTA copy.** New test: filled-slot rows render the trainer name; empty-slot rows render the call-to-action copy `drop a save here` (regex on `response.body`).
3. **Inline DELETE confirm markup.** New test: page renders the per-slot `.confirm-inline` block as hidden (`hidden` attribute or `display: none` style — Bob's call). Assert the per-slot `data-action="click->save-slots#confirmDelete"` is on the trigger button. Assert `DELETE FOREVER` text appears in the response (proves the confirm row is rendered server-side, just hidden).
4. **CLEAR ALL SLOTS inline confirm.** New test mirroring (3) for the footer action.
5. **No `confirm_modal(...)` for save-slot DELETE or CLEAR ALL SLOTS.** New test: response body should NOT contain `id="delete-slot-1-confirm"` (or any of `1..5`) and should NOT contain `id="clear-all-slots-confirm"`. Defensive — locks the architecture decision.
6. **No peso sign.** Existing test or new: response body for both the slot column and the roster sidebar contains `&#8369;` zero times.
7. **Roster card structure.** Extend `soul_link_emulator_save_slot_test.rb#run_sidebar_card partial renders standalone with only \`s\` local`: assert the rendered partial contains `class="roster-card"`, contains the 3-tile stat grid (`class="stats"` and three `class="stat"` children), contains `<details>` and `STATS` summary text. Existing assertions on seed presence + `data-discord-user-id` must continue to pass.
8. **HOF inline pill.** New test: when `parsed_hof_count >= 1`, rendered partial contains `class="hof-pill"` adjacent to the player name (assert the pill markup is inside the `.name` span).
9. **TID conflict warning band.** New test: when the run's `tid_conflict_groups` reports the session, the partial contains `class="conflict-warning"` and the substring `re-roll the seed`. When there's no conflict, the warning is absent.
10. **`format_progress_phrase`.** New helper test: `nil` → `"less than a minute of progress"`, `30` → `"less than a minute of progress"`, `1800` → `"30 minutes of progress"` (or whatever rounding rule you pick — pick one and lock it), `3600` → `"1 hour of progress"`, `4 * 3600 + 23 * 60` → `"4 hours of progress"`. Stake a single rule and document it inline.
11. **Mobile breakpoint regression.** New test in `test/integration/responsive_grids_test.rb` (extend the existing class): assert the new R3 styles are scoped (no `@media (max-width: ...)` rule overrides `.slot` or `.roster-card` in a way that breaks at <520px). Pattern: read the CSS file, regex-match the breakpoint blocks, assert nothing inside them collapses `.slot`'s grid in a way that hides content. (This is a shape test, not a real headless-browser test — match the Step 20 pattern.) Also: assert the new tokens (`--d0`, `--green-glow`, `--crimson`) are declared exactly once each in `:root`.
12. **Emulator-grid stays single-column at <900px.** New CSS-shape assertion: regex-match `.emulator-grid { grid-template-columns: 1fr; }` outside any media block AND `@media (min-width: 900px) { .emulator-grid { grid-template-columns: 280px minmax(0, 1fr) 280px; } }` inside the existing breakpoint. Ensures the redesign didn't accidentally break the existing collapse.

Existing `roster_you_marker_controller`-touching tests don't exist as system tests, so no regression there. **Do not** add a JS unit test framework — this project doesn't use one. The behavior is exercised by integration tests asserting on rendered markup.

---

### Out of scope (do NOT touch)

- R2 (PC Box redesign) — Step 22.
- R4 (Map redesign) — Step 23.
- R1 (Dashboard restructure) — Step 24.
- Any backend / parser pipeline change. The data model doesn't move.
- Discord notifier — Step 19 already covers save-slot ingest events.
- The Step 20 confirm-modal partial / helper / controller — leaves them alone except for removing the two save-slot wire sites. Other consumers (END RUN, group DEL, schedule cancel, mark-dead reuse) are NOT in scope.
- The 6 "not ready" panels in `emulator/show.html.erb:15-58` — the audit flagged them but R3 mockup doesn't redesign them.
- The `roster_you_marker_controller.js` extension is allowed (selector update for the new card structure, badge injection point) but don't refactor its broader contract.
- Don't touch `_pc_box_content.html.erb` — that's the OFF-FEED surface; R3 is sidebar-only.

---

### Things to flag (Known Gap candidates)

If any of these come up during build, log them and ship anyway:

- "Active … ago" + "Save: bytes" rows are removed from the roster card; the redesign doesn't show them. If anyone misses the time-since-last-save signal, that's a follow-up step.
- TID conflict text: if `tid_conflict_groups` doesn't expose partner session ids in a usable shape, fall back to the bare "⚠ TID CONFLICT · re-roll the seed" without partner names — log as Known Gap.
- The mockup HTML uses `--d0: #0a1a0a` for slot-card backgrounds; this is darker than Soul Link's existing `--d1`. If the contrast against the page background ends up too bright/dark in real renders, escalate before fudging the token value.
- `data-confirm-modal-id-param^='delete-slot-'` references in any unrelated controller/test — grep before deleting the modal wiring.
- If the `<details>` collapse animation looks bad with the GB pixel font, fall back to no animation (browser default). Don't pull in a JS lib for it.

---

### Done criteria

Bob, you are done when ALL of these are true:

1. The redesigned save-slot column visually matches Screen 1, Screen 2, Screen 3 of the mockup — pills, banner, inline confirm, dashed-border CLEAR ALL, empty-slot CTA copy.
2. The redesigned roster card visually matches Screen 4 — name + status pill, 3-tile stat strip, HOF inline pill, TID conflict warning band, `<details>STATS</details>` collapse, click-to-copy seed, no peso sign.
3. Mobile single-column reflow holds at <520px (CSS-shape test passes).
4. Per-slot DELETE and CLEAR ALL SLOTS use inline confirmation, not the Step 20 `_confirm_modal` partial. Other Step 20 consumers untouched.
5. Overwrite-pending mode uses the sticky banner + whole-slot click target, not the absolutely-positioned overlay button.
6. All 11 new test buckets from B-5 are green. All existing tests still pass. Rubocop clean. Brakeman clean (no new warnings).
7. `_run_sidebar_card.html.erb` still renders standalone with only the `s` local — broadcast contract preserved (existing test `run_sidebar_card partial renders standalone with only \`s\` local` still passes).
8. No new gems. No JS framework additions. No new design tokens beyond `--d0`, `--green-glow`, `--crimson`.

When done: write `REVIEW-REQUEST.md`. Hand off to Richard. Stop until Richard returns `Ready for Builder: YES`.

---

## Builder Plan — Bob

> Drafted 2026-05-04 after reading the brief, mockup HTML end-to-end, audit § 4 R3 + Workflow 4, and the four current implementation files. Awaiting Ava's confirmation before B-1.

### What I'm building (in execution order)

**B-1 — Tokens + scoped CSS** (`app/assets/stylesheets/pixeldex.css`, ~140 lines added)
- Add `--d0: #0a1a0a;`, `--green-glow: #5fd45f;`, `--crimson: #c75a5a;` to the existing `:root` block (~line 5–14), each with a `/* Step 21 R3 — <role> */` inline comment.
- Insert a new `/* ── R3 Save Slots ── */` block immediately above the `RESPONSIVE` divider (line 1039). All selectors copied verbatim from mockup `<style>` lines 85–322 with one normalisation: rename the mockup's `.slot.overwriteTarget` to `.slot.overwrite-target` everywhere it appears, so the JS class-toggle reads as kebab-case (project convention — every existing modifier in pixeldex.css is kebab-cased). The mockup's `--d1`/`--d2`/`--l1`/`--l2`/`--white`/`--amber` line up 1:1 with ours; only the three new tokens need declaring.
- Do not touch `.gb-card`, `.gb-grid-N`, the existing 900px / 520px / 1200px media blocks, or any other existing rule. Pure addition.

**B-2 — `_save_slots_sidebar.html.erb`** (full body rewrite, same outer wrapper)
- Keep the outer `<div data-controller="save-slots" ...>` wrapper and its three `*-value`s exactly as-is.
- Replace the `SAVE SLOTS` heading row with a plain `<h2>SAVE SLOTS</h2>` styled by the new CSS (no inline `style=""`).
- Replace the existing banner div with the mockup's `.pending-banner` markup (icon span + copy + CANCEL button wired to `save-slots#cancelOverwrite`). Banner stays `data-save-slots-target="banner"` so the existing show/hide logic in B-3 still finds it.
- Per slot loop (`MIN_SLOT..MAX_SLOT`):
  - Wrapper: `<div class="slot[ active][ empty]" data-save-slots-target="slot" data-slot-number="N" data-filled="true|false">`. Drop all inline `style=""`.
  - `.slot-head` with `.slot-num` (`SLOT N`) + `.state-pill.<empty|saved|active>` carrying `data-save-slots-target="slotPill"`. Pill always present.
  - For empty: `.slot-meta` body = literal `— drop a save here from the emulator —` (real em-dash, U+2014).
  - For filled: `.slot-meta` containing `<strong>` trainer name (only when `parsed_trainer_name.present?`; if missing, fall through and show only the available rows — preserves existing nil-gating). Then label/value rows for PLAY+BADGES (one row, mockup line 392 stacks both), MAP, DEX (`X caught · Y seen`), TID/SID (only when `parsed_trainer_id.to_i.positive?`). Drop the peso glyph row entirely from the slot card — slot card has no MONEY row in the mockup. Drop the `time_ago_in_words` "saved … ago" footer (Known Gap candidate — log).
  - HOF pill: keep on filled slot per the brief's "if in doubt, keep functionality, restyle only." Render as `<span class="hof-pill">🏆 HOF</span>` after the body rows.
  - `.slot-actions` (only when filled, hidden via `data-save-slots-target="actionRow"`): DOWNLOAD `<a>` (existing href), MAKE ACTIVE `<button>` (only when not active, existing `save-slots#makeActive` wiring), DELETE `<button>` wired to `save-slots#confirmDelete` carrying `data-slot-number="N"`. No more `confirm-modal#open` action, no more `confirm_modal(...)` partial call.
  - `.confirm-inline` block (only when filled, rendered with `hidden` attribute, `data-save-slots-target="confirmRow"`, `data-slot-number="N"`): `.q` "DELETE THIS SLOT?", `.body` with stake copy from `format_progress_phrase(parsed_play_seconds)`, `.actions` with CANCEL (`save-slots#cancelDelete`) + DELETE FOREVER (`save-slots#deleteSlot`, both carry `data-slot-number="N"`).
- Footer: `.footer-actions` div containing the CLEAR ALL SLOTS button wired to `save-slots#confirmClearAll`, plus a sibling `.confirm-inline` rendered `hidden` with CANCEL (`save-slots#cancelClearAll`) + a confirm button firing the existing `clear-save#clear` action. Wrap both in the existing `data-controller="clear-save"` element so the inline confirm's button sees the controller's URL/CSRF values.
- Gate filled-only sections with `next if slot.nil?` style guards. Keep server-side conditional rendering on every parsed_* field — never force a row when nil.

**B-3 — `save_slots_controller.js`** (additive, no replacement of existing actions)
- Static targets: extend to `["banner", "slot", "slotPill", "actionRow", "confirmRow", "clearAllAction", "clearAllConfirm"]`. Drop `overwriteOverlay` (the per-slot overlay button is gone — the slot itself becomes the click target).
- New `connect()` work: cache the original pill class + text per slot in a WeakMap or a per-slot dataset attribute so `_exitOverwriteMode` and `cancelDelete` can restore them. Pick dataset (`data-original-pill-class`, `data-original-pill-text`) — survives broadcast replacements better than a JS-side WeakMap if the partial ever re-renders.
- `_enterOverwriteMode`: walk every filled `slot` target. Cache pill state in dataset, swap pill class to `target` and textContent to `TARGET`, add `.overwrite-target` class to the slot wrapper, set `data-action="click->save-slots#overwriteSlot"` on the wrapper, hide its `actionRow`. Disable `_actionButtons()` for keyboard safety.
- `_exitOverwriteMode`: reverses the above. Triggered both on success and by the new `cancelOverwrite()` action wired to the banner's CANCEL button.
- `confirmDelete(event)` / `cancelDelete(event)`: locate the matching slot via `data-slot-number`, toggle its `actionRow.hidden` and `confirmRow.hidden`, swap the slot pill to `confirm` (and back). Focus the cancel button after revealing (safe-default keyboard behavior the mockup annotation calls out).
- `confirmClearAll()` / `cancelClearAll()`: hide/show the two footer rows. No pill swap (the footer button has no pill).
- `overwriteSlot`: drop the `window.confirm(CONFIRM_OVERWRITE)` line and the `CONFIRM_OVERWRITE` constant. Banner + amber slot border is the announcement; the click on a TARGET slot is the explicit consent. Keep the rest of the byte-grab + PATCH + reload flow untouched.
- `_actionButtons()`: replace the `[data-confirm-modal-id-param^='delete-slot-']` clause with `[data-action*='save-slots#confirmDelete']`. Keep the makeActive clause.
- Preserve all existing public action signatures (`makeActive`, `deleteSlot`, `overwriteSlot`) so the markup wiring just changes which trigger fires them.

**B-4 — `_run_sidebar_card.html.erb`** (full body rewrite, same `s` local)
- Wrapper: `<div class="roster-card" data-discord-user-id="<%= s.discord_user_id %>">`. Drop `gb-card` so the new `.roster-card` rules apply cleanly.
- `.head` row: `<span class="name roster-card-name">PLAYER<span class="hof-pill">🏆 HOF</span></span>` (HOF only when `active_slot&.parsed_hof_count.to_i >= 1`) + `.state-pill` carrying the session status. Status → pill class mapping per the brief: `ready` → `saved`, `pending`/`generating` → `target`, `failed` → `confirm`, fallback → `saved`. Pill text is `s.status.upcase`.
- `.stats` 3-tile grid: BADGES / DEX / PLAY. BADGES = `active_slot&.parsed_badges` (em-dash for nil), DEX = `active_slot&.parsed_pokedex_caught` (em-dash for nil), PLAY = `format_play_time(active_slot&.parsed_play_seconds)` which already returns `—` for nil. Always render the 3 tiles — empty tiles show `—` so the grid stays rectangular.
- TID conflict warning band (outside the `<details>`, between `.stats` and `<details>`, only when applicable): compute partner labels from `s.soul_link_run.tid_conflict_groups` — find the group containing `s.id`, drop `s.id`, map remaining ids → `SoulLinkEmulatorSession.find_by(id: id)&.discord_user_id` → `SoulLink::GameState.player_name(...)`. The model returns session ids inside the conflict groups (confirmed in `app/models/soul_link_run.rb:98–113`), so this works without a fallback — but if the partner-session lookup yields no usable label list (e.g. all partner names are nil), I'll fall back to the bare `⚠ TID CONFLICT · re-roll the seed` and log a Known Gap. Inline N+1 risk noted: `find_by` per partner is at most 3 queries per render, only fires on the conflict path, and the partial is broadcast-rendered with no preload context. Acceptable per the existing partial contract; if Richard objects, escalate.
- `<details><summary>STATS</summary><div class="extra">…</div></details>`: TRAINER (`parsed_trainer_name`, no "In-game:" prefix), MAP (`format_map_name(parsed_map_id)`), MONEY (`number_with_delimiter(parsed_money)` only — no peso glyph), TID/SID, DEX SEEN. Each row is `<div class="row"><span class="lbl">LABEL</span><span>value</span></div>`. Skip rows whose underlying field is nil. Drop the existing "Active … ago" + "Save: bytes" rows entirely (Known Gap candidate — log).
- Seed: `<div class="seed" data-controller="roster-seed" data-action="click->roster-seed#copy">Seed: <%= s.seed %></div>` — placed inside the `<div class="extra">` block, after the row list, matching the mockup's structure. The `cursor: copy` + hover hint come from the new CSS; the controller does the actual copy.

**B-4b — `roster_you_marker_controller.js`** (selector + injection update)
- Update `apply()` so:
  - When a card matches: add `you` class (not `gb-card--current-user`) to the wrapper to match `.roster-card.you` in the new CSS, and inject the `.you-badge` span inside the `.roster-card-name` element (not appended to `card.querySelector("div")`). Keep the data attribute `data-roster-you-marker-badge="true"` and the dedupe guard.
  - When a card doesn't match: strip `you` class and remove any prior badge.
- Drop the inline `style.cssText` on the badge — the new `.you-badge` CSS owns the styling.
- The Stimulus controller name and registration stay; only the selector + class names change. Don't refactor the broader contract (per brief).

**B-4c — `roster_seed_controller.js`** (new file, ~25 lines)
- Stimulus controller. On click: read the seed text (strip the "Seed: " prefix or just copy the full element textContent), `await navigator.clipboard.writeText(seed)`, briefly swap the element's textContent to `Copied!` and a pulse class for 1 second, then revert. Catch failures (older browsers, secure-context restrictions) and `window.alert("Could not copy seed — copy it manually.")` to match the project's friendly-error pattern.
- Register in `app/javascript/controllers/index.js` alongside the other controllers.

**B-5 — Helper + tests**
- `app/helpers/emulator_helper.rb`: add `format_progress_phrase(seconds)`. Locked rule:
  - `nil` or `seconds.to_i < 60` → `"less than a minute of progress"`
  - `60 <= seconds < 3600` → `"X minutes of progress"` where `X = (seconds / 60).round` (`60` → `1 minute`, `1800` → `30 minutes`, `3540` → `59 minutes`). Note: pluralisation handled by always-`s`-suffix is wrong for `1` minute — special-case 60 ≤ s < 120 → `"1 minute of progress"`.
  - `seconds >= 3600` → `"X hours of progress"` where `X = seconds / 3600` (integer div, drops the partial hour to keep the phrase honest about "at least"). Special-case `3600 <= s < 7200` → `"1 hour of progress"`.
  - Document the rule inline in the helper docstring so the test and the helper agree.
- Tests (per the 12 buckets in B-5):
  - Extend `test/controllers/emulator_controller_test.rb` `show renders ACTIVE badge…` (line 166) to also assert `>SAVED<` and `>EMPTY<` markers in the response body.
  - New tests in `emulator_controller_test.rb` for: empty-slot CTA copy, inline DELETE confirm markup (hidden block + DELETE FOREVER substring + the `save-slots#confirmDelete` data-action regex), CLEAR ALL SLOTS inline confirm, no-`confirm_modal` lock (assert no `id="delete-slot-N-confirm"` and no `id="clear-all-slots-confirm"`), no peso sign anywhere in the response body.
  - Extend `test/models/soul_link_emulator_save_slot_test.rb#run_sidebar_card partial renders standalone…` for: `class="roster-card"`, three `class="stat"` children, `<details>` + `STATS` summary, HOF inline pill inside `.name`, TID conflict band with `re-roll the seed` (build a 2-session conflict via two slots sharing TID/SID), conflict-absent path.
  - New helper test file or extension to `emulator_helper_test.rb`: `format_progress_phrase` matrix.
  - Extend `test/integration/responsive_grids_test.rb`: assert the three new tokens are declared exactly once in `:root`; assert no R3 rule inside the existing 520px/900px media blocks collapses `.slot` or `.roster-card` content; assert `.emulator-grid` declarations match the brief's pattern (need to grep for the existing rule first — if `.emulator-grid` lives elsewhere, log and adapt).

### Open questions / decisions I want Ava to confirm before B-1

1. **Status → pill-class mapping is a colour repurpose.** The brief says `ready` → `state-pill.saved`, `pending`/`generating` → `state-pill.target`, `failed` → `state-pill.confirm`. The CSS classes were named for the slot semantics (saved file / overwrite target / delete confirm) — repurposing them on the roster card is fine semantically (target=amber=in-progress, confirm=red=failure) but it means a future visual tweak to "delete confirm" colour also tweaks "session failed" colour. Acceptable trade-off, or do you want a parallel `.state-pill.ready/.pending/.failed` class set?
2. **`format_progress_phrase` edge cases.** I'm picking integer-hour truncation (`3h 59m` → `"3 hours of progress"`, not `"4 hours"`). The mockup example uses `"04 hours"` for a 4h:23m slot which suggests truncation is fine, but it pads to two digits. I'm dropping the zero-pad — `"4 hours of progress"` reads cleaner in mid-sentence. Confirm or override.
3. **Dropped fields' Known Gaps.** I plan to log two: (a) "saved Xm ago" footer dropped from slot card; (b) "Active … ago" + "Save: <bytes>" dropped from roster card. Both are mockup-omissions, not parser regressions. Confirm both are acceptable as Known Gaps without escalating to the Project Owner.
4. **HOF pill on the slot card.** Brief says keep functionality, restyle only. I'll render it as `<span class="hof-pill">🏆 HOF</span>` after the slot body but before `.slot-actions`. The mockup doesn't depict a slot-card HOF, so I'm picking the placement that reads cleanly with the new CSS. Confirm or override.
5. **`.emulator-grid` media-query test (B-5 #12).** The brief asserts a specific declaration shape but doesn't say which file owns `.emulator-grid`. I'll grep when I get there; if it lives in a partial-scoped `<style>` rather than `pixeldex.css`, I'll adjust the test target accordingly. Flagging early so you're not surprised if the test points at a different file.

### Risk / scope check

- **Test coverage shape.** I'm putting the controller-rendered assertions in `emulator_controller_test.rb` (already has the `>ACTIVE<` precedent at line 174). The partial-rendered assertions go in `soul_link_emulator_save_slot_test.rb` (already has the `run_sidebar_card partial renders standalone` precedent at line 227). No new test files unless `responsive_grids_test.rb` won't bear the token-declaration assertion (it will).
- **No new JS framework, no new gems, no new design tokens beyond the three named.** Confirmed.
- **Broadcast contract.** `_run_sidebar_card.html.erb` keeps its `s`-only locals contract. The `roster-seed` and `you-marker` Stimulus controllers attach client-side to the broadcast-rendered DOM the same way they do today.
- **`window.confirm` removal in `overwriteSlot`.** The brief explicitly authorises this. I'll do it. If Richard pushes back I'll cite the brief.

Awaiting Ava's confirm or redirect.

---

## Architect response — Ava

> 2026-05-04. Plan approved with the answers below. **Build per B-1 → B-5. Don't wait for further confirmation.**

### Answers to your five questions

1. **Pill-class repurposing — approved.** Keep one colour vocabulary (`saved`/`target`/`confirm`) across slots and roster. The visual language is "neutral / in-progress / failed" regardless of the surface it's on; that consolidation outweighs the small risk that a future tweak to one rule cascades to the other. If a future divergence is genuinely needed, that'll be a separate redesign step. Do not introduce parallel `.ready/.pending/.failed` classes.

2. **`format_progress_phrase` rule — approved.** Integer-hour truncation, no zero-pad. `"4 hours of progress"` reads cleaner. The mockup's `04 hours` was decorative leftover from the `04:23` time format on stat tiles, not a copywriting choice. Lock the rule in the helper docstring. Special-cased singular ("1 minute" / "1 hour") is correct.

3. **Dropped fields → Known Gaps — approved both, no escalation needed.** Log:
   - **KG-33**: slot card no longer shows "saved Xm ago" footer or byte count. Mockup-driven, not a parser regression. Surface again if the Project Owner misses it.
   - **KG-34**: roster card no longer shows "Active … ago" or "Save: bytes". Same shape.

4. **HOF pill placement on slot card — approved.** After the body rows, before `.slot-actions`. The placement is consistent with how the mockup positions HOF on the roster card (inside the head, but the slot card has no head HOF slot — bottom of body is the next-best read).

5. **`.emulator-grid` location confirmed.** Lives in `app/assets/stylesheets/pixeldex.css` lines 27–38. The default rule is `grid-template-columns: 1fr;` outside any media block; the 900px breakpoint sets `grid-template-columns: 280px minmax(0, 1fr) 280px;`. Test against that file. No grepping needed.

### Two reminders for the build

- **Singular minute / hour pluralisation:** stake your rule in the helper docstring. Test cases should pin both ends (`60 → 1 minute`, `120 → 2 minutes`, `3600 → 1 hour`, `7200 → 2 hours`). Tedious but locks behaviour.
- **TID conflict partner-name lookup N+1 is fine.** Conflict path only fires when there's a real conflict (rare), max 3 partner lookups per render. No preload contortions for a cold path. If Richard asks, the trade is "broadcast partial has no preload context, conflict is rare, lookups are by primary key" — quote that and move on.

### Build approved. Go.

---
