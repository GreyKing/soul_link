# Old-Style Canon Audit — Step 27 (2026-05-06)

*Architect: Ava. Source-of-truth audit for the Step 27 restyle.*

User's framing: *"dashboard has gotten busier and busier and when it looked more like the pc box (the original inspiration) it felt cluttered but aesthetically consistent. /teams is another 'old style' view. I am definitely okay with the functional improvements, I like the updates I just think the old style was a little more fitting for the site."*

The Phase 2 redesigns (Steps 21–24) added pills, badges, filter chips, sticky banners, sub-tabs, sub-pills, badge-dots, glyph-squares, animations, and stacked chrome bars. Each addition was justified individually; collectively they pushed the four surfaces away from the **Game-Boy-menu-density** dialect that `/species` + `/teams` still speak. This audit catalogues that dialect and lists every drifted primitive.

The four redesigned surfaces (R1 dashboard, R3 save slots, R2 PC Box review tray, R4 map timeline) keep their **functional** improvements — URL persistence, ARIA tablist, drag-drop, click-to-open, modal pre-fill. The visual treatment around those features rebases to the old-style canon.

---

## 1. The Old-Style Canon (extracted from `/species` + `/teams`)

### 1.1 Page chrome (single-bar, text-first)

`/species` and `/teams` start with a 2-line header and go straight to content:

```erb
<div class="gb-page-title">SPECIES ASSIGNMENT</div>
<div class="gb-page-subtitle">Drag your species from the pool onto the correct group.</div>
```

```css
.gb-page-title    { font-size: 18px; color: var(--d1); margin-bottom: 4px; }
.gb-page-subtitle { font-size: 11px; color: var(--d2); margin-bottom: 16px; }
```

**No** title-bar background, **no** title-glyph, **no** stat-strip, **no** status badges, **no** sub-pills. A title and a subtitle. That's it.

### 1.2 Cards — `gb-card` / `gb-card-dark`

```css
.gb-card      { background: var(--l1); border: var(--border); padding: 12px; margin-bottom: 10px; }
.gb-card-dark { background: var(--d2); color: var(--l2); border: var(--border); padding: 12px; margin-bottom: 10px; }
```

- 3px solid `--ink` border (= `--border`) — the load-bearing visual primitive of the entire site.
- 12 px padding (= `--s-5`) all sides.
- 10 px margin-bottom (= `--s-4`).
- No box-shadow, no transitions, no hover-lift, no gradient fades.
- One color (`--l1` light or `--d2` dark) per card; emphasis is achieved by the border, not by accent rings.

### 1.3 Buttons — `gb-btn` / `gb-btn-primary` / `gb-btn-danger` / `gb-btn-sm`

```css
.gb-btn         { font: 11px PressStart2P; padding: 8px 14px; border: var(--border-thin); background: var(--l1);     color: var(--d1); ls: var(--ls-tight); lh: 1.4; }
.gb-btn-primary { font: 11px PressStart2P; padding: 8px 14px; border: var(--border-thin); background: var(--d1);     color: var(--l2); ls: var(--ls-tight); lh: 1.4; }
.gb-btn-danger  { font: 11px PressStart2P; padding: 8px 14px; border: 2px solid var(--danger-border); background: var(--danger-bg); color: var(--danger-fg); }
.gb-btn-sm      { font-size: 10px; padding: 4px 8px; }
```

- Single-line text labels. Always.
- 2-px solid border (= `--border-thin`).
- Hover swaps bg ↔ fg, no glow / shadow / transform / animation.
- `transition: all 0.05s` (one-frame snap, not a fade).

### 1.4 Tab-bar — legacy `.tab-bar` / `.tab-item`

```css
.tab-bar  { display: flex; background: var(--d1); border-bottom: var(--border); }
.tab-item { flex: 1; padding: 10px 8px; font-size: 13px; color: var(--l1); background: var(--d2); border-right: 2px solid var(--d2); transition: background 0.05s; ls: 0.05em; }
.tab-item.active { background: var(--d1); color: var(--l2); }
```

- **Single horizontal strip.** No icon-stacked-above-label. No vertical 2-line layout.
- 13 px font, 10 × 8 px padding.
- Active state = background swap to `--d1`. **No** colored underline, **no** badge-dot, **no** active-text-color shift to `--accent`.

