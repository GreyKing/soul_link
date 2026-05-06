# Review Request — Step 25: Site-wide design canon adoption

**Builder:** Bob
**Branch:** `claude/stupefied-burnell-62b48d` (worktree)
**Ready for Review: YES**
**Scope:** Step 25 — site-wide design canon adoption per `handoff/ARCHITECT-BRIEF.md` and the locked Architect references `handoff/2026-05-06-design-canon-audit.md` + `app/assets/stylesheets/design_canon.md`. Mechanical CSS-only normalization — single CSS file edit + one new test file. No view / controller / model / service / config / migration touched.

---

## Summary

Six self-contained slices, all shipped per the brief:

1. **Slice 1 — Tokens added to `:root`**: 30+ new tokens (semantic aliases `--shadow/--ink/--shade/--moss/--canvas/--paper/--accent/--success/--danger`, danger family `--danger-bg/--danger-border/--danger-fg`, spacing scale `--s-1..--s-8`, type scale `--t-micro..--t-xl`, letter-spacing scale `--ls-tight/--ls-default/--ls-wide`, line-height scale `--lh-tight/--lh-snug/--lh-body`). Existing tokens preserved verbatim; semantic aliases point at them. `--border`/`--border-thin`/`--border-double` rewritten to use `var(--ink)` (value-stable — still resolves to `--d1`).
2. **Slice 2 — Danger family adopted on 3 shared surfaces**: `.gb-flash-alert`, `.gb-btn-danger` (+ `:hover` `background` only), `.gb-status-dead` swap from hardcoded `#4a1c1c/#6b2c2c/#e8a0a0` → `var(--danger-bg/--danger-border/--danger-fg)`. The `#f0c0c0` `.gb-btn-danger:hover` color stays inline per audit Section 1.
3. **Slice 3 — Pill paddings snapped**: 4 sites of `padding: 2px 5px` → `var(--s-1) var(--s-2)` (= `2px 6px`). Post-edit grep: 0 remaining matches.
4. **Slice 4 — Amber CTA paddings unified**: `.dash-r1 .next-battle .draft-cta` (`8px` → `var(--s-3) var(--s-5)`) + `.map-r4 .status-bar .jump-btn` (`6px 12px` → same). Both small CTAs now share `8px 12px`.
5. **Slice 5 — `0.03em` letter-spacing → `var(--ls-tight)`** on 3 `.gb-btn*` sites (`.gb-btn`, `.gb-btn-primary`, `.gb-btn-danger`). The `.gb-btn-danger` letter-spacing was folded into the Slice 2 edit (same selector block — one combined Edit operation, value-equivalent).
6. **Slice 6 — Smoke test**: New `test/integration/design_canon_test.rb` (5 assertions, all passing): asserts `--accent` aliases `--amber`, danger family declared, spacing scale declared, danger-family blocks reference `var(--danger-*)`, and `design_canon.md` references the locked tokens.

---

## File manifest

| File | Status | Notes |
|------|--------|-------|
| `app/assets/stylesheets/pixeldex.css` | Modified | `:root` block extended (lines ~5-72); 13 selector-block edits |
| `test/integration/design_canon_test.rb` | Added (Bob) | 5 assertions covering canon tokens + danger-surface adoption |
| `app/assets/stylesheets/design_canon.md` | Pre-existing (Architect) | Confirmed present — locked source of truth, untouched |
| `handoff/2026-05-06-design-canon-audit.md` | Pre-existing (Architect) | Confirmed present — audit + rationale, untouched |
| `handoff/BUILD-LOG.md` | Modified | Step 25 entry added; Step 24 moved into Status archive |
| `handoff/REVIEW-REQUEST.md` | Modified | This file |

**Confirmed: 0 view files touched, 0 controller files touched, 0 model files touched, 0 service files touched, 0 config files touched, 0 migrations.**

---

## Per-line summary of CSS edits

| Slice | Selector | Before → After | Note |
|-------|----------|----------------|------|
| 1 | `:root { … }` (lines 5-21) | Whole block replaced with canon-aligned version (lines ~5-72) | Adds tokens; preserves all existing |
| 2 | `.gb-flash-alert` (~178-181) | `#4a1c1c / #e8a0a0 / #6b2c2c` → `var(--danger-bg / --danger-fg / --danger-border)` | |
| 2+5 | `.gb-btn-danger` (~788-799) | `border: 2px solid #6b2c2c` → `var(--danger-border)`; `background: #4a1c1c` → `var(--danger-bg)`; `color: #e8a0a0` → `var(--danger-fg)`; `letter-spacing: 0.03em` → `var(--ls-tight)` | Slice 2 + Slice 5 combined in one Edit |
| 2 | `.gb-btn-danger:hover` (~801-804) | `background: #6b2c2c` → `var(--danger-border)`; `color: #f0c0c0` LEFT INLINE | Per brief — `#f0c0c0` is a hover-only one-off |
| 2 | `.gb-status-dead` (~920-924) | `#4a1c1c / #6b2c2c / #e8a0a0` → `var(--danger-bg / --danger-border / --danger-fg)` | |
| 3 | `.map-r4 .group-card .head .pill` (~line 1503) | `padding: 2px 5px` → `padding: var(--s-1) var(--s-2)` | |
| 3 | `.pc-box-r2 .badge-legend .badge` (~line 1639) | `padding: 2px 5px` → `padding: var(--s-1) var(--s-2)` | |
| 3 | `.state-pill` (~line 1900) | `padding: 2px 5px` → `padding: var(--s-1) var(--s-2)` | |
| 3 | `.hof-pill` (~line 2079) | `padding: 2px 5px` → `padding: var(--s-1) var(--s-2)` | |
| 4 | `.dash-r1 .next-battle .draft-cta` (~line 2428) | `padding: 8px` → `padding: var(--s-3) var(--s-5)` | Gains 4px horizontal |
| 4 | `.map-r4 .status-bar .jump-btn` (~line 1117) | `padding: 6px 12px` → `padding: var(--s-3) var(--s-5)` | Gains 2px vertical |
| 5 | `.gb-btn` (~line 761) | `letter-spacing: 0.03em` → `var(--ls-tight)` | |
| 5 | `.gb-btn-primary` (~line 779) | `letter-spacing: 0.03em` → `var(--ls-tight)` | |

