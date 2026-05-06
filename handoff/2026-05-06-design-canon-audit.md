# Design Canon Audit — 2026-05-06

*Architect: Ava. Step 25 — site-wide design system clarification.*

Source files inspected directly (no Explore agent):
- `app/assets/stylesheets/pixeldex.css` (2683 lines, 75 KB) — sole site-wide stylesheet.
- `app/assets/stylesheets/application.css` (41 lines) — Tailwind reset + import. No design tokens.
- View-level `<style>` blocks: only `app/views/layouts/mailer.html.erb` (transactional email; out of scope).

The site has a deliberate **Game Boy / Pokémon Platinum CRT** aesthetic — pixel font (`Press Start 2P`), 2-3 px solid borders, no rounded corners except for circles, scanline overlay, dimmed amber accent. That core aesthetic is intact. The drift is **inside** that aesthetic — duplicated tokens, off-scale spacing, ad-hoc button/pill/card variants per surface.

Drift sources are the four Phase 2 redesigns (Step 21 R3 save slots `.slot.*` & `.roster-card`, Step 22 R2 `.pc-box-r2`, Step 23 R4 `.map-r4`, Step 24 R1 `.dash-r1`) plus the legacy `gb-*` utility set. Each was scoped to one surface; the visual idiom drifted across them.

---

## 1. Color tokens

### In use (CSS variables — source of truth)

| Token | Hex | Uses | Semantic role (inferred) |
|---|---|---|---|
| `--d1` | `#1a2e1a` | 63 | Deep base — primary border, dark text on light, dark page surfaces |
| `--d0` | `#0a1a0a` | 74 | Deepest — inner panel bg, button-bg-dark, monospace seed bg |
| `--d2` | `#3a5a3a` | 114 | Mid-dark — secondary bg, dimmed text on dark, dashed dividers |
| `--l1` | `#8a9e6a` | 72 | Mid-light — card bg on light, dim text on dark |
| `--l2` | `#9aae7a` | 60 | Primary light bg, hi-contrast text on dark |
| `--white` | `#c0d0a0` | 46 | High-contrast text on dark surfaces |
| `--amber` | `#d4b14a` | 70 | Primary accent — CTA, earned badge, focus ring |
| `--green-glow` | `#5fd45f` | 30 | Success/active — alive count, save-slot active border |
| `--crimson` | `#c75a5a` | 30 | Danger/dead — destructive button fg, dead-state border |

### Drift (hardcoded hex codes — should become tokens)

| Hex | Uses | Where | Maps to |
|---|---|---|---|
| `#4a1c1c` | 7 | `.gb-flash-alert` bg, `.gb-btn-danger` bg, `.gb-status-dead` bg, `.map-r4 .node.dead .glyph` bg, `.map-r4 .acc-row .glyph.dead` bg, `.map-r4 .node-legend .glyph.dead` bg | **Danger surface bg** — needs `--ember-bg` token |
| `#6b2c2c` | 4 | `.gb-flash-alert` border, `.gb-btn-danger` border + `:hover` bg | **Danger border / hover bg** — needs `--ember-border` token |
| `#e8a0a0` | 4 | `.team-builder-status--error`, `.gb-flash-alert` color, `.gb-btn-danger` color | **Danger text on dark** — needs `--ember-fg` token |
| `#4a3a1c` | 1 | `.conflict-warning` bg | One-off "deep amber surface" — leave alone (single use, scoped) |
| `#2a1a1a` | 1 | `.pc-box-r2 .box-cell.dead` bg | "Even-deeper red" — already adjacent to `#4a1c1c`; **fold into `--ember-bg` family or leave as one-off**. Decision: leave (single use, distinct intent — extra-darkened dead cell). |
| `#f0c0c0` | 1 | `.gb-btn-danger:hover` color | Brighter danger fg on hover — minor, **leave inline**. |
| `#d4a444` | 2 | `.tcg-coin__face` inset shadow ring | Coin-flip motif, scoped to single component — **leave**. |
| `#1a1a1a`, `#ffffff`, `#fff7d8`, `#fff2cc`, `#f7d358`, `#f4cccc`, `#ee1515`, `#d9ead3`, `#c9daf8`, `#6b3c0a` | 1 each | All inside `.tcg-coin*` (Pokéball gradient) and `.gb-avatar--c0..c3` (initial-letter pastel fallbacks) | **Leave alone** — purely component-decorative (Pokéball red, avatar initial pastels). Not part of the canon. |

