# Review Request — Step 28
*Bob → Richard. Visual rebuild of the dashboard against `designs/04-pixeldex.html`.*

**Branch:** `claude/confident-kare-0d3dab`
**Builder:** Bob
**Status:** Ready for Review: YES

---

## Scope reminder

Step 28 is the dashboard's visual rebuild against the canonical PixelDex source spec
(`designs/04-pixeldex.html`). Functional behaviour preserved verbatim from Steps 20–27;
backend untouched; out-of-scope partials (`_pc_box_content`, `_map_content`,
`_save_slots_sidebar`) untouched. All work happens inside the existing `.dash-r1`
namespace block in `pixeldex.css` plus mechanical class-rename / wrapper-restructure
edits in 4 ERB views.

---

## Files changed

### `app/views/dashboard/_tab_bar.html.erb` — class rename + comment header
- **L1–14** comment header rewritten — Step 24 / Step 28 reference, describes the new
  block-above `.tab-icon` form and that the `aria-selected` / `tabindex` keyboard
  contract is preserved.
- **L33** `class="tab<%= ' active' if tab[:active] %>"` → `class="tab-item<%= ' active'
  if tab[:active] %>"` (per D2; PixelDex source class name).
- **L42** `<span class="icon" aria-hidden="true">` → `<span class="tab-icon"
  aria-hidden="true">` (per D2).

### `app/views/dashboard/_title_bar.html.erb` — wrap stat-strip in `.title-right` + comment header
- **L1–10** comment header rewritten — Step 28 reference, describes the new `--d2`
  band + `.title-right` flex group + column-reverse stat-strip.
