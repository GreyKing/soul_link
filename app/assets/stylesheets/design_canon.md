# Soul Link Design Canon

*Locked 2026-05-06 (Step 25). Updated 2026-05-06 (Step 27) — visual primitives re-pinned to the legacy `gb-*` idiom after the Phase-2 redesigns drifted too far toward decorative chrome.*

The site has a deliberate **Game Boy / Pokémon Platinum CRT** aesthetic — `Press Start 2P` display + `VT323` body, dimmed green accent, 2-3 px solid borders, no rounded corners except for circles, scanline overlay. This canon does not change that aesthetic — it tightens the *language* used inside it so future surfaces speak the same dialect as the existing un-redesigned views (`/species`, `/teams`, the gym-draft, the run-management views).

When in doubt, use semantic names. Existing positional names (`--d0`, `--l1`, etc.) remain as the source of truth — semantic names alias them.

---

## 0. The Game-Boy-menu-density principle (Step 27)

**The canonical visual language for Soul Link is text-first, fewer chrome elements per screen, accent color used sparingly for emphasis not decoration.** It mimics a Game Boy menu — high information density, low decorative density.

The reference surfaces are **`/species`** and **`/teams`**. They demonstrate:

- One header per screen — a 2-line `gb-page-title` + `gb-page-subtitle`. No boxed title-bar, no title-glyph, no stat-strip.
- One tablist per surface (and only when navigation is needed). `/species` has one `tab-bar` with `tab-item`s — single horizontal strip, single-line label, bg swap on active.
- Status conveyed by the **existing** surface's bg/border — `.gb-status-dead` is a **modifier on the card**, not a new pill.
- One inline status pill per row, single color treatment. Not a 4-pill stack with 4 colors.
- No animations beyond `transition: 0.05s` color swaps. No `pulseNext`, no `subtleBlink`, no hover-`translateY`, no glow box-shadows on dots.
- No badge-dots, no glyph-squares, no gradient-fade overlays, no sub-tabs nested inside panels.

The four Phase-2-redesigned surfaces (Step 21–24: dashboard, save slots, PC Box review, map timeline) keep their **functional** improvements (URL persistence, ARIA tablist, drag-drop, modal pre-fill) and rebase their **visual chrome** to these primitives.

Anything not on the canon below is a candidate for removal during a Step 27-style consolidation — even if it was added in good faith for a real affordance. Real affordances usually have a quieter expression in the canon idiom (a bg swap instead of a glow, a 2 px border instead of a 3 px border + ring + animation).

### What changed vs Step 25's canon

Step 25 set up the **token-level** canon (spacing scale, type scale, danger family, semantic aliases) and explicitly framed the canonical primitives `.btn` / `.pill` / `.card` / `.modal` as the **forward path** for new work. Step 27 re-anchors those primitives to the **old gb-\* idiom** (instead of the slightly-glossier values that the Phase-2 redesign block introduced):

- **`.btn` primitives** rebase to the `gb-btn` form (11 px font, 8 × 14 padding, 2 px solid border, single-line label, `transition: 0.05s` bg swap on hover — no `translateY`, no glow). The `--ls-tight` letter-spacing is the canon (Step 25).
- **`.pill` primitives** stay at 7 px font, 2 × 6 padding (Step 25). The Step 27 directive is that **active states get one bg swap, not a multi-color family**. Pill kind (1ST / TRADE / EVENT / OFFFEED, etc.) is conveyed by the **label**, not by 4 different colors.
- **`.card` primitives** rebase to the `gb-card` form (3 px solid `--ink` border = `--border`, 12 px padding, 10 px margin-bottom). No `.card--shadow` glossy variant. Active = thicker border, not a glow ring.
- **`.modal` primitives** stay at the `gb-modal` form (4 px solid `--ink` border, 16 px padding). Title carries a 2 px border-bottom underline; no glyph-square, no inline status pill.
- **Section structure** uses **stacked `gb-section-header`s** instead of nested sub-tablists. A panel internal to a tab does not need a second tablist — header + section + content is enough.

If a future redesign wants to introduce new chrome (a status-bar, a filter chip row, a sub-tablist), the burden is on the redesign to justify why the old primitives are insufficient. The default answer is: they aren't.

