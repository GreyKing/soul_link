# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 25 — Site-wide design canon adoption

**Goal:** make every redesigned surface speak the same language without changing layouts, mockups, or component shapes. This is **mechanical CSS normalization only** — no view changes, no controller changes, no model changes, no migrations, no new components.

**Source-of-truth docs (already written by Architect — read both before editing CSS):**
1. `handoff/2026-05-06-design-canon-audit.md` — what's in use, what's drift, what's canonical (Sections 1-9 give the rationale; Section 9 is your mechanical fix list).
2. `app/assets/stylesheets/design_canon.md` — the locked canon (tokens, scales, primitives).

**Single file you will edit:** `app/assets/stylesheets/pixeldex.css`. Plus one new test file. That's it.

---

### Build order — six slices

Each slice is a single self-contained edit. Run `bin/rails test`, `bundle exec rubocop`, `bundle exec brakeman` after each slice. Commit after slice 6 (or earlier if a slice gets large). One commit total is fine; two commits if it feels cleaner — your call.

---

#### Slice 1 — Add the new tokens to `:root`

In `pixeldex.css`, replace the existing `:root { … }` block (lines 5-21) with the canon-aligned version below. **Add** the new tokens; **keep** every existing token. Do not delete `--d0`, `--d1`, etc. — they remain the source of truth.

```css
:root {
  /* ── Game Boy palette (positional — the source of truth) ── */
  --d0: #0a1a0a;
  --d1: #1a2e1a;
  --d2: #3a5a3a;
  --l1: #8a9e6a;
  --l2: #9aae7a;
  --white: #c0d0a0;
  --amber: #d4b14a;
  --green-glow: #5fd45f;
  --crimson: #c75a5a;

  /* ── Semantic aliases (Step 25 canon — preferred for new work) ── */
  --shadow: var(--d0);    /* deepest bg */
  --ink: var(--d1);       /* primary border, dark text */
  --shade: var(--d2);     /* mid-dark bg, dim text */
  --moss: var(--l1);      /* mid-light bg */
  --canvas: var(--l2);    /* light page bg */
  --paper: var(--white);  /* hi-contrast text on dark */
  --accent: var(--amber);
  --success: var(--green-glow);
  --danger: var(--crimson);

  /* ── Danger family (Step 25 — replaces 3 hardcoded hexes) ── */
  --danger-bg: #4a1c1c;
  --danger-border: #6b2c2c;
  --danger-fg: #e8a0a0;

  /* ── Borders ── */
  --border: 3px solid var(--ink);
  --border-thin: 2px solid var(--ink);
  --border-double: 4px double var(--ink);

  /* ── Spacing scale (Step 25 — 8 steps, 2-px grid) ── */
  --s-1: 4px;
  --s-2: 6px;
  --s-3: 8px;
  --s-4: 10px;
  --s-5: 12px;
  --s-6: 14px;
  --s-7: 16px;
  --s-8: 22px;

  /* ── Type scale (Step 25 — 7 steps) ── */
  --t-micro: 7px;
  --t-xs: 8px;
  --t-sm: 9px;
  --t-md: 10px;
  --t-body: 11px;
  --t-lg: 13px;
  --t-xl: 16px;

  /* ── Letter-spacing scale ── */
  --ls-tight: 0.5px;
  --ls-default: 1px;
  --ls-wide: 0.1em;

  /* ── Line-height scale ── */
  --lh-tight: 1;
  --lh-snug: 1.4;
  --lh-body: 1.6;
}
```

Replace the whole block in one edit. **Do not** rewrite or reorder anything else in the file as part of this slice.

---

#### Slice 2 — Replace hardcoded danger hexes with tokens

Three sites in `pixeldex.css` use `#4a1c1c`, `#6b2c2c`, `#e8a0a0` as the danger-surface family. Replace each with the matching `var(--danger-*)` token. **Do not touch** any other hex code in the file (the tcg-coin gradient, gb-avatar pastels, conflict-warning, box-cell.dead, gb-btn-danger:hover `#f0c0c0`, and `#4a3a1c` are explicitly out of scope — see audit Section 1).

Specific edits (use `Grep` to locate exact line numbers; counts confirm scope):

1. `.gb-flash-alert` block — currently:
   ```css
   .gb-flash-alert {
     background: #4a1c1c;
     color: #e8a0a0;
     border-color: #6b2c2c;
   }
   ```
   becomes:
   ```css
   .gb-flash-alert {
     background: var(--danger-bg);
     color: var(--danger-fg);
     border-color: var(--danger-border);
   }
   ```