- **L101–117** stat-strip wrapped in `<div class="title-right">` (per D1: "Add a new
  flex group `.title-right` containing the stat-strip"). DOM inside the strip is
  preserved exactly so the existing test assertion (each `<div class="item"><span>
  LABEL</span><span class="val">N</span></div>`) still matches.

### `app/views/dashboard/_status_rail.html.erb` — h3-row → panel-header, panel-body wraps, gym glyph
- **L57–67 / L116–122 / L181–186** the three `<div class="h3-row"><h3>…</h3>
  <span class="count">…</span></div>` blocks rewritten to `<div class="panel-header">
  <span>…</span><span class="panel-header-sub">…</span></div>` (per D6). Same content,
  canonical primitive class names so the canonical `:root`-level rules apply.
- **L69–110 / L124–168 / L188–243** each panel's body content wrapped in `<div class=
  "panel-body">` (per D6) so padding lines up with the rest of the dashboard's panels.
- **L137–149** gym-row markup updated to emit a glyph in the `.num` cell instead of a
  numeric label (per D5: "rewrite the ERB to emit the right glyph"). Glyphs: `★` for
  beaten rows, `▶` for the next row, `·` for upcoming rows. The numeric position is
  implicit in row order; the glyph carries the state.

### `app/views/dashboard/show.html.erb` — drop `.col-party` wrapper
- **L33–37** `<div class="col-party"><%= render "party_panel" %></div>` → `<%= render
  "party_panel" %>` (per D7 / Architect preference: option (a)). `_party_panel` already
  provides its own `<div class="panel">` shell, so the partial participates directly in
  `.pc-layout`'s 3-col grid.

### `app/assets/stylesheets/pixeldex.css` — `.dash-r1` block rebuilt (lines ~2155–2615)
All edits stay inside the `.dash-r1` namespace. Canonical primitives at `:root` level
(lines 1–520) untouched; out-of-scope namespace blocks (`.pc-box-r2`, `.map-r4`,
`gb-*`) untouched.

- **L2155–2166** section header comment updated — Step 28 reference + summary of the
  visual-rebuild deltas.
- **L2168–2195** `.dash-r1 .title-bar`: PixelDex `--d2` band + `--l2` text + 3 px ink
  border-bottom + `padding: 10px 20px` + flex space-between + `flex-shrink: 0`.
  `margin-bottom` dropped (the title bar now sits flush above the tab-bar). New rule
  `.dash-r1 .title-right { display: flex; align-items: center; gap: 16px; }`. Player
  caption recoloured to `--l2` to pop on the `--d2` band, letter-spacing 0.08em.
  Meta caption letter-spacing 0.05em.
- **L2197–2222** `.dash-r1 .run-pill`: rebased to label-on-d2-band form — transparent
  bg, `--l2` text, 2 px `--l1` underline as the affordance. Hover is a subtle
  semi-transparent green wash (`rgba(155, 188, 15, 0.15)`) instead of a full bg flip.
  Chevron coloured `--l1`. Run-pill-menu (`.run-pill-menu` and children, L2224–2284)
  unchanged — opens correctly against the new button.
- **L2285–2306** `.dash-r1 .stat-strip`: rebuilt to PixelDex `.title-stat` block grid
  form. `display: flex; gap: 16px;` (was `align-items: baseline; flex-wrap: wrap; gap:
  var(--s-3)`). Each `.item` is `flex-direction: column-reverse; align-items: center;
  gap: 0; text-align: center;` so the LABEL `<span>` (first in DOM) renders below the
  `.val` `<span>` (second in DOM) — matches PixelDex `.title-stat` num-on-top
  label-below visual without changing DOM. `.val` font-size 21 px `--l2`; LABEL span
  11 px `--l1` letter-spacing 0.05em. `.sep` separator `<span>`s hidden via CSS — gap
  does the spacing.
- **L2308–2343** `.dash-r1 .tab-bar` / `.dash-r1 .tab-item` / `.dash-r1 .tab-item .tab-
  icon`: rebuilt to the PixelDex 2-line stacked form. `.tab-bar` itself unchanged.
  `.tab-item` matches the canonical `:root`-level rule (--d2 bg, --l1 text, 13 px,
  `border-right: 2px solid --d2`, hover/active swap to --d1 bg + --l2 text).
  `.tab-icon` is `display: block; font-size: 20px; margin-bottom: 4px; line-height: 1;`
  so the icon stacks block-above the label. The legacy `.dash-r1 .tab` and
  `.dash-r1 .tab .icon` rule names removed — replaced by `.tab-item` and `.tab-icon`.
- **L2345–2367** `.dash-r1 .pc-layout`: `gap: 0` (was 14 px); `margin-top: 0` (was 14
  px); `background: var(--l2)` (was transparent). New shared-frame rule:
  `.dash-r1 .pc-layout > .panel, .dash-r1 .pc-layout > .status-rail
  { border-right: var(--border); }` and `.dash-r1 .pc-layout > *:last-child
  { border-right: none; }`. The optional `.pc-layout::after` scanline overlay is
  **skipped** — the body-level `body::after` overlay (lines 113–126,
  `position: fixed; inset: 0;` covers full viewport) already does this work, per D3's
  "Skip if the body-level scanline already covers this".
- **L2369–2405** `.dash-r1 .status-rail` flattened: `background: transparent; border:
  none; padding: 0;` (was `--d1` bg + 3 px border + 14 px padding). `.dash-r1
  .side-tabs` rebuilt as a horizontal mini `.tab-bar` with `--d1` bg + 3 px ink
  border-bottom. `.dash-r1 .side-tab` rebuilt as a `.tab-item`-sibling cell (--d2 bg,
  --l1 text, 13 px, 10/8 padding, flex 1). Active state and hover swap to --d1 bg +
  --l2 text (matches the main tab-bar's active rule). Legacy `.dash-r1 .status-panel
  .h3-row`, `.dash-r1 .status-panel h3`, `.dash-r1 .status-panel .count` rules deleted
  — replaced by the canonical `.panel-header` rules at root level.
- **L2407–2449** `.dash-r1 .player-card`: rebased to PixelDex light-card form (--l1
  bg, 2 px ink border, --d1 text). The `.you` accent border is kept as the canonical
  "this is you" affordance per canon § 11.3. Sprite cells get a 2 px ink border on a
  --l2 bg, --d1 fallback text colour.
- **L2451–2495** `.dash-r1 .gym-list .gym-row`: rebased to PixelDex `.gym-list-item`
  form — single-line flex row, 11 px font, solid `--d2` divider (was dashed),
  `gap: 6px`, line-height 1.6. `.num` is now an inline glyph slot (14 px wide,
  transparent bg, no border) carrying `★` / `▶` / `·` from the ERB.
  `.gym-row.next` becomes a `.gym-next-highlight` filled-bar (--d2 bg + --l2 text,
  6/8 padding, margin: 4px -6px so it bleeds into the panel-body's negative space).
  `.gym-row.upcoming` uses `opacity: 0.35` instead of grey-text. The legacy boxed
  `.num` numbered chip + `.gym-row.beaten .num` accent fill + `.gym-row.next .num`
  accent border rules deleted — replaced by the glyph form.
- **L2505–2546** `.dash-r1 .next-battle`: rebased to `.route-card` light-card skin
  (--l1 bg, 2 px ink border, 10 px padding, no dashed-top divider). Children get
  light-on-light text (label `--d2`, leader `--d1`, prep `--d2`). `.draft-cta` button
  retains the gb-btn-primary form (--d1 bg, --l2 text, 2 px ink border) — a dark CTA
  inside the light card.
- **L2576–2585** responsive 900 px breakpoint: `.dash-r1 .col-party { display: none;
  }` rule replaced with `.dash-r1 .pc-layout > .panel:first-child { display: none;
  }` (the party-panel is now the first `.panel` child of `.pc-layout` after the
  wrapper drop).
- **L2599–2615** responsive 720 px breakpoint: `.dash-r1 .tab` → `.dash-r1 .tab-item`
  rename. New `.dash-r1 .title-right { width: 100%; }` so the stat-strip wraps onto
  its own row on phone widths.

### `test/integration/dashboard_redesign_test.rb` — 1 new test
- **L82–90** new test `each dashboard tab cell uses the canonical .tab-item class
  (Step 28 PixelDex source spec)` per Brief assertion.

### `test/integration/responsive_grids_test.rb` — 2 stale assertions updated
- **L153** `.dash-r1 .col-party { display: none }` → `.dash-r1 .pc-layout >
  .panel:first-child { display: none }`. Same intent (left party col hidden on
  tablet); the rule's selector form changed because the `.col-party` wrapper was
  removed per D7 / option (a). The functional contract — "tablet collapse hides the
  left col" — is preserved.
- **L164–172** `.dash-r1 .tab` → `.dash-r1 .tab-item` rename in the "do NOT collapse
  inside any breakpoint" assertion. Same intent; class name follows the Step 28
  rename.

---

## Test status

- `bin/rails test`: **783 runs, 0 failures, 0 errors, 0 skips** (was 782 → 783; +1
  new Step 28 assertion in `dashboard_redesign_test.rb`).
- `bundle exec rubocop`: **clean** (203 files, 0 offenses).
- `bundle exec brakeman`: **2 warnings** — same 2 pre-existing weak-confidence
  warnings (`emulator_controller.rb:79` SendFile + `gym_schedule_discord_update_job.rb:14`
  FileAccess). **Zero delta on Step-28-touched files.**

---

## Standing rules check

- **Animation budget:** all hover/active swaps are `transition: 0.05s` colour-only.
  No `translateY`, no glow, no per-item colour coding. The `pulseNext` keyframes
  block stays as an inert no-op (Step 27 decision; not referenced by any Step 28
  rule).
- **Step 25 design canon tokens:** untouched. Token names + values unchanged in
  `:root`. `design_canon_test.rb` passes.
- **Step 24 WAI-ARIA tablist contract:** preserved — every `role="tab"`,
  `aria-selected`, `aria-controls`, `tabindex`, plus `pixeldex#tablistKeydown`,
  `pixeldex#numericJump`, `status-rail#keydown`, all controller targets and
  data-attributes intact.
- **Step 26 accent (`--accent: var(--green-glow)`):** untouched. The
  `.gym-row.beaten .name { color: var(--accent); }` and `.player-card.you
  { border-color: var(--accent); }` rules retained.

---

## Open questions for Richard

None. The brief was unambiguous on every directive (D1–D7); the only judgement calls
were:

1. **D3 inset overlay**: skipped per the "Skip if the body-level scanline already
   covers this" instruction. Verified `body::after` is `position: fixed; inset: 0;`
   covering the full viewport (lines 113–126), so an additional `.pc-layout::after`
   would be a double-overlay.
2. **D5 gym glyph emission**: chose to emit the glyph in ERB (`★` / `▶` / `·`) per
   D5's "OR just rewrite the ERB to emit the right glyph in
   `<div class="num">…</div>`". This avoids CSS `::before` content + per-row glyph
   rules and keeps the ERB self-explanatory.
3. **D7 `.col-party` rule**: clean removal preferred per Architect note ("Bob's
   call; clean removal preferred"). The 900 px breakpoint rule rewritten to target
   the new DOM (`.pc-layout > .panel:first-child`).
4. **`responsive_grids_test.rb` updates**: not in the brief's "tests likely most
   affected" list, but the test file's assertions hard-coded the old
   `.dash-r1 .col-party` and `.dash-r1 .tab` selector forms, both of which the
   brief's structural directives required to change. Updating the assertions in
   lockstep matches the same pattern from Step 27 (where 3 redesign tests had
   visual-chrome assertions updated when the chrome was restyled).

Ready for Review: YES
