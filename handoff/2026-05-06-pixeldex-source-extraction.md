# PixelDex Source Extraction + Dashboard Diff
*Step 28 — Architect Halves 1 + 2.*
*Reference: `designs/04-pixeldex.html` (849 lines, committed 2026-04-05).*
*Current dashboard: post-Step-27 HEAD `52930f2` on `origin/main`.*

The PixelDex variant (`designs/04-pixeldex.html`) is the source-of-truth for the
project's visual idiom — its `:root` palette literally became the project's
`pixeldex.css` tokens. This document extracts the structural and visual spec
from that file and diffs the live dashboard against it. The diff drives the
Step 28 Bob brief.

---

## Half 1 — PixelDex source spec

### 1.1 Token palette (locked, already in the project)

| Token | Hex | Used for |
|---|---|---|
| `--d1` | `#0f380f` | body bg, panel borders, panel-header bg, scrollbar borders, X-mark on dead box-cells, hp-fill, dialog ::after |
| `--d2` | `#306230` | title-bar bg, hover bg, badge-earned bg, gym-next-highlight bg, type-text border, scrollbar thumb, "no coverage" header bg, route-detail color |
| `--l1` | `#8bac0f` | card bg (route-card, team-slot, box-cell, map-area), tab-item color, accent text on dark bg (panel-header-sub, title-stat-label, title-sub) |
| `--l2` | `#9bbc0f` | pc-layout bg, panel-header text, badge-empty bg, dialog bg, team-sprite bg, hp-bar bg, tab-item active text, "no coverage" pill text |
| `--white` | `#c6de8a` | declared but unused in the file body (project's `--white` overrides where needed) |

Border tokens: `--border = 3px solid var(--d1)`, `--border-thin = 2px solid var(--d1)`, `--border-double = 4px double var(--d1)`.

### 1.2 Top title bar (`.title-bar`)

```
[ ⚙ GREY's PC                                          [ 11   ] [ 8    ] [ 3   ] [ 5/8   ] ]
[   PLATINUM SOUL LINK · RUN #1                        [CAUGHT] [ALIVE ] [DEAD ] [BADGES ] ]
```

- 1-line horizontal bar, full-width.
- `background: var(--d2)`, `color: var(--l2)`, `border-bottom: var(--border)`.
- `padding: 10px 20px`. `display: flex; align-items: center; justify-content: space-between`.
- `flex-shrink: 0` (sticks to top of viewport when layout flexes).
- **Left**: `.title-left` (gap 12px) — `.title-logo` (18px emoji) + 2-line `.title-block` (`.title-text` 18px caps + `.title-sub` 13px `--l1` color, letter-spacing 0.05em).
- **Right**: `.title-right` (gap 16px) — 4× `.title-stat` blocks. Each stat: `.title-stat-num` (21px caps, `--l2` color) above `.title-stat-label` (11px caps, `--l1` color).
- Letter-spacing: `.title-text` 0.08em; `.title-sub` 0.05em.

### 1.3 Tab bar (`.tab-bar` + `.tab-item` + `.tab-icon`)

```
[  ▣      ▣       ⚛       ★       ⚙           ⚙          ∑    ]
[ PARTY  PC BOX   MAP    GYMS  STRATEGY      RUNS        CALC  ]
```

- 1-line horizontal strip below the title bar.
- `.tab-bar`: `display: flex; background: var(--d1); border-bottom: var(--border); flex-shrink: 0`.
- `.tab-item`: `flex: 1; padding: 10px 8px; text-align: center; font-size: 13px; color: var(--l1); background: var(--d2); border-right: 2px solid var(--d2); font-family: 'Press Start 2P'; transition: background 0.05s; letter-spacing: 0.05em`.
- `.tab-item:last-child { border-right: none }`.
- **Active and hover**: `background: var(--d1); color: var(--l2)` (identical treatment).
- `.tab-icon`: `display: block; font-size: 20px; margin-bottom: 4px` — **icon stacks ABOVE the label**, not inline-prefix.
- Tab cell visual: 2-line stacked (icon row + label row).

### 1.4 3-panel grid (`.pc-layout`)

- `flex: 1; display: grid; grid-template-columns: 280px 1fr 300px; min-height: 0; background: var(--l2);`
- **No `gap`**. Panels share borders.
- Each `.panel`: `border-right: var(--border); overflow-y: auto; scrollbar-width: thin; scrollbar-color: var(--d2) var(--l1)`.
- `.panel:last-child { border-right: none }`.
- Custom WebKit scrollbar: `width: 10px; track --l1; thumb --d2 with 2px --d1 border`.
- `::after` scanline overlay on `.pc-layout`: `position: fixed; inset: 0; repeating-linear-gradient(0deg, transparent 0px, transparent 3px, rgba(15,56,15,0.025) 3px 6px); pointer-events: none; z-index: 100`.
- Entrance animation: `.pc-layout { animation: screenFlash 0.3s ease-out }` — bg pulses from --d1 to --l2.

**Responsive**:
- `@media (max-width: 900px)`: single column (`grid-template-columns: 1fr`); `.panel` swaps `border-right` for `border-bottom`; `max-height: 500px` on each.
- `@media (min-width: 901px) and (max-width: 1200px)`: tighter grid (`240px 1fr 260px`).

### 1.5 Panel header (`.panel-header`)

- Sticky bar at top of each panel.
- `background: var(--d1); color: var(--l2); padding: 8px 12px; font-size: 13px; letter-spacing: 0.1em; position: sticky; top: 0; z-index: 5`.
- `display: flex; align-items: center; justify-content: space-between`.
- Left: caps title (e.g. `PARTY`, `PC BOX - ALL POKEMON`, `MAP & GYMS`).
- Right: `.panel-header-sub` (`font-size: 10px; color: var(--l1)`) — count or subtitle (e.g. `6/6`, `11 TOTAL`, `SINNOH`).

### 1.6 Panel body cards

Three reusable card primitives, all on light backgrounds inside `.pc-layout`:

**`.team-slot`** (left rail row):
- `background: var(--l1); border: var(--border-thin); padding: 10px 8px; margin-bottom: 6px`.
- `display: flex; gap: 10px; align-items: center; cursor: pointer; transition: background 0.05s`.
- **Hover**: `background: var(--d2); color: var(--l2)` — and child colors cascade (`.team-nick` and `.team-types .type-text` border swap to `--l1`, `.team-slot-num` swaps to `--l1`).
- Children: `.team-slot-num` (18px `--d2` width 20px), `.team-sprite` (36×36 `--l2` bg w/ 2px ink border, 25px emoji), `.team-info` (flex 1 — `.team-name` 14px caps + `.team-nick` 10px `--d2` italic + `.team-types`), `.hp-bar` (56×8 with `--d1` border + `--l2` bg, fill `--d1`).

**`.box-cell`** (center grid):
- `aspect-ratio: 1; border: var(--border-thin); background: var(--l1); padding: 4px`.
- `display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px`.
- `cursor: pointer; transition: background 0.05s; position: relative`.
- **Hover**: `background: var(--d2); color: var(--l2)` (cascading on name + loc colours).
- Modifiers:
  - `.box-cell.dead`: `opacity: 0.4`; name `text-decoration: line-through`; `::after` `'X'` mark top-right `--d1`.
  - `.box-cell.empty`: `border-style: dashed; opacity: 0.3` (no content).
  - `.box-cell.on-team::before`: `'★'` mark top-left `--d1`.
- Children: `.box-cell-sprite` (35px line-1), `.box-cell-name` (9px caps letter-0.03em line-1.3), `.box-cell-loc` (8px `--d2` line-1.2).

**`.route-card`** (right rail card):
- `background: var(--l1); border: var(--border-thin); padding: 10px; margin-bottom: 8px`.
- Children: `.route-label` (10px `--d2` letter-0.1em), `.route-name` (15px caps), `.route-detail` (10px `--d2` line-1.8).

### 1.7 Box section labels (`.box-section-label`)

```
★ ON TEAM (6)
─────────────────
[ box-cell ][ box-cell ]...
```

- `font-size: 11px; color: var(--d2); padding: 6px 0 4px; letter-spacing: 0.08em; border-bottom: 2px solid var(--d2); margin-bottom: 8px`.
- Caps with optional inline glyph prefix (`★`).
- Acts as a divider WITHIN a panel-body — between sub-sections like ON TEAM / IN STORAGE / FALLEN.

### 1.8 Lists & rows

**Gym list (`.gym-list-item`)**:
- `font-size: 11px; padding: 4px 0; border-bottom: 1px solid var(--d2); display: flex; gap: 6px; line-height: 1.6`.
- `:last-child { border-bottom: none }`.
- `.gym-check` (14px wide, 13px font) — `★` for beaten, `.` for upcoming.
- Future entries: `opacity: 0.35` directly on the row.

**Gym next highlight (`.gym-next-highlight`)**:
- A FILLED ROW within the gym list (not a separate panel).
- `background: var(--d2); color: var(--l2); padding: 6px 8px; margin: 4px -6px; font-size: 11px`.
- Same dark-fill treatment as `.tab-item.active` — visual rhyme.

**Stat row (`.stat-row`)**:
- `display: flex; justify-content: space-between; padding: 3px 0; font-size: 11px; border-bottom: 1px dotted var(--d2)`.
- `.stat-val` 14px.

### 1.9 Type pill (`.type-text`)

- `font-size: 10px; display: inline-block; padding: 1px 4px; border: 2px solid var(--d2); margin: 0 1px; line-height: 1.6`.
- Text inside is the 3-letter abbrev (FIR, WTR, GRS, ELC, etc.).
- Special "no coverage" variant: `border-color: var(--l1)` for emphasis on dark `--d2` bg.

### 1.10 Badge row (`.badge-row` + `.badge-cell`)

- `display: grid; grid-template-columns: repeat(4, 1fr); gap: 6px`. (Project uses 8-col for 8 gyms.)
- `.badge-cell`: `aspect-ratio: 1; border: var(--border-thin); display: flex; align-items: center; justify-content: center; font-size: 20px`.
- `.badge-earned`: `background: var(--d2); color: var(--l2)`.
- `.badge-empty`: `background: var(--l2); color: var(--d2); font-size: 13px` (showing `...`).

### 1.11 Map area (`.map-area`)

- `background: var(--l1); border: var(--border-thin); padding: 10px; margin-bottom: 8px`.
- `font-size: 9px; line-height: 1.4; color: var(--d2); white-space: pre; overflow-x: auto`.
- `.map-you` inside: `color: var(--d1); font-weight: bold`.

### 1.12 Dialog (`.dialog`)

- `border: var(--border-double); background: var(--l2); padding: 10px 12px; margin-top: 10px; font-size: 13px; line-height: 1.8; position: relative`.
- `::after`: `'▼'` blinker at `bottom: 6px; right: 10px; font-size: 10px; animation: dialogBlink 1s step-end infinite`.
- Used at the end of the left rail and right rail to surface NPC-style strategy hints.

### 1.13 Color application rules (audit)

- **`--d1` (darkest)** appears as: panel-header background, panel borders (the structural frame), body background, hp-fill (the bar's filled portion), the `X` mark on dead box-cells, the `★` on on-team box-cells, the `▼` dialog blinker. **It is the structural ink — never decorative.**
- **`--d2` (mid-dark)** appears as: title-bar background, hover state for cards, type-text border, dotted/solid dividers inside cards, scrollbar thumb, route-detail/secondary text, badge-earned background, gym-next-highlight background. **It is the secondary surface — used sparingly to mark hover, mid-emphasis dividers, or "this row is the active one" highlight.**
- **`--l1` (mid-light)** appears as: card background (team-slot, box-cell, route-card, map-area), tab-item resting color, panel-header-sub text (sub-info on dark bg), title-sub/title-stat-label text. **It is the primary card surface and dim accent text.**
- **`--l2` (lightest)** appears as: pc-layout body background, panel-header text, badge-empty background, dialog background, team-sprite background, hp-bar background, tab-item active text. **It is the foreground / "things light up to say I'm active" colour.**
- **No accent colour** in the source. The "active state" pattern is `bg=--d1, color=--l2` (or `bg=--d2, color=--l2` for hover/highlight) — purely a light/dark inversion within the green palette.

### 1.14 Typography reference

All text is `'Press Start 2P', monospace`. Sizes used:

| px | Where |
|---|---|
| 8 | `.box-cell-loc` |
| 9 | `.box-cell-name`, `.map-area`, sub-text in highlight |
| 10 | `.title-stat-label`, `.panel-header-sub`, `.type-text`, `.team-nick`, `.route-label`, `.route-detail` |
| 11 | `.gym-list-item`, `.box-section-label`, `.stat-row`, `.title-stat-label`, `.gym-next-highlight`, `.dialog` (left rail/right rail variant) |
| 13 | `.panel-header`, `.tab-item`, `.title-sub`, `.gym-check`, `.dialog` (default), "no coverage" caps |
| 14 | `.team-name`, `.stat-val` |
| 15 | `.route-name` |
| 18 | `.title-logo`, `.title-text`, `.team-slot-num` |
| 19 | body |
| 20 | `.tab-icon`, `.badge-cell` |
| 21 | `.title-stat-num` |
| 25 | `.team-sprite` (emoji glyph) |
| 35 | `.box-cell-sprite` (emoji glyph) |

Letter-spacing: 0.03em on `.team-name` / `.box-cell-name`; 0.05em on `.tab-item` / `.title-sub`; 0.08em on `.title-text` / `.box-section-label`; 0.1em on `.panel-header` / `.route-label`.

### 1.15 Animations & motion

- `screenFlash 0.3s ease-out` on `.pc-layout` entrance only (one-shot).
- `dialogBlink 1s step-end infinite` on the `.dialog::after` `▼` glyph.
- All hover/active state changes: `transition: background 0.05s` (or `0.05s` on individual properties).
- **No translate, no glow, no pulse, no shadow animations.** Visual feedback = bg/colour swap on a single frame.

---

## Half 2 — Diff vs current dashboard (post-Step-27 `52930f2`)

### Surface map

| PixelDex element | Current dashboard | Verdict |
|---|---|---|
| `.title-bar` (1-line, --d2 bg, ink border-bottom, padding 10/20, flex space-between) | `.dash-r1 .title-bar` (no bg, no border, just `margin-bottom`) — 2-line text + run-pill + dim stat-strip flowing inline | **DRIFT** |
| `.title-left` with `.title-logo` + `.title-block` (player + meta) | `.title-left` with `.title-block` only (logo dropped Step 27) + run-pill-wrap inline | **PARTIAL DRIFT** — keep logo dropped (Step 27 decision); add `--d2` band around the bar |
| `.title-right` 4-stat block grid (CAUGHT / ALIVE / DEAD / BADGES, num-on-top label-below) | `.stat-strip` dim 1-line `--l1` text inline at top-right | **DRIFT** — rebuild as 4 stacked stat blocks |
| `.tab-bar` (--d1 container, ink border-bottom, flex space-between with each tab `flex: 1`) | `.dash-r1 .tab-bar` (matches container — bg --d1, border-bottom --border, flex) | **MATCH** at the container level |
| `.tab-item` class name | `.tab` class name | **DRIFT (cosmetic)** — rename to `.tab-item` to match source |
| `.tab-icon { display: block; font-size: 20px; margin-bottom: 4px }` (icon stacks above label) | `.dash-r1 .tab .icon { display: inline; font-size: inherit; margin-right: var(--s-1) }` (icon inline-prefix in label) | **DRIFT** — rebuild to 2-line stacked (icon block above label, 20px glyph) |
| `.tab-item.active { bg: --d1, color: --l2 }` | `.dash-r1 .tab[aria-selected="true"] { bg: --d1, color: --l2 }` | **MATCH** at the active-state level |
| `.pc-layout { grid: 280px 1fr 300px; gap: 0; bg: --l2 }` + per-panel ink `border-right` | `.dash-r1 .pc-layout { grid: 280px 1fr 320px; gap: 14px; bg: transparent }` — no shared frame, gapped boxes | **DRIFT** — drop gap, swap bg to --l2, add `border-right` to panels |
| `.pc-layout::after` scanline overlay | None (the body-level scanline overlay exists but it's separate; the per-pc-layout one isn't there) | **ABSENT** — add the inset overlay so the dashboard reads as a CRT screen |
| `.panel-header` (sticky `--d1` cap on each panel) | Center column has it (`_pc_box_content` panel-header etc.); left col `_party_panel.html.erb` has it (rendered in `.col-party`); right rail `_status_rail.html.erb` does NOT have a unified `.panel-header` | **PARTIAL DRIFT** — right rail needs a unified `.panel-header` instead of the multi-row `.side-tabs` cap-bar stack |
| Right rail outer container | `.dash-r1 .status-rail { bg: --d1, border: var(--border), padding: 14px }` — boxed | **DRIFT** — drop the outer box; the rail should match the other panels (no extra wrapper, just a `.panel` with sticky `.panel-header`) |
| Right rail sub-tabs (PARTY · GYMS · MAP) | `.dash-r1 .side-tabs` vertical stack of full-width `--d1`-bg caps bars (Step 27 form) | **DRIFT — STRUCTURAL KEEP / VISUAL REBUILD** — preserve WAI-ARIA tablist + controller targets (Step 24); rebuild visual to a horizontal mini `.tab-bar` at top of the rail panel, immediately above a single sticky `.panel-header` for the active sub-tab |
| `.player-card` (in PARTY sub-tab) | `--d2` bg + `var(--border)` 3px ink border + `--l2` text — dark card | **DRIFT** — rebase to `.route-card` light-card form (`--l1` bg + `--border-thin` 2px) |
| `.gym-list .gym-row` (in GYMS sub-tab) | grid-row with custom `.num` chip + `.name` + `.lvl`, dashed `--d2` divider | **PARTIAL DRIFT** — visual treatment differs from PixelDex's `.gym-list-item` (8-col solid divider, `.gym-check` glyph prefix, `.gym-next-highlight` filled bar). Rebuild row markup to use canonical `.gym-list-item` + `.gym-next-highlight` primitives |
| `.next-battle` block (post Step 27) | `--d2` bg subdued block with dashed top divider, `.draft-cta` button | **PARTIAL DRIFT** — rebuild as `.gym-next-highlight` filled bar style for the leader/loc/lvl line, with the CTA button below. Or: keep the block but skin it as a `.route-card` so it harmonises with the rest of the rail |
| `.route-card` (CURRENT LOCATION, BADGE CASE, RECENT ROUTES, GYM LEADERS) | Already used in `_status_rail.html.erb` MAP sub-tab | **MATCH** — leave alone |
| `.dialog` (right-rail strategy line, left-rail team line) | Already used in `_party_panel`, `_party_detail`, `_map_content`, `_status_rail` MAP panel | **MATCH** — leave alone |
| Banner / mode chrome | None on the dashboard (the brief lists "banner" — confirmed absent on this surface; banners live on `_save_slots_sidebar` and `_pc_box_content`'s `.empty-tray-bar`, both out of scope) | **N/A** |
| Active run indicator | `.run-pill` ("RUN #2 — ACTIVE ▾") clickable, `--l1` bg + ink border (gb-btn form) | **PARTIAL DRIFT** — PixelDex source has run number shown only as static `.title-sub` text. Run-pill is functional value (run-switching dropdown, START NEW RUN). **Keep functional, restyle so it sits inline within the title-bar's `--d2` band** — make the pill `--l2`-text `--d2`-bg-transparent so it reads as part of the title bar rather than as a button bolted on |
| `.col-party` (compact left rail) | Renders `_party_panel.html.erb` (already correct PixelDex `.panel` form) | **MATCH** at the partial level — but the wrapper `.col-party` div needs to become a `.panel` (no extra div) so the shared frame works |
| Center column wrapper | `<div class="panel">` already correct | **MATCH** |
| Center column `.panel-header` | Each tab content provides its own panel-header (`_pc_box_content` etc.) | **MATCH** |

### Cross-cutting drift summary

1. **Outer chrome doesn't read as PixelDex**: title-bar lacks the `--d2` band, tabs are single-line not stacked, the 3-col grid is gapped + transparent (looks like 3 separate widgets), and the right rail is a boxed inset rather than a flush panel. Fixing these four things alone gets the dashboard 80% of the way back.
2. **Right-rail card aesthetic is dark, source is light**: `.player-card` and `.gym-row` use `--d2` dark cards; the source uses `--l1` light cards. This is the single biggest "feels different" gap.
3. **Tab-bar icon orientation**: source stacks icon above label (2-line cell ~50 px tall); current is single-line. The 2-line stacked form is signature PixelDex.
4. **Sub-tabs visual hierarchy**: source has no sub-tabs (one `.panel-header`); current has 3 stacked caps bars (Step 27 form). Step 24's structural sub-tab content is functional value (consolidates duplication) — but its visual form should mimic the main tab-bar (horizontal mini tab strip), so the rail reads as "a smaller version of the main 3-panel layout".
5. **Stat strip vs stat blocks**: source has 4 right-aligned vertical stat blocks; current has a dim 1-line text strip. Source form is much more visually distinctive and reinforces the title bar as a real chrome row.

### Cross-cutting matches (leave alone)

- All inner panel content partials (`_party_panel`, `_party_detail`, `_pc_box_content`, `_map_content`, `_gyms_content`) already use the canonical PixelDex primitives (`.panel-header`, `.box-grid`, `.box-cell`, `.route-card`, `.gym-list-item`, `.gym-next-highlight`, `.dialog`).
- Body-level CRT scanline overlay (in `pixeldex.css` `:root`-scoped section) already exists.
- `--d1`/`--d2`/`--l1`/`--l2` tokens are pinned and untouched.
- `.tab-bar` container styling matches source.
- `.tab[aria-selected="true"]` active-state colour swap matches source.
- The Step 25 `design_canon_test.rb` token references are intact.

### Functional-value items to preserve through the rebuild

| From | What | Why |
|---|---|---|
| Step 20 | ARIA modal contracts, confirm-modal partial, `gb-grid` breakpoint | safety net; tests assert it |
| Step 21 | save-slots state pills + overwrite-pending mode + inline DELETE | other surface, already stable |
| Step 22 | PC Box filter chips + URL hash + per-row actions + badge legend | Step 22 R2 surface inside the dashboard's PC BOX tab — keep as-is |
| Step 23 | Map clickable locations + catch-pre-fill modal + pulse-ring | Step 23 R4 surface inside the dashboard's MAP tab — keep as-is |
| Step 24 | WAI-ARIA tablist (`role="tab"`, `aria-controls`, `aria-selected`, arrow keys), run consolidation, sub-tab controller targets | structural foundation — chrome rebuilds visual only |
| Step 25 | design canon tokens | tests assert it |
| Step 26 | `--accent` = `--green-glow` | keep; PixelDex source has no accent so accent appearances stay rare |
| Step 27 | chrome-reduction principles (banned primitives, ghost pills, no animations beyond `transition: 0.05s`) | apply throughout |

### Out-of-scope

- Save Slots sidebar (`_save_slots_sidebar.html.erb`) — restyled in Step 27, separate page.
- PC Box review tray + filter bar + box-grid inside the dashboard's PC-BOX tab — Step 22 R2 / Step 27, internal styling untouched. Only its outer `<div class="pc-box-r2">` lives within the new shared-frame `.panel`.
- Map content inside the dashboard's MAP tab — Step 23 R4 / Step 27.
- New features, backend changes.

### Known Gap candidates (raised during diff)

- **KG-A (potential)**: PixelDex source uses `.tab-item` as the class name on tab cells; current is `.tab`. Rebuild renames to `.tab-item` for source-faithfulness, but other call sites (CSS, JS, tests) need to follow. If the rename is non-trivial we keep `.tab` and add a class alias `.tab-item` — flagged here so Bob can choose mechanically.
- **KG-B (potential)**: PixelDex source's right column has a single panel-header "MAP & GYMS" across the entire column; the rebuild keeps three sub-tabs (functional value from Step 24 consolidation). The visual rhyme is a horizontal mini tab-bar at the top of the rail panel. If user later prefers a single panel-header with vertical scroll and accordion sections, file as a follow-up step rather than expanding scope here.

---

## Spec → directives

The diff above produces a focused build list for Bob:

1. **Title bar**: `--d2` band; drop dim stat-strip; rebuild as PixelDex `.title-stat` block grid (4 stacked stat blocks, num-on-top label-below).
2. **Tab bar**: rename `.tab` → `.tab-item`; convert icon to `.tab-icon` block-above-label form (20 px glyph, 4 px margin-bottom); 2-line stacked tab cells.
3. **3-col layout**: drop the 14 px `gap`; swap `background: transparent` to `var(--l2)`; add `border-right: var(--border)` to each panel; remove `margin-top` (let title-bar + tab-bar live flush above).
4. **Scanline overlay**: add `.dash-r1 .pc-layout::after` per source spec (or scope the existing body overlay so it covers the dashboard area).
5. **Status rail**: drop the boxed `.dash-r1 .status-rail { bg --d1; border; padding 14px }` wrapper; make the rail a plain `.panel`. Rebuild `.side-tabs` from a vertical stack of full-width caps bars to a horizontal mini `.tab-bar` (canonical primitive) at the top of the rail panel, with a single sticky `.panel-header` showing the active sub-tab name + count below it.
6. **Right-rail cards**: rebase `.player-card` and `.gym-row` (and `.next-battle`) to PixelDex light-card form (`--l1` bg, `--border-thin` 2 px). Use `.gym-list-item` + `.gym-next-highlight` for the gym list.
7. **Run-pill**: keep functional (dropdown, START NEW RUN), but restyle to read as part of the title-bar's `--d2` band — transparent bg, `--l2` text, no extra border (or thin `--l1` underline) so it reads as a clickable label not a stamped-on button.
8. **Class structure preserved**: WAI-ARIA tablist contract, all data-controller/data-action/data-target hooks, all keyboard wiring, all turbo_stream / turbo_refreshes_with binding, all controller-side state.
9. **Tests**: existing dashboard_redesign_test must pass; add a new assertion that the rendered tab-bar uses the canonical `.tab-bar` container and `.tab-item` cells (regex match per Brief).

Bob runs the rebuild against this directive list. Anything ambiguous escalates back to Architect.