---

## 1. Color tokens

> *Step 26 (2026-05-06): `--accent` rebased from `--amber` to `--green-glow` per user feedback — the site's main accent is now vibrant green. `--amber` stays defined as a positional palette token but is unreferenced. `--success` and `--accent` now resolve to the same hex; the semantic distinction is preserved in prose (success = state markers; accent = primary attention).*

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
| `--accent` (= `--green-glow`) | `#5fd45f` | CTA button bg, earned badge, focus ring, "next" pulse, run-pill border |
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

3 sizes × 3 styles, plus a `--ghost` modifier for the dashed-transparent treatment. **Re-pinned to gb-btn values (Step 27).**

### Sizes

```css
.btn--sm   { font-size: var(--t-md);   padding: 4px 8px; }                  /* 10px font, 4×8  — gb-btn-sm */
.btn       { font-size: var(--t-body); padding: 8px 14px; }                 /* 11px font, 8×14 — gb-btn (canonical) */
.btn--lg   { font-size: var(--t-lg);   padding: var(--s-3) var(--s-6); }    /* 13px font, 8×14 (rare; promoted page-CTA only) */
```

All buttons share:

```css
font-family: 'Press Start 2P', monospace;
letter-spacing: var(--ls-tight);     /* 0.5px — gb-btn baseline */
line-height: 1.4;
cursor: pointer;
transition: all 0.05s;               /* one-frame snap, NOT a fade */
```

**Single-line text labels.** Never icon-stacked-above-label. If you need an icon, prefix it inline (`☰ MENU`).

### Styles

```css
.btn               { background: var(--moss);      color: var(--ink);       border: var(--border-thin); }   /* gb-btn       */
.btn--primary      { background: var(--ink);       color: var(--canvas);    border: var(--border-thin); }   /* gb-btn-primary — primary = bg-swap to dark, NOT accent green bg */
.btn--danger       { background: var(--danger-bg); color: var(--danger-fg); border: 2px solid var(--danger-border); }
.btn--ghost        { background: transparent;      color: var(--moss);      border: 1px dashed var(--shade); }
```

Hover = bg/fg swap (`.btn:hover { background: var(--shade); color: var(--canvas); }`). **No** `transform: translateY`, **no** `box-shadow`, **no** outline ring, **no** filter brightness.

### Existing classes (kept, do not rebase the class itself)

`.gb-btn`, `.gb-btn-primary`, `.gb-btn-danger`, `.gb-btn-sm`, `.slot-actions button`, `.confirm-inline .actions button`, `.map-r4 .submit-btn`, `.dash-r1 .next-battle .draft-cta`, `.dash-r1 .run-pill-menu .start-btn`, `.pc-box-r2 .review-row .actions button`, `.pc-box-r2 .filter-chip`, `.map-r4 .status-bar .jump-btn`, `.map-r4 .dupes-btn`, `.map-r4 .sheet-head .close`, `.dash-r1 .side-tab` — all stay.

**Step 27 directives** for buttons inside the Phase-2-redesigned surfaces:

- Drop hover `translateY`, `transform: scale`, `filter: brightness`, `box-shadow` glows.
- Drop multi-color "primary / danger / confirm" stacks within a single button cluster — at most ONE accent-bg button per cluster (the actual primary action). The rest are `gb-btn` form (light-bg), even if they're labeled DELETE / DISMISS / SKIP — those use color **on the text**, not on the entire button background.
- Drop animated buttons (`subtleBlink`, etc.). Static.

---

## 5. Pills

1 primitive + 4 style modifiers + 2 size modifiers. **Re-pinned (Step 27): one pill per row default; multi-pill stacks are a code smell.**

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

