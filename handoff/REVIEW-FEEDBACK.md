# Review Feedback — Step 22
**Reviewer:** Richard
**Date:** 2026-05-04
**Ready for Builder:** YES — Step 22 is clear.

**Resolution:** Should Fix #1 landed inline (`pixeldex.css:1191` + `pc_box_filter_controller.js:65`). Tests still 712/712 / 0 failures, Rubocop still clean (199 files). Mockup-fidelity gap closed.

---

## Must Fix

*None.*

---

## Should Fix

**1. Mockup Screen 2 contract — non-active chips must dim when a non-ALL filter is active.** `handoff/2026-05-04-ui-audit-mockup-pc-box.html` lines 631-633 show:
```html
<span class="filter-chip" style="opacity: 0.55;">ALL · 19</span>
<span class="filter-chip" style="opacity: 0.55;">ON TEAM · 4</span>
<span class="filter-chip" style="opacity: 0.55;">STORAGE · 12</span>
<span class="filter-chip active">FALLEN · 3</span>
```
The mockup's annotation A under Screen 2 calls this out: *"Other chips dim slightly to suggest 'you can switch back.'"* On default (Screen 1) all chips are full opacity; on a non-ALL filter (Screen 2) the inactive chips drop to opacity 0.55. The annotation is part of the locked design.

The current build doesn't implement this. `pixeldex.css:1184` has only `.filter-chip.active { ... }` (full opacity); `.filter-chip:hover:not(.active)` only changes color on hover. `pc_box_filter_controller.js:_render` toggles `.active` on the right chip but does nothing to dim the others.

**Fix** (5-line change, two files):

`app/javascript/controllers/pc_box_filter_controller.js` — inside `_render()` after the chip loop:
```js
this.element.classList.toggle("filter-active", this.status !== "all")
```

`app/assets/stylesheets/pixeldex.css` — add inside the `/* ── R2 PC Box ── */` section (right after the existing `.filter-chip:hover:not(.active)` rule at line 1188):
```css
.pc-box-r2.filter-active .filter-chip:not(.active) { opacity: 0.55; }
```

This matches the mockup verbatim — opacity 0.55 on inactive chips iff a non-ALL filter is active. ALL-active-or-empty leaves all chips full opacity.

Optional: extend `responsive_grids_test.rb`'s Step 22 block to assert the new selector exists. Not required — same shape as the existing test where Stimulus state mutations aren't covered by markup assertions.

---

## Escalate to Architect

*None.*

---

## Cleared (passed audit)

I read the files Bob listed in REVIEW-REQUEST.md and tested against the brief's 11-item acceptance checklist:

1. **Visual fidelity** — Each of the 4 mockup screens has a 1:1 surface in the new view. Spacing / typography / colors transcribed faithfully, except the chip-dim issue (Should Fix #1 above).
2. **Filter chip wiring** — All four chips carry correct `data-pc-box-filter-status-param` + `data-status` attributes. Cells carry matching `data-status`. URL hash logic in `pc_box_filter_controller.js:24-33` reads + writes correctly.
3. **Badge legend** — All four rows (`1ST` / `TRADE-IN` / `EVENT` / `OFF-FEED`) present in `_pc_box_content.html.erb:71-74`, copy verbatim from the mockup.
4. **Empty-state** — `_pc_box_content.html.erb:154-157` renders the dashed-border bar with the locked copy when `auto_catches.empty?`. Panel-head reads `ALL CAUGHT-UP` per the mockup.
5. **Mobile breakpoint** — `responsive_grids_test.rb` extended with 4 new Step 22 assertions covering the namespace declaration, the 520px reflow to `repeat(3, 1fr)`, the 900px collapse to `1fr`, and the no-`display: none` contract on cells/rows. Pattern matches Step 21.
6. **Read-only mode gating** — `+ NEW CATCH` (line 51-57), LOG (line 129-136), EDIT (line 137-142) all inside `<% unless read_only %>`. SKIP (line 144-148) outside the gate. Test `test "read-only mode hides..."` exercises the contract.
7. **Accessibility** — Filter chips are real `<button type="button">`. Search input has `aria-label="Search nicknames or species"`. Group-marker glyphs are `aria-hidden="true"`. Cells have descriptive `aria-label`. Per-row LOG/EDIT/SKIP are real `<button>` elements with text content.
8. **No backend drift** — `git diff --stat HEAD` shows zero changes under `app/controllers/`, `app/models/`, `db/`, `app/services/`, `app/jobs/`, `config/`. Helper change is non-mutating (pure function). Confirmed.
9. **CSS namespace integrity** — Every new selector in pixeldex.css lines 1045-1296 is prefixed with `.pc-box-r2`. The legacy `.box-grid`, `.box-cell`, etc. rules (used by `_pc_box_panel.html.erb`) are untouched. Grep-confirmed.
10. **Test suite** — 712 runs / 0 failures, Rubocop clean (199 files), Brakeman 0 errors with the same 2 pre-existing weak warnings. Verified.
11. **Scope discipline** — KG-35 (SKIP non-persistence) and KG-36 (mockup-locked filter scope) logged in BUILD-LOG.md. No out-of-scope additions; no mark-dead button; no schema changes.

**Logic correctness spot-checks:**
- `is_first` derivation (line 79): `first_ids_by_location[p.location.to_s] == p.id`. With `auto_catches.reject { |p| p.id.nil? }` at line 24, no nil-id rows survive into the calc. Safe.
- `highlight = is_first && recommended == :log` (line 82): a first-encounter trade-in row does NOT get the green-glow border because the recommendation flips to `:skip`. Matches mockup row 2 (Machop TRADE-IN at Eterna — has the trade badge but no first-row border).
- `log_label = is_event ? "LOG AGAIN" : "LOG CATCH"` (line 83) — matches mockup row 3 (Piplup EVENT renders LOG AGAIN).
- `recommended_review_action` precedence (helper test): event_gift wins over trade_in. ✓
- `prefillCatch` action chain order (`dashboard#openCatchModal` first, then `review-tray#prefillCatch`): correct per the discovered Stimulus-target contract. ✓

**Security spot-checks:**
- All user-supplied strings (`nickname`, `location`, `species`) flow through `<%= %>` ERB auto-escape. ✓
- `data-group-pokemon` uses `pixeldex_group_pokemon_json(...)` which calls `.to_json`; ERB auto-escapes the string into the attribute, browser parses it back. Matches existing pixeldex flow. ✓
- No `raw`, no `html_safe`, no string interpolation into attribute names. ✓
- The `data-search-haystack` is computed server-side from already-trusted `group.nickname` and `my_pokemon.species`; client-side `.toLowerCase().includes()` matching is innocuous. ✓

Once Bob lands the Should Fix, Step 22 is clear.