### 1.5 Section header — `.gb-section-header`

```css
.gb-section-header { background: var(--d1); color: var(--l2); padding: 8px 12px; font-size: 13px; ls: 0.1em; margin-bottom: 8px; }
```

- Single horizontal bar with caps text.
- No glyph, no count chip, no inline status pill, no sub-tabs underneath.
- One bar per section, one section per logical group of content.

### 1.6 Modal — `.gb-modal`

```css
.gb-modal-backdrop { position: fixed; inset: 0; background: rgba(15, 56, 15, 0.75); }
.gb-modal          { background: var(--l1); border: var(--border); border-width: 4px; padding: 16px; max-width: 420px; }
.gb-modal-title    { font-size: 14px; color: var(--d1); padding-bottom: 8px; border-bottom: var(--border-thin); }
```

- 4px solid `--ink` border. The border itself is the chrome.
- 14 px title with a 2 px border-bottom underline. No glyph, no badge, no sub-actions, no drag handle.

### 1.7 Inline status — `.gb-status-dead` / `.gb-status-caught`

```css
.gb-status-dead   { background: var(--danger-bg); border-color: var(--danger-border); color: var(--danger-fg); }
.gb-status-caught { background: var(--l1); }
```

- A class modifier, **applied to the existing card or button**. Not a new pill, not a new badge.
- Status is conveyed by changing the *existing* surface's bg/border, not by stacking a new primitive on top of it.

### 1.8 Drag zones — `.gb-drag-zone` / `.gb-drag-item`

```css
.gb-drag-zone { border: var(--border-thin); border-style: dashed; background: var(--l2); padding: 8px; }
.gb-drag-item { background: var(--l1); border: var(--border-thin); padding: 8px 10px; margin-bottom: 4px; }
```

- 2-px **dashed** border = "drop target" affordance. The dashing is the entire signal.
- No hover glow, no animated outline, no pulsing border. Drag-item gets `cursor: grab` and a bg swap on hover. That is it.

### 1.9 Inline labels & sub-text

`/species` group-card row:

```erb
<span style="font-size: 10px; width: 80px; ...">PLAYER NAME</span>
<span style="font-size: 10px; padding: 2px 8px; border: var(--border-thin); ...">SPECIES NAME + sprite + types</span>
```

- Inline labels `width: 80px` truncate-with-ellipsis.
- Inline status pill = bordered text with sprite, **single color treatment** (you/them = bg swap, not a new color family).
- 2 × 8 px padding — the canon's compact pill.

### 1.10 Layout grid — `.gb-grid-2/3/4`

```css
.gb-grid-2 { grid-template-columns: repeat(2, 1fr); gap: 8px; }
.gb-grid-3 { grid-template-columns: repeat(3, 1fr); gap: 8px; }
.gb-grid-4 { grid-template-columns: repeat(4, 1fr); gap: 8px; }
```

- Single CSS grid utility. No nested status-rails, no inset sub-grids, no sticky sidebars.
- 8 px gap (= `--s-3`).

### 1.11 What is NOT in the old canon

- **No badge-dots** (the small colored circle indicators with box-shadow glow).
- **No glyph-squares** (the 36 × 36 colored square with initials / number / icon at the front of a header).
- **No multi-color inline pill stacks** (1ST + TRADE-IN + EVENT + OFF-FEED on one row).
- **No sub-tabs nested inside a panel.** A page picks one tablist; sub-content is sectioned with `.gb-section-header`, not with a second tablist.
- **No filter chip rows separate from the primary tab-bar.** Filtering happens via search input or via the existing tab choices.
- **No sticky banner alerting the user to a transient mode.** Transient modes use the existing primitives (a different button color, an inline confirm row).
- **No animations beyond `transition: 0.05s` color swaps.** (`pulseNext`, `subtleBlink`, hover-lift transforms are post-canon additions.)
- **No accent-color underlines / outline rings on active states.** Active state = bg swap.
- **No 2-line vertical buttons** (icon stacked above label).
- **No gradient fades (linear-gradient overlays) on container edges.**
- **No box-shadow glows.**

---

## 2. The Drift Catalogue — what each Phase-2 redesign added

