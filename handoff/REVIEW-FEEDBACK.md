# Review Feedback — Step 28
Date: 2026-05-06
Ready for Builder: YES

## Must Fix
None.

## Should Fix
None.

## Escalate to Architect
None.

## Cleared

Step 28 — dashboard visual rebuild against `designs/04-pixeldex.html` — is clear.

Spot-checked all seven directives against the diff:

- **D1 title-bar / stat-strip / run-pill** — `.title-bar` rebuilt as `--d2` band
  with flex space-between, ink border-bottom, 10/20 padding, `flex-shrink: 0`,
  no `margin-bottom` (pixeldex.css L2170–2179). `.title-right` flex group added
  (L2184–2186). `.stat-strip` rebuilt with `display: flex; gap: 16px;` plus
  `flex-direction: column-reverse` per `.item` to render value-on-top
  label-below without DOM change (L2291–2306). Run-pill rebased to
  transparent / `--l2` text / 2 px `--l1` underline (L2204–2222), hover wash
  rgba(155, 188, 15, 0.15) per spec.
- **D2 tab-bar rename** — `.tab` → `.tab-item` and `.icon` → `.tab-icon` in
  `_tab_bar.html.erb` L31 / L40. CSS rules renamed in `.dash-r1` block
  (L2319–2343); `.tab-icon` is `display: block; font-size: 20px;
  margin-bottom: 4px; line-height: 1;` for the block-above stack form.
- **D3 pc-layout shared-frame** — `gap: 0`, `margin-top: 0`,
  `background: var(--l2)`, ink border-right per child, `:last-child` drops it
  (L2352–2367). Inset overlay correctly skipped — verified `body::after` at
  L113–126 is `position: fixed; inset: 0` covering the full viewport.
- **D4 status-rail flatten + horizontal sub-tabs** — `.status-rail` now
  `background: transparent; border: none; padding: 0;` (L2374–2378).
  `.side-tabs` rebuilt as horizontal mini tab-bar with `--d1` bg + ink
  border-bottom (L2379–2385). `.side-tab` rebuilt as `.tab-item`-sibling cell,
  active state swaps to `--d1` bg + `--l2` text (L2386–2403). Legacy
  `.h3-row` / `h3` / `.count` rules deleted, replaced by canonical `:root`
  level `.panel-header` (L349–366).
- **D5 right-rail cards** — `.player-card` light-card form
  (`--l1` bg + 2 px ink border + `--d1` text, sprite-cell on `--l2` bg with
  2 px ink border) per L2413–2449. `.gym-row` rebased to single-line flex
  with solid `--d2` divider, glyph slot in `.num` (L2456–2495).
  `.gym-row.next` filled-bar with -6px horizontal margin (L2488–2495).
  `.gym-row.upcoming` uses `opacity: 0.35`. `.next-battle` rebased to
  `.route-card` light-card skin (L2509–2546); `.draft-cta` keeps the
  `gb-btn-primary` form per spec.
- **D6 `_status_rail.html.erb` markup** — three `.h3-row` blocks rewritten
  to `.panel-header` / `.panel-header-sub` (L64–67, L119–122, L193–196).
  Three `.panel-body` wrappers added (L69, L124, L198). All ARIA targets
  intact. Gym glyph emitted in ERB per D5: ★ / ▶ / · (L141–148, L151).
- **D7 `show.html.erb`** — `.col-party` wrapper dropped; `_party_panel`
  rendered directly inside `.pc-layout` (L39). Verified `_party_panel`
  provides its own `<div class="panel">` shell so the partial participates
  in the 3-col grid. Responsive 900 px rule rewritten to target
  `> .panel:first-child` (L2585).

WAI-ARIA preservation verified end-to-end: every `role="tab"`,
`aria-selected`, `aria-controls`, `tabindex`, `keydown->pixeldex#tablistKeydown`,
`keydown->status-rail#keydown`, `data-pixeldex-target="tabButton"`,
`data-status-rail-target="tabButton"`, `data-action`, `data-tab` /
`data-status-rail-tab-param` is present in `_tab_bar.html.erb` and
`_status_rail.html.erb`. Window-level `numericJump` binding intact on
`show.html.erb` L15.

Step 25 token canon and Step 26 accent rebase preserved — `--accent` rule on
`.dash-r1 .player-card.you` (L2419–2421) and `.dash-r1 .gym-row.beaten .name`
(L2480) both retained.

CSS scope-locked: every diff hunk falls inside lines 2160–2606 of
`pixeldex.css`, all within the `.dash-r1` namespace block. The `:root`
palette, canonical primitives (1–520), `.pc-box-r2`, `.map-r4`, and `.gb-*`
namespaces untouched.

Step 28 assertion (L82–89 in `dashboard_redesign_test.rb`) correctly targets
the main dashboard tab cells via `id="tab-#{key}"` selector — the regex won't
collide with the status-rail's `status-tab-` ids. The seven keys cover every
tab in the bar.

`responsive_grids_test.rb` updates (L153 col-party → first-child, L164–172
tab → tab-item) are necessary stale-assertion follow-ups to D7 / D2 — same
intent, new selector form. Same pattern as Step 27's test updates.

Test status verified locally: `bin/rails test` reports 783 runs, 2644
assertions, 0 failures, 0 errors, 0 skips. Rubocop: 203 files, 0 offenses.
Brakeman: 2 weak-confidence warnings on Step-28-untouched files
(`emulator_controller.rb:79`, `gym_schedule_discord_update_job.rb:14`) — zero
delta.

Step 28 is clear.