### Canon decision

Adopt **9 semantic alias tokens** layered on top of the existing palette (not a rename — purely additive). New code uses semantic names; existing usages stay; the danger family unifies hardcoded hexes.

```
--ink     → existing --d1   (primary border, default text on light)
--shadow  → existing --d0   (deepest bg, button bg dark)
--shade   → existing --d2   (mid-dark bg, dim text on dark)
--moss    → existing --l1   (mid-light bg, dim text on dark)
--canvas  → existing --l2   (light page bg, button-ghost-bg)
--paper   → existing --white  (high-contrast text on dark)
--accent  → existing --amber  (CTA / earned / focus)
--success → existing --green-glow  (alive / active / saved)
--danger  → existing --crimson  (dead / destructive)

NEW — danger family (replaces 3 hardcoded hexes):
--danger-bg     = #4a1c1c   (gb-flash-alert bg, gb-btn-danger bg, gb-status-dead bg, dead-glyph bg)
--danger-border = #6b2c2c   (gb-flash-alert border, gb-btn-danger border)
--danger-fg     = #e8a0a0   (gb-flash-alert color, gb-btn-danger color, team-builder error)
```

Rationale: keeping `--d0..--white` as the source of truth avoids a 300-line find-replace; semantic aliases give Bob a clear path forward; the 3 new danger tokens kill the only true "duplicated hardcoded color" drift.

---

## 2. Spacing values

### In use (counts of unique values, all properties combined)

**Padding shorthand (top values):** `8px 10px` (7), `8px` (7), `10px` (7), `6px 8px` (6), `10px 12px` (6), `8px 12px` (5), `8px 14px` (4), `4px 8px` (4), `3px 6px` (4), `2px 6px` (4), `0` (4), `6px 10px` (3), `6px` (3), `2px 4px` (3), `1px 4px` (3), `16px` (3), `12px` (3), …**~40 distinct paddings**.

**Gap (top values):** `6px` (17), `8px` (14), `10px` (6), `14px` (5), `4px` (4), `12px` (4), `16px` (3), `22px` (2), `3px` (1), `2px` (1), `1px` (1), `0` (1).

**Margin distinctly distributed:** `8px / 6px / 4px / 10px / 12px / 14px` dominant, with one-offs at `13px`, `18px`, `22px`, `28px`, `32px`. The redesigns introduced `22px` (R4 layout gap, R2 box-layout gap, R4 special-bar margin-top variant `28px`).

### Drift (off-scale or near-duplicates)

| Value | Uses | Verdict |
|---|---|---|
| `1px`, `2px`, `3px` | rare | Used for fine pill/badge padding; keep as-is (sub-quarter step). |
| `5px` (e.g. `2px 5px`) | 4 | Off-scale. **Snap → `4px` or `6px`.** Both `2px 4px` and `2px 6px` already exist. |
| `13px` | 0 in spacing (only font-size) | n/a |
| `18px` | 1 in margin (`margin: 0 18px`) | One-off. Rare but acceptable. |
| `22px` | several | Used as "extra-loose gap" in R2/R4 layouts. Keep — it's a legitimate scale step. |
| `0px`, `0` mix | various | Just `0` — fine. |

### Canon decision

**8-step scale, 2-px increments where most usage clusters, then jump:**

