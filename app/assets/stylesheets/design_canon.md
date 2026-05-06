# Soul Link Design Canon

*Locked 2026-05-06 (Step 25). Source of truth for tokens, spacing, type, buttons, pills, cards, modals.*

The site has a deliberate **Game Boy / Pokémon Platinum CRT** aesthetic — `Press Start 2P` display + `VT323` body, dimmed amber accent, 2-3 px solid borders, no rounded corners except for circles, scanline overlay. This canon does not change that aesthetic — it tightens the *language* used inside it so future surfaces speak the same dialect as the existing four (legacy `gb-*`, `.slot/.roster-card`, `.pc-box-r2`, `.map-r4`, `.dash-r1`).

When in doubt, use semantic names. Existing positional names (`--d0`, `--l1`, etc.) remain as the source of truth — semantic names alias them.

---

## 1. Color tokens

### Palette (positional — the Game Boy values)

| Token | Hex | Use |
|---|---|---|
| `--shadow` (= `--d0`) | `#0a1a0a` | Deepest bg, button bg dark, monospace seed bg |
| `--ink` (= `--d1`) | `#1a2e1a` | Primary border, dark text on light, deep page surfaces |
| `--shade` (= `--d2`) | `#3a5a3a` | Mid-dark bg, dim text on dark, dashed dividers |
| `--moss` (= `--l1`) | `#8a9e6a` | Mid-light bg, dim text on dark |
| `--canvas` (= `--l2`) | `#9aae7a` | Primary light page bg, hi-contrast text on dark |
| `--paper` (= `--white`) | `#c0d0a0` | High-contrast text on dark surfaces |

### Accents (semantic — the meaning-carriers)

| Token | Hex | Use |
|---|---|---|
| `--accent` (= `--amber`) | `#d4b14a` | CTA button bg, earned badge, focus ring, "next" pulse, run-pill border |
| `--success` (= `--green-glow`) | `#5fd45f` | Alive count, save-slot active, group-card alive border, sheet-status pill |
| `--danger` (= `--crimson`) | `#c75a5a` | Destructive button fg, dead state border, delete-confirm bg |
| `--danger-bg` | `#4a1c1c` | Danger filled-surface bg (gb-flash-alert, gb-btn-danger, dead-glyph) |
| `--danger-border` | `#6b2c2c` | Danger filled-surface border |
| `--danger-fg` | `#e8a0a0` | Danger filled-surface text |

### Out of canon (decorative one-offs — leave inline)

`.tcg-coin*` Pokéball palette, `.gb-avatar--c0..c3` initial-letter pastels, `.conflict-warning` deep-amber bg, `.pc-box-r2 .box-cell.dead` extra-dark red. Not part of the canon — single-use, scoped, intentionally distinct.

---

## 2. Spacing scale

8 steps, 2-px increments (matches the Game Boy pixel grid + actual usage clustering).

| Token | Value | Typical use |
|---|---|---|
| `--s-1` | `4px` | hairline padding, micro gap, gb-grid-* gap, badge legend gap |
| `--s-2` | `6px` | tight (filter-chip gap, gym-row padding, slot-actions gap) |
| `--s-3` | `8px` | default card padding sm, button padding-y default, gb-grid gap |
| `--s-4` | `10px` | relaxed (slot card padding, group-card padding, route-card padding) |
| `--s-5` | `12px` | card padding md (gb-card, sheet-head padding-x, page-padding desktop) |
| `--s-6` | `14px` | card padding lg (review-tray, status-rail, R4 layout margin-bottom) |
| `--s-7` | `16px` | page padding (gb-page, gb-modal padding) |
| `--s-8` | `22px` | extra-loose (R2 box-layout gap, R4 layout gap, R4 special-bar margin-top) |

Off-scale `5px` is normalized to `4px` or `6px` (snap toward the closer existing value). One-off `13px` / `18px` / `28px` / `32px` paddings or margins survive where they're scoped to a single decorative element.

---

## 3. Typography

### Fonts

- **`'Press Start 2P', monospace`** — display, labels, buttons (default).
- **`'VT323', monospace`** — body / form input values / decorative (R4 nodes & forms, R2 search input).
- **`monospace`** (no specific family) — `.roster-card .seed` only (intentional, generic monospace for seed copy field).

### Size scale (7 steps)

