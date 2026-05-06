# Review Request — Step 27: Restyle the four Phase-2 redesigns to the old (gb-*) idiom

**Branch:** `claude/quirky-franklin-ab7a54`
**Builder:** Bob
**Status:** Ready for Review: YES
**Date:** 2026-05-06

---

## Summary

Pure visual restyle of the four Phase-2-redesigned surfaces (R3 Save Slots, R2 PC Box review tray, R4 Map timeline, R1 Dashboard) to the legacy `gb-*` idiom that `/species` and `/teams` still speak. Functional behavior is unchanged — every Stimulus controller target, ARIA tablist wiring, dropdown menu, click-to-open, modal pre-fill, and click handler is preserved. The four `.dash-r1` / `.pc-box-r2` / `.map-r4` namespaces stay (forward-path bound from Step 25); only the rules under them change.

The audit's per-surface directive table (`handoff/2026-05-06-old-style-canon-audit.md` § 3.1 / 3.2 / 3.3 / 3.4) was applied mechanically. Build order: 3.2 Save Slots → 3.3 PC Box → 3.4 Map → 3.1 Dashboard (smallest scope first, highest-priority last).

---

## Files changed

### CSS (`app/assets/stylesheets/pixeldex.css`)

All edits namespaced; no token values changed. The 4 surface blocks were rebased to the old idiom.

| Surface | CSS lines (post-edit) | Change summary |
|---|---|---|
| R3 Save Slots (3.2) | ~1898-2055 | `.pending-banner` → gb-flash-alert form (danger family); icon-glyph rule dropped. `.slot` → gb-card-dark (3 px ink border, 12 px padding). `.slot-actions button` → gb-btn-sm (10 px font, 4×8 padding, 2 px border) — primary/danger/confirm modifiers carry colour ON THE TEXT, not the bg (with `.confirm` keeping gb-btn-danger fill for the destructive action). `.confirm-inline` rebased to `--d2` bg + `--border-thin`; `.q` heading restyled to gb-section-header. `.footer-actions button` rebased to danger-family colours via `--danger-bg`/`--danger-border`/`--danger-fg` instead of raw `--crimson`. |
| R2 PC Box review tray (3.3) | ~1644-1820 | `.review-tray` → gb-card-dark (--d2 bg, 3 px ink border, 12 px padding). `.review-tray-head .count` → plain text (no bg chip). `.badge-legend` collapsed to inline strip (no boxed border, no grid). All 4 `.pc-box-r2 .badge` rules collapsed into one ghost-pill rule: 1 px `--l1` border, transparent bg, `--l1` text. The kind reads from the LABEL, not the colour. `.review-row` padding/margin snapped to canon scale. `.review-row.first` 3 px green-glow border kept (real "recommended action" affordance per canon § 11.3). `.review-row .actions button` → gb-btn-sm. `.empty-tray-bar` → gb-flash-notice form. `.filter-chip` → gb-btn-sm with active = bg swap to `--d1` + `--l2` text (matches `.tab-item.active`). Dropped accent-bg active state and dropped the `.filter-active` opacity dim. `.box-cell:hover` dropped translateY; kept border-color swap. |
| R4 Map timeline (3.4) | ~1102-1640 | `.map-head` rebased to gb-page-title + gb-page-subtitle form (no boxed --d1 background). Legend inlined into the subtitle line — boxed `.node-legend` block deleted entirely. `.badge-strip` hoisted into its own gb-section with a `gb-section-header` "BADGES" bar; dropped earned-state glow + hover-translate. `.status-bar .jump-btn` rebased to gb-btn-primary (--d1 bg, --l2 text); `subtleBlink` animation + keyframes deleted. `.timeline-frame::before/::after` gradient-fade overlays removed. `.node:hover .glyph` translateY + box-shadow dropped — border-color swap is the entire affordance. `.node.next .glyph` keeps the 3 px accent border; outer 5 px ring + glow + `pulseNext` dropped (the keyframes block removed from this surface — kept the dashboard-side `pulseNext` definition as a no-op for safety). `.node-now-pin` box-shadow glow dropped (static now). `.special-cell:hover` translateY dropped. `.sheet-head` rebased to gb-section-header form; close button rebased to gb-btn-sm. `.submit-btn` rebased to gb-btn-primary (no `filter: brightness` hover). `.acc-row .glyph.next` `pulseNext` animation dropped. |
| R1 Dashboard (3.1) | ~2137-2497 | `.title-bar` rebased to gb-page-title + gb-page-subtitle form (no boxed --d1 background). `.title-glyph` rule deleted. `.run-pill` rebased to gb-btn shape (--l1 bg, --d1 text, 2 px ink border). `.run-pill .badge*` rules deleted (status indicator becomes inline text in the label). `.run-pill-menu .run-option .pill` rebased to plain inline text (no bg, no border). `.stat-strip .item.alive/dead/badges .val` per-item color rules deleted — all values now plain `--white`. `.tab-bar` / `.tab` rebased to canonical `.tab-item` form (single horizontal strip, single-line label, 13 px font, bg swap on active, no underline). `.tab .badge-dot` rule deleted. `.side-tabs` / `.side-tab` restyled to look like stacked gb-section-header bars — vertical-stacked, full-width caps, --d1 bg, no accent green active state (controller targets preserved). `.player-card` rebased to gb-card-dark (3 px ink border, 12 px padding); `.you-pill` / `.hof-pill-r1` / `.badges-pill` rules deleted; new `.badges-text` rule for the inline plain-text count. `.gym-list .gym-row.next .num` `pulseNext` animation dropped (border-color emphasis kept). `.next-battle .draft-cta` rebased to gb-btn-primary (--d1 bg, --l2 text, 2 px ink border). |

