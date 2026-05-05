# Session Checkpoint
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*
*Session-scoped — archived to `handoff/archive/` at session end.*

---

## Where We Stopped

Step 23 (R4 Map / Route timeline redesign + clickable map locations — Phase 2 R4 of the 2026-05-04 UI/UX audit) shipped on the worktree branch `claude/objective-faraday-c9b66b`, FF-merged to `origin/main` and pushed. Awaiting next brief from Project Owner.

The user's instructions were explicit: after Step 23 ships, **stop**. R1 Dashboard gets its own future session. Locked Phase 2 ship order: R3 ✓ → R2 ✓ → R4 ✓ → **R1** (last, next session).

---

## What Was Built

**Step 23 — R4 Map / Route timeline redesign + clickable-map-locations feature.**

Implements the locked mockup `handoff/2026-05-04-ui-audit-mockup-map.html` across all 4 screens (desktop full timeline · sheet open / new catch · sheet open / existing catches · mobile accordion). Layered on the existing `MapController` + `SoulLinkPokemonGroup`/`SoulLinkPokemon` data; only the view + CSS + Stimulus controller + helper change. Net-additive new feature — clickable map locations with URL-hash persistence + per-state sheet rendering (no-catch → catch form, single-catch → group card + dupes button, multi-catch → reverse-chronological stacked cards + dupes button) — sits on top of the visual redesign.