```
--s-1 = 4px    /* hairline padding, micro gap (gb-grid-* gap, badge legend gap) */
--s-2 = 6px    /* tight (filter-chip gap, gym-row padding) */
--s-3 = 8px    /* default (card padding sm, button padding-y default) */
--s-4 = 10px   /* relaxed (slot card padding, group-card padding) */
--s-5 = 12px   /* card padding md (gb-card, sheet-head padding-x) */
--s-6 = 14px   /* card padding lg (review-tray, status-rail) */
--s-7 = 16px   /* page padding (gb-page, gb-modal) */
--s-8 = 22px   /* extra-loose (R2 box-layout gap, R4 layout gap) */
```

Off-scale `5px` snap → `4px` for the 4 instances (state-pill, hof-pill paddings — no perceptual change at 8px font).

Rationale: 2-px stair matches actual usage (4/6/8/10/12/14/16) and the Game Boy pixel grid; the 22px step preserves the "loose" feel of the new redesigns without introducing a 24/32 jump that would look out of place against 14/16. Tokens are positional (`--s-1..s-8`), not semantic — spacing is genuinely a scale, not a meaning.

---

## 3. Typography

### Font stacks in use

- `'Press Start 2P', monospace` — display / labels / buttons. Used **everywhere** (95%+ of declarations).
- `'VT323', monospace` — body / form input values / decorative — used in `.map-r4 .node`, `.map-r4 .form-row input/select`, `.map-r4 .player-row input`, `.map-r4 .special-cell`, `.map-r4 .accordion-frame`, `.pc-box-r2 .filter-search input`. Introduced in R4 then partially used in R2 search.
- `monospace` (no specific family) — `.roster-card .seed` (seed code copy field).

**No drift here.** The Press Start 2P / VT323 pairing is intentional and the pairing maps to "label/structural" vs "body/data" cleanly.

### Font sizes in use

`6px` (1) · **`7px` (15)** · **`8px` (25)** · **`9px` (24)** · **`10px` (26)** · **`11px` (23)** · `12px` (11) · **`13px` (15)** · **`14px` (19)** · `15px` (1) · `16px` (6) · `18px` (5) · `19px` (1) · `20px` (2) · `21px` (1) · `25px` (1) · `28px` (1) · `35px` (1).

Real distribution → **6 working sizes** (7, 8, 9, 10, 11, 13, 14) + occasional headers (16, 18) + decorative one-offs (20+).

### Drift

- `12px` (11 uses) and `13px` (15 uses) overlap — should pick one for "body small". 13px is the dominant value (used in nav, title-sub, panel-header, route-name, status-bar). **Canonical = 13px.** Convert ~11 instances of `12px` to `13px` *only where the surface is "secondary text on dark"* — leave `12px` for VT323 (which renders larger pixel-for-pixel).
- `15px`, `19px`, `21px`, `25px`, `28px`, `35px` (one each) — all decorative one-offs (route-name 15px, body 19px, title-stat-num 21px, box-cell-sprite emoji 35px, tcg-coin 28px, team-slot-num 18→25px). **Leave** — these aren't part of the type scale.
- Letter-spacing chaos: `1px` (53 uses, dominant), `0.5px` (11 uses), `0.03em` / `0.05em` / `0.08em` / `0.1em` (15 uses combined). Mixed `px` and `em` confuses the scale.
- Line-height: `1.4` (9 uses), `1.6` (4), `1.8` (3), `1.5` (3), `1` (3 — buttons/glyphs, intentional), `1.2`/`1.3` (2 each), and absolute `28px`/`20px` (1 each — gb-avatar fallbacks).

### Canon decision

**Type scale (7 steps):**

```
--t-micro = 7px / 1.4   /* state-pill, hof-pill, sub-tab labels */
--t-xs    = 8px / 1.4   /* labels, sub-tab text, badge text */
--t-sm    = 9px / 1.4   /* button md, side-tab, run-pill */
--t-md    = 10px / 1.4  /* h3 small, button lg, count chips */
--t-body  = 11px / 1.6  /* gb-btn, nav links, slot-meta lbl */
--t-lg    = 13px / 1.6  /* nav logo, title-sub, status-bar val, route-name */
--t-xl    = 16px / 1.6  /* page-title medium, slot strong */
```

Headings (18px, 21px) and decorative font-sizes (20–35px) are **not part of the canon** — each is single-use and can stay inline.