### 2.1 Step 24 — `.dash-r1` Dashboard (HIGHEST PRIORITY)

**Title bar (`.dash-r1 .title-bar`)** — chrome-dense block:
1. `.title-glyph` — 36 × 36 amber square with player initials, 2 px `--d0` border
2. `.title-block` — 2-line player block (name + meta line)
3. `.run-pill-wrap` → `.run-pill` — capsule with status badge (ACTIVE/HOF/ENDED) + chev triangle + dropdown menu
4. `.run-pill .badge` (3 variants: default green, hof accent, dim grey) inside the run-pill itself
5. `.stat-strip` — CAUGHT · ALIVE · DEAD · BADGES with `·` separators and per-item color coding (ALIVE green, DEAD crimson, BADGES amber)

→ **Drift:** 5 stacked chrome elements where /species uses 1 (gb-page-title).

**Tab-bar (`.dash-r1 .tab-bar`)** — vertical-stacked tabs:
- Each tab = `.icon` (14 px) on top + label (9 px) below = 2-line button
- Active state: bg swap **plus** a 3 px accent-green underline (`::after` element)
- `.badge-dot` — top-right colored circle with `box-shadow: 0 0 4px var(--green-glow)` (glow effect)

→ **Drift:** vertical 2-line buttons + accent underline + glow-shadow dots vs old `.tab-item` single-line + bg swap.

**Status rail (`.dash-r1 .status-rail`)** — sub-tabs nested inside a panel:
- `.side-tabs` — 3-tab sub-tablist (PARTY · GYMS · MAP) with accent-green active state
- Each sub-panel has an `.h3-row` with a count chip + a dashed divider underneath

