# Review Request — Step 24

**Builder:** Bob
**Branch:** `claude/sad-haslett-33d407` (worktree)
**Ready for Review: YES**
**Scope:** Step 24 — R1 Dashboard restructure per § 4 R1 of `handoff/2026-05-04-ui-audit.md` and the locked mockup `handoff/2026-05-04-ui-audit-mockup-dashboard.html` (6 screens: desktop 3-col + slim title + real tablist · right-rail PARTY view · tablet 2-col · phone single column + scrollable tab strip · run-pill open · ARIA spec sheet). Final Phase 2 redesign — closes Phase 2 (R3 ✓ → R2 ✓ → R4 ✓ → **R1**).

---

## Summary

4 new + 9 modified + 2 deleted code files (+ 2 handoff doc updates). Full suite: **755 → 777 runs (+22); 0 failures, 0 errors**. Rubocop clean (202 files, 0 offenses; +2 files for the new Stimulus controllers). Brakeman: clean — same 2 pre-existing weak-confidence warnings unchanged from Steps 18-23 (`emulator_controller.rb:79` SendFile, `gym_schedule_discord_update_job.rb:14` FileAccess). **0 migrations. 0 gem deps. 0 new design tokens. 0 new model/service/job/channel/config code.**

Built directly per BUILDER.md Pt. 4 — the brief was locked + unambiguous, so no Builder Plan section was added to ARCHITECT-BRIEF.md. Build order followed the suggested order in the prompt: backend nudge → CSS → Stimulus → views → file deletions → tests → lint+brakeman+full-run.

---

## Files changed