.pill--ghost    { color: var(--moss);   background: transparent;    border-color: var(--moss);    }    /* the default — neutral text-on-transparent */
.pill--success  { color: var(--shadow); background: var(--success); border-color: var(--success); }
.pill--accent   { color: var(--shadow); background: var(--accent);  border-color: var(--accent);  }
.pill--danger   { color: var(--paper);  background: var(--danger);  border-color: var(--danger);  }
```

### Multi-pill rule (Step 27)

A single row of content may carry **at most one** colored pill (`pill--success` / `pill--accent` / `pill--danger`). Additional informational pills on the same row default to `pill--ghost` — neutral text-on-transparent so the eye registers them as labels, not as colored decorations.

If a row needs to convey four orthogonal flags (e.g. PC Box review-tray's 1ST / TRADE-IN / EVENT / OFF-FEED), use **four ghost pills with text labels** rather than four color-coded pills. The information lives in the label, not the color.

### Existing pill-shaped classes (kept where functional, removed where decorative)

Kept (functional state markers):
`.state-pill` (5 variants — empty/saved/active/target/confirm; each represents a distinct save-slot state), `.hof-pill` (HOF achievement marker), `.pc-box-r2 .type-pill` (covered/gap/weak — type analysis output).

Removed in Step 27 (decorative, not load-bearing):
`.dash-r1 .player-card .you-pill` (the `.player-card.you` border already conveys "you"), `.dash-r1 .player-card .hof-pill-r1` (replaced by 🏆 prefix in name), `.dash-r1 .player-card .badges-pill` (replaced by inline `N/8 BADGES` text), `.dash-r1 .run-pill .badge` (status moves into the run-pill label as text).

Restyled in Step 27 (kept, but rebased to `pill--ghost` form unless meaningfully a state marker):
`.pc-box-r2 .badge-legend .badge`, `.dash-r1 .run-pill-menu .run-option .pill`.

**Off-scale `2px 5px` paddings already snap to `2px 6px`** (= `var(--s-1) var(--s-2)`) per Step 25.

---

## 6. Cards

**Re-pinned to `gb-card` / `gb-card-dark` values (Step 27).** The 3 px solid `--ink` border is the load-bearing visual element. No `box-shadow`, no `transform: translateY` on hover, no `.card--shadow` glossy variant.

```css
.card {
  background: var(--moss);                /* gb-card */
  border: var(--border);                  /* 3px solid var(--ink) */
  padding: var(--s-5);                    /* 12px */
  margin-bottom: var(--s-4);              /* 10px */
}

