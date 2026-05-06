# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 27 — Restyle the four Phase-2 redesigns to the old (gb-*) idiom

Pure visual restyle. Functional behavior unchanged. One step, not split into 27a/b/c/d (the changes are mechanical and share the same canon update).

### Read first (in order)

1. `app/assets/stylesheets/design_canon.md` — **the canon, Step 27 update.** Read sections 0, 4, 5, 6, 11 in particular. Section 11 is the chrome-reduction rules.
2. `handoff/2026-05-06-old-style-canon-audit.md` — **the directive table.** Section 3 (3.1 / 3.2 / 3.3 / 3.4) is the per-surface restyle table. Each row is one element to keep / remove / restyle. Apply them mechanically.
3. `handoff/SESSION-CHECKPOINT.md` — Step 25 + Step 26 (the immediate prior steps that this builds on).

The audit (#2) is the **source of truth for what changes**. Don't second-guess it; apply it.

### Reference surfaces (do NOT touch)

- `/species` (`app/views/species_assignments/show.html.erb` + `_group_card.html.erb` + `_species_card.html.erb` + `_pokedex_card.html.erb`)
- `/teams` (`app/views/teams/index.html.erb`)

These are the canon. They define the dialect. Any restyled surface should **read as part of the same family** as these views when rendered.

### Surfaces to restyle (in build order)

1. **Save Slots** (`app/views/emulator/_save_slots_sidebar.html.erb` + the `.slot` / `.state-pill` / `.confirm-inline` / `.pending-banner` rules in `pixeldex.css` lines ~1898-2030). Smallest scope — start here as a warm-up. Apply audit section 3.2.
2. **PC Box review tray** (`app/views/dashboard/_pc_box_content.html.erb` + `.pc-box-r2 .review-tray*` / `.badge-legend` / `.review-row` / `.filter-bar` / `.filter-chip` / `.empty-tray-bar` rules in `pixeldex.css` lines ~1644-1893). Apply audit section 3.3.
3. **Map / Route timeline** (`app/views/map/show.html.erb` + `.map-r4 .map-head` / `.status-bar` / `.node-legend` / `.timeline-frame` / `.node` / `.special-bar` / `.sheet*` rules in `pixeldex.css` lines ~1102-1640). Apply audit section 3.4.
4. **Dashboard** (`app/views/dashboard/_title_bar.html.erb` + `_tab_bar.html.erb` + `_status_rail.html.erb` + `.dash-r1 .title-bar` / `.tab-bar` / `.player-card` / `.side-tabs` / `.stat-strip` / `.run-pill*` / `.next-battle*` / `.gym-list*` rules in `pixeldex.css` lines ~2137-2492). **Highest priority per user feedback — the most-acute regression.** Apply audit section 3.1.

### Build order within each surface

1. Edit `pixeldex.css` first — change CSS rule values. The audit's per-row directives are mostly CSS-only (paddings, borders, drop-animations, drop-transforms).
2. Edit the ERB view to remove decorative elements (title-glyph, badge-dot DOM nodes, etc.) the audit calls for **removal** of. Don't remove anything the audit calls "restyle" or "keep" — those stay in the markup; only their CSS values change.
3. Where Stimulus controllers depend on `data-*-target` attributes, leave those targets in place. Restyling the *visual* of a button/section that carries a target is fine; deleting the target is not.
4. After each surface, run `bin/rails test` and confirm 0 failures.

### Constraints (must preserve)

- All Step 21–24 functional behaviors:
  - Save Slots: TARGET / overwrite-pending mode, inline DELETE / CLEAR-ALL confirm, the 5 state pills as functional state markers (keep their bg-color coding — they're real state).
  - PC Box: filter-chip filter behavior (`.filter-active` body class, `.filter-hidden` / `.search-hidden` cell visibility), URL-hash search persistence, review-tray pre-fill into catch modal, dismiss row.
  - Map: timeline + accordion swap at 720 px breakpoint, sticky sheet, jumpToNow button, gym toggle, click-to-open with catch-pre-fill.
  - Dashboard: WAI-ARIA tablist (`role="tab"` / `aria-selected` / `aria-controls` / `tabindex` + `keydown@window->pixeldex#numericJump`), status-rail sub-tab switching, run-picker dropdown with keyboard navigation, real-time Turbo refresh + ActionCable subscription.
- Step 20 cross-cutting safety nets: modal a11y wiring, `confirm_modal` partial, gb-grid breakpoints, gym-schedule cancel-button visibility (those last two are out of restyle scope but verify nothing leaks).
- Step 26 accent: `--accent` stays at `--green-glow`. The audit confirms this — the restyle is to use accent **less**, not to change its value.

### Things you must NOT guess at — flag to Ava if any of these are unclear

- **Status-rail sub-tabs collapse.** The user said "drop or downplay sub-tab pills" — interpret as **downplay the visual styling** (rebase to `gb-tab-item`-shape buttons with bg-swap-on-active, no accent green). Keep the controller + targets + sub-tab toggle behavior. Do NOT collapse them into 3 stacked always-visible sections — that's a structural change beyond the user's directive.
- **Run-pill rebase.** The audit says rebase the `.run-pill` trigger to `gb-btn`-shape. The dropdown menu stays. The status indicator (ACTIVE / HOF / ENDED / VIEWING) moves into the button label as text — drop the inline `<span class="badge ...">` element from the trigger button (NOT from the dropdown options — those keep getting their pill rebased per audit 3.1). If you can't get this to render cleanly with text-only status, surface to Ava.
- **Stat strip per-item color removal.** ALIVE / DEAD / BADGES values lose their per-value color coding and become plain `--white`. The labels (ALIVE / DEAD / BADGES) stay caps text. If the resulting strip is unreadable, surface to Ava — don't re-introduce color coding silently.
- **PC Box review-row badge family.** All 4 badges (1ST / TRADE / EVENT / OFFFEED) get the same `pill--ghost`-style treatment per canon 5: 1 px `--l1` border, transparent bg, `--l1` text. The user must read the kind from the **label** (1ST / TRADE-IN / EVENT / OFF-FEED) — that's intentional per the user's "fewer chrome elements" directive.
- **Map node-legend inline.** The audit says collapse `.node-legend` into the `gb-page-subtitle` line. The 5 glyphs (●/☠/○/★/G) become inline text characters in the subtitle. If the subtitle becomes unreadable on phone, fall back to a single-line `<div>` with no boxed border below the title — don't re-introduce the dashed-bordered legend bar.
- **Tests:** the existing `test/integration/design_canon_test.rb` asserts `--accent` aliases `--green-glow`, danger family declared, spacing scale declared, danger selectors reference `var(--danger-*)`, `design_canon.md` exists and references locked tokens. Step 27 doesn't change any token values — those assertions should still pass. If a token value DOES need to change (you find an audit instruction that requires it), surface to Ava before changing the test.

### Things that are out of scope

- New layouts / new mockups / new components. The audit's restyle directives are the entire scope.
- Backend changes. None needed.
- Deleting the `.dash-r1` / `.pc-box-r2` / `.map-r4` namespaces — those stay; only the rules under them change.
- Migrating any of the existing classes to the canonical `.btn` / `.pill` / `.card` / `.modal` primitives. Step 25 explicitly said the canon is forward-path, not refactor-target. Step 27 honors that bound — we're rebasing existing surfaces' VALUES to the gb-* idiom, not renaming classes.
- `/teams` and `/species` themselves — they're the canon, leave them alone.

### Done state

- All 4 surfaces' chrome rebased per the audit's directive tables.
- `bin/rails test` — 782 tests, 0 failures, 0 errors (or: existing test count + any incidental new tests Bob adds for visual regression).
- `bundle exec rubocop` — clean.
- `bundle exec brakeman` — same 2 pre-existing weak-confidence warnings as Steps 18-26 (not a new finding).
- Manual smoke: load each of `/`, `/emulator`, `/map`, `/teams`, `/species`, `/gym_drafts/...` and confirm each redesigned surface now reads as the same dialect as `/species` + `/teams`. The 4 surfaces should feel like quieter / more text-dense versions of themselves, not new designs.
- `REVIEW-REQUEST.md` written for Richard with the diff scope + verification steps.

### Resume prompt for Bob

> You are Bob on this project. Load token-optimizer skill first.
> Then read BOB.md, then ARCHITECT-BRIEF.md, then the 3 files referenced in "Read first" (canon, audit, checkpoint).
> Your task is Step 27. Confirm the brief is complete before writing any code.
