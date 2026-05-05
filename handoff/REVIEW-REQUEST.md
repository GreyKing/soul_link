# Review Request — Step 23

**Builder:** Bob
**Branch:** `claude/objective-faraday-c9b66b` (worktree)
**Ready for Review: YES**
**Scope:** Step 23 — R4 Map / Route timeline redesign per § 4 R4 of `handoff/2026-05-04-ui-audit.md` and the locked mockup `handoff/2026-05-04-ui-audit-mockup-map.html` (4 screens: desktop full timeline · sheet open / new catch · sheet open / existing catches · mobile accordion). Third Phase 2 redesign (R3 ✓ → R2 ✓ → **R4** → R1 ship order locked by the audit).

---

## Summary

8 modified or new code files (+ 2 handoff doc updates). Full suite: **712 → 754 runs (+42); 0 failures, 0 errors**. Rubocop clean (201 files, 0 offenses). Brakeman clean — same 2 pre-existing weak-confidence warnings unchanged from Steps 18/19/20/21/22 (`emulator_controller.rb:79` SendFile, `gym_schedule_discord_update_job.rb:14` FileAccess). **0 migrations. 0 new gem deps. 0 new design tokens. 0 controller/model/service changes.**

Built per Bob's plan inside `ARCHITECT-BRIEF.md` § "Builder Plan — Bob, 2026-05-05", with all six of Bob's questions answered in Ava's "Architect endorsement" section (also at the bottom of the brief). Build order followed exactly: Bucket 1 (helpers + unit tests) → Bucket 2 (CSS) → Bucket 3 (view) → Bucket 4 (controller) → Bucket 5 (tests) → Bucket 6 (lint + brakeman + full run).

---

## Files changed

