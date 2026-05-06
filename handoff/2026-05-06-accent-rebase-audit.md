# Step 26 — Accent rebase audit

*Architect-prep doc. The brief in `ARCHITECT-BRIEF.md` is the build instruction; this is the rationale + grep.*

---

## 1. The user's ask

> "I think the new design is a downgrade from the old styling, can you look at the gym draft view page for the lighter green color and use that as the main color? I like the unified styling but I'm focused on the colors"

The user is happy with Step 25's normalization but wants the **main accent** rebased from gold/amber to the **lighter green** that they see on the gym draft view page.

## 2. Identify the green

Greens in the current `:root`:

| Token | Hex | Character |
|---|---|---|
| `--d2` | `#3a5a3a` | Mid-dark olive (page chrome) |
| `--l1` | `#8a9e6a` | Muted moss (mid-bg, dim text) |
| `--l2` | `#9aae7a` | Sage (page bg) |
| `--green-glow` | `#5fd45f` | **Vibrant lime-green (success / active state)** |

On the gym draft view (`app/views/gym_drafts/show.html.erb`), the bright, "lighter green" the user is reading off the page is **`--green-glow`** (`#5fd45f`). It appears at:

- `.slot.active { border: 4px solid var(--green-glow) }` — locked picks
- `.state-pill.active { background: var(--green-glow) }` — active state-pill
- `.dash-r1 .stat-strip .item.alive .val { color: var(--green-glow) }` — alive count
- `.pc-box-r2 .box-cell.team { border-color: var(--green-glow) }` — team-cell border
- `.map-r4 .timeline-line.done { background: var(--green-glow) }` — completed timeline
- And ~25 other "alive / caught / first / done / active" state markers

The other Game Boy greens (`--d2`, `--l1`, `--l2`) are positional surface/text colors, not "main color" candidates. **Target: `--green-glow` = `#5fd45f`.**

## 3. The mistake in Step 25 (and why this step is bigger than it looks)

Step 25 added `--accent: var(--amber)` as a semantic alias but **never replaced any `var(--amber)` reference in `pixeldex.css`**. Verify:

```
$ grep -c "var(--accent)" pixeldex.css
0
```

`var(--accent)` exists only in `design_canon.md` (4 prose examples). So just swapping the alias to `var(--green-glow)` would have **zero visual effect** — the entire site reads `var(--amber)` directly.

To actually rebase the main color, Step 26 must do the propagation Step 25 deferred: sweep `var(--amber)` → `var(--accent)` across the codebase (and update the rgba decompositions of the amber hex so glows match the new color).

## 4. Inventory of what to swap

### A. `pixeldex.css` — token alias (1 line)

`--accent: var(--amber)` → `--accent: var(--green-glow)`.

`--amber: #d4b14a` stays defined (positional Game Boy palette token) but no longer referenced. We don't delete it — keeping the palette intact preserves the option for a "gold" surface in the future without re-adding the hex.

### B. `pixeldex.css` — `var(--amber)` references (47 lines)

Mechanical replacement: `var(--amber)` → `var(--accent)`. All 47 occurrences. Affected surfaces (categorized for sanity-check, not for selective handling):

- **Team-builder save-status** (line 71): `--saving` color
- **Save-slot ACTIVE pill border-glow** (lines 1928, 1952, 2038, 2049): `.slot.overwrite-target`, `.state-pill.target`, `.roster-card.you`, save-slot heading bg
- **Map R4 special / gym / next-pulse** (lines 1192-1399): node-legend glyphs, special/gym nodes, next-pulse animation, status-bar special-cell, dupes-btn hover, accordion summary, acc-row glyph
- **Gym sheet bar + button** (lines 1507, 1568, 1591): map sheet-status pill bg, dupes-btn, accordion[open] summary
- **PC box trade badge / type-pill / hover / box-cell** (lines 1691, 1774, 1817, 1844, 1900, 1912): `.badge.trade`, search input on focus, `.box-cell:hover`, group-marker, `.type-pill.target`
- **Roster + run-pill + run-pill-menu** (lines 2103, 2111, 2112, 2122, 2149, 2170, 2184, 2186, 2232): roster-card.you decorations, conflict-warning bg+border (caveat below), run-pill border, hof-pill, run-pill-menu chev
- **Dashboard stat-strip badges count** (line 2262): badges val color
- **Map R4 special-cell / dupes** (lines 1136, 1160, 1664, 1660, 1649): special-cell hover, focus, headers
- **Gym beaten glyph** (lines 1314, 1318, 1345, 1359, 1399): map gym beaten, beaten-state markers

### C. `pixeldex.css` — rgba decompositions of `#d4b14a` (10 lines)