| Token | Value | Use |
|---|---|---|
| `--t-micro` | `7px` | state-pill / hof-pill / sub-tab labels |
| `--t-xs` | `8px` | labels, sub-tab text, badge text, slot-actions button |
| `--t-sm` | `9px` | button md, side-tab, run-pill, filter-chip |
| `--t-md` | `10px` | h3 small, button lg, count chips, card titles |
| `--t-body` | `11px` | gb-btn, nav links, slot-meta lbl, default body text on labels |
| `--t-lg` | `13px` | nav logo, title-sub, status-bar val, route-name, panel-header |
| `--t-xl` | `16px` | page-title medium, slot strong stat |

Decorative font-sizes (18, 21, 25, 28, 35) are **not part of the canon** — they're single-use (page titles, sprite emoji, coin-flip glyph). Leave inline.

### Letter-spacing (`px`-based, normalized away from `em`)

| Token | Value | Use |
|---|---|---|
| `--ls-tight` | `0.5px` | compact rows, dense lists, button text on small buttons |
| `--ls-default` | `1px` | almost everything else (53 existing uses) |
| `--ls-wide` | `0.1em` | page titles only (preserves the few existing 0.1em uses) |

`0.03em` (4 button uses) → `0.5px` (visually identical). `0.05em` / `0.08em` (8 nav/title uses) → `1px` where they're labels.

### Line-height (3 steps)

| Token | Value | Use |
|---|---|---|
| `--lh-tight` | `1` | buttons, glyphs, tcg-coin, navbar dense |
| `--lh-snug` | `1.4` | labels, dense rows, accordion summary |
| `--lh-body` | `1.6` | body text, list items, card body |

Global `body { line-height: 1.8 }` and `.dialog { line-height: 1.8 }` are preserved — they're the typewriter-like default for prose-y content and shouldn't change.

---

## 4. Buttons

3 sizes × 3 styles, plus a `--ghost` modifier for the dashed-transparent treatment.

### Sizes

```css
.btn--sm   { font-size: var(--t-xs);   padding: var(--s-2) var(--s-3); }   /* 8px font, 6×8 */
.btn       { font-size: var(--t-sm);   padding: var(--s-2) var(--s-5); }   /* 9px font, 6×12 (default) */
.btn--lg   { font-size: var(--t-body); padding: var(--s-3) var(--s-6); }   /* 11px font, 8×14 */
```

All buttons share:

```css
font-family: 'Press Start 2P', monospace;
letter-spacing: var(--ls-default);
line-height: var(--lh-snug);
cursor: pointer;
transition: all 0.05s;
```

### Styles

```css
.btn               { background: var(--shade);     color: var(--canvas);    border: 1px solid var(--shadow); }
.btn--primary      { background: var(--accent);    color: var(--shadow);    border: 2px solid var(--shadow); }
.btn--danger       { background: var(--danger-bg); color: var(--danger-fg); border: 2px solid var(--danger-border); }
.btn--ghost        { background: transparent;      color: var(--moss);      border: 1px dashed var(--shade); }
```

### Existing classes (kept, do not rebase)

`.gb-btn`, `.gb-btn-primary`, `.gb-btn-danger`, `.gb-btn-sm`, `.slot-actions button`, `.confirm-inline .actions button`, `.map-r4 .submit-btn`, `.dash-r1 .next-battle .draft-cta`, `.dash-r1 .run-pill-menu .start-btn`, `.pc-box-r2 .review-row .actions button`, `.pc-box-r2 .filter-chip`, `.map-r4 .status-bar .jump-btn`, `.map-r4 .dupes-btn`, `.map-r4 .sheet-head .close`, `.dash-r1 .side-tab` — all stay. They are the legacy + Phase-2-redesign forms; refactoring them is layout risk.

The canon `.btn` is the **forward path** — new surfaces start with `.btn` + a style modifier. Existing surfaces keep their classes but adopt token replacements (no hardcoded hexes).

---

## 5. Pills

1 primitive + 4 style modifiers + 2 size modifiers.

```css
.pill {
  display: inline-block;
  font-family: 'Press Start 2P', monospace;
  font-size: var(--t-micro);             /* 7px */
  padding: var(--s-1) var(--s-2);         /* 2px 6px */
  letter-spacing: var(--ls-default);
  border: 1px solid currentColor;
}

.pill--sm  { font-size: 6px; padding: 1px var(--s-1); }   /* 1px 4px */
.pill--lg  { font-size: var(--t-xs); }                    /* 8px font, same padding */

.pill--success  { color: var(--shadow); background: var(--success); border-color: var(--success); }
.pill--accent   { color: var(--shadow); background: var(--accent);  border-color: var(--accent);  }
.pill--danger   { color: var(--paper);  background: var(--danger);  border-color: var(--danger);  }
.pill--ghost    { color: var(--moss);   background: transparent;    border-color: var(--moss);    }
```