| File | Lines | What |
|---|---|---|
| `app/views/map/show.html.erb` | full body rewrite (~280 lines) | New `.map-r4`-namespaced view per mockup Screens 1-4. Outer wrapper `<div class="map-r4" data-controller="timeline dashboard pixeldex" …>` with all timeline + dashboard + pixeldex value attrs declared. Sections: `.map-head` (h2 + sub + 8-badge strip) → `.status-bar` (NEXT GYM · LEVEL CAP · CURRENT SEG + JUMP TO NOW pill) → `.node-legend` (5 always-visible glyphs) → `.layout` grid (left = `.timeline-frame` desktop / `.accordion-frame` mobile + `.special-bar`; right = sticky `<aside class="sheet">`). Pulse-ring + `↓ NOW` pin on next-uncaught route, segment dividers between segments, Elite Four endpoint preserved. `<%= render "dashboard/pokemon_modal" %>` + `<%= render "dashboard/mark_dead_modal" %>` at the bottom. Read-only mode gates the `<form data-timeline-target="sheetForm">` (single source of truth per Ava Q5/Q6). |
| `app/assets/stylesheets/pixeldex.css` | +~545 lines new R4 section; +6 lines extending 520px block; +7 lines new 720px block | New `/* ── R4 Map ── */` section above the R2 marker, **all selectors namespaced under `.map-r4`** so existing timeline/route surfaces are untouched. Mockup CSS verbatim with the namespace prefix; mockup-document chrome (`.page`, `.page-banner`, `.legend`, `.section-anchor`, `.annotation`, `.phone`, `.phone-bezel`) stripped per Ava's note (those styled the mockup HTML, not the production component). Extended existing `@media (max-width: 520px)` to reflow `.map-r4 .special-grid` from 4 cols to 2. NEW `@media (max-width: 720px)` block hides `.map-r4 .timeline-frame`, shows `.map-r4 .accordion-frame`, drops `.map-r4 .layout` to single column, drops `.map-r4 .sheet`'s `position: sticky`. **No new design tokens.** |
| `app/javascript/controllers/timeline_controller.js` | full extension (~430 lines, ~120 new) | Targets renamed `panel*` → `sheet*`; `backdrop` removed. New targets `emptyState`, `groupList`, `jumpBtn`, `accordionSegment`. New actions: `jumpToNow` (smooth-scrolls to `.next` node, no-op when absent), `showCatchFormForCurrent` (dupes-clause: swaps sheet from group-list to form mode for the same loc_key). Internal helpers `_renderSheetCatchForm` / `_renderSheetGroupList` / `_buildGroupCardHtml` build the in-flow sheet content; group cards are JS-built and carry the `pixeldex#selectPokemon` + `dashboard#openMarkDeadModal` data attrs (additive `groups_json_for` payload makes this work without controller surgery). URL hash `#route=<key>` synced via `connect() → applyHashRoute()` (RAF-deferred so the sheet markup is laid out) and written in `selectLocation`; cleared in `closePanel` via `history.replaceState`. Existing actions (`submitCatch`, `toggleGym`, `filterSpecies`, `selectSpecies`, `closeAllDropdowns`, `handleKeydown`, `scrollToCurrentProgress`) all preserved verbatim. `.selected` class on `.glyph` replaces inline Tailwind `ring-*` classes (CSS owns the visual). Read-only mode gate: `hasSheetFormTarget` → JS skips EDIT / MARK DEAD / dupes button. Tiny `_escape()` HTML-attr escape for templated nicknames. |
| `app/helpers/map_helper.rb` | +~155 lines | Six new helpers + extended `groups_json_for`: `next_uncaught_route_key(progression, locations, groups_by_location)` (first-uncaught-route across segments; skips cities/dungeons/lakes/specials), `current_segment_label(progression, gym_info, next_uncaught_key)` (bare-city label; FINAL STRETCH fallback; ELITE FOUR for null-gym segment per Ava Q3), `segment_divider_label(progression, gym_info, seg_idx)` (bare-city of upcoming segment; nil after last; ELITE FOUR before null-gym), `segment_progress(segment, locations, groups_by_location)` (catchable-types-only denominator per Ava Q4: route/dungeon/lake/special; caught counts caught+dead), `segment_open_by_default?(segment, next_uncaught_key)`, `node_status_class(loc_data, status)` (special only for uncaught specials). `groups_json_for(groups, current_user_id)` extended additively per Ava Q1 — added per-pokemon `id`, `is_mine`, `level`, `ability`, `nature`, `sprite_url`, `types`; per-group `id`, `species_for_user`, `types_for_user`. Existing `species` / `player` / `sprite` fields retained. Private `bare_city_label(loc_key)` strips `_city` / `_town` suffix and uppercases. |
| `test/integration/map_redesign_test.rb` | new, 217 lines | 13 markup-assertion tests covering: `.map-r4` wrapper + 3-controller wiring; legend's 5 glyph items; pulse-ring `.next` + `↓ NOW` pin (exactly once on a fresh run, route_201); JUMP TO NOW hides when every route caught (helper returns nil → `.jump-btn.hidden` rendered); status bar 3 items; em-dash fallback when `gyms_defeated = 8`; sheet's emptyState + groupList + sheetForm targets (with one species input per `SoulLink::GameState.players` entry); `data-groups` carries 2-element JSON when 2 groups exist on same location (dupes-clause); read-only mode hides `sheetForm` + `+ LOG GROUP`; `.special-bar` 4 cells (gift/egg/trade/other) wired to `click->timeline#selectLocation`; accordion frame renders one details per segment, exactly one `[open]`, every `.acc-row` carries the click chain; pokemon + mark-dead modal partials render on `/map`; every timeline node carries the click action. Same `GREY = 153665622641737728` + `login_as` pattern as `pc_box_redesign_test.rb`. FactoryBot only. |
| `test/helpers/map_helper_test.rb` | new, 303 lines | 25 unit tests covering all six new helpers + the previously-untested `location_status` / `primary_group` (brief §21 bonus) + the additive `groups_json_for` payload. Pure-function helpers exercise plain Hash inputs shaped like the YAML config, so no dependency on the live config files. `build_stubbed` for `location_status` / `primary_group` group inputs (status predicate is bypassed-create-safe). FactoryBot for the JSON payload test. |
| `test/integration/responsive_grids_test.rb` | +38 lines | Four new Step 23 R4 tests: `.map-r4` declared outside any media block; 720px block hides `.map-r4 .timeline-frame` + shows `.map-r4 .accordion-frame` + collapses `.map-r4 .layout` to single column; 520px reflows `.map-r4 .special-grid` to `repeat(2, 1fr)`; 520/720/900px breakpoints do NOT set `display: none` on `.map-r4 .node`, `.sheet`, or `.acc-row` (mockup-fidelity contract, mirrors Step 21/22 shape). |
| `handoff/ARCHITECT-BRIEF.md` | rewrite for Step 23 | Locked decisions, files-to-verify pass (A-F), build order, acceptance checklist. Builder Plan section (Bob's, with 6 questions and surfaced contradictions) + Architect endorsement (Ava's, all 6 answered) live at the bottom. |
| `handoff/BUILD-LOG.md` | Step 23 added to Step History; Current Status updated; Step 22 → "Status archive" (one-step lookback) | Step 23 entry matches Step 22's level of detail: status, all locked architecture decisions, test count delta, file inventory with line counts, full 42-test breakdown, backward-compat invariants, diff scope, KG closures + new gaps. |