---

## Out-of-scope sites left untouched (per brief)

Verified by post-edit grep:

- `.team-builder-status--error { color: #e8a0a0 }` (line ~73) — single-use error text, brief Slice 2 explicit out-of-scope.
- `.map-r4 .node-legend .glyph.dead` (~line 1193), `.map-r4 .node.dead .glyph` (~line 1295), `.map-r4 .acc-row .glyph.dead` (~line 1621) — namespaced redesign blocks; brief Slice 2 explicitly defers them ("namespaced redesigns can adopt tokens at their next iteration").
- `.pc-box-r2 .box-cell.dead { background: #2a1a1a; border-color: #4a1c1c }` (~line 1819) — extra-dark variant per audit Section 8.
- `.gb-btn-danger:hover { color: #f0c0c0 }` (~line 803) — bright-fg-on-hover one-off; brief explicitly leaves inline.
- `.team-name { letter-spacing: 0.03em }` (~line 428), `.box-cell-name { letter-spacing: 0.03em }` (~line 522) — NOT `.gb-btn*`. Definition of Done says "0.03em → var(--ls-tight) **on `.gb-btn*`**" — these 2 text-label sites are out of scope and stayed unchanged.
- All other decorative one-offs in audit Section 8 (`.tcg-coin*`, `.gb-avatar--c0..c3`, `.conflict-warning`, `.pending-banner`, `.dialog`, `.gb-flash`).
- `body { line-height: 1.8 }` and `.dialog { line-height: 1.8 }` — Hard Constraints DO-NOT.

---

## Verification gates

| Gate | Result | Note |
|------|--------|------|
| `bin/rails test` | **782 runs, 0 failures, 0 errors** | Was 777 (Step 24); +5 from new `design_canon_test.rb` (matches DoD's "+5 tests" expectation) |
| `bin/rails test test/integration/design_canon_test.rb` | **5 runs, 5 passes** | Direct run of the new file |
| `bundle exec rubocop` | **Clean (203 files, 0 offenses)** | |
| `bundle exec brakeman -q` | **2 weak-confidence warnings — unchanged** | Same `emulator_controller.rb:79` SendFile + `gym_schedule_discord_update_job.rb:14` FileAccess as Steps 18-24 |
| `grep -E 'padding: 2px 5px' pixeldex.css` | **0 matches** | Was 4 |
| `grep -E 'letter-spacing: 0\.03em' pixeldex.css` | **2 matches** (`.team-name`, `.box-cell-name`) | Both intentionally out of scope per DoD |
| `grep -E '#4a1c1c\|#6b2c2c\|#e8a0a0' pixeldex.css` | **9 matches**: 3 in `:root` token defs (correct) + 6 in explicitly out-of-scope sites | All shared-surface adoptions complete |

---

## Open questions / deviations

None. The brief was self-contained and decisive. No deviations were forced; no questions need to escalate.

---

## Hard constraints — confirmed honored

- [x] Did not rename `--d0`, `--d1`, `--d2`, `--l1`, `--l2`, `--white`, `--amber`, `--green-glow`, `--crimson`.
- [x] Did not rebase any existing button class.
- [x] Did not edit any view file (`app/views/**`).
- [x] Did not edit any controller / model / service / config.
- [x] Did not add a new migration.
- [x] Did not rewrite namespaced `.dash-r1` / `.pc-box-r2` / `.map-r4` / `.slot` / `.roster-card` rules — only the 4 specific pill paddings (Slice 3) and the 2 specific amber CTA paddings (Slice 4) called out by the brief.
- [x] Did not touch `.tcg-coin*`, `.gb-avatar--c0..c3`, `.conflict-warning`, `.pc-box-r2 .box-cell.dead`, `.team-builder-status--error`, the `0.05em` / `0.08em` letter-spacings, or any decorative one-offs from audit Section 8.
- [x] Did not change `body { line-height: 1.8 }` or `.dialog { line-height: 1.8 }`.
