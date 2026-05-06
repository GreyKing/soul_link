# Session Checkpoint
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*
*Session-scoped — archived to `handoff/archive/` at session end.*

---

## Where We Stopped

Step 24 (R1 Dashboard restructure — Phase 2 R1 of the 2026-05-04 UI/UX audit) shipped on the worktree branch `claude/sad-haslett-33d407`, FF-merged to `origin/main` and pushed. **Phase 2 of the audit is now closed** — all four redesigns (R3 ✓ Save Slots → R2 ✓ PC Box → R4 ✓ Map → R1 ✓ Dashboard) are live on `main`. Awaiting next brief from Project Owner.

The user's instructions were explicit: after Step 24 ships, **stop**. The user will pick what's next.

---

## What Was Built

**Step 24 — R1 Dashboard restructure + run-management consolidation.**

Implements the locked mockup `handoff/2026-05-04-ui-audit-mockup-dashboard.html` across all 6 screens (desktop 3-col + slim title bar + real tablist · right-rail PARTY view · tablet 2-col · phone single column + scrollable tab strip · run-pill open · ARIA spec sheet). Layered on the existing dashboard controller + tab system + panels each tab renders. Net-additive backend work — only `@all_player_teams` instance variable added + `RunsController#index` body replaced with a 301 redirect. Closes audit cross-cutting #3 (run-management dual surfaces) and #6 (right-rail / map-panel duplication).

**Surfaces introduced/changed:**