---

## How the new feature lands the four cases

The R4 redesign's headline feature is "clickable map locations." The brief locks four cases, all routed through `selectLocation`:

1. **No-catch (uncaught route)** → `_renderSheetCatchForm(key, name)` — empty state hides, groupList hides, sheetForm shows, location key written to hidden input, nickname focused. (Read-only mode: form is absent server-side; JS shows a "this run is read-only" message in the groupList area.)
2. **Single-catch** → `_renderSheetGroupList(key, name, groups)` — one `.group-card` rendered with EDIT + MARK DEAD buttons + the dashed `+ ANOTHER ENCOUNTER (DUPES CLAUSE)` button.
3. **Multi-catch (dupes-clause re-rolls)** → same `_renderSheetGroupList` path — N stacked `.group-card`s + the dashed dupes button.
4. **Special encounter cell** (`.special-cell`) → same `selectLocation` chain → empty/single/multi as above.

The `+ ANOTHER ENCOUNTER` button doesn't change the URL hash — it just toggles the same sheet body to form mode for the already-selected route via `showCatchFormForCurrent`. Submitting reloads the page; the new group appears as an additional card next time the route's sheet opens.

---

## Decisions made (lookups + interpretations)

These came up during the build pass and were resolved without churn.

1. **Modal wrapper attaches `dashboard pixeldex` plus value attrs** so `_pokemon_modal.html.erb` and `_mark_dead_modal.html.erb` work without bespoke wiring. Pre-write check confirmed both controllers' `connect()` methods are benign on `/map` — dashboard has no `connect`; pixeldex's `#initSortables()` is a no-op without on-team grids and `#applyHashTab()` looks for tab buttons matching `route=route_205` (none exist). Safe.
2. **`groups_json_for(groups, current_user_id)` is the single source of truth** for both the new sheet rendering AND the JS-built EDIT button's `data-group-pokemon` payload. Additive extension per Ava Q1; no parallel `pixeldex_groups_json_for` helper.
3. **`.selected` class on `.glyph`** replaces inline Tailwind `ring-2 ring-indigo-400 ring-offset-2 ring-offset-gray-800` from the legacy controller. CSS owns the visual via `.map-r4 .node.selected .glyph { outline: 3px solid var(--amber); outline-offset: 2px; }`.
4. **`.jump-btn.hidden`** is rendered server-side when `next_uncaught_key.nil?` (helper returns nil → ERB conditionally adds the `hidden` class). The `connect()` method also re-runs the safety check JS-side (`if (!hasNext) this.jumpBtnTarget.classList.add("hidden")`) — both gates fire for the same condition; harmless redundancy. Test asserts the `class="jump-btn hidden"` shape directly.
5. **Final segment divider label = `"ELITE FOUR"`** per Ava Q3 override. Mockup's `data-segment="…"` was a truncation artifact (mockup only renders 3 segments). The helper's logic: if `next_seg["gym"]` is blank, return `"ELITE FOUR"`. Tested.
6. **`segment_progress` denominator counts catchable types only** per Ava Q4: `route` / `dungeon` / `lake` / `special`. Excludes `city` / `town` because most have no tall grass and don't consume an encounter slot. Caught counts those with `location_status` of `caught` OR `dead` (both consume the encounter slot). Tested with the 5/6 ✓ mockup case.
7. **`#route=<key>` URL hash is JS-only — no integration test** per brief §9. Same KG-35-style decision as Step 22's tab-hash. Documented in the controller; manual smoke-test contract: open `/map#route=route_205` → sheet opens for Route 205 on load.
8. **CSS landed at ~545 lines** — bigger than Ava's 250-280 estimate after stripping mockup chrome. The bloat comes from (a) the namespace prefix `.map-r4 ` adding ~10 chars per selector, (b) extra `.group-card` / `.dupes-btn` / `.species-dropdown` styles needed for the JS-built sheet content (mockup shows them inline-styled inside the screen samples; we surfaced them as named classes for the production controller to reach), and (c) accordion responsiveness + `.acc-row` glyph variants. **Not a concern for me — happy to revisit if Richard sees redundancy.**