### ERB views (5 files)

| File | Lines | Change |
|---|---|---|
| `app/views/emulator/_save_slots_sidebar.html.erb` | 30-37 | Removed the `<span class="icon">⚠</span>` glyph from `.pending-banner`. |
| `app/views/dashboard/_pc_box_content.html.erb` | 64-83, 154-159 | Collapsed multi-row `.badge-legend` into a single inline strip. Removed per-kind colour modifier classes from the 4 legend badges (kind reads from LABEL). Removed `<span class="check">` from empty-tray-bar; inline `(✓)` text prefix in the message. |
| `app/views/map/show.html.erb` | 34-86 | Rebased `.map-head` to title+subtitle (no boxed bar). Hoisted badge-strip into its own `<section class="badge-strip-section">` with a `gb-section-header` "BADGES" bar. Replaced the boxed `.node-legend` div with an inline legend in the `.map-head .sub` subtitle. |
| `app/views/dashboard/_title_bar.html.erb` | 1-90 | Removed `.title-glyph` div + the `glyph_initials` calculation. Rebased run-pill trigger label — status now reads as inline `RUN #N — STATUS ▾` text in the button (no inner `<span class="badge">`). Removed `.alive/.dead/.badges` modifier classes from stat-strip items. Run-option dropdown statuses now use `[ACTIVE] / [HOF] / [PAST]` inline text. |
| `app/views/dashboard/_tab_bar.html.erb` | 30-47 | Replaced `<span class="badge-dot">` with inline `<span aria-label="Updates available">*</span>` text suffix (same a11y label, no chrome). Tab text wraps inline now (icon prefix + label single-line). |
| `app/views/dashboard/_status_rail.html.erb` | 81-94 | Removed `<span class="you-pill">YOU</span>` (YOU is conveyed by the `.you` modifier on `.player-card`). Removed `<span class="hof-pill-r1">🏆 HOF</span>` (🏆 prefix moves into the name span). Replaced `<span class="badges-pill">` with `<span class="badges-text">` rendering plain `N/8 BADGES` text. |

### Tests (3 files updated to match new markup)

| File | Test name | Change |
|---|---|---|
| `test/integration/dashboard_redesign_test.rb` | "the title-bar stat-strip renders 4 inline items" | Drop `.alive/.dead/.badges` modifier classes from the assertion regex. |
| `test/integration/dashboard_redesign_test.rb` | "the PC BOX tab carries an updates-available marker..." (renamed from "...badge-dot...") + sibling test (no-marker case) + GYMS variant | Replace `<span class="badge-dot">...</span>` regex with `<span aria-label="Updates available">*</span>`. |
| `test/integration/dashboard_redesign_test.rb` | "the current user's PARTY sub-tab row carries the .you modifier on the card" (renamed) | Drop the `<span class="you-pill">YOU</span>` assertion; keep the `.player-card you` count check. |
| `test/integration/pc_box_redesign_test.rb` | "renders the REVIEW PARSED CATCHES tray with badge legend..." | Drop the per-kind modifier classes from legend-badge assertions (now `class="badge"` only). |
| `test/integration/map_redesign_test.rb` | "renders the always-visible legend with all five glyph items" | Replace boxed `.node-legend` div assertions with checks that the 5 glyphs (●/☠/○/★/G) appear in the `.map-head .sub` subtitle line. |