**Surfaces introduced/changed:**
- **`/map` standalone page** (`app/views/map/show.html.erb`, full body rewrite ~280 lines) — wraps in `<div class="map-r4" data-controller="timeline dashboard pixeldex" …>` carrying every dashboard + pixeldex value attr the modal partials need. Sections: `.map-head` (h2 + sub + 8-badge strip with the existing `toggleGym` action) → `.status-bar` (NEXT GYM · LEVEL CAP · CURRENT SEG + JUMP TO NOW pill, server-gated `.hidden` when no `.next` route) → `.node-legend` (5 always-visible glyphs) → `.layout` grid (`minmax(0, 1fr) 380px` desktop, `1fr` at <720px). Left column = `.timeline-frame` desktop / `.accordion-frame` mobile + `.special-bar` (gift/egg/trade/other). Right column = sticky `<aside class="sheet">` with empty-state default + JS-built form-or-group-list. Pulse-ring + `↓ NOW` pin on the next-uncaught route node. Segment dividers between segments with bare-city labels ("ETERNA", "VEILSTONE") + `"ELITE FOUR"` before the null-gym segment. Existing Elite Four endpoint node preserved at the very end. `<%= render "dashboard/pokemon_modal" %>` + `<%= render "dashboard/mark_dead_modal" %>` rendered at the bottom so EDIT/MARK DEAD dispatches work without partial duplication.
- **`pixeldex.css`** — new `/* ── R4 Map ── */` section above the R2 marker (~545 lines, all selectors namespaced under `.map-r4`). Mockup CSS verbatim with the namespace prefix; mockup-document chrome (`.page`, `.page-banner`, `.legend`, `.section-anchor`, `.annotation`, `.phone`, `.phone-bezel`) stripped per Architect note — those styled the mockup HTML, not the production component. Extended existing `@media (max-width: 520px)` to reflow `.map-r4 .special-grid` from 4 cols to 2. NEW `@media (max-width: 720px)` block hides `.map-r4 .timeline-frame`, shows `.map-r4 .accordion-frame`, drops `.map-r4 .layout` to single column, drops `.map-r4 .sheet`'s `position: sticky`. **Zero new design tokens.**
- **`timeline_controller.js`** — extended (~430 lines, ~120 new). Targets renamed `panel*` → `sheet*`; `backdrop` removed (no overlay anymore). New targets `emptyState`, `groupList`, `jumpBtn`, `accordionSegment`. New actions: `jumpToNow` (smooth-scrolls to `.next` node, no-op when absent), `showCatchFormForCurrent` (dupes-clause: swaps sheet from group-list to form mode for the same loc_key without changing the hash). Internal helpers `_renderSheetCatchForm` / `_renderSheetGroupList` / `_buildGroupCardHtml` build the in-flow sheet content; group cards are JS-built and carry the `pixeldex#selectPokemon` + `dashboard#openMarkDeadModal` data attrs (additive `groups_json_for` payload makes this work without controller surgery). URL hash `#route=<key>` synced via `connect() → applyHashRoute()` + written in `selectLocation` via `history.replaceState` (Should Fix #2 inline) + cleared in `closePanel`. `_renderSheetGroupList` reverse-iterates groups (`[...groups].reverse().map(...)`) so most-recent renders first (Architect-resolved escalate + Should Fix #1 inline). Existing actions (`submitCatch`, `toggleGym`, `filterSpecies`, `selectSpecies`, `closeAllDropdowns`, `handleKeydown`, `scrollToCurrentProgress`) all preserved verbatim. `.selected` class on `.glyph` replaces inline Tailwind `ring-*` classes.
- **`map_helper.rb`** — six new helpers + extended `groups_json_for(groups, current_user_id)`. New: `next_uncaught_route_key` (first uncaught route across segments; skips cities/dungeons/lakes/specials), `current_segment_label` (bare-city + FINAL STRETCH fallback + ELITE FOUR for null-gym), `segment_divider_label` (bare city of upcoming segment + ELITE FOUR before null-gym), `segment_progress` (catchable-types-only denominator: route/dungeon/lake/special), `segment_open_by_default?`, `node_status_class`. `groups_json_for` extended additively per Architect Q1 — added per-pokemon `id`, `is_mine`, `level`, `ability`, `nature`, `sprite_url`, `types`; per-group `id`, `species_for_user`, `types_for_user`. Existing fields preserved.

**Counts:** 712 → 754 tests (+42). 0 failures, 0 errors. Rubocop clean (201 files, 0 offenses). Brakeman clean — same 2 pre-existing weak-confidence warnings unchanged from Steps 18/19/20/21/22. **0 migrations. 0 new gem deps. 0 new design tokens. 0 controller/model/service/config changes.**

**Review:** 0 Must Fix, 2 Should Fix (both fixed inline), 1 Escalate (Architect-resolved + folded into the Should Fix #1 fix). The two Should Fixes:
- **#1 — Multi-group order.** Brief §11 said "show the most-recent group prominently" but `position: asc` showed oldest first. Architect resolution (also resolves the Escalate): reverse-iterate in `_renderSheetGroupList` so most-recent renders first, no primary/secondary CSS lift needed (top-of-stack is the prominence). Single-line fix at `timeline_controller.js:194` (`[...groups].reverse().map(...)`).
- **#2 — Hash back-stack pollution.** `selectLocation` wrote `window.location.hash = …`, adding a back-stack entry per click. Switched to `history.replaceState(null, "", "#route=" + encodeURIComponent(key))` at `timeline_controller.js:106`. Same one-line spirit; no back-stack bloat. The `connect()` hash read still works identically.

---

## What Was Decided This Session

- **No backend changes — none.** No new column, no migration, no new endpoint, no model method, no config change. The redesign is pure view + CSS + helper + Stimulus extension.
- **CSS namespace under `.map-r4`** (Step 22 `.pc-box-r2` precedent) prevents collision with future `.timeline-*` rules elsewhere. Architect-locked.
- **The mockup's right-rail sticky SHEET replaces today's overlay slide-out panel.** No `position: fixed`, no `translateX`, no backdrop overlay, no body-scroll lock. Sheet is in-flow, sticky on desktop, stacks below accordion at <720px.
- **Two-tier mobile breakpoint:** `@media (max-width: 720px)` swaps timeline → accordion + drops layout to single column; `@media (max-width: 520px)` reflows the special-encounters grid 4 → 2 cols (extends Step 20's existing block). Mockup uses 720px for the timeline → accordion swap; that's R4-specific, not a generic gb-grid breakpoint.
- **Pulse-ring identifies the next-uncaught ROUTE only.** Helper `next_uncaught_route_key` walks segments in order and returns the first uncaught location whose `loc_data["type"] == "route"`. Skips cities, towns, dungeons, lakes, specials. Late-game (all routes caught) → no `.next` class anywhere, JUMP TO NOW button has `.hidden` class.
- **Segment divider label = bare city ("ETERNA"/"VEILSTONE")**, derived from `gym_info[next_seg["gym"]]["location"]` with `_city`/`_town` suffix stripped + uppercased. **Final divider before the null-gym segment = `"ELITE FOUR"`** (Architect Q3 override of Bob's mockup-verbatim `"…"` default — mockup ellipsis was a truncation artifact since the mockup only renders 3 segments).
- **`segment_progress` denominator counts catchable types only** (route / dungeon / lake / special). Excludes city / town. Caught counts those with status `caught` OR `dead` (both consume the encounter slot).
- **`groups_json_for(groups, current_user_id)` is extended additively** — added per-pokemon `id`, `is_mine`, `level`, `ability`, `nature`, `sprite_url`, `types` + per-group `id`, `species_for_user`, `types_for_user`. Single source of truth for both the new sheet rendering AND the JS-built EDIT button's `data-group-pokemon` payload. No parallel pixeldex-shaped helper.
- **Read-only mode is gated by `hasSheetFormTarget` exclusively** (Architect Q5/Q6 — no parallel `readOnlyValue` on the controller). View renders the sheet form only when `!dashboard_read_only?`; JS reads the absence as the read-only signal and skips EDIT / MARK DEAD / dupes button rendering.
- **Modal partials at the bottom of `/map`** — `<%= render "dashboard/pokemon_modal" %>` + `<%= render "dashboard/mark_dead_modal" %>` reuse the dashboard partials verbatim. Wrapper carries `data-controller="timeline dashboard pixeldex"` plus all dashboard + pixeldex value attrs. Pre-write check confirmed both controllers' `connect()` are benign on `/map` (dashboard has no `connect`; pixeldex's `#initSortables` is a no-op without team grids and `#applyHashTab` doesn't match `route=…` hash).
- **Multi-group disambiguation: most-recent first.** When 2+ groups exist on a location (dupes-clause re-rolls), reverse-iterate so the latest-position group renders at the top of the sheet. Top-of-stack is the prominence; no primary/secondary CSS decoration. Architect-resolved post-review.
- **URL hash `#route=<key>` written via `history.replaceState`** — no back-stack pollution. Same `connect()` hash-read semantics survive.
- **Dashboard MAP tab (`_map_content.html.erb`) untouched.** That's the cross-cutting-6 IA decision; R1 (next session) reshapes the dashboard chrome including the MAP tab.

---

## Known Gaps / Future Work

*See `handoff/BUILD-LOG.md` Known Gaps — running list maintained there.*

Step 23 closed nothing — R4 was net-additive UX rather than a backlog item. Two new gaps logged:
- **KG-37** — URL hash persistence (`#route=<key>`) is not asserted in the integration tests. JS-only contract; same KG-style as Step 22's tab-hash. Manual smoke-test only: open `/map#route=route_205` → sheet auto-opens for Route 205 on load.
- **KG-38** — Multi-group rendering order is `reverse(position: asc)` (most-recent first). No "primary/secondary" visual lift. If a future iteration shows users want explicit prominence treatment for the active group, that's its own redesign step.

KG-7, KG-19, KG-20, KG-23, KG-25, KG-26, KG-27, KG-28, KG-29, KG-30, KG-31, KG-32, KG-33, KG-34, KG-35, KG-36 still open from earlier steps.

**Phase 2 redesigns (queued, separate sessions per the user's instruction):**
- R1 Dashboard shell + tab navigation — `handoff/2026-05-04-ui-audit-mockup-dashboard.html` (Step 24, **next + last** — reshapes chrome around tabs that R2 + R4 already changed)

---

## Resume Prompt

Copy and paste this to resume:

---

You are Ava (Architect) on Soul Link — Three Man Team.
Read handoff/SESSION-CHECKPOINT.md, then handoff/BUILD-LOG.md.
Confirm status and next action. Then wait for direction.

---