## Open questions / things to surface

None. The brief, the Architect endorsement, and the mockup all agree. No mockup contradictions surfaced during implementation.

---

## Verification

- `bin/rails test` (full suite) — **754 runs, 0 failures, 0 errors** (was 712 at Step 22).
- `bundle exec rubocop` — **0 offenses across 201 files**.
- `bundle exec brakeman -q --no-progress` — **2 weak-confidence warnings** (`emulator_controller.rb:79` SendFile, `gym_schedule_discord_update_job.rb:14` FileAccess), unchanged from Steps 18/19/20/21/22 baseline.
- `bin/rails routes` — `/map` route preserved (`map GET /map(.:format) maps#show`), no controller changes.
- `git diff Gemfile Gemfile.lock db/ config/importmap.rb` — empty (no gem deps, no migrations, no JS bundling change). Verified.

Manual smoke-test paths I'd suggest Richard run if you have a dev server up:
1. **Fresh run:** `/map` should render with no `.next` class anywhere (everything uncaught means route_201 IS uncaught and gets the pulse). Click route_201 → form opens. Click special "GIFT" → form opens.
2. **Mid-run:** create a group on route_201. `/map` should put `.next` on route_202 (next uncaught route). Click route_201 → group card with EDIT + MARK DEAD + dupes button. Click EDIT → pokemon modal opens via `pixeldex#selectPokemon`. Click MARK DEAD → mark-dead modal opens via `dashboard#openMarkDeadModal`.
3. **Late-run:** mark all 8 gyms beaten + catch every route. JUMP TO NOW button has `.hidden` class; status bar's CURRENT SEG = "FINAL STRETCH"; NEXT GYM = "All 8 earned · Elite Four ahead"; LEVEL CAP = "—".
4. **Mobile (DevTools, < 720px):** timeline-frame hides; accordion-frame shows; the segment containing the next-uncaught route is `[open]` by default. Sheet stacks below the accordion (not sticky).
5. **URL hash:** `/map#route=route_205` should auto-open the sheet for Route 205 on load. Closing the sheet clears the hash without reload.

---

## Diff scope sanity check

Inside the brief's stated scope (≤7 files outside `handoff/`):
- Modified: `app/views/map/show.html.erb`, `app/assets/stylesheets/pixeldex.css`, `app/javascript/controllers/timeline_controller.js`, `app/helpers/map_helper.rb`, `test/integration/responsive_grids_test.rb` (5).
- New: `test/integration/map_redesign_test.rb`, `test/helpers/map_helper_test.rb` (2).

Total: **7 files outside `handoff/`** (5 modified + 2 new). Within budget.

**Zero changes** under `app/controllers/`, `app/models/`, `db/`, `app/services/`, `app/jobs/`, `config/`, `Gemfile*`. Verified via `git status`.

---

## Closing note

I want to flag one judgement call: the new CSS section is ~545 lines, not 250-280. The number was an Architect estimate after stripping mockup chrome (which I did — all 7 chrome selectors gone). The remaining bulk comes from (a) the `.map-r4 ` namespace prefix on every selector, (b) the JS-built group-card / dupes-btn / species-dropdown surfaces that the mockup shows inline-styled (we needed named classes for the controller to reach), and (c) accordion + `.acc-row` glyph variants. I think this is the right shape — the alternatives are inline styles in the JS strings or shared classes that risk collision. Happy to revisit if Richard sees redundancy.

The main feature concern I'd flag is the `applyHashRoute` race: on a slow network or a Turbo morph, the sheet markup might not be in the DOM by the time `connect()` fires. I wrapped the sheet open in `requestAnimationFrame` to give the layout one tick to settle, but if Richard sees a more robust pattern (e.g. waiting on a target callback) I'd take the suggestion.

**Ready for Review: YES**