- **`/` dashboard root** (`app/views/dashboard/show.html.erb`, full rewrite ~80 lines) — wraps in `<div class="dash-r1" data-controller="dashboard pixeldex run-management" data-action="keydown@window->pixeldex#numericJump" …>`. Hoists `run-management` to dashboard root so the title-bar `+ START NEW RUN` button reaches `run-management#startRun` via DOM bubbling without spawning a second ActionCable subscription. Order: top-nav (from `application.html.erb`) → `_title_bar` → `_tab_bar` → `.pc-layout` (`.col-party` + `.panel` + `_status_rail`) → 4 modal partials. Each `tabContent` div now also carries `role="tabpanel"` + `id="panel-<key>"` + `aria-labelledby="tab-<key>"` + `tabindex="0"` so the tablist contract is complete.
- **`_title_bar.html.erb`** full rewrite (~80 lines) — slim one-row strip: 36×36 amber `.title-glyph` (player initials, falls back to "PC") + 2-line title block (`<player>'s PC` + `PLATINUM · SOUL LINK`) + run-pill (`<button class="run-pill">RUN #N <span class="badge">ACTIVE</span> <span class="chev">▾</span></button>`) replacing the legacy `<select onchange="window.location.href = …">` per audit annotation C. Right side: single inline stat strip (`CAUGHT N · ALIVE N · DEAD N · BADGES N/8`) with `·` separators. Run-pill dropdown renders all runs as `<a href="/?run_id=N" role="option" tabindex="-1">` (works without JS); the new `run-picker` Stimulus controller adds toggle + keyboard nav (↑/↓/Home/End/Enter/Esc) + outside-click close. **CAUGHT/ALIVE math fixed inline** — controller's `@caught_count` is `count(&:caught?)` (currently-alive); mockup wants total ever caught, so the view computes `@caught_count + @dead_count` for CAUGHT and `@caught_count` for ALIVE without changing controller semantics.
- **`_tab_bar.html.erb`** full rewrite (~50 lines) — real WAI-ARIA tablist (`<div role="tablist" aria-label="Dashboard sections" data-action="keydown->pixeldex#tablistKeydown">` + per-tab `<button role="tab" id="tab-<key>" aria-controls="panel-<key>" aria-selected aria-tabindex>`). 2-line vertical tab buttons (icon top + label bottom). Active tab `tabindex="0"`, others `-1`. Live-update green dots: PC BOX when `@auto_detected_catches.any?`; GYMS when `@active_draft.present?`. Server-rendered — Turbo morph keeps them in sync.
- **`_status_rail.html.erb`** NEW (~205 lines) — `<aside class="status-rail" data-controller="status-rail" aria-label="Live status">` replaces deleted `_map_panel.html.erb`. Three sub-tabs: PARTY · GYMS · MAP; GYMS is default-active (mockup screen 1). PARTY iterates `SoulLink::GameState.players` against `@all_player_teams.index_by(:discord_user_id)` rendering one `.player-card` per player; current user's row gets `.you` modifier (amber border + YOU pill, plus 🏆 HOF when `@run.completed? && badges == 8`). GYMS lists all 8 leaders compact (.beaten / .next w/ pulse-ring / .upcoming) + a `↓ NEXT BATTLE` block with leader / location / level / type prep + `START GYM DRAFT →` CTA via `button_to gym_drafts_path, method: :post` (read-only mode renders "RUN ENDED" instead of the CTA). MAP keeps today's body content (ASCII map + CURRENT LOCATION + BADGE CASE + RECENT ROUTES + Strategy Dialog) — GYM LEADERS section removed because it now lives in the GYMS sub-tab (closes audit cross-cutting #6).
- **`_runs_content.html.erb`** extended — added the 3 emulator-ROM affordances (`Generate Emulator ROMs` when `:none`, `Regenerate ROMs` when `:failed`, `ROMs generating…` status span when `:generating`); removed the inner `data-controller="run-management"` wrapper (now hoisted to dashboard root in `show.html.erb`). The dashboard RUNS tab is now canonical — `/runs` was redirected.
- **`pixeldex.css`** — new `/* ── R1 Dashboard ── */` section above the RESPONSIVE block (~325 lines, **every selector namespaced under `.dash-r1`**): title bar + glyph + run-pill + run-pill-menu + stat strip + tab bar (2-line button + active underline + badge-dot) + pc-layout grid + status rail + side-tabs + status-panel content + player-card (with `.you` variant + sprite cells) + gym-list (with `.beaten`/`.next`/`.upcoming` + `pulseNext` keyframe) + next-battle CTA + map-area. Extended `@media (max-width: 900px)` block: `.dash-r1 .pc-layout { grid-template-columns: minmax(0, 1fr) 280px; }` + `.dash-r1 .col-party { display: none; }` + title-bar wraps to column. Extended `@media (max-width: 720px)` block (already existed for `.map-r4`): `.dash-r1 .pc-layout { grid-template-columns: 1fr; }` + `.dash-r1 .tab-bar { overflow-x: auto; flex-wrap: nowrap; }` + stat-strip pulls top border. Extended `@media (max-width: 520px)` block: `.dash-r1 .stat-strip { font-size: 7px; gap: 8px; }`. **Zero new design tokens.**
- **Stimulus controllers** — 2 new + 1 extended:
  - `run_picker_controller.js` (~110 lines) — toggle / open / close / navigate (↑/↓/Home/End/Enter/Esc). RAF-deferred focus on first option after open. Anchors trigger natively (no JS dependency for the switch action); the non-anchor `+ START NEW RUN` button uses `target.click()` for Enter activation. Outside-click via `document.addEventListener("click", _closeOnOutside)`.
  - `status_rail_controller.js` (~60 lines) — `switch` (click) + `keydown` (←/→/Home/End focus+activate). `_activate(tab, { focus })` flips `aria-selected` + `tabindex` on every sub-tab button and toggles the matching panel's `.hidden` class.
  - `pixeldex_controller.js` extended (NOT replaced) — new `tablistKeydown` action (←/→/Home/End move focus AND activate per mockup spec); new `numericJump` window-bound action (1–7 jump tabs; skipped when `<input>`/`<textarea>`/`<select>`/`[contenteditable]` has focus or any modifier key is held); `switchTab` extended with `aria-selected` + `tabindex` flips on every tab button (legacy `.active` class kept for back-compat) and `history.replaceState(null, "", "#" + tab)` (no back-stack pollution — Step 23 `#route=` precedent). Existing `#applyHashTab` preserved verbatim. Stimulus controller registration is automatic via `eagerLoadControllersFrom` + `pin_all_from`; no manual `index.js` edit needed.
- **Backend** — `dashboard_controller.rb` adds **one** new instance variable (`@all_player_teams = run.soul_link_teams.includes(soul_link_team_slots: { soul_link_pokemon_group: :soul_link_pokemon }).order(:discord_user_id)`) for the PARTY sub-tab to avoid per-player N+1. `runs_controller.rb` body replaced with `redirect_to root_path(anchor: "runs"), status: :moved_permanently` (closes audit cross-cutting #3 — dashboard RUNS tab is canonical; `/runs` view file deleted). `app/views/dashboard/_map_panel.html.erb` deleted (content folded into `_status_rail` MAP sub-tab; `_map_content.html.erb` for the MAP main tab is untouched).

**Counts:** 755 → 777 tests (+22). 0 failures, 0 errors. Rubocop clean (202 files, 0 offenses; +2 files for new Stimulus controllers). Brakeman clean — same 2 pre-existing weak-confidence warnings unchanged from Steps 18–23. **0 migrations. 0 new gem deps. 0 new design tokens. 0 model/service/job/channel changes; 1 controller line added (`@all_player_teams`), 1 controller body replaced (RunsController#index → redirect).**

**Review:** 0 Must Fix, 4 Should Fix (all fixed inline):
- **#1 — Run-option `tabindex`.** Run-pill menu options had `tabindex="0"`, putting every option in the page Tab order. WAI-ARIA listbox uses roving focus instead — switched options to `tabindex="-1"`; the controller's `open()` handler still focuses the first option for screen readers. Trivial 1-attribute change.
- **#2 — `+ START NEW RUN` button missed `role="option"`.** Inside a `role="listbox"` container, the start-new-run button needed `role="option"` for screen readers walking the listbox children. Added `role="option" aria-selected="false" tabindex="-1"`.
- **#3 — `run_picker_controller.js` ArrowUp edge case.** When `currentIndex === -1` (trigger has focus, no option focused yet), the modulo math `(-1 - 1 + n) % n = n - 2` jumped to the second-to-last option instead of the last. Added explicit `currentIndex === -1` guards: ArrowUp lands on last, ArrowDown lands on first.
- **#4 — Inline form margin.** `button_to "START GYM DRAFT", form: { style: "margin: 0;" }` carried an inline style on the wrapper form — exactly the anti-pattern audit cross-cutting #5 calls out. Moved to `.dash-r1 .next-battle form { margin: 0; }` in `pixeldex.css`; dropped the `form: { style: ... }` arg.

---

## What Was Decided This Session

- **Run-management consolidation: dashboard RUNS tab is canonical.** `/runs` redirects to `root_path(anchor: "runs")` with `:moved_permanently` (301) — permanent IA decision per audit cross-cutting #3. The dashboard RUNS tab gains the missing emulator-ROM affordances; the run pill in chrome handles cross-run switching from any page.
- **CSS namespace under `.dash-r1`** (Step 22 `.pc-box-r2`, Step 23 `.map-r4` precedent). Within `.dash-r1`, the new rules **override** the legacy `.title-bar` (slim row), `.tab-bar` (tablist), `.pc-layout` (3-col) shapes without touching elsewhere-rendered surfaces.
- **`run-management` Stimulus controller hoisted to dashboard root.** Pre-Step-24 it was scoped to `_runs_content.html.erb`; Step 24 hoists it to `dashboard/show.html.erb`'s outer `.dash-r1` div so the title-bar `+ START NEW RUN` reaches `run-management#startRun` via DOM bubbling. One ActionCable subscription per dashboard load.
- **Run-pill switching is anchor-based.** Each menu option is `<a href="/?run_id=N" role="option" tabindex="-1">` — works without JS. Stimulus only handles toggle + keyboard nav + outside-click close. No XSS-adjacent `<select onchange="window.location.href">` anywhere in the app.
- **Right-rail consolidation: 3 sub-tabs replace stacked panels.** Old `_map_panel.html.erb` stacked ASCII map + current location + badge case + GYM LEADERS + recent routes — duplicating MAP and GYMS main-tab content. New `_status_rail.html.erb` collapses this into one card with PARTY / GYMS / MAP sub-tabs; GYMS default-active (mockup screen 1). PARTY is NEW data (one row per registered player); MAP is the old `_map_panel` body MINUS the GYM LEADERS section (now in GYMS sub-tab). Closes audit cross-cutting #6.
- **Tablist activation on focus move (mockup spec).** WAI-ARIA recommends focus-only with Enter/Space to activate, but the mockup explicitly says "←/→ moves between tabs (with wrap), updates `aria-selected` and `tabindex` immediately, **and activates the tab**." `pixeldex#tablistKeydown` calls `target.focus(); target.click()`. Single-line revert to WAI-ARIA-strict if a future iteration wants it.
- **`pixeldex#numericJump` window-level binding gated for input focus.** Skip `INPUT`/`TEXTAREA`/`SELECT`/`isContentEditable`; skip on any modifier key (so users with Cmd-1 to switch browser tabs aren't intercepted).
- **`switchTab` URL-hash write via `history.replaceState`** (Step 23 `#route=` precedent). No back-stack pollution.
- **Per-player badge counts on PARTY sub-tab share `@gyms_defeated`** (KG-39). Per-player badge variance is a future feature; for now all 4 player rows show the run's `gyms_defeated`. The YOU pill identifies the current user; the 🏆 HOF pill renders only when `@run.completed? && badges == 8`.
- **CAUGHT/ALIVE labeling inversion fixed inline in the view** without touching controller semantics. Pre-Step-24 the title bar showed `@caught_count` for "CAUGHT" and `@caught_count - @dead_count` for "ALIVE" — labeling inversion (controller's `@caught_count` is `count(&:caught?)` = currently-alive). Mockup locks the conventional reading: CAUGHT = total ever caught; ALIVE = currently alive; DEAD = currently dead. View math: `@caught_count + @dead_count` for CAUGHT, `@caught_count` for ALIVE.
- **`@all_player_teams` is the only new controller variable** — computed once with `includes(...)` to avoid per-player N+1. The PARTY sub-tab partial does `@all_player_teams.index_by(&:discord_user_id)` and tolerates missing rows.
- **Dashboard MAP main-tab partial (`_map_content.html.erb`) untouched.** Different file, different surface. Step 23's `_map_content.html.erb` lock holds.

---

## Known Gaps / Future Work

*See `handoff/BUILD-LOG.md` Known Gaps — running list maintained there.*

Step 24 closed nothing — R1 was net-additive UX + IA consolidation rather than a backlog item. One new gap logged:
- **KG-39** — Per-player badge variance on the PARTY sub-tab. Today all 4 player rows show the run's shared `@gyms_defeated`. Per-player badge counts are a future feature (would require a per-player gym-progression table or a join through `gym_results` filtered by which player participated). The YOU pill + 🏆 HOF pill logic is in place; only the badge-count value is shared.

KG-7, KG-19, KG-20, KG-23, KG-25, KG-26, KG-27, KG-28, KG-29, KG-30, KG-31, KG-32, KG-33, KG-34, KG-35, KG-36, KG-37, KG-38 still open from earlier steps.

**Phase 2 redesigns** (all four shipped, audit § 5 ship order complete):
- ✓ R3 Save Slots — Step 21
- ✓ R2 PC Box — Step 22
- ✓ R4 Map / Route timeline — Step 23
- ✓ R1 Dashboard shell + tab navigation — Step 24

Phase 2 closes. Future redesign work (cross-cutting #2 ARIA-modals, #5 inline-styles inventory, #7 color-only status indicators, #8 hover states, #9 9–10px text review) are separate steps if/when prioritized.

---

## Resume Prompt

Copy and paste this to resume:

---

You are Ava (Architect) on Soul Link — Three Man Team.
Read handoff/SESSION-CHECKPOINT.md, then handoff/BUILD-LOG.md.
Confirm status and next action. Then wait for direction.

---