### Existing pill-shaped classes (kept)

`.state-pill`, `.hof-pill`, `.roster-card .you-badge`, `.dash-r1 .player-card .you-pill`, `.dash-r1 .player-card .hof-pill-r1`, `.dash-r1 .player-card .badges-pill`, `.dash-r1 .run-pill .badge`, `.map-r4 .sheet-status .pill`, `.map-r4 .group-card .head .pill`, `.pc-box-r2 .badge-legend .badge`, `.pc-box-r2 .type-pill`. All stay, but **off-scale `2px 5px` paddings snap to `2px 6px`** (`var(--s-1) var(--s-2)`) for visual consistency — affects 4 declarations site-wide.

---

## 6. Cards

```css
.card {
  background: var(--moss);
  border: 2px solid var(--ink);
  padding: var(--s-5);                    /* 12px */
  margin-bottom: var(--s-4);              /* 10px */
}

.card--dark      { background: var(--shade);  color: var(--canvas); }
.card--shadow    { background: var(--shadow); }   /* deepest — inner panel */
.card--emphasis  { border-width: 3px; }
.card--active    { border: 4px solid var(--success); }
.card--warn      { border: 4px solid var(--accent); }
.card--danger    { border: 4px solid var(--danger);  }
```

### Existing card classes (kept)

`.gb-card` / `.gb-card-dark` (3px border treatment — legacy), `.route-card`, `.roster-card`, `.dash-r1 .player-card`, `.map-r4 .group-card`, `.map-r4 .special-cell`, `.pc-box-r2 .review-row`, `.pc-box-r2 .box-cell`, `.gb-candidate-card`, `.slot`. All stay — per-surface intentionality matters for cards (a draft-mode group-card legitimately wants a green-glow border, not a generic dark card).

The canon `.card` is the **forward path**.

---

## 7. Modals

```css
.modal {
  background: var(--moss);
  border: 4px solid var(--ink);
  padding: var(--s-7);                    /* 16px */
  max-width: 420px;
  margin: var(--s-7);                     /* 16px */
  position: relative;
  max-height: calc(100vh - 32px);
  overflow-y: auto;
}

.modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(15, 56, 15, 0.75);
  z-index: 50;
  display: flex;
  align-items: center;
  justify-content: center;
}
```

`.gb-modal` / `.gb-modal-backdrop` are the existing names — `.modal` is a forward-path alias.

The three "almost-modal" surfaces (`.confirm-inline`, `.map-r4 .sheet`, `.dash-r1 .run-pill-menu`) are **intentionally not modals** — they're inline / sticky / dropdown. They each have their own scoped class. Do not unify.

---

## 8. Borders (existing, unchanged)

```css
--border        = 3px solid var(--ink)
--border-thin   = 2px solid var(--ink)
--border-double = 4px double var(--ink)
```

Plus ad-hoc treatments: `1px solid var(--shade)`, `1px dashed var(--shade)`, `2px solid var(--shadow)`, `4px solid var(--accent)`, `4px solid var(--success)`. All remain — they encode meaning ("4px amber = warn-emphasis", etc.).

---

## 9. What this canon does NOT cover

- The `.tcg-coin*` Pokéball flip illustration — single-purpose decorative.
- `.gb-avatar--c0..c3` initial-letter fallback pastels — purely seeded-by-user-id.
- `.conflict-warning` deep-amber surface — single-use save-slot warning.
- `.pc-box-r2 .box-cell.dead` extra-dark dead cell — intentionally deeper than `--danger-bg`.
- `.gb-flash-notice` (uses `--shade` / `--canvas` — already on canon).
- Animations (`screenFlash`, `pulseNext`, `subtleBlink`, `dialogBlink`, `tcgCoinFlip`) — preserved as-is.

---

## 10. Adoption guidance for new work

1. Start a new surface with `.btn`, `.pill`, `.card`, `.modal` (no per-surface class) when you can.
2. If you need per-surface tweaks (color override, layout), namespace them: `.your-section .btn--primary { … }`.
3. Reach for **semantic** tokens first (`--accent`, `--success`, `--danger`) — fall back to positional (`--ink`, `--shade`) only when the role is genuinely about the *position* in the palette, not the *meaning*.
4. Spacing: snap to the 8 scale steps. If you need something between, the answer is almost always "use the next step up".
5. Type sizes: use one of the 7 scale steps. Decorative one-offs are allowed but should not be promoted to tokens.
6. Letter-spacing: prefer `var(--ls-default)` (`1px`) for caps + `Press Start 2P`. Use `var(--ls-tight)` for compact dense layouts only.
