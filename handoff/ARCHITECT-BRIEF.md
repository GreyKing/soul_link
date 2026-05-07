# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 28 — Rebuild the dashboard against `designs/04-pixeldex.html`

**Reference spec**: `handoff/2026-05-06-pixeldex-source-extraction.md` (extraction + diff). Architect drafted Halves 1 + 2 there. Bob does Half 3.

**Scope**: dashboard-only visual rebuild. Functional behaviour preserved verbatim from Steps 20–27. Backend untouched.

**Out of scope**:
- Save Slots, PC Box content (`_pc_box_content.html.erb`), Map content (`_map_content.html.erb`) — Step 22/23 R2/R4 surfaces, restyled in Step 27, leave alone.
- New features.
- Backend or controller changes.

---

### Files in scope

| File | Change |
|---|---|
| `app/views/dashboard/_title_bar.html.erb` | Rebuild stat-strip layout to render value-above-label per PixelDex source (DOM order stays — see directives) |
| `app/views/dashboard/_tab_bar.html.erb` | Rename `class="tab"` → `class="tab-item"`; rename inner `<span class="icon">` → `<span class="tab-icon">`. ARIA + targets stay |
| `app/views/dashboard/_status_rail.html.erb` | Replace vertical `.side-tabs` stack with a horizontal mini `.tab-bar` of `.side-tab-item` cells; keep all ARIA + `data-status-rail-*` targets |
| `app/views/dashboard/show.html.erb` | Wrap left col `_party_panel` render in a `<div class="panel">` shell (or move to direct render — `_party_panel` already provides `.panel`); remove `class="col-party"` if redundant. Verify center `<div class="panel">` wrapper stays |
| `app/assets/stylesheets/pixeldex.css` | All visual change happens here under `.dash-r1` namespace. No edits outside `.dash-r1` (lines ~2155–2603) — the canonical primitives at `:root`-level (lines ~1–520) already match source |

---

### Build directives

#### D1 — Title bar (`.dash-r1 .title-bar` + ERB)
- Add the PixelDex `--d2` band: `background: var(--d2); color: var(--l2); border-bottom: var(--border); padding: 10px 20px; display: flex; align-items: center; justify-content: space-between; flex-shrink: 0`. Drop `margin-bottom`.
- Inside the bar: keep `.title-left` (title-block + run-pill-wrap inline). Add a new flex group `.title-right` containing the stat-strip.
- `.title-block .player`: keep 18 px, but recolor to `var(--l2)` so it pops on the `--d2` band. Letter-spacing 0.08em.
- `.title-block .meta`: keep 11 px, recolor to `var(--l1)` (already correct). Letter-spacing 0.05em.
- **Stat-strip rebuild (CSS only — DOM stays)**: keep ERB markup of `<div class="stat-strip"><div class="item"><span>LABEL</span><span class="val">N</span></div>...</div>`. In CSS:
  - `.dash-r1 .stat-strip { display: flex; gap: 16px; }` (was `align-items: baseline; flex-wrap: wrap; gap: var(--s-3)`).
  - `.dash-r1 .stat-strip .item { display: flex; flex-direction: column-reverse; align-items: center; gap: 0; text-align: center; }` (column-reverse renders `.val` on top, label below — visual rhyme with PixelDex `.title-stat`).
  - `.dash-r1 .stat-strip .item .val { font-size: 21px; color: var(--l2); }` (was 11 px).
  - `.dash-r1 .stat-strip .item span:first-child { font-size: 11px; color: var(--l1); letter-spacing: 0.05em; }` (the LABEL span — first in DOM, rendered below via column-reverse).
  - `.dash-r1 .stat-strip .sep { display: none; }` — drop the `·` separators, the gap does the spacing visually. (ERB still emits them for accessibility / future toggle; hidden via CSS.)
- **Run-pill restyle (CSS only — DOM stays)**: rebase to a "label-on-d2-band" form so it reads as part of the title bar, not as a stamped-on button.
  - `.dash-r1 .run-pill { background: transparent; color: var(--l2); border: none; border-bottom: 2px solid var(--l1); padding: 4px 6px; font-size: 11px; }` (was `--l1` bg + `border-thin` + `--d1` text).
  - `.dash-r1 .run-pill:hover { background: rgba(155, 188, 15, 0.15); color: var(--l2); }` (subtle, no full bg flip).
  - `.dash-r1 .run-pill .chev { color: var(--l1); }`.
  - Dropdown menu (`.run-pill-menu`) untouched — opens correctly against the button.