**Letter-spacing canon (`px`-based, matching Press Start 2P):**

```
--ls-tight  = 0.5px   /* compact rows, dense lists */
--ls-default = 1px    /* almost everything else */
--ls-wide   = 0.1em   /* page titles only (preserves the few existing 0.1em uses) */
```

Convert `0.03em` (~5 uses, all on buttons) → `0.5px` (visually identical at 11px/9px) for consistency. Convert `0.05em`/`0.08em` (8 uses) → `1px` where they're labels.

**Line-height canon (3 steps):**

```
--lh-tight = 1     /* buttons, glyphs (already in use) */
--lh-snug  = 1.4   /* labels, dense rows */
--lh-body  = 1.6   /* body text, list items */
```

`1.8` (body global) — preserved on `body { }` and `.dialog`; it's the global default and shouldn't change. `1.5` / `1.2` / `1.3` — fold into `1.4` where they're functionally equivalent (~6 sites).

---

## 4. Buttons

### Variants in use

| Class | font-size | padding | bg / fg / border | Where |
|---|---|---|---|---|
| `.gb-btn` | 11px | 8px 14px | l1 / d1 / 2px d1 | global ghost button |
| `.gb-btn-primary` | 11px | 8px 14px | d1 / l2 / 2px d1 | global "filled dark" — limited use |
| `.gb-btn-danger` | 11px | 8px 14px | `#4a1c1c` / `#e8a0a0` / `2px #6b2c2c` | global destructive (4 uses) |
| `.gb-btn-sm` | 10px | 4px 8px | (size mod, paired with one of the above) | sm size mod |
| `.gb-nav-logout` | 10px | 2px 6px | none / l1 / 2px d1 | nav logout — **one-off** |
| `.slot-actions button` | 8px | 6px 8px | d2 / l2 / 1px d0 | save-slot actions |
| `.slot-actions button.primary` | 8px | 6px 8px | green-glow / d0 / 1px d0 | "ACTIVE" save-slot |
| `.confirm-inline .actions button` | 8px | 6px 8px | d2 / l2 / 1px d0 | inline-confirm cancel |
| `.confirm-inline .actions button.confirm` | 8px | 6px 8px | crimson / white / 1px d0 | inline-confirm confirm |
| `.footer-actions button` | 9px | 8px 10px | transparent / crimson / 1px dashed crimson | clear-all-slots |
| `.dash-r1 .next-battle .draft-cta` | 9px | 8px | amber / d0 / 2px d0 | dashboard "DRAFT TIEBREAK" |
| `.dash-r1 .run-pill-menu .start-btn` | 8px | 6px | d2 / l2 / 1px dashed l1 | "START NEW RUN" |
| `.dash-r1 .side-tab` | 8px | 6px 4px | d2 / l1 / none (border-right d0) | dashboard sub-tab |
| `.dash-r1 .tab` | 9px | 10px 8px | transparent / l1 / none | main tab |
| `.map-r4 .submit-btn` | 10px | 10px | green-glow / d0 / 2px d0 | map sheet submit (catch) |
| `.map-r4 .submit-btn.danger` | 10px | 10px | crimson / white / 2px d0 | map sheet danger |
| `.map-r4 .submit-btn.muted` | 10px | 10px | d2 / l2 / 2px d0 | map sheet cancel |
| `.map-r4 .dupes-btn` | 9px | 10px | transparent / l1 / 1px dashed d2 | map dupes |
| `.map-r4 .status-bar .jump-btn` | 9px | 6px 12px | amber / d0 / 2px d0 | map "JUMP TO NOW" |
| `.map-r4 .sheet-head .close` | 8px | 4px 8px | none / l2 / 1px d2 | map sheet close |
| `.map-r4 .accordion-segment summary` | 9px | 10px 14px | d2 / white / none | map mobile accordion |
| `.map-r4 .acc-row` | (VT323) | 8px | none | map mobile row |
| `.pc-box-r2 .review-row .actions button` | 8px | 6px 14px | d2 / l2 / 1px d0 | PC box review action |
| `.pc-box-r2 .review-row .actions button.primary` | 8px | 6px 14px | green-glow / d0 / 1px d0 | PC box "ADD" |
| `.pc-box-r2 .filter-chip` | 9px | 6px 12px | d1 / l1 / 1px d2 | PC box filter chip (button-shaped) |
| `.dialog::after` blink — n/a |