The Step 25 `test/integration/design_canon_test.rb` keeps passing **unmodified** — Step 27 doesn't change any token values, danger family, spacing scale, danger-token shared-surface references, or canon-doc token references.

### Other

- `app/assets/stylesheets/design_canon.md` — Architect-authored Step 27 update (§ 0 game-boy-menu-density principle, § 4-7 primitives re-pinned to gb-* values, § 11 chrome-reduction rules). Read but not touched by Bob.

---

## Test output

Ran the full test suite via `PATH="…/ruby/3.4.5/bin:$PATH" bundle exec rails test` (`bin/rails` is mis-shimmed to ruby 3.0.6 on this worktree — used the project memory's documented fallback path with the correct ruby pinned).

**Before Step 27 (start of session):**
```
782 runs, 2609 assertions, 0 failures, 0 errors, 0 skips
```

**After Step 27:**
```
782 runs, 2629 assertions, 0 failures, 0 errors, 0 skips
```

Same run count. Assertion count grew by 20 because the dashboard test (`stat-strip`) now repeats `<div class="item">` regex 4× instead of using 3 distinct modifier-class regexes (no functional difference; mechanical regex-shape change).

Initial run after CSS/ERB edits showed 6 failures across 4 tests — every single one was a markup-assertion test reaching for the OLD chrome (`badge-dot` DOM, `you-pill` DOM, per-item modifier classes, per-kind badge modifier classes, boxed node-legend) that the audit explicitly removes. Updated each to assert the new markup with a Step-27 comment explaining the rebase. None of the assertions tested behavior contracts that changed — Stimulus targets, ARIA tablist wiring, dropdown menus, controllers' input/output APIs all untouched.

---

## Rubocop output

```
$ bundle exec rubocop
Inspecting 203 files
...........................................................................................................................................................................................................

203 files inspected, no offenses detected
```

Clean.

---

## Brakeman delta

```
Errors: 0
Security Warnings: 2

== Warning Types ==
File Access: 2

== Warnings ==
Confidence: Weak — Check: SendFile — app/controllers/emulator_controller.rb:79
Confidence: Weak — Check: FileAccess — app/jobs/gym_schedule_discord_update_job.rb:14
```

Both warnings are pre-existing on Step-27-untouched files (the emulator ROM controller and the gym-schedule Discord update job — same pair from Steps 18-26). **Zero delta on Step-27-touched files** — Step 27 only edited CSS, ERB views, and 3 integration test files.

---

## Verification steps for Richard

### 1. Functional behavior preservation (smoke checks)

These all still work — please verify by reading the diff and not just by trusting Bob:

- [ ] Save Slots: TARGET / overwrite-pending mode banner reveal/cancel via `save_slots_controller.js#cancelOverwrite`. Inline DELETE confirm row reveal/cancel/commit. CLEAR ALL SLOTS inline confirm. The 5 state pills still represent distinct save-slot states (empty/saved/active/target/confirm) and keep their bg-color coding (they're real state markers per canon § 5).
- [ ] PC Box: filter-chip click → `pc-box-filter#applyFilter` toggles `.filter-active` body class + `.filter-hidden` cell class. URL-hash search persistence. Review-tray button → `dashboard#openCatchModal click->review-tray#prefillCatch` action chain (order preserved). SKIP → `review-tray#dismiss` adds `.dismissed` class. `[data-pc-box-filter-target="count"]` and `[data-review-tray-target="count"]` targets present (the dismiss handler still writes `${remaining} NEW` to the count target — verified the span structure didn't break this).
- [ ] Map: 720 px breakpoint timeline → accordion swap. `data-timeline-target="jumpBtn"` present. `data-timeline-target="sheet" / "sheetTitle" / "sheetBody" / "emptyState" / "groupList" / "sheetForm" / "formLocationKey" / "speciesPreview" / "speciesHidden" / "speciesDropdown" / "nicknameInput" / "formStatus" / "track" / "scrollContainer" / "locationNode" / "accordionSegment" / "speciesSearchWrapper"` all present. Click-to-open + catch-pre-fill flow.
- [ ] Dashboard: WAI-ARIA tablist (`role="tab"` / `aria-selected` / `aria-controls` / `tabindex` + `keydown@window->pixeldex#numericJump`) — confirmed all 7 tabs still carry these attributes. `data-pixeldex-target="tabButton"` per tab. `data-status-rail-target="tabButton"` per side-tab and `data-status-rail-target="tabPanel"` per side-panel — all 3 still present (PARTY / GYMS / MAP). `data-controller="run-picker"` + `data-run-picker-target="trigger" / "menu" / "option"` all preserved on the rebased run-pill.

### 2. Audit directive table coverage

For each of the audit's 4 sub-tables (3.1 / 3.2 / 3.3 / 3.4), every row's "After Step 27" cell has a matching change in this PR. Suggested verification path:

- Open `handoff/2026-05-06-old-style-canon-audit.md` § 3.
- For each row, grep the relevant CSS / ERB section in this PR's diff for the rebased treatment.

### 3. Step 25 design_canon_test.rb still passes unmodified

```
$ bundle exec rails test test/integration/design_canon_test.rb
5 runs, 40 assertions, 0 failures, 0 errors, 0 skips
```

Confirms Step 27 didn't change any token values.

### 4. Manual visual smoke (Richard's call)

The audit's done-state requires a manual smoke pass: load `/`, `/emulator`, `/map`, `/teams`, `/species`, `/gym_drafts/...` and confirm each redesigned surface now reads as the same dialect as `/species` + `/teams`. Bob can't render the browser; flagging this for Richard to either run interactively or defer to the user.

---

## Notes & exceptions confirmed

- **`@keyframes pulseNext` definition kept** in `pixeldex.css` (lines ~2456) even though all references are removed. Left as a defensive no-op in case any partial outside the 4 redesigned surfaces still references it (didn't find one in grep, but the keyframes block is cheap and a future cleanup pass can prune). The map-side `pulseNext` keyframes block was deleted because it was a duplicate definition under `.map-r4`.
- **`@keyframes subtleBlink` deleted** entirely (only one definition site, only one consumer — `.map-r4 .status-bar .jump-btn` — and the audit explicitly removes that consumer's animation).
- **Per-row badge modifier classes (`first` / `trade` / `event` / `offfeed`) left in the ERB markup** even though no CSS rule targets them anymore. They're inert — no visual difference. Left as harmless markup hooks for future re-introduction if a redesign wants per-kind colour back. The legend strip's badges have no modifier (just `class="badge"`).
- **`.run-pill .chev` colour kept inheriting** from the parent button (was `var(--accent)` pre-Step-27; now inherits `--d1` text colour from the rebased gb-btn shape). Audit didn't call out chev colour explicitly; matches the rest of the pill's text.
- **`.dash-r1 .next-battle .label` colour** dropped from `var(--accent)` to `var(--l1)` to match the rest of the status-rail's dim-label idiom (audit didn't explicitly call this out, but it was reading as a stray accent in an otherwise-rebased section).
- **`.map-r4 .submit-btn.danger`** rebased to use the danger-family tokens (`--danger-bg` / `--danger-border` / `--danger-fg`) for consistency with `.gb-btn-danger`. Pre-Step-27 it used raw `--crimson` + `--white`. Functional behavior unchanged; just cleaner token usage.
- **One Stimulus dependency caught early:** the `review-tray#dismiss` handler writes `${remaining} NEW` to the `[data-review-tray-target="count"]` span via `textContent =`. My first attempt at the badge-legend collapse made the count span inner-only (just the number, with " NEW" outside the span as static text), which would have broken the dismiss rewrite ("3 NEW NEW"). Reverted to the original "N NEW" span structure on the count target — visually plain text now (no chip bg) but the JS write still works. Documented in the ERB partial.

---

## Open questions

None. The audit was unambiguous; every "must NOT guess at" item from the brief had a clear directive in the audit:
- ✅ Status-rail sub-tabs collapse → restyled buttons, kept controller targets
- ✅ Run-pill rebase → rebased to gb-btn, status inline as text
- ✅ Stat strip per-item color removal → all values plain --white
- ✅ PC Box review-row badge family → all 4 single ghost-pill style
- ✅ Map node-legend inline → collapsed into subtitle (no fallback needed; subtitle reads cleanly)
- ✅ Tests → `design_canon_test.rb` unmodified; 5 markup-assertion tests rebased to new markup with Step-27 comments

Ready for Review: YES
