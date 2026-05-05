# Review Request — Step 22

**Builder:** Bob
**Branch:** `claude/happy-brattain-e3cdb1` (worktree)
**Ready for Review: YES**
**Scope:** Step 22 — R2 PC Box redesign per § 4 R2 of `handoff/2026-05-04-ui-audit.md` and the locked mockup `handoff/2026-05-04-ui-audit-mockup-pc-box.html` (4 screens). Second Phase 2 redesign (R3 → **R2** → R4 → R1 ship order locked by the audit).

---

## Summary

7 modified or new code files (+ 3 handoff doc updates). Full suite: **697 → 712 runs (+15); 0 failures, 0 errors**. Rubocop clean (199 files, 0 offenses; +2 files for the new Stimulus controllers). Brakeman clean — same 2 pre-existing weak-confidence warnings unchanged from Steps 18/19/20/21. **0 migrations. 0 new gem deps. 0 new design tokens** (mockup uses tokens already in `:root` since Step 21).

Built per Bob's plan inside `ARCHITECT-BRIEF.md` § "Builder Plan — Step 22", with one Arch correction folded in: the catch modal is keyed by Stimulus targets (`data-dashboard-target="catch*"`), not `name=` attributes; `dashboard#openCatchModal` BLANKS the three fields before opening, so the LOG/EDIT action chain runs **`openCatchModal` first, then `prefillCatch`** — the reverse would have the prefill wiped. Also dropped the `level` param (catch modal has no level field). Brief Constraint #5 corrected inline.

---

## Files changed

| File | Lines | What |
|---|---|---|
| `app/views/dashboard/_pc_box_content.html.erb` | full body rewrite (283 lines) | New `.pc-box-r2`-namespaced view: panel head + REVIEW PARSED CATCHES tray (badge legend + per-row LOG/EDIT/SKIP) + filter chip bar + free-text search + unified `[team, storage, fallen]` grid with corner glyphs + 280px type-coverage rail. Mockup-verbatim per Screens 1-4. Read-only mode gates `+ NEW CATCH` and per-row LOG/EDIT (SKIP stays). |
| `app/assets/stylesheets/pixeldex.css` | +265 lines (new R2 section + 11 lines extending two existing media queries) | New `/* ── R2 PC Box ── */` section above the R3 section, **all selectors namespaced under `.pc-box-r2`** so the legacy `.box-grid` / `.box-cell` rules used by `_pc_box_panel.html.erb` (sidebar) are untouched. Mockup CSS verbatim except for the prefix. Extended the existing `@media (max-width: 900px)` block to stack the type-coverage rail under the grid; extended the existing `@media (max-width: 520px)` block with the mobile reflow rules from mockup Screen 4. **No new design tokens.** |
| `app/javascript/controllers/pc_box_filter_controller.js` | new, 76 lines | Chip filter + free-text search + URL hash for the unified grid. State is `this.status` (`all`/`team`/`storage`/`fallen`) + `this.search` (lowercase, trimmed, 150ms-debounced). `connect()` reads `location.hash` so state survives reloads AND Turbo morphs. Toggles `.filter-hidden` / `.search-hidden` on cells, `.active` on the chip, `.dimmed` on the rail when filter ≠ team/all. Updates the count target with `K OF N SHOWN` when filtered (restores ERB-rendered text on ALL + empty search). |
| `app/javascript/controllers/review_tray_controller.js` | new, 38 lines | `prefillCatch` action populates `[data-dashboard-target="catchSpecies"]` and `[data-dashboard-target="catchLocation"]` from the button's `data-review-tray-prefill-*-param`s. Wired second in the action chain (after `dashboard#openCatchModal`). `dismiss` adds `.dismissed` to the closest row + decrements the count pill. Client-side only (KG-35). |
| `app/helpers/pixeldex_helper.rb` | +11 lines | New `recommended_review_action(pokemon)` — pure-function `:log`/`:skip` decision: event_gift / trade_in → `:skip`; else `:log`. Used by the view to apply `class="primary"` on the matching button. |
| `test/integration/pc_box_redesign_test.rb` | new, 167 lines | 7 markup-assertion tests covering: wrapper + dual-controller wiring; review tray with badge legend + per-row buttons + recommended-action highlight; filter chip counts + active-state contract; unified grid cell `data-status` coverage + preserved `pixeldex#selectPokemon` click; type-coverage rail; empty-state copy + `ALL CAUGHT-UP`; read-only mode gates LOG/EDIT but keeps SKIP. Same `GREY = 153665622641737728` + `login_as` pattern as `confirm_modal_flow_test.rb` / `wipe_flow_test.rb`. |
| `test/integration/responsive_grids_test.rb` | +34 lines | Four new Step 22 tests: `.pc-box-r2` declared outside any media block; `@media (max-width: 520px)` reflows `.pc-box-r2 .box-grid` to `repeat(3, 1fr)`; `@media (max-width: 900px)` collapses `.pc-box-r2 .box-layout` to `1fr`; neither breakpoint sets `display: none` on `.pc-box-r2 .box-cell` or `.pc-box-r2 .review-row` (mockup-fidelity contract, mirrors the Step 21 `.slot` / `.roster-card` shape). |
| `test/helpers/pixeldex_helper_test.rb` | new, 29 lines | 4 assertions for `recommended_review_action` covering all four input shapes (event_gift, trade_in, ordinary catch, event_gift+trade_in precedence). |
| `handoff/ARCHITECT-BRIEF.md` | rewrite for Step 22 | Locked decisions, action-chain ordering, constraints, acceptance checklist. The Builder Plan section + Architect endorsement live at the bottom. |
| `handoff/BUILD-LOG.md` | +4 lines | KG-35 (SKIP non-persistence) and KG-36 (chip-filter scope = mockup-locked) under a new "Step 22 (2026-05-04)" subheading. |

