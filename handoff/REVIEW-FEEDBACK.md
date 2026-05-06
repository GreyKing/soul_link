# Review Feedback — Step 27
Date: 2026-05-06
Ready for Builder: YES

## Must Fix
None.

## Should Fix
None blocking. Two cleanup items Bob already flagged in REVIEW-REQUEST § Notes — both are acceptable as conservative-build "leave-it" calls for this step. Logging here so they don't get lost:

- `app/assets/stylesheets/pixeldex.css:2477-2483` — `@keyframes pulseNext` is retained as a defensive no-op. I grepped `app/` and `test/` for any `animation: pulseNext` consumer and found zero (only doc-prose mentions in `design_canon.md`, which list it as a banned animation). Since the keyframes block is genuinely orphaned, a future cleanup pass can safely delete it. Not a blocker for Step 27 — leaving it shipping as-is is the cheaper call.
- `app/views/dashboard/_pc_box_content.html.erb:114-124` — Per-row badge modifier classes (`first` / `trade` / `event` / `offfeed`) remain in the markup with no CSS targeting them. Inert; no visual difference. Acceptable as harmless markup hooks; a future cleanup can remove them when nothing else needs the affordance.

## Escalate to Architect
None.

## Cleared

Reviewed Step 27 — pure visual restyle of the four Phase-2 redesigned surfaces (R3 Save Slots, R2 PC Box review tray, R4 Map timeline, R1 Dashboard) to the legacy `gb-*` idiom that `/species` and `/teams` still speak.

**Aesthetic consistency** — the four surfaces now use the canon primitives uniformly:

- `gb-card-dark` shape (3 px ink border, 12 px padding, `--d2` bg) on `.review-tray` (`pixeldex.css:1636-1641`), `.slot` (`1919-1925`), `.player-card` (`2399-2403`).
- `gb-btn` family (light bg, 2 px ink border, 10 px font, 4×8 padding) on `.filter-chip` (`1761-1770`), `.review-row .actions button` (`1726-1736`), `.slot-actions button` (`1970-1982`), `.run-pill` (`2192-2203`), `.sheet-head .close` (`1395-1403`).
- `gb-btn-primary` (`--d1` bg, `--l2` text, 2 px ink border) on `.next-battle .draft-cta` (`2504-2514`), `.map-r4 .submit-btn` (`1489-1500`), `.map-r4 .status-bar .jump-btn` (`1166-1175`). All static, no `subtleBlink`, no filter-brightness hover.
- `gb-page-title` + `gb-page-subtitle` form on `.map-head` (`1107-1119`) and `.dash-r1 .title-bar` (`2168-2183`). No boxed background; no title-glyph.
- `.tab-bar` rebased to canonical horizontal-strip shape (`2292-2321`): single-line label, 13 px font, `--d2` → `--d1` bg-swap on active, no underline.
- Accent color is now reserved for functional state markers only — `.state-pill.target/.active`, `.player-card.you` border, `.node.next .glyph` 3 px border, `.review-row.first` 3 px border, `.box-cell.team` border, `.gym-list .gym-row.next .num` border, `.badge-strip .badge.earned`. Decorative accent appearances all removed.
- All animations dropped: `pulseNext` (3 consumer rules removed), `subtleBlink` (consumer + keyframes removed), gradient-fade overlays on `.timeline-frame`, hover `translateY` on nodes / cells / chips, box-shadow glows on now-pin and badge-dots.

The dialect now reads as the same family as `/species` + `/teams`. Subjective check passes.

**Functional preservation** — verified by grep against the cited line ranges:

- Save Slots — `data-save-slots-target="banner"` (`_save_slots_sidebar.html.erb:32`), `slot` (`:50`), `slotPill` (`:56`), `cancelOverwrite` action (`:34`). TARGET / DELETE / CLEAR-ALL flows unbroken.
- PC Box — `data-controller="pc-box-filter review-tray"` chain preserved. `data-pc-box-filter-target="chip"` on each filter-chip; `data-review-tray-target="count"` on the review-tray count span (`_pc_box_content.html.erb:71`); `data-review-tray-target="row"` per row (`:101`); `click->dashboard#openCatchModal click->review-tray#prefillCatch` action chain order preserved (`:137`); `click->review-tray#dismiss` on every SKIP (`:151`). The dismiss handler's `${remaining} NEW` write into the count span still works because Bob kept the count span containing both number and " NEW" text (Bob caught this trap in his § Notes; my own grep confirms the structure matches).
- Map — every `data-timeline-target=*` cited in REVIEW-REQUEST present in `map/show.html.erb`: `jumpBtn` (:89), `track` / `scrollContainer` / `locationNode` (:98-99, 122, 226, 273), `accordionSegment` (:209), `sheet` / `sheetTitle` / `sheetBody` / `emptyState` / `groupList` / `sheetForm` / `formLocationKey` / `speciesPreview` / `speciesHidden` / `speciesDropdown` / `nicknameInput` / `formStatus` / `speciesSearchWrapper` (:296-…). 720 px breakpoint accordion swap unchanged. `node-now-pin` is now static but still rendered.
- Dashboard — full WAI-ARIA tablist preserved on the main tab-bar (`_tab_bar.html.erb:34-41` carries `role="tab"`, `aria-controls`, `aria-selected`, `tabindex` on every tab; `data-action="keydown->pixeldex#tablistKeydown"` on the wrapper at :30). `data-pixeldex-target="tabButton"` per tab. Status-rail sub-tabs: 3 `data-status-rail-target="tabButton"` + 3 `data-status-rail-target="tabPanel"` (`_status_rail.html.erb:22, 34, 46, 62, 117, 178`). `data-controller="run-picker"` + `trigger` / `menu` / `option` targets on the rebased run-pill (`_title_bar.html.erb:32-40, 45-48, 73, 91`).