2. `.gb-btn-danger` block — currently the `background: #4a1c1c; color: #e8a0a0; border: 2px solid #6b2c2c;` becomes:
   ```css
   .gb-btn-danger {
     /* …keep font-family / font-size / padding / cursor / transition / letter-spacing / line-height as-is… */
     background: var(--danger-bg);
     color: var(--danger-fg);
     border: 2px solid var(--danger-border);
   }
   ```
   The `:hover` block keeps its own colors:
   ```css
   .gb-btn-danger:hover {
     background: var(--danger-border);   /* was #6b2c2c — same value, now token */
     color: #f0c0c0;                      /* one-off bright-fg-on-hover; LEAVE inline */
   }
   ```
   (i.e. only the `#6b2c2c` in `:hover { background }` becomes `var(--danger-border)`. The `#f0c0c0` stays.)

3. `.gb-status-dead` block — currently:
   ```css
   .gb-status-dead {
     background: #4a1c1c;
     border-color: #6b2c2c;
     color: #e8a0a0;
   }
   ```
   becomes:
   ```css
   .gb-status-dead {
     background: var(--danger-bg);
     border-color: var(--danger-border);
     color: var(--danger-fg);
   }
   ```

**Out of scope for this slice (do NOT touch):**
- `.team-builder-status--error { color: #e8a0a0 }` — this is a single-use error text, not a danger-surface. Leave inline.
- `.map-r4 .node.dead .glyph { background: #4a1c1c }`, `.map-r4 .acc-row .glyph.dead { background: #4a1c1c }`, `.map-r4 .node-legend .glyph.dead { background: #4a1c1c }` — these *could* swap to `var(--danger-bg)` but they're inside a namespaced redesign block. **Skip them this step.** The brief is "kill drift on shared surfaces"; namespaced redesigns can adopt tokens at their next iteration.
- `.pc-box-r2 .box-cell.dead { background: #2a1a1a; border-color: #4a1c1c }` — explicitly out of canon (extra-dark variant; audit Section 1).

---

#### Slice 3 — Snap off-scale pill paddings (`2px 5px` → `2px 6px`)

Four declarations use `padding: 2px 5px`. The `5px` is off-scale; snap to `6px` (= `var(--s-2)`).

Use `Grep` to find the exact locations. Replace each `padding: 2px 5px;` with `padding: var(--s-1) var(--s-2);` (= `2px 6px`):

1. `.state-pill` (~line 1900)
2. `.hof-pill` (~line 2079)
3. `.map-r4 .group-card .head .pill` (~line 1503)
4. `.pc-box-r2 .badge-legend .badge` (~line 1639)

**Verify by grep before and after:** `grep -n 'padding: 2px 5px' pixeldex.css` should go from 4 matches → 0 matches.

---

#### Slice 4 — Unify the two amber-CTA paddings

Two amber-CTA buttons currently disagree on padding (`6px 12px` vs `8px`). Both should use `var(--s-3) var(--s-5)` (= `8px 12px`). The visual difference is minor but they're functionally the same role ("primary amber CTA on dark bg"):

1. `.dash-r1 .next-battle .draft-cta` — currently `padding: 8px;` → change to `padding: var(--s-3) var(--s-5);` (gains 4 px horizontal, ~mockup-aligned).
2. `.map-r4 .status-bar .jump-btn` — currently `padding: 6px 12px;` → change to `padding: var(--s-3) var(--s-5);` (gains 2 px vertical).

These are both "small CTAs in a narrow strip"; the snap is conservative and unifies their look.

---

#### Slice 5 — Convert `0.03em` letter-spacing to `var(--ls-tight)` (= `0.5px`)

Four uses on the `.gb-btn*` classes. They're visually identical at 11 px font but mixing `em` and `px` is the kind of drift the canon kills.

Use `Grep` to find: `letter-spacing: 0.03em`. Each becomes `letter-spacing: var(--ls-tight);`. Sites:

1. `.gb-btn` (~line 761)
2. `.gb-btn-primary` (~line 779)
3. `.gb-btn-danger` (~line 797)

(There may be a 4th site — search and convert all matches.)

**Out of scope:** the `0.05em` and `0.08em` sites in nav / titles are legitimate "wider tracking for headers". Do not touch those this step.

---

#### Slice 6 — Add a smoke test asserting the canon token is referenced

Create `test/integration/design_canon_test.rb` (FactoryBot conventions per CLAUDE.md):