→ **Drift:** a panel-internal tablist (the canon doesn't have nested tablists) + count-chip on every section header.

**Player cards (`.dash-r1 .player-card`)** — multi-pill stack:
- `.you-pill` (accent bg)
- `.hof-pill-r1` (accent bg, 6 px font)
- `.badges-pill` (green-glow text, can shift to accent when full)

→ **Drift:** 3 pills per card. /species uses one inline status pill.

**Run pill menu (`.run-pill-menu .run-option`)** — dropdown options each carry a status pill (`pill` + `pill.hof`).

**Stat strip color coding** — per-item color values (`.alive .val { color: var(--green-glow); }`, etc.).

### 2.2 Step 21 — `.slot` / `.state-pill` Save Slots column

**Sticky `.pending-banner`** (full-bleed amber, with icon + uppercase text + cancel button):
- Background `var(--accent)`, 2 px `--d0` border
- 14 px icon glyph + 9 px label + inline cancel button

→ **Drift:** sticky transient-mode banner. /species shows transient state inline (e.g. "Drop your species here" placeholder in the drop-zone).

**`.state-pill`** — 5 color variants (empty/saved/active/target/confirm).

**`.slot.active`** — 4 px green-glow border (vs 2 px standard).

**`.slot-actions`** — inline button row with primary/danger/confirm color modifiers (4 button styles per slot).

**`.confirm-inline`** — inline confirm with separate header (`.q`), body, and action row.

**`.hof-pill`** — 🏆 HOF inline pill on the slot card.

### 2.3 Step 22 — `.pc-box-r2` Review Tray

**`.review-tray`** — boxed black-on-accent-border container (`--d0` bg, 2 px accent border, 14 × 16 padding).

**`.review-tray-head`** — h3 + count chip (`background: var(--accent); color: var(--d0);`) — accent-colored count badge.

**`.badge-legend`** — separate boxed legend grid (1 px dashed `--d2`), 2-up grid of 4 badges + descriptions:
- `.badge.first` (green-glow)
- `.badge.trade` (accent)
- `.badge.event` (`--d2` text on `--l1`)
- `.badge.offfeed` (`--l1`)

**`.review-row`** — 3-col grid (sprite 56 × 56 + meta + actions):
- Inline pill stack on `.name` row (1ST + TRADE-IN + EVENT + OFF-FEED)
- `.review-row.first` — 3 px green-glow border emphasis

**`.filter-bar` + `.filter-chip`** — separate filter row above the grid (4 chips with `.active` accent state + dim-non-active behavior + free-text search).

→ **Drift:** stacked chrome bars (review-tray + badge-legend + filter-bar) before the actual content. Filter chips are a second navigational system on top of the existing tab-bar.

**`.box-cell:hover`** — `transform: translateY(-2px)` lift + `border-color: var(--accent)` glow.

### 2.4 Step 23 — `.map-r4` Map Timeline

**`.map-head`** — boxed title bar (12 × 18 padding, `--border`) with h2 + subtitle + `.badge-strip` of 8 badges (28 × 28 with hover-translate-y).

**`.status-bar`** — separate bar for NEXT GYM + LEVEL CAP + CURRENT SEG + JUMP TO NOW button (with `subtleBlink` animation).

**`.node-legend`** — separate legend bar (1 px dashed) with 5 color-coded glyph-squares.

**`.timeline-frame::before` / `::after`** — `linear-gradient` fade-out overlays on left/right edges.

**`.node`** — 56 × 56 glyph + label + nick. Hover transforms (`translateY(-2px)`, `border-color: var(--accent)`, `box-shadow: 0 4px 0 rgba(95,212,95,0.3)`).

**`.node.next`** — 3 px accent border + 0 0 0 5 px accent ring + glow + `pulseNext` animation.

**`.node-now-pin`** — pulsing label tag pinned above the .next node.

**`.special-bar`** — 4-up grid of special encounter cells with hover-lift transforms.

**`.sheet`** — sticky right rail with multi-section scrollable body.

→ **Drift:** four stacked chrome bars (map-head + status-bar + node-legend + special-bar) all before / around the actual timeline. /species has a 2-line title and the content underneath.

---

## 3. Reduction directives — per-surface

For each redesigned surface, we keep the **structure** and **interaction**, and rebase the **chrome** to old-canon primitives.

### 3.1 Dashboard (`.dash-r1`) — most-acute regression

| Element | Now | After Step 27 |
|---|---|---|
| `.title-bar` | Boxed `--d1` bar with title-glyph + 2-line player block + run-pill + stat-strip | Single 2-line `gb-page-title` + `gb-page-subtitle`. Run picker becomes a `gb-btn-sm`-style button next to the subtitle (or moves below the title). Stat strip becomes a single dim line ("CAUGHT 12 · ALIVE 8 · DEAD 4 · BADGES 3/8") in `.gb-page-subtitle` styling — no per-item color coding. |
| `.title-glyph` | 36 × 36 amber square with initials | **Remove.** The page title already says whose dashboard it is. |
| `.run-pill` (the pill itself) | Capsule with 2 px accent border + status badge + chev | Restyle to `gb-btn` form (2 px `--ink` border, `--l1`/`--l2` color treatment). Status indicator becomes inline text inside the button label (`RUN #2 — ACTIVE ▾`) instead of a separate badge. Dropdown menu still works. |
| `.run-pill .badge` (inside-pill badges) | 3 color variants | **Remove from the trigger label.** Single text status next to the run number — bg swap conveys ENDED/HOF (bg `--d2` for ended, `--accent` for HOF). |
| `.run-pill-menu .run-option .pill` | Pill on every menu option | Rebase to inline `[ACTIVE]` / `[HOF]` / `[PAST]` plain-text suffix in the `.label` span. Same info, no inline pill chrome. |
| `.stat-strip` | 4 stat items with `·` separators + per-item color coding (alive/dead/badges) | **Remove per-item color coding.** Single line `--l1` text with `--white` values. ALIVE / DEAD / BADGES values stay readable but lose the green/crimson/amber per-value coloring — the info already reads from the label. |
| `.tab-bar` (.dash-r1's version) | Vertical 2-line tabs (icon stacked over label) + active accent underline + badge-dots | Rebase to legacy `.tab-bar` / `.tab-item` form: single horizontal strip, single-line label (drop the icon line), 13 px font, bg swap on active (no underline). |
| `.tab .badge-dot` | Top-right colored circle with glow box-shadow | **Remove.** "PC BOX has new parsed catches" is conveyed by the review-tray itself once the tab is opened. The tab-bar shouldn't carry an attention indicator on top of an already-navigable surface. *(Architect call — escalating: this drops a real affordance. Recommend keeping but re-shaping as a small unstyled `*` suffix on the tab text — same affordance, no glow chrome.)* |
| `.status-rail .side-tabs` (sub-tabs) | Mini-tablist inside the panel | Rebase to `gb-section-header` headings stacked. PARTY / GYMS / MAP each become its own `<section>` with a `gb-section-header`. They're all in the right rail anyway — nesting tabs inside doesn't shorten the page. |
| `.player-card .you-pill` / `.hof-pill-r1` / `.badges-pill` | 3 pills per card | **Drop all three.** YOU is conveyed by the existing `.player-card.you` border treatment (already 2 px accent — keep it). HOF can be a 🏆 prefix in the `.name` span. BADGES count goes inline in the `.head` row as plain text (`3/8 BADGES`) with no pill background. |
| `.player-card` | `--d2` bg + 1 px `--d0` border + 8 px padding | Rebase to `gb-card-dark` shape (3 px `--ink` border, 12 px padding). Keep the `.you` accent-border emphasis. |
| `.next-battle .draft-cta` | Big green-accent CTA button with 2 px `--d0` border | Rebase to `gb-btn-primary` form. Keep the prominence (it's the primary action) — primary in old canon = `--d1` bg + `--l2` text + 2 px `--ink` border. |
| `.gym-list .gym-row.next .num` | 2 px accent border + `pulseNext` animation | **Drop the animation.** Keep the 2 px accent border — that's the static affordance. |

### 3.2 Save Slots (`.slot` + `.state-pill` + `.confirm-inline` + `.pending-banner`)

| Element | Now | After Step 27 |
|---|---|---|
| `.pending-banner` | Full-bleed accent banner with icon + uppercase + cancel | Rebase to `.gb-flash-alert` form (or a similarly-shaped notice-style block). Keep the cancel button. Drop the 14 px icon glyph in favor of plain text. |
| `.slot` | `--d1` bg, 2 px `--ink` border, 10 × 12 padding | Rebase to `gb-card-dark` shape (3 px border, 12 px padding). The `.active` 4-px green-glow border is a real affordance — keep it. |
| `.state-pill` (5 variants) | Color-coded mini-pill on every slot | Keep — these are state markers and they already use the canon palette (empty=`--d2`, saved=`--l2`, active=green-glow, target=accent, confirm=crimson). But pin the **padding to canon** (`var(--s-1) var(--s-2)` already done in Step 25, verify it still matches) and pin the **font scale to canon** (`var(--t-micro)` = 7 px). |
| `.slot-actions button.primary` / `.danger` / `.confirm` | 4 distinct button color treatments | Keep — these are functional state markers. But rebase **padding + font + border** to `gb-btn-sm` form (`4px 8px`, 10px font, 2 px border). Right now they're 6 × 8 + 8 px font + 1 px border — half a step off canon. |
| `.confirm-inline` | `--d0` bg, 2 px crimson border, separate `.q` header | Rebase: `--d2` bg (not `--d0` — too dark), `var(--border-thin)` border (2 px `--ink`, not crimson — the buttons inside carry the danger color, not the container), 10 px padding. The `.q` header rebases to `gb-section-header`-shape. |

### 3.3 PC Box Review Tray (`.pc-box-r2`)

| Element | Now | After Step 27 |
|---|---|---|
| `.review-tray` | `--d0` bg + 2 px accent border | Rebase to `gb-card-dark` (3 px `--ink` border, 12 px padding). The "review parsed catches" surface is a card, not a special accented zone. |
| `.review-tray-head .count` | Accent-bg count chip | Rebase to plain text `(3 NEW)` after the h3, no chip background. |
| `.badge-legend` | Boxed grid with 4 color-coded badges | **Collapse into the review-tray.** No separate boxed legend — the 4 badges (1ST / TRADE-IN / EVENT / OFF-FEED) move to the **first row** of `.review-tray` as a single inline legend strip ("LEGEND: 1ST = first encounter · TRADE-IN = traded · EVENT = mystery gift · OFF-FEED = from PC") in plain `--l1` text. |
| `.badge.first/trade/event/offfeed` (inline pills on rows) | Multi-color inline pill stack on each `.review-row .name` | Keep the badges (they're functional information), but rebase to a **single color treatment** — all 4 badges get the same `gb-pill`-style: 1 px `--l1` border + transparent bg + `--l1` text. The kind (1ST/TRADE/EVENT/OFFFEED) is conveyed by the **text label**, not by a different color. |
| `.review-row` | `--d1` bg, 2 px `--ink` border | Rebase padding + margin to canon (`--s-3`/`--s-5` family). Keep the 3-col grid. |
| `.review-row.first` | 3 px green-glow border emphasis | Keep — meaningful "this is the recommended action" cue. |
| `.filter-bar .filter-chip` | 4 chip pills with active = accent green bg + dim-non-active opacity | Rebase to **`gb-btn-sm` form**. Active state = bg swap to `--d1` + text `--l2` (matches `.tab-item.active`). No accent green bg, no opacity dim. The dim-on-non-active behavior was a fade — confusing; bg-swap is enough. |
| `.box-cell:hover` | `translateY(-2px)` + accent border | Drop the translate. Keep border swap to `--accent` (1-frame snap). |
| `.empty-tray-bar` | `--d0` bg + 1 px dashed | Rebase to a `gb-flash-notice`-style inline strip (current `--shade`/`--canvas` palette already on canon). Drop the 10 px green-glow check glyph in favor of an inline `(✓)` text. |

### 3.4 Map / Route timeline (`.map-r4`)

| Element | Now | After Step 27 |
|---|---|---|
| `.map-head` | Boxed `--d1` bar with h2 + sub + 8-badge strip | Rebase to `gb-page-title` + `gb-page-subtitle` form (no boxed background). Badge-strip moves below as its own `gb-section` ("BADGES" header + the 8 28×28 badges). |
| `.badge-strip .badge` | 28 × 28 button with 2 px `--d0` border + accent glow when earned + hover translate | Drop the box-shadow glow + hover translate. Keep the 28 × 28 dimensions (the badges literally need to be visible badges). Active = bg swap to `--accent` only. |
| `.status-bar` | Separate `--d2` bar with 3 stat items + JUMP TO NOW button | Rebase to a single `gb-card-dark`-shape row. JUMP TO NOW button rebases to `gb-btn-primary`-shape (no `subtleBlink` animation). |
| `.status-bar .jump-btn` `subtleBlink` animation | Animated glow | Drop animation. Static `gb-btn-primary` with the existing label. |
| `.node-legend` | Separate dashed-border legend bar | Inline this into the `.gb-page-subtitle` line ("Legend: ● caught · ☠ dead · ○ uncaught · ★ special · G gym") — no separate boxed bar. |
| `.timeline-frame::before / ::after` | Linear-gradient fade overlays on edges | **Remove.** The horizontal scroll already implies more content; the gradient fades are gloss on top of an existing affordance. |
| `.node` `.glyph` 56 × 56 | Square glyph with hover translate + box-shadow | Keep the size. Drop the hover translate + box-shadow. Border-color swap on hover stays. |
| `.node.next` `pulseNext` animation + 5 px accent outer ring + glow | Multi-layered emphasis | Keep the 3 px accent inner border (the single canonical "NEXT" marker). Drop the outer 5 px ring and glow. Drop the animation (or replace with a static `↓ NOW` text label above the glyph — already exists as `.node-now-pin`, just make it static). |
| `.special-cell:hover` | `translateY(-2px)` + accent border | Drop translate. Keep border swap. |
| `.sheet` | Sticky right rail | Keep the sticky behavior (it's a layout choice, not chrome). Restyle the head to `gb-section-header` form. |

---

## 4. Accent color check

Step 26 rebased `--accent` from `--amber` → `--green-glow` (#5fd45f). `/species` and `/teams` use:
- `gb-card-dark` `--d2` bg + `--l2` text — no accent
- `gb-btn-primary` — `--d1` bg + `--l2` text — no accent on the button itself
- `gb-status-dead` — danger family, no accent

The legacy primitives use **almost no accent color at all**. Accent is reserved for the four redesigned surfaces (CTA buttons, NEXT markers, primary affordances). This matches the user's spirit ("accent color used sparingly for emphasis not decoration").

**No accent token change needed.** Step 26 green-glow is correct. The Step 27 work is to make accent appearances **rarer**, not differently-colored.

---

## 5. Architect call — single-step ship

**One big step (Step 27), not split into 27a/b/c/d.**

Reasoning:
- All four surfaces share the same primitive substitutions (boxed bar → `gb-page-title`, custom buttons → `gb-btn*`, multi-pill stacks → single-color or removal, animations → static, sub-tabs → `gb-section-header`). The application is mechanical.
- Splitting into 4 mini-steps would force 4 review/commit cycles for one design decision; the canon update applies once and propagates.
- The risk of inconsistency between mini-steps (one surface restyled "more" than another) is higher than the risk of bundling.
- The canon update in Half 2 is the **logical contract**; the four-surface application in Half 3 is the **mechanical fulfillment**.

If Bob hits a surface where a substitution requires nontrivial layout judgment (most likely: dashboard title-bar collapse), he should **stop and surface that to Ava** rather than guessing — then we ship that one as a follow-up Step 28 if it turns out to be substantive.

---

## 6. Functional features that MUST survive

Bob: do not regress any of these while restyling. Tested by existing test suite + manual smoke check.

- ARIA tablists on Step 24 dashboard tab-bar (`role="tab"` + `aria-selected` + `tabindex` + `keydown@window->pixeldex#numericJump`) — preserve all of it; only the *visual* of the tab changes.
- `run-picker` controller dropdown menu (Step 24 replaced inline `<select onchange>` with a Stimulus dropdown). Keep working.
- `status-rail` controller sub-tab switching (Step 24). The visual rebase to stacked `<section>`s means `.status-panel` containers stay; the `.side-tabs` button strip goes away. **However**, the controller depends on `data-status-rail-target="tabButton"` + `data-status-rail-target="tabPanel"`. If we collapse the sub-tabs into stacked sections, those are no longer behind tabs. **Architect decision:** keep the sub-tab structure functionally (the JS) but restyle the *buttons* to look like `gb-section-header`s. The user can still switch panels; the visual hierarchy reads as section-header rather than tablist. Bob must not delete the controller targets.
- `save-slots` controller — TARGET mode, inline DELETE confirm, CLEAR ALL inline confirm. All `data-save-slots-target=*` references stay.
- `pc-box-filter` controller — chip filtering, search input, `.filter-active` body class, dim-non-active behavior. The dim opacity behavior is dropped per directive 3.3, but the underlying filter still applies (display: none on filtered cells via `.filter-hidden` is functional).
- `review-tray` controller — pre-fill into catch modal, dismiss row (`.dismissed` opacity stays — it's the "you skipped this" cue).
- `timeline` controller — sheet open/close, jumpToNow button, accordion segments, gym toggle. Visual rebase only.
- Step 20 cross-cutting safety nets:
  - Modal a11y (`role="dialog"` + `aria-modal="true"` + `aria-labelledby` + `data-controller="modal-a11y"`) — preserved.
  - `confirm_modal` partial — preserved (the partial output stays; only the inline `gb-btn-danger` triggering it might restyle).
  - `gb-grid` breakpoint behaviors at 900 / 720 / 520 px — preserved.
  - `gym-schedule` cancel-button visibility (Step 20 fix) — preserved (out of scope of this step but verify nothing leaks).

---

## 7. Tests Bob updates

- **Existing test suite**: 782 tests must pass. The Step 25 `design_canon_test.rb` file may need updates if specific token values change in the canon — this audit doesn't propose new tokens, so it should keep passing.
- **No new tests required** (this is a CSS-only restyle; functionality is unchanged and existing functional tests already cover it).
- Manual visual smoke: Bob loads `/`, `/emulator`, `/map`, `/teams`, `/species`, `/gym_drafts/...` and confirms each redesigned surface now reads as the same dialect as `/species` + `/teams`.

---

## 8. Out of scope

- New layouts / new mockups / new components.
- Backend changes.
- Functional regressions of any Phase-2 redesign improvement.
- Migration of legacy `gb-*` classes into `.btn` / `.pill` / `.card` / `.modal` canonical primitives (Step 25 said "the canon is the forward path, not a refactor target" — that bound still holds).
- Touching `/teams` or `/species` themselves (they ARE the canon — preserving them is the entire point).

---

*Audit complete. Half 2 (canon doc update) follows in `app/assets/stylesheets/design_canon.md`.*