Plus inline button-y elements (`.run-pill`, `.tab`, etc.) that are clickable but logically navigation.

### Drift

The same "small ghost button" appears as 5 different patterns: `.slot-actions button`, `.confirm-inline .actions button`, `.review-row .actions button`, `.dash-r1 .run-pill-menu .start-btn`, `.dash-r1 .side-tab`. They differ in font-size (8 vs 9 vs 10), padding (6×8 vs 6×4 vs 6×14), and border (`1px d0` vs `1px dashed l1` vs `none border-right d0`). Most could be a single "small ghost" with one or two modifiers.

The same "primary CTA" appears as: `.map-r4 .submit-btn` (green-glow), `.map-r4 .status-bar .jump-btn` (amber), `.dash-r1 .next-battle .draft-cta` (amber). Two amber CTA paddings (`6px 12px` vs `8px`) for the same role.

The same "destructive" appears as: `.gb-btn-danger`, `.confirm-inline .actions button.confirm` (crimson bg / white fg / 1px d0 — **inconsistent border** with gb-btn-danger), `.map-r4 .submit-btn.danger`, `.slot-actions button.danger:hover`.

### Canon decision

**3 sizes × 3 styles, plus a `--ghost` modifier for the transparent treatment.**

Sizes:
```
.btn--sm   font-size: var(--t-xs);   padding: var(--s-2) var(--s-3);   /* 8px font, 6×8 */
.btn        font-size: var(--t-sm);   padding: var(--s-2) var(--s-5);   /* 9px font, 6×12 */  (default md)
.btn--lg   font-size: var(--t-body); padding: var(--s-3) var(--s-6);   /* 11px font, 8×14 */
```

Styles:
```
.btn               background: var(--shade);    color: var(--canvas); border: 1px solid var(--shadow);   /* default ghost */
.btn--primary      background: var(--accent);   color: var(--shadow); border: 2px solid var(--shadow);    /* amber CTA */
.btn--danger       background: var(--danger-bg); color: var(--danger-fg); border: 2px solid var(--danger-border);   /* destructive */
```

A `.btn--ghost` modifier exists for the dashed transparent treatment (footer-actions, dupes-btn). Existing classes (`.gb-btn`, `.gb-btn-primary`, `.gb-btn-danger`, namespaced sub-buttons) **stay as-is** — they continue to work. The canon is the **new** path forward + a shared inventory documented for reuse. Bob's normalization is selective:

1. Replace hardcoded danger hexes (`#4a1c1c`, `#6b2c2c`, `#e8a0a0`) with `var(--danger-bg)` / `var(--danger-border)` / `var(--danger-fg)` everywhere — 4 sites, mechanical.
2. Snap the two amber-CTA paddings (`.jump-btn` `6px 12px` vs `.draft-cta` `8px`) to the same value `var(--s-3) var(--s-5)` (8×12).
3. Leave per-namespace button shapes alone — they're scoped, intentional, and changing them is layout risk.

Rationale: a full button rebase is a 100-edit churn that risks visual regressions on every surface. Selective normalization (kill hardcoded hexes, unify the two amber paddings) is the high-ROI subset. The canon doc tells the next feature where to start; existing code keeps working.

---

## 5. Pills / badges / chips

### Variants in use

12 distinct "pill-shaped" element classes:

| Class | font-size | padding | shape | Where |
|---|---|---|---|---|
| `.state-pill` | 7px | 2px 5px | 1px solid border | save-slot status (EMPTY/SAVED/ACTIVE/TARGET/CONFIRM) |
| `.hof-pill` | 7px | 2px 5px | filled amber | run-roster HOF marker |
| `.roster-card .you-badge` | 7px | 2px 4px | filled amber | run-roster "YOU" |
| `.dash-r1 .player-card .you-pill` / `.hof-pill-r1` | 6px | 1px 4px | filled amber | dashboard player-card YOU/HOF |
| `.dash-r1 .player-card .badges-pill` | 7px | (none — text only) | text-only | badge count |
| `.dash-r1 .run-pill .badge` | 7px | 2px 4px | filled green-glow | run-pill HOF/active marker |
| `.dash-r1 .run-pill-menu .run-option .pill` | 7px | 1px 4px | filled green-glow | run option marker |
| `.map-r4 .sheet-status .pill` | 8px | 3px 6px | filled green-glow / crimson | sheet status |
| `.map-r4 .group-card .head .pill` | 8px | 2px 5px | 1px solid border green-glow / crimson | group state |
| `.pc-box-r2 .badge-legend .badge` | 8px | 2px 5px | 1px solid border + min-width 56px | badge legend chip |
| `.pc-box-r2 .type-pill` | 8px | 3px 6px | 1px solid border (multiple states) | type-coverage chip |
| `.pc-box-r2 .filter-chip` | 9px | 6px 12px | 1px solid border (active=filled amber) | filter chip — closer to a button |

Plus stylistic variants (filled vs outline vs text-only).

### Drift

Six different paddings for what is fundamentally the same "pill at 7-8px font" element:
- `2px 4px` (you-badge, badges-pill, run-pill .badge, run-option .pill)
- `2px 5px` (state-pill, hof-pill, group-card .pill, badge-legend .badge)
- `3px 6px` (sheet-status .pill, type-pill)
- `1px 4px` (you-pill / hof-pill-r1, run-option .pill in some states)

The 2 vs 3 px vertical and 4 vs 5 vs 6 px horizontal differences are imperceptible at 7-8 px font. They are accidental.

### Canon decision

**1 pill primitive + 4 style modifiers + 2 size modifiers.** All pills speak the same shape language.

```
.pill                         /* primitive */
  font-family: 'Press Start 2P', monospace;
  font-size: var(--t-micro);    /* 7px */
  padding: var(--s-1) var(--s-2);   /* 2px 6px */  ← canonical pill padding
  letter-spacing: var(--ls-default);
  border: 1px solid currentColor;
  display: inline-block;

.pill--sm                     /* very small (player-card YOU/HOF) — 6px font */
  font-size: 6px;
  padding: 1px var(--s-1);     /* 1px 4px */

.pill--lg                     /* group-card / sheet-status — 8px font */
  font-size: var(--t-xs);       /* 8px */
  padding: var(--s-1) var(--s-2);   /* still 2px 6px (just bigger font) */

/* Style modifiers (all use border: 1px solid currentColor by default) */
.pill--success      color: var(--shadow); background: var(--success); border-color: var(--success);
.pill--accent       color: var(--shadow); background: var(--accent);  border-color: var(--accent);
.pill--danger       color: var(--paper);  background: var(--danger);  border-color: var(--danger);
.pill--ghost        color: var(--moss);  background: transparent; border-color: var(--moss);  /* outline */
```

Bob's normalization for pills: **don't touch namespaced `.dash-r1 .*-pill` etc.** — the shape modifications are scoped + intentional. The canon doc is the **forward path** (a `.pill` primitive Bob can introduce + future surfaces use). Existing pills stay. Snap the off-scale 5 px → 6 px (4 instances of `2px 5px`) to anchor the scale.

Rationale: 12 pill variants on one site is fine when each is intentional; the drift is the 2-vs-3-vs-4-vs-5 padding variance for the same role. Picking `2px 6px` for the canon (mid-point, scale-aligned) anchors future work without breaking existing surfaces.

---

## 6. Cards / panels

### Variants in use

11 card-shaped containers:

| Class | bg | border | padding | margin-bottom |
|---|---|---|---|---|
| `.gb-card` | l1 | 3px solid d1 (`var(--border)`) | 12 | 10 |
| `.gb-card-dark` | d2 | 3px solid d1 | 12 | 10 |
| `.route-card` | l1 | 2px solid d1 (`var(--border-thin)`) | 10 | 8 |
| `.roster-card` | d1 | 2px solid d1 | 12 14 | 10 |
| `.roster-card.you` | (same) | 4px solid amber | 10 12 | 10 |
| `.dash-r1 .player-card` | d2 | 1px solid d0 | 8 | 10 |
| `.dash-r1 .player-card.you` | d0 | 2px solid amber | 8 | 10 |
| `.map-r4 .group-card` | d0 | 2px solid green-glow | 12 | 14 |
| `.map-r4 .group-card.dead` | d0 | 2px solid crimson | 12 | 14 |
| `.map-r4 .special-cell` | d2 | 2px solid d1 | 10 12 | (in grid) |
| `.pc-box-r2 .review-row` | d1 | 2px solid d1 | 10 14 | 8 |
| `.pc-box-r2 .review-row.first` | d1 | 3px solid green-glow | 8 12 | 8 |
| `.pc-box-r2 .box-cell` | d2 | 2px solid d0 | 8 | (in grid) |
| `.gb-candidate-card` | l1 | 2px solid d1 | 10 | (in grid) |
| `.slot` | d1 | 2px solid d1 | 10 12 | 8 |

### Drift

Four border-width treatments: `1px solid`, `2px solid` (dominant), `3px solid` (`var(--border)` — gb-card, slot.active), `4px solid` (slot.active, roster-card.you, gym-r1 next-glow). All four are intentional ("border thickens to indicate emphasis"). **Not drift** — that's the system.

But: the **base** card border is split between `2px solid d1` and `3px solid d1`. Old gb-card → 3px. New redesigns → 2px. Inconsistent.

Card padding: 8, 10, 12, 14 — all on-scale. No drift here.

### Canon decision

**1 card primitive, base border = 2 px solid `--ink`. The 3 px / 4 px borders become emphasis modifiers, not the default.**

```
.card                         /* primitive */
  background: var(--moss);    /* default light surface */
  border: 2px solid var(--ink);
  padding: var(--s-5);        /* 12px */
  margin-bottom: var(--s-4);  /* 10px */

.card--dark                   background: var(--shade);  color: var(--canvas);
.card--shadow                 background: var(--shadow); /* deepest — inner panel */
.card--emphasis               border-width: 3px;
.card--active                 border: 4px solid var(--success);
.card--warn                   border: 4px solid var(--accent);
.card--danger                 border: 4px solid var(--danger);
```