- Responsive: `@media (max-width: 720px)` keep current `flex-direction: column; align-items: flex-start` fallback. Add stat-strip-on-its-own-row form (already in CSS).

#### D2 — Tab bar (`.dash-r1 .tab-item` + ERB)
- ERB rename in `_tab_bar.html.erb`:
  - `class="tab<%= ' active' if tab[:active] %>"` → `class="tab-item<%= ' active' if tab[:active] %>"`.
  - Inner glyph: `<span class="icon" aria-hidden="true"><%= tab[:icon] %></span>` → `<span class="tab-icon" aria-hidden="true"><%= tab[:icon] %></span>`.
- ARIA, `data-action="click->pixeldex#switchTab"`, `data-pixeldex-target="tabButton"`, `data-tab=...`, `id`, `aria-controls`, `aria-selected`, `tabindex` — all stay.
- CSS rename in `pixeldex.css`:
  - All `.dash-r1 .tab { ... }` rules → `.dash-r1 .tab-item { ... }`.
  - All `.dash-r1 .tab:hover`, `.dash-r1 .tab[aria-selected="true"]`, `.dash-r1 .tab:last-child` → `.tab-item` versions.
  - `.dash-r1 .tab .icon { ... }` → `.dash-r1 .tab-item .tab-icon { display: block; font-size: 20px; margin-bottom: 4px; line-height: 1; }` (block-above form per source).
- Tab cell becomes 2-line stacked: 20 px icon row + 13 px label row. Active state colour swap unchanged (bg `--d1`, color `--l2`).