| File | Lines | What |
|---|---|---|
| `app/views/dashboard/show.html.erb` | full rewrite (~80 lines) | Wrapped top-level in `<div class="dash-r1" data-controller="dashboard pixeldex run-management" data-action="keydown@window->pixeldex#numericJump" …>`. Hoisted `run-management` controller to the dashboard root so the title-bar `+ START NEW RUN` button reaches `run-management#startRun` via DOM bubbling without spawning a second ActionCable subscription. Renders `_title_bar` → `_tab_bar` → `.pc-layout` (`<div class="col-party">_party_panel</div>` + `<div class="panel">tab content × 7</div>` + `_status_rail`) → 4 modal partials. Each `tabContent` div now also carries `role="tabpanel"` + `id="panel-<key>"` + `aria-labelledby="tab-<key>"` + `tabindex="0"` so the WAI-ARIA tablist contract is complete. |
| `app/views/dashboard/_title_bar.html.erb` | full rewrite (~80 lines) | One-row flex strip: 36×36 amber `.title-glyph` (player initials, falls back to "PC") + 2-line title block (`<player>'s PC` + `PLATINUM · SOUL LINK`) + run-pill replacing the legacy `<select onchange="window.location.href = …">` per audit annotation C. Right side: single inline stat strip (`CAUGHT N · ALIVE N · DEAD N · BADGES N/8`) with `·` separators. Run-pill dropdown renders all runs as `<a href="/?run_id=N" role="option">` + a non-anchor `+ START NEW RUN` button at the bottom that fires `click->run-management#startRun`. Run-pill carries `data-controller="run-picker"` + `data-action="keydown->run-picker#navigate"` on the wrapper, `aria-haspopup="listbox"` + dynamic `aria-expanded` on the trigger. **CAUGHT count fixed inline** — controller's `@caught_count` is `count(&:caught?)` (currently-alive); mockup wants total ever caught, so the view computes `@caught_count + @dead_count` for CAUGHT and `@caught_count` for ALIVE without changing controller semantics. WHY comment in the partial. |
| `app/views/dashboard/_tab_bar.html.erb` | full rewrite (~50 lines) | Real WAI-ARIA tablist: outer `<div role="tablist" aria-label="Dashboard sections" data-action="keydown->pixeldex#tablistKeydown">`, each tab is `<button role="tab" id="tab-<key>" aria-controls="panel-<key>" aria-selected="…" tabindex="…" data-action="click->pixeldex#switchTab" data-pixeldex-target="tabButton" data-tab="<key>">`. Active tab `tabindex="0"`, others `-1`. 2-line vertical button shape: icon top (14px) + label bottom (9px). Live-update green dots: PC BOX when `@auto_detected_catches.any?`; GYMS when `@active_draft.present?`. Server-rendered — Turbo morph keeps them in sync. |
| `app/views/dashboard/_status_rail.html.erb` | NEW (~205 lines) | `<aside class="status-rail" data-controller="status-rail" aria-label="Live status">` with sub-tab strip (`role="tablist" aria-label="Status panels"` on `.side-tabs`; per-tab `role="tab"` + `aria-selected` + `tabindex` + `data-status-rail-tab-param` + `data-action="click->status-rail#switch"`). PARTY sub-tab iterates `SoulLink::GameState.players` against `@all_player_teams.index_by(:discord_user_id)` lookup, rendering one `.player-card` per player with name + badges pill + 6 sprite cells. Current user's row gets `.you` modifier (amber border + `<span class="you-pill">YOU</span>`). HOF pill (🏆) renders only when `@run.completed? && badges == 8`. GYMS sub-tab renders a compact 8-row gym list (`.beaten` / `.next` with pulse / `.upcoming`) + a `↓ NEXT BATTLE` block with leader / location / level / type prep + `START GYM DRAFT →` CTA via `button_to gym_drafts_path, method: :post`. Read-only mode renders "RUN ENDED" instead of the CTA. MAP sub-tab keeps today's body content (ASCII map + CURRENT LOCATION + BADGE CASE + RECENT ROUTES + Strategy Dialog) — GYM LEADERS section removed (now in GYMS sub-tab → closes audit cross-cutting #6). GYMS is `aria-selected="true" tabindex="0"`; the other two carry the `.hidden` class on their tabpanel section. |
| `app/views/dashboard/_runs_content.html.erb` | +27 lines | Added 3 emulator-ROM affordances: `<button data-action="click->run-management#generateEmulatorRoms" data-run-management-target="generateRomsButton" class="…<%= 'hidden' if active_run&.emulator_status != :none %>">Generate Emulator ROMs</button>`, the `regenerateEmulatorRoms` mirror, and a `<span data-run-management-target="generateRomsStatus" class="<%= 'hidden' if active_run&.emulator_status != :generating %>">ROMs generating…</span>` status span. Removed the inner `<div data-controller="run-management" …>` wrapper (now hoisted to dashboard root in `show.html.erb`); replaced with a plain `<div>`. Targets and actions resolve up the DOM. |
| `app/views/dashboard/_map_panel.html.erb` | DELETED | Content folded into `_status_rail` MAP sub-tab. The MAP main-tab partial (`_map_content.html.erb`) is unchanged — different file, different surface. |
| `app/views/runs/index.html.erb` | DELETED | Canonical content lives in `_runs_content.html.erb`. `app/views/runs/` directory removed (now empty). |
| `app/controllers/runs_controller.rb` | full rewrite (4 lines body) | `index` becomes `redirect_to root_path(anchor: "runs"), status: :moved_permanently`. WHY comment in the controller. Closes audit cross-cutting #3. |
| `app/controllers/dashboard_controller.rb` | +5 lines | Added `@all_player_teams = run.soul_link_teams.includes(soul_link_team_slots: { soul_link_pokemon_group: :soul_link_pokemon }).order(:discord_user_id)` for the PARTY sub-tab to avoid per-player N+1. WHY comment in the controller. |
| `app/javascript/controllers/run_picker_controller.js` | NEW (~110 lines) | `toggle` (event-stop + open/close), `open` (RAF-deferred focus on first option, sets `aria-expanded="true"`), `close` (`aria-expanded="false"`), `navigate` (↑/↓/Home/End/Enter/Esc — wraps at edges; anchors trigger natively, non-anchor `+ START NEW RUN` button uses `target.click()` for Enter activation). Outside-click via `document.addEventListener("click", _closeOnOutside)` in `connect()`, removed in `disconnect()`. |
| `app/javascript/controllers/status_rail_controller.js` | NEW (~60 lines) | `switch` (click) + `keydown` (←/→/Home/End focus+activate). Internal `_activate(tab, { focus })` flips `aria-selected` + `tabindex` on every sub-tab button and toggles the matching panel's `.hidden` class. `data-status-rail-tab-param` carries the key. |
| `app/javascript/controllers/pixeldex_controller.js` | +~70 lines | New `tablistKeydown(event)` action: ←/→ (wrapping) + Home/End move focus AND activate (mockup spec — `target.focus(); target.click()`). New `numericJump(event)` action bound on window via `keydown@window->pixeldex#numericJump`: parses `event.key` as 1-7, focuses + clicks the matching tab. Skipped when `event.target.tagName` is `INPUT`/`TEXTAREA`/`SELECT`, when `target.isContentEditable`, or when any modifier key is held. `switchTab` body extended: in addition to the existing `.active` class toggle (kept for back-compat), now flips `aria-selected` + `tabindex` on every tab button with `role="tab"`, and writes `history.replaceState(null, "", "#" + tab)` (Step 23 `#route=` precedent). Existing `#applyHashTab` preserved verbatim. |
| `app/assets/stylesheets/pixeldex.css` | +~338 lines | New `/* ── R1 Dashboard ── */` section above the RESPONSIVE block (~325 lines, every selector namespaced under `.dash-r1`): title bar + glyph + run-pill + run-pill-menu + stat strip + tab bar (2-line button + active underline + badge-dot) + pc-layout grid + status rail + side-tabs + status-panel content + player-card (with .you variant + sprite cells) + gym-list (with .beaten/.next/.upcoming + pulseNext keyframe) + next-battle CTA + map-area. Extended `@media (max-width: 900px)`: `.dash-r1 .pc-layout { grid-template-columns: minmax(0, 1fr) 280px; }` + `.dash-r1 .col-party { display: none; }` + `.dash-r1 .title-bar { flex-direction: column; align-items: flex-start; }`. Extended `@media (max-width: 720px)` (existing for `.map-r4`): `.dash-r1 .pc-layout { grid-template-columns: 1fr; }` + `.dash-r1 .tab-bar { overflow-x: auto; flex-wrap: nowrap; }` + `.dash-r1 .tab { min-width: 80px; flex: 0 0 auto; }` + `.dash-r1 .title-bar { flex-direction: column; }` + `.dash-r1 .stat-strip { padding-top: 6px; border-top: 1px dashed var(--d2); }`. Extended `@media (max-width: 520px)`: `.dash-r1 .stat-strip { font-size: 7px; gap: 8px; }`. **Zero new design tokens.** |
| `test/integration/dashboard_redesign_test.rb` | NEW (~250 lines, 18 tests) | See test list below. |
| `test/integration/responsive_grids_test.rb` | +38 lines (4 new tests) | `.dash-r1` namespace declared outside any media block; 900px breakpoint hides `.col-party` + drops layout to 2-col; 720px breakpoint drops layout to 1fr + tab-bar overflows; 520/720/900px breakpoints do NOT collapse `.dash-r1 .tab` or `.dash-r1 .status-rail` (negative-assertion guard). |
| `test/integration/confirm_modal_flow_test.rb` | rewrite (3 tests re-pointed; 1 new) | The 3 legacy tests against `get runs_path` (which now redirects) re-pointed at `get root_path` (the canonical surface) and renamed accordingly. The legacy `end-run-page-confirm` modal id is gone with the deleted `/runs` view; the dashboard surface keeps the `end-run-dashboard-confirm` id (Step 20 distinct-id precedent). New test: `/runs redirects to root_path with #runs anchor` (`assert_response :moved_permanently`; `assert_equal "http://www.example.com/#runs", response.redirect_url`). Existing `dashboard RUNS tab END RUN trigger uses a distinct modal id from /runs` sanity test preserved. |
| `handoff/BUILD-LOG.md` | Step 24 added to Step History; Current Status updated; Step 23 → "Status archive"; Step 21 archive removed (one-step lookback) | Step 24 entry matches Step 23's level of detail: status, all locked architecture decisions (12 decisions), test count delta (+22), file inventory with line counts, full 22-test breakdown, backward-compat invariants, diff scope, KG-39 logged. |
| `handoff/REVIEW-REQUEST.md` | this file | New. |

---

## Decisions made (lookups + interpretations)

These came up during the build pass and were resolved without churn.

1. **CAUGHT/ALIVE labeling inversion** — pre-Step-24 the title bar showed `@caught_count` next to "CAUGHT" and `@caught_count - @dead_count` next to "ALIVE", which read as inverted (the controller's `@caught_count` is `count(&:caught?)` = currently-alive). Mockup locks the conventional reading: CAUGHT = total ever caught (alive + dead); ALIVE = currently alive. Fixed inline in the title bar partial without changing controller semantics (`@caught_count + @dead_count` for CAUGHT, `@caught_count` for ALIVE). Documented in the view with a WHY comment.
2. **`run-management` controller hoisted to dashboard root.** The brief said the `+ START NEW RUN` button "wires to `run-management#startRun`". The simplest path: hoist `data-controller="run-management"` from `_runs_content.html.erb` to the dashboard root in `show.html.erb`. This avoids spawning two ActionCable subscriptions when both surfaces (title-bar pill + RUNS tab panel) are on the page; one shared subscription services both. Removed the now-redundant inner wrapper from `_runs_content`.
3. **Stimulus controller registration is automatic.** The brief listed `app/javascript/controllers/index.js` under Files Bob will touch; verified it uses `eagerLoadControllersFrom("controllers", application)` with `pin_all_from "app/javascript/controllers"` in `config/importmap.rb`. The 2 new controllers are picked up without manual edit. No change needed to `index.js`.
4. **301 vs 302 for `/runs` redirect.** Brief offered Bob's pick. Chose `:moved_permanently` (301) — this is a permanent IA decision and search engines / social previews benefit from learning the new URL. No CSRF/session issue surfaced in test runs; sticking with 301.
5. **`emulator_status` is computed, not stored.** The model's `emulator_status` returns `:none` when sessions are empty, `:failed` when any session has `status: "failed"`, `:generating` when any is pending/generating, `:ready` when all ready. To exercise the `:failed` path in tests, the test creates `:soul_link_emulator_session, status: "failed"` (no factory trait for this — used inline string). Verified.
6. **`button_to gym_drafts_path` for the START GYM DRAFT CTA in the GYMS sub-tab** matches the existing pattern in `_gyms_content.html.erb:9` (also `button_to gym_drafts_path, method: :post`). Same surface, same behavior — just placed in the right rail too. The `.draft-cta` styling lives on the inner `<button>` element via `class:`. The `form: { style: "margin: 0;" }` flattens the wrapper form's default block layout.
7. **Tab-bar activation on focus move (mockup spec)**, not WAI-ARIA-strict (focus-only with Enter/Space to activate). Mockup explicitly says "←/→ moves between tabs (with wrap), updates `aria-selected` and `tabindex` immediately, **and activates the tab**." If a follow-up wants strict WAI-ARIA, drop `target.click()` from `tablistKeydown` — single line.
8. **HOF pill conditional simpler than mockup nuance.** Mockup screen 2 shows "BOB 🏆 HOF" alongside `8 BADGES`. Brief said: "show only if `@run.completed? && badge count == 8`" as the simpler-MVP read. Implemented exactly. Per-player HOF state is a future feature (KG-39 covers per-player badge variance broadly).

---

## Test list (18 new in `dashboard_redesign_test.rb`)

1. `.dash-r1` wrapper renders with dashboard + pixeldex + run-management controllers attached (3-controller assertion in any order).
2. Title-bar renders with the run-pill replacing the legacy `<select>` — no inline `onchange="window.location.href"`; `<button class="run-pill">` + `data-controller="run-picker"` + `aria-haspopup="listbox"` + `data-run-picker-target="trigger"` all present.
3. Title-bar stat-strip renders 4 inline items (CAUGHT/ALIVE/DEAD/BADGES) with values from a seeded run (1 alive + 1 dead → CAUGHT 2 / ALIVE 1 / DEAD 1 / BADGES 0/8) and the correct CSS modifiers (`.alive`, `.dead`, `.badges`).
4. Tab-bar renders with `role="tablist"` + `aria-label="Dashboard sections"` + per-tab `role="tab"` + `id="tab-<key>"` + `aria-controls="panel-<key>"` for all 7 keys.
5. Active tab has `aria-selected="true"` + `tabindex="0"`; others have `aria-selected="false"` + `tabindex="-1"`. Scoped to the main tab-bar (right rail also uses `role="tab"`).
6. PC BOX tab carries a `<span class="badge-dot">` when `@auto_detected_catches.any?`.
7. PC BOX tab does NOT carry a badge-dot when no auto-detected catches exist.
8. GYMS tab carries a badge-dot when an active draft exists.
9. Right status rail renders `<aside class="status-rail" data-controller="status-rail">` with 3 sub-tabs (PARTY/GYMS/MAP).
10. GYMS sub-tab is the default-active (exactly one `aria-selected="true"` under the rail; key is "gyms").
11. GYMS sub-tab renders the START GYM DRAFT CTA when `@next_gym && !dashboard_read_only?(@run)`.
12. GYMS sub-tab does NOT render the START GYM DRAFT CTA in read-only mode (wiped run); shows "RUN ENDED" state instead.
13. PARTY sub-tab renders one `.player-card` per registered player (4 in test settings).
14. Current user's PARTY sub-tab row has `class="player-card you"` and the YOU pill.
15. RUNS tab includes the Generate Emulator ROMs button when `emulator_status == :none`.
16. RUNS tab includes the Regenerate ROMs button when `emulator_status == :failed`.
17. RUNS tab does NOT include the legacy `/runs` page selector (no `RUN MANAGEMENT` heading).
18. `/runs` redirects to `root_path` with `#runs` anchor (status 301 or 302).

Plus 4 new in `responsive_grids_test.rb` (Step 21/22/23 pattern):
- `.dash-r1` declared outside any media block.
- 900px breakpoint sets `.dash-r1 .pc-layout { grid-template-columns: minmax(0, 1fr) 280px; }` and `.dash-r1 .col-party { display: none; }`.
- 720px breakpoint drops `.dash-r1 .pc-layout` to `1fr` and sets `.dash-r1 .tab-bar { overflow-x: auto; }`.
- 520/720/900px breakpoints do NOT set `display: none` on `.dash-r1 .tab` or `.dash-r1 .status-rail`.

Plus the `confirm_modal_flow_test.rb` rewrite (5 tests now — 4 dashboard surface, 1 redirect).

---

## Backward-compat invariants exercised

- `DashboardController#show` instance variables preserved verbatim (controller's `@caught_count`, `@dead_count`, `@gyms_defeated` semantics unchanged); only `@all_player_teams` added (additive).
- `_party_panel.html.erb` (left-col party panel), `_party_detail.html.erb` (PARTY main-tab), `_pc_box_content.html.erb`, `_map_content.html.erb`, `_gyms_content.html.erb`, `_strategy_panel.html.erb`, `_calc_content.html.erb`, `_catch_modal.html.erb`, `_pokemon_modal.html.erb`, `_mark_dead_modal.html.erb`, `_reset_draft_modal.html.erb` all unchanged. The existing tab content + modals render inside the new shell exactly as before.
- `pixeldex_controller.js` actions all preserved verbatim: `switchTab`, `selectPokemon`, `searchSpecies`, `savePokemon`, `evolvePokemon`, `updateNatureLabel`, `closePokemonModal`, all `#initSortables` / `#onDragEnd` / `#saveTeamSlots` / `#updateGroupStatus` / `#openModal` / `#applyHashTab` private helpers. Targets all preserved. Only additions: `tablistKeydown`, `numericJump` actions; `switchTab` body extended (still backward-compat — legacy `.active` class still toggled).
- `run_management_controller.js` action surface unchanged. Targets unchanged. Hoisting the `data-controller` to the dashboard root means a single controller instance services both the title-bar pill and the RUNS tab panel; only one ActionCable subscription per dashboard load. No lifecycle subtleties — Stimulus's `connect()` runs once when the wrapper is connected.
- `dashboard_controller.js` action surface unchanged.
- `pc_box_redesign_test`, `map_redesign_test`, `wipe_flow_test`, `gym_draft_test`, all model/service/job tests unaffected — full suite green at 777.

---

## Open questions / escalations

None. The brief was complete + unambiguous; the only ambiguities (HOF pill semantics, per-player badge variance, run-pill switching mechanism) were architect-decided in the brief itself and implemented per the answers.

---

**Test count:** 755 → **777** (+22). 0 failures, 0 errors.
**Lint:** rubocop clean (202 files, 0 offenses; +2 files for new Stimulus controllers).
**Brakeman:** Clean (no new warnings; same 2 pre-existing weak-confidence warnings unchanged from Steps 18-23).
**Migrations:** None. **Zero new gem deps. Zero new design tokens. Zero new model/service/job/channel/config code.**

**Ready for Review: YES**

---

## Should Fixes resolved (post-review, inline-applied — 2026-05-05)

Richard's review (`handoff/REVIEW-FEEDBACK.md`) cleared Step 24 with **0 Must Fix** and **4 Should Fix**. All four were ≤5-min surgical fixes per BUILDER.md Pt. 6, applied inline before deploy gate. Suite still **777 / 0 failures**; rubocop clean (202 files, 0 offenses); brakeman clean (same 2 pre-existing weak-confidence warnings, unchanged).

1. **`app/views/dashboard/_title_bar.html.erb:81`** — Run-option `<a class="run-option">` `tabindex="0"` → `tabindex="-1"`. The WAI-ARIA listbox pattern keeps options out of the page Tab order; `run_picker_controller.js`'s `open()` handler already routes focus into the first option, and `navigate()` handles roving focus via Arrow/Home/End. Tab through the page no longer walks every run.
2. **`app/views/dashboard/_title_bar.html.erb:94-100`** — Added `role="option"` + `aria-selected="false"` to the `+ START NEW RUN` `<button>`, and matched the `tabindex="-1"` change above. A screen reader walking the `role="listbox"` children no longer skips the start-new affordance.
3. **`app/javascript/controllers/run_picker_controller.js:81`** — Fixed the ArrowUp / ArrowDown edge case when `currentIndex === -1` (trigger has focus, no option focused yet). Added a guard at the top of each branch: ArrowUp lands on the last option (was: `n - 2`, second-to-last); ArrowDown lands on the first option (was: works by accident from the modulo, made explicit). Comments document why.
4. **`app/views/dashboard/_status_rail.html.erb:155-158`** — Dropped the `form: { style: "margin: 0;" }` arg from the `button_to "START GYM DRAFT →"` call. Added `.dash-r1 .next-battle form { margin: 0; }` to `pixeldex.css` (in the existing `.dash-r1 .next-battle` namespaced block at line 2411). Audit cross-cutting #5 (inline styles) — the redesign now has zero inline styles in the new partials.

No backend / model / controller / migration / test changes. View + Stimulus + CSS edits only. Test suite re-run after fixes: **777 runs, 0 failures, 0 errors**.