Bob's normalization: **don't touch `.gb-card`** (it's the legacy 3px treatment used in many places — changing the base border-width on a 3-uses-everywhere class is too risky). Instead, **document the canon** so any new surface adopts `.card` (2px). Existing namespaced cards stay.

The single mechanical fix: route-card uses `var(--border-thin)` (2px) but the rest of `gb-card` siblings use `var(--border)` (3px). That's correct — leave it.

Rationale: cards are where the per-surface intentionality matters most (a draft-mode group-card legitimately wants a green-glow border, etc.). The canon defines the *primitive* + *modifiers*; existing cards don't need to fold into it.

---

## 7. Modals

### Variants in use

| Class | Treatment | Where |
|---|---|---|
| `.gb-modal` + `.gb-modal-backdrop` | Full overlay, `rgba(15, 56, 15, 0.75)` backdrop, centered, `4px solid d1` border, `420px max-width`, `var(--l1)` bg | Standard confirm-modal (delete pokemon, mark-dead, etc.) — Step 20 |
| `.confirm-inline` | **Not a modal** — inline expanding confirmation block within save-slots panel | Step 21 R3 — DELETE / CLEAR ALL SLOTS |
| `.map-r4 .sheet` | **Not a modal** — sticky right-rail sheet, in-flow | Step 23 R4 — route detail "modal-replacement" |
| `.dash-r1 .run-pill-menu` | **Not a modal** — anchored dropdown | Step 24 R1 — run picker |

### Drift

None. The 3 "non-modal" patterns are deliberately **not** modals (Step 23's sheet was an explicit decision documented in BUILD-LOG; inline-confirm in Step 21 was an explicit anti-pattern decision to avoid stacking modals over already-busy panels). They are different visual treatments serving different intents (overlay vs. sticky vs. inline). **Keep all four; do not unify.**

### Canon decision

`.gb-modal` is the canonical full-overlay modal. Document it. The three "almost-modal" patterns (sheet / run-pill-menu / confirm-inline) keep their existing class names — they're *intentionally* not part of the modal canon.

```
.modal                        /* primitive (alias of existing .gb-modal) */
  background: var(--moss);
  border: 4px solid var(--ink);
  padding: var(--s-7);
  max-width: 420px;
  /* + .gb-modal-backdrop unchanged */
```

Bob's normalization: **none required** for modals. Just document.

---

## 8. Decorative / one-offs (intentionally NOT canon)

The following are scoped to a single component and should **not** be folded into the canon. Each is its own thing:

- `.tcg-coin*` (coin-flip TCG modal — Pokéball red `#ee1515`, gold ring `#d4a444`, character white-shadow `#fff7d8`).
- `.gb-avatar--c0..c3` (4 pastel initial-letter fallbacks `#f4cccc`, `#c9daf8`, `#d9ead3`, `#fff2cc`).
- `.conflict-warning` (`#4a3a1c` deep-amber surface).
- `.pc-box-r2 .box-cell.dead` (`#2a1a1a` extra-dark dead cell).
- `.pending-banner`, `.dialog`, `.gb-flash` — single-use decorative.

These survive the audit untouched.

---

## 9. Summary of mechanical fixes for Bob (Half 3)

Tight, surgical, low-risk:

1. **Add 12 new tokens** to `:root` in `pixeldex.css` (semantic aliases + danger family + spacing scale + type scale + letter-spacing + line-height). ~30 added lines.
2. **Replace 4 hardcoded danger hexes** with `var(--danger-*)` tokens at:
   - `.gb-flash-alert` (lines ~178-181) — bg, border, color
   - `.gb-btn-danger` (lines ~788-803) — bg, border, color (NOT the `:hover` `#f0c0c0` text; that one's a hover variant — leave inline)
   - `.gb-status-dead` (lines ~920-924) — bg, border, color
3. **Snap 4 instances of `2px 5px`** to `var(--s-1) var(--s-2)` (= `2px 6px`):
   - `.state-pill` line ~1900
   - `.hof-pill` line ~2079
   - `.map-r4 .group-card .head .pill` line ~1503
   - `.pc-box-r2 .badge-legend .badge` line ~1639
4. **Snap 2 amber-CTA paddings** to share `var(--s-3) var(--s-5)` (= `8px 12px`):
   - `.dash-r1 .next-battle .draft-cta` line ~2428 (currently `padding: 8px;`)
   - `.map-r4 .status-bar .jump-btn` line ~1117 (currently `padding: 6px 12px;`)
5. **Convert `0.03em` letter-spacing → `0.5px`** (4 instances on `.gb-btn*`).
6. **Smoke test:** assert that `--accent` is referenced in `pixeldex.css` (canon-token presence test).

**Do NOT:**
- Rename `--d0..--white` etc. (massive churn, no value).
- Rebase any existing button class.
- Touch any view file.
- Touch any controller / model / config.
- Rewrite namespaced `.dash-r1 / .pc-box-r2 / .map-r4 / .slot` rules.
- Touch the `tcg-coin*`, `gb-avatar--c*`, `conflict-warning`, or `box-cell.dead` decorative one-offs.

The total expected diff: **~12 line touches in pixeldex.css + ~40 net new lines (tokens + canon doc) + 1 new test + 1 new doc**. Small, mechanical, easily reviewable.

---

## 10. Canon document location

`app/assets/stylesheets/design_canon.md` — source of truth for future work. Contains the same token names + intent + usage table. Bob writes this in Half 2 from this audit's "Canon decision" sections.