#### D3 — 3-col layout (`.dash-r1 .pc-layout`)
- Drop `gap: 14px`; set `gap: 0`.
- `background: transparent` → `background: var(--l2)`.
- `margin-top: 14px` → `margin-top: 0` (let title-bar + tab-bar sit flush above).
- Keep `grid-template-columns: 280px minmax(0, 1fr) 320px` (close enough to source's `300px`; the wider right column accommodates the sub-tab content).
- Add per-panel ink frame:
  - `.dash-r1 .pc-layout > .panel`, `.dash-r1 .pc-layout > .col-party`, `.dash-r1 .pc-layout > .status-rail { border-right: var(--border); }`.
  - `.dash-r1 .pc-layout > *:last-child { border-right: none; }`.
- `.dash-r1 .col-party` already wraps `_party_panel` (which provides `.panel` internally). Either (a) drop the `.col-party` wrapper and let `_party_panel`'s `.panel` div participate directly, or (b) keep `.col-party` and apply `border-right` to it — Bob's call. **Architect preference: option (a)** — render `_party_panel` directly and drop `.col-party`. Update `show.html.erb` accordingly. Less wrapping, matches source structure 1:1.
- Optional CRT inset overlay: add `.dash-r1 .pc-layout::after { content: ''; position: absolute; inset: 0; background: repeating-linear-gradient(0deg, transparent 0px, transparent 3px, rgba(15,56,15,0.025) 3px, rgba(15,56,15,0.025) 6px); pointer-events: none; z-index: 1; }` and `.dash-r1 .pc-layout { position: relative; }`. **Skip if the body-level scanline already covers this** — verify before adding to avoid double-overlay.

#### D4 — Right rail (`.dash-r1 .status-rail` + sub-tabs + cards)
- Drop the boxed outer container. Edit:
  - `.dash-r1 .status-rail { background: transparent; border: none; padding: 0; }` (was `bg --d1, border, padding 14px`).
- Restyle the sub-tab strip from a vertical caps-bar stack to a horizontal mini `.tab-bar`:
  - `.dash-r1 .side-tabs { display: flex; flex-direction: row; background: var(--d1); border-bottom: var(--border); margin-bottom: 0; gap: 0; }`.
  - `.dash-r1 .side-tab { flex: 1; background: var(--d2); color: var(--l1); border: none; border-right: 2px solid var(--d2); padding: 10px 8px; cursor: pointer; font-family: 'Press Start 2P', monospace; font-size: 13px; letter-spacing: 0.05em; text-align: center; transition: background 0.05s, color 0.05s; }`.
  - `.dash-r1 .side-tab:last-child { border-right: none; }`.
  - `.dash-r1 .side-tab[aria-selected="true"], .dash-r1 .side-tab:hover { background: var(--d1); color: var(--l2); }`.
- Each `.status-panel` becomes a flush sub-panel with a `.panel-header` cap. Add markup inside each `<section class="status-panel">` (in `_status_rail.html.erb`):
  - The existing `.h3-row` becomes a `.panel-header` div: replace `<div class="h3-row"><h3>...</h3><span class="count">...</span></div>` with `<div class="panel-header"><span>...</span><span class="panel-header-sub">...</span></div>`. (Class rename; same content.) Drop `.dash-r1 .status-panel .h3-row { ... }`, `.dash-r1 .status-panel h3 { ... }`, `.dash-r1 .status-panel .count { ... }` rules — replaced by the canonical `.panel-header` rules at `:root` level (already in `pixeldex.css` lines ~349–367).
  - Wrap each panel's body content in a `<div class="panel-body">` so padding + spacing match the rest of the dashboard's panels. Existing inner content (cards, gym-list, map-area) stays unchanged.

#### D5 — Cards inside the right rail
- **`.dash-r1 .player-card`**: rebase to PixelDex light-card form.
  - `background: var(--l1); color: var(--d1); border: var(--border-thin); margin-bottom: 8px; padding: 10px;` (was `--d2` bg + `--l2` text + `var(--border)` 3px).
  - `.dash-r1 .player-card .name { color: var(--d1); }` (was `--white`).
  - `.dash-r1 .player-card .badges-text { color: var(--d2); }` (was `--l1`).
  - `.dash-r1 .player-card.you { border-color: var(--accent); border-width: 2px; }` (keep accent affordance per Step 27 § 11.3, just on the lighter base).
  - `.dash-r1 .player-card .sprite-cell { background: var(--l2); border: 2px solid var(--d1); color: var(--d1); }` (was `--d1` bg + 1 px `--d0` border).
- **`.dash-r1 .gym-list .gym-row`**: rebase to PixelDex `.gym-list-item` form.
  - `display: flex; align-items: center; gap: 6px; font-size: 11px; padding: 4px 0; border-bottom: 1px solid var(--d2); line-height: 1.6;`. (Drop the `grid-template-columns: 24px 1fr auto` form.)
  - `.dash-r1 .gym-list .gym-row:last-child { border-bottom: none; }`.
  - `.dash-r1 .gym-list .gym-row .num { width: 14px; text-align: center; font-size: 13px; background: transparent; border: none; color: var(--d1); display: inline; padding: 0; }` (becomes a glyph slot mirroring `.gym-check` — markup tip: emit `★` for beaten, `▶` for next, `.` for upcoming, generated from the same row class).
  - `.dash-r1 .gym-list .gym-row.beaten .num::before { content: '★'; }` etc., OR just rewrite the ERB to emit the right glyph in `<div class="num">…</div>`.
  - `.dash-r1 .gym-list .gym-row .name { font-size: 11px; color: var(--d1); letter-spacing: 0.5px; }` (was `--white` 9 px).
  - `.dash-r1 .gym-list .gym-row.beaten .name { color: var(--accent); }` (keep accent rule).
  - `.dash-r1 .gym-list .gym-row.upcoming { opacity: 0.35; }` (PixelDex source uses opacity instead of grey text).
  - `.dash-r1 .gym-list .gym-row .lvl { color: var(--d2); font-size: 10px; margin-left: auto; }`.
- **`.dash-r1 .gym-list .gym-row.next`** (the next gym): rebase to `.gym-next-highlight` filled-bar form.
  - `background: var(--d2); color: var(--l2); padding: 6px 8px; margin: 4px -6px; font-size: 11px; border: none;` (replaces accent-bordered num cell).
  - `.dash-r1 .gym-list .gym-row.next .num { color: var(--l2); }`, `.dash-r1 .gym-list .gym-row.next .name { color: var(--l2); }`, `.dash-r1 .gym-list .gym-row.next .lvl { color: var(--l1); }`.
  - The pulseNext keyframes block stays as a no-op (Step 27 decision; already inert).
- **`.dash-r1 .next-battle`** (CTA block below the gym list): rebase to a `.route-card` skin so it harmonises.
  - `background: var(--l1); color: var(--d1); border: var(--border-thin); padding: 10px; margin-top: 8px; margin-bottom: 0;` (was `--d2` bg + dashed top divider).
  - `.dash-r1 .next-battle .label { color: var(--d2); font-size: 10px; letter-spacing: 0.1em; margin-bottom: 4px; }`.
  - `.dash-r1 .next-battle .leader { color: var(--d1); font-size: 13px; }`.
  - `.dash-r1 .next-battle .prep { color: var(--d2); font-size: 11px; }`.
  - `.dash-r1 .next-battle .draft-cta { background: var(--d1); color: var(--l2); border: var(--border-thin); padding: 8px 14px; font-size: 11px; ... }` — already correct (Step 27 form). Leave the rule as-is.
  - `.dash-r1 .next-battle .read-only { background: var(--d2); color: var(--l1); ... }` — already correct.
- **MAP sub-tab content**: already uses `.route-card`, `.badge-row`/`.badge-cell`, `.map-area`, `.dialog`. No changes needed.

#### D6 — `_status_rail.html.erb` markup updates
- Replace `<div class="h3-row"><h3>…</h3><span class="count">…</span></div>` (3 occurrences, one per sub-panel) with `<div class="panel-header"><span>…</span><span class="panel-header-sub">…</span></div>`.
- Wrap each sub-panel's body content in `<div class="panel-body">` (3 occurrences).
- ALL ARIA, controller targets, button wiring stays. The class rename is the only structural touch.

#### D7 — `show.html.erb` markup updates
- Drop the `<div class="col-party">` wrapper. Render `_party_panel` directly inside `.pc-layout`. (`_party_panel` already provides `<div class="panel">` internally.)
- Verify `.dash-r1 .col-party` rule exists and remove or keep as a no-op (no `.col-party` element will exist after this change). Bob's call; clean removal preferred.
- The center `<div class="panel">` wrapper stays.

---

### Tests

- **Existing tests must pass**:
  - `test/integration/dashboard_redesign_test.rb` (assertions: `.dash-r1` wrapper, run-pill controller wiring, stat-strip 4-item DOM, `.tab-bar` tablist with `role="tab"` + `aria-controls` + `aria-selected` + `tabindex`, badge-dot `*` text marker, `.status-rail` 3 sub-tabs, default-active GYMS, START GYM DRAFT CTA, RUN ENDED in read-only, `.player-card` count + `.you` modifier).
  - `test/integration/design_canon_test.rb` (Step 25 token references).
  - `test/integration/pc_box_redesign_test.rb`, `test/integration/map_redesign_test.rb` (Step 22 R2 / Step 23 R4 — should be untouched but verify).
  - `test/integration/dashboard_redesign_test.rb` line 60–65 already asserts `<div class="stat-strip">` and `<div class="item"><span>CAUGHT</span><span class="val">2</span>…` — keep ERB DOM structure exactly so this still passes.
  - `test/integration/dashboard_redesign_test.rb` line 73 asserts `<div class="tab-bar" role="tablist" aria-label="Dashboard sections"…` — `.tab-bar` container class stays. Tab cell button class CHANGES from `tab` to `tab-item` — no test asserts the cell class so this is safe.
- **Add one new assertion** in `dashboard_redesign_test.rb`: assert each tab cell carries `class="tab-item"` (or `class="tab-item active"`). Suggested test:
  ```ruby
  test "each dashboard tab cell uses the canonical .tab-item class (Step 28 PixelDex source spec)" do
    get root_path
    assert_response :success
    %w[party pcbox map gyms strategy runs calc].each do |key|
      assert_match(/<button[^>]*class="tab-item(?: active)?"[^>]*id="tab-#{key}"/m, response.body,
        "expected tab cell #{key} to use .tab-item class")
    end
  end
  ```

### Don't touch

- Token palette (`pixeldex.css` `:root` block).
- Canonical primitives at `:root` level (`.tab-bar`, `.tab-item`, `.tab-icon`, `.title-bar`, `.title-stat`, `.panel`, `.panel-header`, `.team-slot`, `.box-cell`, `.route-card`, `.gym-list-item`, `.gym-next-highlight`, `.dialog`) — already match source.
- `.pc-box-r2` rules (Step 22 R2 surface).
- `.map-r4` rules (Step 23 R4 surface).
- Stimulus controllers, helpers, models, controllers, routes.
- `design_canon.md` — no canon changes (the canon remains; this step makes the dashboard adhere to it more faithfully, but the token spec is unchanged).

### Standing rules

- Token discipline: grep before read. Don't re-read files already in context.
- Scope lock: out-of-scope items → BUILD-LOG Known Gaps.
- After Bob ships: write `REVIEW-REQUEST.md` with files + line ranges + open questions. Set `Ready for Review: YES`.

---

*Step 27 (Restyle the four Phase-2 redesigns to the legacy `gb-*` idiom) shipped, FF-merged at `9c83c8f`, pushed. Step 28 is the visual rebuild of the dashboard against `designs/04-pixeldex.html`. Reference spec: `handoff/2026-05-06-pixeldex-source-extraction.md`.*