**Drift check** — Bob's 6 confirmed exceptions in REVIEW-REQUEST § Notes evaluated:

1. `@keyframes pulseNext` kept as no-op — defensive, harmless. Acceptable.
2. `@keyframes subtleBlink` deleted — only consumer (`.jump-btn`) had its `animation:` directive removed in this step, so deletion is correct. Helpful.
3. Per-row badge modifier classes left in markup — inert (CSS rules under `.pc-box-r2 .badge.first/.trade/.event/.offfeed` confirmed gone via grep). Harmless.
4. `.run-pill .chev` color now inherits from button — consistent with the pill text color. Helpful.
5. `.next-battle .label` accent → `--l1` — within audit § 3.1 dim-label idiom; consistent with the rest of the rebased status-rail. Helpful.
6. `.map-r4 .submit-btn.danger` migrated from raw `--crimson`/`--white` to danger-family tokens (`--danger-bg` / `--danger-border` / `--danger-fg`) — aligns with canon § 4 danger-button shape. Helpful.

None expand scope.

**Test changes** — 5 markup-shape assertion updates, all shape-only:

- `dashboard_redesign_test.rb:60-64` — drops `.alive` / `.dead` / `.badges` modifier classes from regex; values still asserted. Behavior contract unchanged.
- `dashboard_redesign_test.rb:117, 138` — replaces `<span class="badge-dot">` with `<span aria-label="Updates available">*</span>`. Same a11y contract; only the chrome shape changed.
- `dashboard_redesign_test.rb:128` — refute case for the no-marker scenario; semantic equivalent of the old refutation.
- `dashboard_redesign_test.rb:215` — drops the `<span class="you-pill">YOU</span>` text assertion; keeps the `.player-card you` count check (the load-bearing affordance per canon § 11.3).
- `pc_box_redesign_test.rb:43-46` — drops per-kind modifier classes from legend-badge regex; asserts `<span class="badge">LABEL</span>` instead. Information now lives in the label per canon § 5 ghost-pill rule.
- `map_redesign_test.rb:40-46` — replaces boxed `.node-legend` div assertions with checks that all 5 glyphs (●/☠/○/★/G) appear in the `.map-head .sub` subtitle line. Same coverage; new container.

None weaken behavior. Step 25 `design_canon_test.rb` confirmed unmodified since Step 26 (`git log 3b05a80..HEAD -- test/integration/design_canon_test.rb` returns no commits).

**Standards** — Bob reports rubocop clean (`203 files inspected, no offenses detected`). Brakeman delta = 0 on Step-27-touched files; the same 2 weak warnings on `emulator_controller.rb:79` and `gym_schedule_discord_update_job.rb:14` are pre-existing on out-of-scope files.

**Test suite** — 782 runs, 2629 assertions, 0 failures, 0 errors, 0 skips. The +20 assertion delta is the mechanical regex-shape change in the stat-strip test (4× `<div class="item">` regex instead of 3 distinct modifier-class regexes). No behavioral test was weakened.

**Scope discipline** — `git diff --stat HEAD` shows 14 files changed, matching REVIEW-REQUEST exactly (1 CSS, 5 ERB views, 3 test files, 1 architect-authored canon doc, 4 handoff docs). No off-scope code touched.

**Manual visual smoke** — deferred to interactive run by the user. Bob can't render the browser; this is a CSS-first restyle so all behavior tests pass, but the subjective "does it read as the same dialect as `/species` + `/teams`" call belongs to the user looking at the rendered surfaces.

Step 27 is clear. 0 Must Fix / 0 Should Fix-blocking / 0 Escalate.