.card--dark      { background: var(--shade); color: var(--canvas); border: var(--border); }   /* gb-card-dark */
.card--active    { border: 4px solid var(--success); padding: 9px; }   /* the 1px-shorter padding offsets the +1px border so layout is stable */
.card--accent    { border: 2px solid var(--accent); }                  /* "current/highlighted" emphasis (e.g. .player-card.you) */
.card--danger    { background: var(--danger-bg); border: 2px solid var(--danger-border); color: var(--danger-fg); }   /* gb-status-dead applied to a card */
```

Hover behavior: **none by default**. A clickable card may swap its border color (`border-color: var(--accent)`) on hover — one-frame snap, no `translateY`, no `box-shadow`.

### Existing card classes (kept)

`.gb-card` / `.gb-card-dark` (the canon's reference shape), `.route-card`, `.roster-card`, `.dash-r1 .player-card`, `.map-r4 .group-card`, `.map-r4 .special-cell`, `.pc-box-r2 .review-row`, `.pc-box-r2 .box-cell`, `.gb-candidate-card`, `.slot`. All stay.

**Step 27 directives** for cards inside the Phase-2-redesigned surfaces:

- Drop hover `translateY` lifts (currently on `.pc-box-r2 .box-cell`, `.map-r4 .special-cell`, `.map-r4 .badge-strip .badge`).
- Drop hover `box-shadow` glows.
- Rebase decorative-bg cards to `--moss` / `--shade` (no `--shadow`-deep `--d0` backgrounds for non-status content — that depth is reserved for the page background overlay and danger-state extra-dark).
- Active state = thicker border (3 px → 4 px) or border color swap. Not an outline ring + glow + animation.

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

Plus ad-hoc treatments: `1px solid var(--shade)`, `1px dashed var(--shade)`, `2px solid var(--shadow)`, `4px solid var(--accent)`, `4px solid var(--success)`. All remain — they encode meaning ("4px accent-green = active-emphasis", etc.).

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

---

## 11. Chrome-reduction rules (Step 27)

These rules describe what the canonical idiom **does not** include. They are pinned here so future work doesn't re-introduce the chrome that the Phase-2 redesigns added and Step 27 removed.

### 11.1 Per-surface chrome budget

Each top-level surface gets:
- One header (`gb-page-title` + `gb-page-subtitle`). Not a boxed bar with title-glyph + stat-strip + sub-pills.
- At most one tablist (the existing `tab-bar`). No nested sub-tablists inside panels.
- Optional `gb-section-header`s within the content area (one short bar per section). No badge dots or count chips on section headers — counts go inline in the title text (`PARTY (3)`).

If a surface needs more navigation than that, the answer is usually to **split content**, not to **add chrome**.

### 11.2 Banned visual primitives

These do not appear in `/species` or `/teams` and may not be added to other surfaces:

- **Title-glyph** — a colored square with initials / number / icon next to a header. The header text is the title.
- **Badge-dot** — a small colored circle with `box-shadow` glow indicating "fresh content". A short text suffix (`*` or `(NEW)`) carries the same meaning without the chrome.
- **Multi-color inline pill stack** — 3+ pills on one row with 3+ different bg colors. Use ghost pills + label text instead (Section 5).
- **Stacked chrome bars** before content — title-bar + status-bar + filter-bar + legend-bar before the actual feature. Pick one.
- **Sticky transient-mode banners** — full-bleed accented banners announcing a temporary state. Use an inline notice (`gb-flash-notice` / `gb-flash-alert`) at the top of the content, not a sticky banner above the layout.
- **Animations beyond `transition: 0.05s` color/border swaps.** No `pulseNext`, `subtleBlink`, hover `translateY`, `transform: scale`, `filter: brightness`, `box-shadow` glows.
- **Gradient-fade overlays** (`linear-gradient(to right, transparent, var(--d1))` on container edges). The overflow already implies more content.
- **Active-state outline rings** beyond a single border-width or border-color change. `outline: 3px solid var(--accent); outline-offset: 2px` on `:focus-visible` is a different thing — that's a a11y affordance and stays.
- **Vertical 2-line buttons** (icon stacked above label). Single-line text labels with optional inline icon prefix.
- **Per-item color coding inside a stat strip** (ALIVE green, DEAD crimson, BADGES amber). The labels do the work.

### 11.3 Allowed exceptions

- Sprites are pictorial content, not chrome — they're not subject to these rules.
- The TCG coin-flip (`.tcg-coin*`) is a single-purpose animation that survives intentionally.
- The `gb-status-dead` family is allowed to color-shift the entire card bg/border (it's a *modifier*, not a *new pill*).
- `:focus-visible` outline rings stay — they're a11y, not chrome.
- The `.dash-r1 .gym-list .gym-row.next .num` 2 px border emphasis stays as a static affordance (no animation).
- The `.slot.active` 4 px green-glow border stays — it represents an active save target, a real state.
- The `.pc-box-r2 .review-row.first` 3 px green-glow border stays — it represents the recommended action, a real state.

### 11.4 Tab-bar canonical form

The legacy `.tab-bar` / `.tab-item` is the canonical form (used by `/species`):

```css
.tab-bar  { display: flex; background: var(--ink); border-bottom: var(--border); }
.tab-item { flex: 1; padding: 10px 8px; font-size: var(--t-lg); /* 13px */ background: var(--shade); border-right: 2px solid var(--shade); }
.tab-item.active { background: var(--ink); color: var(--canvas); }
```

- Single horizontal strip, single-line label.
- Active = bg swap from `--shade` to `--ink`. **No** colored underline, **no** glow, **no** badge-dot.
- Optional inline icon prefix in the label text (`☰ MENU`).

The `.dash-r1 .tab-bar` rebases to this form in Step 27. Functional `aria-selected` / `tabindex` / keyboard navigation are preserved — only the visual changes.

### 11.5 Section-header (replaces nested sub-tablists)

When a panel has multiple kinds of content that previously lived behind sub-tabs, use stacked sections:

```html
<section>
  <h3 class="gb-section-header">PARTY <span style="opacity:0.6">(3)</span></h3>
  <!-- party content -->
</section>
<section>
  <h3 class="gb-section-header">GYMS <span style="opacity:0.6">(2/8)</span></h3>
  <!-- gym list -->
</section>
```

The Stimulus controller's `data-target="tabPanel"` pattern stays; the visual treatment is sections instead of tabs.