`#d4b14a` = rgb(212, 177, 74). When border / bg becomes green-glow (rgb 95, 212, 95), the matching glow-shadow must move with it. Mechanical:

`rgba(212, 177, 74,` → `rgba(95, 212, 95,`

Lines: 1137, 1169, 1170, 1287, 1300, 1308, 1309, 1350, 2449, 2450.

### D. View files — inline `var(--amber)` (4 occurrences)

| File | Line | Context |
|---|---|---|
| `app/views/dashboard/_runs_content.html.erb` | 33 | HoF "🏆 COMPLETE" pill (border + bg + color) |
| `app/views/dashboard/_gyms_content.html.erb` | 52 | "NEXT" indicator pill |
| `app/views/map/show.html.erb` | 251 | "↓ NOW · log first encounter" caption |
| `app/views/gym_drafts/show.html.erb` | 194 | Coin-flip result text on tiebreak reveal |

All swap to `var(--accent)`. The HoF pill (Step 16), NEXT indicator, and "NOW" caption are explicitly in the user's audit list. The coin-flip result is a sibling of `.tcg-coin*` (which is out-of-canon) but the result *text* is not part of the coin graphic itself — including it keeps the gym-draft surface consistent with the new accent.

### E. JS file — inline `var(--amber)` (4 occurrences in gym_draft_controller.js)

| Line | Context |
|---|---|
| 157 | Ready-status color when player is ready |
| 262 | Turn-indicator chip border |
| 263 | Turn-indicator chip box-shadow glow |
| 572 | Tag color |

All swap to `var(--accent)`.

### F. Out of scope (do NOT change)

- **`--amber: #d4b14a` token in `:root`** — keep defined. Positional palette token; no longer referenced but remains as the source-of-truth Game Boy hex.
- **`.conflict-warning` rule** (around line 2110-2113) — uses `var(--amber)` border + amber-tinted bg. **Explicitly out of canon per `design_canon.md` § 9** ("`.conflict-warning` deep-amber bg — single-use save-slot warning"). Decorative one-off; the warning is *meant* to read as gold/yellow alarm, not green. Skip.
  - However, lines 2111-2112 *are* in the `.conflict-warning` block: `background: #4a3a1c; color: var(--amber); border: 1px solid var(--amber);`. The `--amber` references here are the deliberate amber identity of this surface — leave them.
- **Coin-flip modal `border-color: #c0392b`** (gym_drafts/show.html.erb:179, 183) — decorative coin-modal red, unrelated to amber.
- **`#4a3a1c` decorative deep-amber bg** in `.conflict-warning` — out of canon, stays.

### G. `design_canon.md` updates

- § 1 *Accents*: change row to `--accent (= --green-glow) | #5fd45f | …`. The `--success` row stays — same hex, different semantic role (success = "alive / caught / first" state markers; accent = "primary CTA / focus / active" surfaces).
- § 8 *Borders*: the line "`4px solid var(--accent)` … '4px amber = warn-emphasis'" is now wrong. Update prose to "4px green = active-emphasis" (or similar) and the example token stays `var(--accent)`.
- Add a one-line note at the top of § 1 documenting the rebase: "Accent rebased to `--green-glow` per user feedback (Step 26, 2026-05-06). Previously `--amber`."

### H. Test update

`test/integration/design_canon_test.rb` line 9:

```ruby
assert_match(/--accent:\s*var\(--amber\)/, css, ...)
```

Change to:

```ruby
assert_match(/--accent:\s*var\(--green-glow\)/, css, ...)
```

The other 4 tests (danger family, spacing scale, danger surfaces, canon doc references) stay unchanged.

## 5. End state

- The site's "main color" (CTA / focus / active / earned-state) shifts from gold (`#d4b14a`) to vibrant green (`#5fd45f`).
- `--success` and `--accent` now share the same hex but remain semantically distinct:
  - `--accent` = primary attention (CTA, focus ring, "next gym" pulse, HoF pill, run-pill border).
  - `--success` = positive-state markers (alive count, save-slot active border, group-card alive border).
  - In Game Boy palette terms, both are "the bright green slot". This is intentional — the palette has only 9 colors; aliasing two roles to one slot keeps the canon honest.
- `--amber` stays defined as a positional palette token (no live references, but available for future rollback or "true gold" need without re-adding the hex).

## 6. What this step does NOT do

- No changes to layout, spacing, typography, or any token besides `--accent`.
- No backend changes.
- `.conflict-warning` and the `--amber` palette token stay.
- Other Phase-2/3 KGs (KG-7, 19, 20, 23, 25-39) are untouched.