```ruby
require "test_helper"

class DesignCanonTest < ActionDispatch::IntegrationTest
  CSS_PATH = Rails.root.join("app", "assets", "stylesheets", "pixeldex.css")
  CANON_PATH = Rails.root.join("app", "assets", "stylesheets", "design_canon.md")

  test "pixeldex.css declares the canonical accent token" do
    css = CSS_PATH.read
    assert_match(/--accent:\s*var\(--amber\)/, css,
                 "Step 25 canon: --accent must alias --amber in :root")
  end

  test "pixeldex.css declares the danger-family tokens" do
    css = CSS_PATH.read
    assert_match(/--danger-bg:\s*#4a1c1c/, css)
    assert_match(/--danger-border:\s*#6b2c2c/, css)
    assert_match(/--danger-fg:\s*#e8a0a0/, css)
  end

  test "pixeldex.css declares the spacing scale" do
    css = CSS_PATH.read
    %w[--s-1 --s-2 --s-3 --s-4 --s-5 --s-6 --s-7 --s-8].each do |tok|
      assert_match(/#{Regexp.escape(tok)}:\s*\d+px/, css,
                   "Step 25 canon: spacing token #{tok} missing from :root")
    end
  end

  test "danger family tokens replaced legacy hardcoded hexes on shared surfaces" do
    css = CSS_PATH.read
    # gb-flash-alert / gb-btn-danger / gb-status-dead must reference the danger tokens
    %w[.gb-flash-alert .gb-btn-danger .gb-status-dead].each do |sel|
      block = css[/#{Regexp.escape(sel)}\s*\{[^}]+\}/m]
      assert block, "missing block for #{sel}"
      assert_match(/var\(--danger-/, block,
                   "Step 25 canon: #{sel} must use var(--danger-*) tokens")
    end
  end

  test "design_canon.md exists and references the locked tokens" do
    assert CANON_PATH.exist?, "design_canon.md must exist as the source of truth"
    md = CANON_PATH.read
    assert_match(/--accent/, md)
    assert_match(/--success/, md)
    assert_match(/--danger/, md)
  end
end
```

Run `bin/rails test test/integration/design_canon_test.rb` and confirm 5 passes.

---

### Definition of done

- [ ] `:root` updated with semantic aliases + danger family + spacing + type + letter-spacing + line-height tokens.
- [ ] `.gb-flash-alert`, `.gb-btn-danger` (+ `:hover` `#6b2c2c` only), `.gb-status-dead` reference `var(--danger-*)` instead of hardcoded hexes.
- [ ] `padding: 2px 5px` → `var(--s-1) var(--s-2)` at 4 sites (state-pill, hof-pill, group-card .pill, badge-legend .badge).
- [ ] `.dash-r1 .next-battle .draft-cta` and `.map-r4 .status-bar .jump-btn` share `padding: var(--s-3) var(--s-5)`.
- [ ] `0.03em` → `var(--ls-tight)` on `.gb-btn*`.
- [ ] `test/integration/design_canon_test.rb` created with 5 assertions, all passing.
- [ ] `bin/rails test` — full suite green (754 → 759 tests, 0 failures, 0 errors).
- [ ] `bundle exec rubocop` — clean.
- [ ] `bundle exec brakeman` — same 2 pre-existing weak-confidence warnings as Steps 18–24, unchanged.
- [ ] `app/assets/stylesheets/design_canon.md` exists (already created by Architect).
- [ ] `handoff/2026-05-06-design-canon-audit.md` exists (already created by Architect).
- [ ] `REVIEW-REQUEST.md` lists exactly which sites changed and confirms no view / controller / model / config / migration touched.

### Hard constraints — DO NOT

- Do **not** rename `--d0`, `--d1`, `--d2`, `--l1`, `--l2`, `--white`, `--amber`, `--green-glow`, `--crimson`. They are the source of truth; semantic aliases point at them.
- Do **not** rebase any existing button class.
- Do **not** edit any view file (`app/views/**`).
- Do **not** edit any controller / model / service / config.
- Do **not** add a new migration.
- Do **not** rewrite namespaced `.dash-r1` / `.pc-box-r2` / `.map-r4` / `.slot` / `.roster-card` rules.
- Do **not** touch `.tcg-coin*`, `.gb-avatar--c0..c3`, `.conflict-warning`, `.pc-box-r2 .box-cell.dead`, `.team-builder-status--error`, the `0.05em` / `0.08em` letter-spacings, or any of the decorative one-offs documented in audit Section 8.
- Do **not** change `body { line-height: 1.8 }` or `.dialog { line-height: 1.8 }`.

### If something forces a deviation

Stop. Write a numbered question into `REVIEW-REQUEST.md` (e.g. `Q1 …`) and wait. Do **not** spin off speculative changes. Do **not** ask the Architect "should I also do X" — the brief above is the full scope.

### What Bob writes when done

`handoff/REVIEW-REQUEST.md`:
- One-paragraph summary of what shipped (mention the 6 slices).
- File manifest: `pixeldex.css` (modified), `design_canon.md` (added by Architect — confirm presence), `2026-05-06-design-canon-audit.md` (added by Architect — confirm presence), `test/integration/design_canon_test.rb` (added by Bob).
- Test counts: before/after.
- Confirm: 0 view files touched, 0 controller files touched, 0 model files touched, 0 config files touched, 0 migrations.

Then signal done and the Architect spins up Reviewer.