---

## Focus areas for Richard

1. **Visual fidelity to the mockup.** Compare each rendered surface side-by-side with the mockup HTML's 4 screens. Spacing / typography / color drift would be a Must Fix. Pay attention to:
   - `.review-row.first` border treatment (3px green-glow + 8/12 padding)
   - `.badge` color grammar — `1ST` green / `TRADE-IN` amber / `EVENT` filled-l1 / `OFF-FEED` outline-l1
   - `.review-row .actions button.primary` → green-glow on the recommended action
   - `.box-cell.team` vs `.box-cell.dead` corner-glyph color (green-glow vs crimson)
   - Type-pill `.covered` / `.gap` (dashed) / `.weak` (filled crimson)

2. **CSS namespace integrity.** Every new selector in pixeldex.css should be prefixed with `.pc-box-r2`. The existing `.box-grid` and `.box-cell` rules (used by `_pc_box_panel.html.erb`) must be **untouched** — please grep-confirm. The new R2 section is at lines 1045-1290 (right above the R3 Save Slots section).

3. **Filter chip + URL hash contract.** The four chips have `data-pc-box-filter-status-param="all|team|storage|fallen"` and `data-status="all|team|storage|fallen"` (both — the param drives the action, the status drives the active-class lookup). `pc-box-filter#applyFilter` writes `location.hash` (or clears it for `all`); `connect()` reads it. URL hash must persist across reloads.

4. **Action chain order on LOG/EDIT.** `data-action="click->dashboard#openCatchModal click->review-tray#prefillCatch"` — open first (which clears the fields), THEN prefill. Reversed order would have `openCatchModal`'s `this.catchSpeciesTarget.value = ""` wipe the prefilled values. Please verify this is the order rendered by the view (it is: see `_pc_box_content.html.erb:128-133`).

5. **Read-only mode gates the right buttons.** `dashboard_read_only?(@run)` hides:
   - `+ NEW CATCH` panel-head button (existing gate)
   - LOG / EDIT inside each review-row's `.actions` (new gate)
   - SKIP stays available — it's client-only, no DB writes.
   
   See `_pc_box_content.html.erb:122-149`.

6. **Accessibility.** All four filter chips are real `<button type="button">`. Search input has `aria-label`. Group-marker glyph spans are `aria-hidden="true"`. Each cell has an `aria-label` describing nickname + status + location. Per-row LOG/EDIT/SKIP are real `<button>` elements.

7. **Backward compat for existing flows.** The unified grid cell preserves all the `data-group-*` attributes the existing pokemon modal needs (`data-group-id`, `data-group-nickname`, `data-group-species`, `data-group-location`, `data-group-status`, `data-group-types`, `data-group-pokemon`). `data-action="click->pixeldex#selectPokemon"` stays on every cell. The pokemon modal opens exactly as before. Verify by clicking a cell in the new view and confirming the modal flow is unchanged.

8. **No backend drift.** `git diff --stat HEAD` shows zero changes under `app/controllers/`, `app/models/`, `db/`, `app/services/`, `app/jobs/`, `config/`. Please confirm via the diff.

9. **Existing tests still green.** Full suite ran 712/712 with 0 failures. `confirm_modal_flow_test.rb`, `wipe_flow_test.rb`, the existing 5 assertions in `responsive_grids_test.rb`, all model and service tests — all green.

---

## Should Fix from review (resolved inline)

**Richard's Should Fix #1 — Mockup Screen 2 dim-on-non-active-chip behavior.** The mockup explicitly shows inactive filter chips at opacity 0.55 when a non-ALL filter is active. The first build had `.active` styling but no rule for the dimmed inactive state. Fixed inline:
- `app/javascript/controllers/pc_box_filter_controller.js:_render` — added 1 line: `this.element.classList.toggle("filter-active", this.status !== "all")` after the chip target loop.
- `app/assets/stylesheets/pixeldex.css:1190` — added 1 CSS rule: `.pc-box-r2.filter-active .filter-chip:not(.active) { opacity: 0.55; }` with a 2-line WHY comment.

Net change: +5 lines across 2 files. Tests still 712/712 / 0 failures. Rubocop still clean (199 files).

---

## Open questions / non-blocking notes

- **`.empty-tray-bar` is a new class name** (mockup left it inline-styled). Named consistently with `.review-tray-head` and friends. Located at `pixeldex.css` ~line 1141.
- **`.dimmed-explainer` inside the rail uses `display: none` by default + `display: block` when parent is `.dimmed`** — this is the Screen 2 "computed against your 6-slot team — switch to ON TEAM to focus" behavior. The CSS contract is in pixeldex.css ~lines 1257-1260.
- **`.pc-box-r2 .box-cell.search-hidden, .pc-box-r2 .box-cell.filter-hidden { display: none; }`** is the only `display: none` rule in the new section, scoped to JS-applied state classes. The `@media` blocks have NO `display: none` overrides on `.pc-box-r2 .box-cell` or `.pc-box-r2 .review-row` — verified by `responsive_grids_test.rb` Step-22 assertion.
- **No KG closures this step.** Phase 2 R2 is net-additive UX; no prior KG was on the line.
- **Sidebar partial `_pc_box_panel.html.erb` is intentionally NOT modified.** Cross-cutting 6 (sidebar/main duplication) is an IA decision, not Phase 2 scope.

---

## Reference

- Mockup: `handoff/2026-05-04-ui-audit-mockup-pc-box.html` (4 screens — locked design)
- Audit narrative: `handoff/2026-05-04-ui-audit.md` § 4 R2
- Step 21 ship for context: commit `3c001ed`
- Worktree based on: `9cd2009` (`origin/main`)
