# Build Log
*Owned by Architect. Updated by Builder after each step.*

`Current Status` and `Step History` are session-scoped — archived to
`handoff/archive/` at session end and reset.
`Known Gaps` and `Architecture Decisions` are durable — they survive session
reset until the gap is addressed or the decision is replaced.

---

## Current Status
*Session-scoped.*

**Step 29 shipped on branch `claude/funny-payne-4df13d` at `d18b966`, FF-merged to `origin/main`, and pushed.** Replace the Rails-default red-dot favicon with a chunky pokeball icon at the canon palette (`--crimson` top, `--white` bottom, `--d1` ink ring + equator + button). Three files: `public/icon.svg` rewritten as a 16×16 viewBox pokeball; `public/icon.png` regenerated at 512×512 from the new SVG via `magick`; `app/views/pwa/manifest.json.erb` `theme_color` / `background_color` swapped from `"red"` (Rails default leftovers) to `"#1a2e1a"` / `"#c0d0a0"` (canon `--d1` / `--white`). No layout-file changes; no new tests (no existing favicon tests, brief says don't add any). Test count holds at **783**. Rubocop clean. Richard cleared 0 / 0 / 0 — rendered the SVG at 16×16 and 32×32 with `magick` nearest-neighbour zoom; equator and button stay distinguishable at favicon size, neither pre-approved D5 simplification needed.

---

## Step 28 — Status archive
*Kept here for one-step lookback; will fold into archive at session end.*

**Step 28 shipped on branch `claude/confident-kare-0d3dab` at `afb39f4`, FF-merged to `origin/main`, and pushed.** Visual rebuild of the dashboard against `designs/04-pixeldex.html` (the canonical source). Functional behavior preserved verbatim from Steps 20–27. Test count 782 → 783. Rubocop clean; Brakeman zero delta on touched files.

---

## Step 27 — Status archive
*Kept here for deeper lookback this session.*

**Step 27:** Restyle the four Phase-2 redesigns (R3 Save Slots, R2 PC Box review tray, R4 Map timeline, R1 Dashboard) to the legacy `gb-*` idiom. Pure CSS-first / minor-ERB visual restyle — functional behavior unchanged. Mechanical application of the audit's per-surface directive tables (`handoff/2026-05-06-old-style-canon-audit.md` § 3.1 / 3.2 / 3.3 / 3.4). The four surfaces' chrome rebased to `gb-card-dark`, `gb-btn` / `gb-btn-primary` / `gb-btn-sm`, `gb-section-header`, `gb-flash-alert` / `gb-flash-notice`, `gb-page-title` / `gb-page-subtitle`. The `.dash-r1`, `.pc-box-r2`, `.map-r4` namespaces stay (forward-path bound from Step 25); only the rules under them change.

**Architect-prep docs:** `handoff/2026-05-06-old-style-canon-audit.md` (the directive table — source of truth for what changes) + Step 27 update to `app/assets/stylesheets/design_canon.md` § 0 / § 4-7 / § 11 (chrome-reduction rules).

**Highlights / decisions:**
- **One step, not split into 27a/b/c/d.** All four surfaces share the same primitive substitutions (boxed bar → gb-page-title, custom buttons → gb-btn*, multi-pill stacks → single-color or removal, animations → static, sub-tabs → gb-section-header). Mechanical bundling.
- **Build order: warm-up → highest-risk last.** Save Slots (3.2) → PC Box (3.3) → Map (3.4) → Dashboard (3.1).
- **`badge-dot` → inline `*` text suffix** with `aria-label="Updates available"` (preserves the affordance without the glow chrome).
- **Status-rail sub-tabs preserved structurally, restyled visually.** Controller wiring stays; `.side-tabs` CSS rebases to look like stacked `gb-section-header`s.
- **Run-pill rebased to gb-btn shape; status indicator inline as text** (`RUN #2 — ACTIVE ▾`). Run-option pills in the dropdown rebase to plain `[ACTIVE] / [HOF] / [PAST]` text suffix.
- **Stat-strip per-item colour coding dropped.** ALIVE / DEAD / BADGES values are plain `--white`; the labels do the work per canon § 11.2.
- **PC Box review-row badges rebased to single ghost-pill family.** All 4 badges (1ST / TRADE-IN / EVENT / OFF-FEED) share the same rule. The kind reads from the LABEL TEXT, not from a colour. Per-row badge modifier classes left in markup as inert hooks.
- **Map node-legend collapsed inline into the subtitle.** No separate boxed legend bar.
- **Animations dropped: `pulseNext` (map nodes + dashboard gym row + map accordion row), `subtleBlink` (jump-btn).** Replaced by static border-color emphasis. `@keyframes pulseNext` definition retained in `pixeldex.css` as a no-op (cheap to leave; can be pruned in a future cleanup pass). `subtleBlink` block deleted.
- **Hover translateY + box-shadow drops** across 4 sites (`.pc-box-r2 .box-cell`, `.map-r4 .node`, `.map-r4 .special-cell`, `.map-r4 .badge-strip .badge`). One-frame border-color swaps replace them.
- **Three test files updated to match new markup** — none of the assertions tested functional contracts that changed; they all asserted *visual chrome* the audit removes.

**Files touched:** `app/assets/stylesheets/pixeldex.css` (~1102-2492 across 4 namespace blocks); 5 ERB views (`_save_slots_sidebar`, `_pc_box_content`, `map/show`, `_title_bar`, `_tab_bar`, `_status_rail`); 3 integration tests (`dashboard_redesign_test`, `pc_box_redesign_test`, `map_redesign_test`); `design_canon.md` (Architect-authored Step 27 update); plus the new audit doc.

**Test count:** 782 → **782** (no count change). 0 failures, 0 errors.
**Lint:** rubocop clean (203 files, 0 offenses).
**Brakeman:** Clean (same 2 pre-existing weak-confidence warnings; zero delta on Step-27-touched files).
**Migrations:** None. **Zero new gem deps. Zero controller / model / service / config / job / channel code touched.** Pure presentation-layer restyle.

**Review:** Richard cleared 0 / 0 / 0 (Must Fix / Should Fix / Escalate). Aesthetic-consistency check verified all four restyled surfaces use canon primitives uniformly; manual visual smoke deferred to PO. Bob's 6 confirmed exceptions all harmless or helpful.

---

## Step 25 — Status archive (deeper lookback, kept this session)
*Will fold into archive at session end.*

**Step 25:** Site-wide design canon adoption (first step after Phase 2 closed at Step 24). Mechanical CSS-only normalization: single file edit (`app/assets/stylesheets/pixeldex.css`) + one new test (`test/integration/design_canon_test.rb`) + two new docs (`handoff/2026-05-06-design-canon-audit.md` + `app/assets/stylesheets/design_canon.md` — Architect-locked source of truth). Six self-contained slices per `handoff/ARCHITECT-BRIEF.md`:
- **Slice 1 — Tokens:** Replaced the `:root` block (lines 5-21) with the canon-aligned version. Added 30+ new tokens (semantic aliases `--shadow/--ink/--shade/--moss/--canvas/--paper/--accent/--success/--danger`, danger family `--danger-bg/--danger-border/--danger-fg`, spacing scale `--s-1` through `--s-8`, type scale `--t-micro` through `--t-xl`, letter-spacing scale `--ls-tight/--ls-default/--ls-wide`, line-height scale `--lh-tight/--lh-snug/--lh-body`). Kept every existing token (`--d0/--d1/--d2/--l1/--l2/--white/--amber/--green-glow/--crimson`); semantic aliases point at them. `--border` / `--border-thin` / `--border-double` rewritten to use `var(--ink)` (still resolves to `--d1` — value-stable).
- **Slice 2 — Danger tokens:** Three sites swapped from hardcoded hex (`#4a1c1c` / `#6b2c2c` / `#e8a0a0`) to `var(--danger-*)`: `.gb-flash-alert` (lines ~178-181), `.gb-btn-danger` block + only the `:hover` `background: #6b2c2c` (lines ~792-803; the `#f0c0c0` hover `color` stays inline as documented in audit Section 1), `.gb-status-dead` (lines ~921-924). Out-of-scope sites untouched: `.team-builder-status--error #e8a0a0` (single-use error text), `.map-r4` namespaced redesign blocks (`.node.dead .glyph` / `.acc-row .glyph.dead` / `.node-legend .glyph.dead`), `.pc-box-r2 .box-cell.dead #2a1a1a/#4a1c1c` (extra-dark variant).
- **Slice 3 — Pill paddings:** Snapped 4 sites of `padding: 2px 5px` → `padding: var(--s-1) var(--s-2)` (= `2px 6px`): `.state-pill` (~line 1900), `.hof-pill` (~line 2079), `.map-r4 .group-card .head .pill` (~line 1503), `.pc-box-r2 .badge-legend .badge` (~line 1639). Post-edit grep confirms 0 remaining `padding: 2px 5px` lines in the file.
- **Slice 4 — Amber CTA paddings:** Unified two amber-CTA paddings to `padding: var(--s-3) var(--s-5)` (= `8px 12px`). `.dash-r1 .next-battle .draft-cta` (was `8px`, gains 4px horizontal) and `.map-r4 .status-bar .jump-btn` (was `6px 12px`, gains 2px vertical). The visual delta is minor; both are "small CTAs in a narrow strip".
- **Slice 5 — Letter-spacing tokens:** Converted `letter-spacing: 0.03em` → `var(--ls-tight)` on the 3 `.gb-btn*` sites enumerated in the brief: `.gb-btn` (line 761), `.gb-btn-primary` (line 779), `.gb-btn-danger` (line 797 — done in the same edit as Slice 2). Per brief Definition of Done ("`0.03em` → `var(--ls-tight)` on `.gb-btn*`"), the 2 non-button uses (`.team-name` line ~383, `.box-cell-name` line ~477) are explicitly out of scope and remain unchanged. Audit's "all on `.gb-btn*` classes" gloss + DoD scope match.
- **Slice 6 — Smoke test:** New `test/integration/design_canon_test.rb` (5 assertions, 5 passes): asserts `--accent: var(--amber)` aliased in `:root`, asserts `--danger-bg/--danger-border/--danger-fg` declared, asserts spacing scale `--s-1`..`--s-8` declared, asserts `.gb-flash-alert/.gb-btn-danger/.gb-status-dead` blocks reference `var(--danger-*)`, asserts `design_canon.md` exists and references the locked semantic aliases.

**Test count:** 777 → **782** (+5). 0 failures, 0 errors.
**Lint:** rubocop clean (203 files, 0 offenses).
**Brakeman:** Clean (same 2 pre-existing weak-confidence warnings on `emulator_controller.rb:79` SendFile + `gym_schedule_discord_update_job.rb:14` FileAccess unchanged from Steps 18/19/20/21/22/23/24).
**Migrations:** None. **Zero new gem deps. Zero new model / service / controller / view / config code.** This is a pure-CSS normalization step.

**Pre-existing context:** Step 25 follows the design canon audit shipped pre-step by Architect (`handoff/2026-05-06-design-canon-audit.md` + `app/assets/stylesheets/design_canon.md`, both locked). Step 24 (R1 Dashboard) shipped at `4923876` on `main` (Phase 2 closed). Step 25 is the first step after Phase 2 — it normalizes shared surfaces against the locked canon without rewriting any redesign.

**Step 25 highlights / decisions:**
- **Brief is the source of truth on letter-spacing scope.** The brief enumerates 3 `.gb-btn*` sites and parenthetically allows for a 4th `.gb-btn*` site. The audit's "0.03em (~5 uses, all on buttons)" was slightly off — there are 5 total `0.03em` sites but only 3 are on `.gb-btn*` (the other 2 are `.team-name` and `.box-cell-name`, which are text labels not buttons). Definition of Done says "0.03em → var(--ls-tight) on .gb-btn*" — converted only the 3 button sites. Per "Do not improvise. Do not expand scope" rule, the 2 non-button sites are left for a future canon iteration.
- **`.gb-btn-danger` letter-spacing was folded into the Slice 2 edit** because the same selector block changes both the danger hexes (Slice 2) and the letter-spacing (Slice 5). One edit instead of two — value-equivalent.
- **Post-edit grep verification:** `padding: 2px 5px` → 0 matches (was 4); `letter-spacing: 0.03em` → 2 matches remaining (`.team-name`, `.box-cell-name` — out of scope per DoD); `#4a1c1c/#6b2c2c/#e8a0a0` remain only in the token definitions (`:root`) and on the explicitly out-of-scope sites (`.team-builder-status--error`, `.map-r4` namespaced blocks, `.pc-box-r2 .box-cell.dead`).
- **Reference docs unchanged.** `handoff/2026-05-06-design-canon-audit.md` and `app/assets/stylesheets/design_canon.md` are Architect-locked source of truth — Bob did not edit them.

---

## Step History
*Session-scoped.*

### Step 28 — Rebuild the dashboard against `designs/04-pixeldex.html` — 2026-05-06
**Status:** Shipped on branch `claude/confident-kare-0d3dab` at `afb39f4`; FF-merged to `origin/main` and pushed. Richard cleared 0 / 0 / 0 (Must Fix / Should Fix / Escalate). **No KGs close, 0 KGs open.**

Visual rebuild of the dashboard surface against the canonical PixelDex source spec (`designs/04-pixeldex.html`) — the source-of-truth file from which the project's `:root` palette was originally derived. Functional behaviour preserved verbatim from Steps 20–27; backend / controllers / models / Stimulus targets untouched. Out-of-scope partials (`_pc_box_content`, `_map_content`, `_save_slots_sidebar`) untouched. All work happens inside the existing `.dash-r1` namespace block in `pixeldex.css` plus mechanical class-rename / wrapper-restructure edits in 4 ERB views.

**Architect-prep doc:** `handoff/2026-05-06-pixeldex-source-extraction.md` (Halves 1 + 2 — locked source spec extracted from `designs/04-pixeldex.html` and live-vs-source diff). Half 3 (the rebuild itself) is this step.

**Highlights / decisions:**
- **Title bar gets the PixelDex `--d2` band.** Single horizontal `--d2` row with `--l2` text + 3 px ink border-bottom. `.title-left` (title-block + run-pill) flex-aligned against new `.title-right` (stat-strip). Player caption recoloured from `--white` to `--l2` to read on the dark band; letter-spacing 0.08em.
- **Stat-strip rebuilt to PixelDex `.title-stat` block grid form via CSS-only flex `column-reverse`.** ERB DOM stays — the existing test assertion `<div class="item"><span>LABEL</span><span class="val">N</span></div>` continues to match. The label `<span>` is first in DOM but renders below the `.val` `<span>` because of `flex-direction: column-reverse`. The `·` separators are kept in DOM but hidden via CSS — gap does the spacing.
- **Run-pill restyled to a label-on-d2-band form.** Transparent bg, `--l2` text, 2 px `--l1` underline as the affordance. Hover is a subtle 15%-opacity green wash, not a full bg flip — reads as part of the title bar, not a stamped-on button.
- **Tab-bar cells stack icon-above-label (PixelDex 2-line form).** Renamed `.tab` → `.tab-item` and `.icon` → `.tab-icon` (both ERB and CSS) to match source. `.tab-icon` is `display: block; font-size: 20px; margin-bottom: 4px; line-height: 1;` so the 20 px glyph sits above the 13 px label.
- **3-col layout adopts shared-frame form.** `gap: 0` (was 14 px), `margin-top: 0` (was 14 px), `background: var(--l2)`. Per-panel `border-right: var(--border)` shares a single 3 px ink frame across columns; `:last-child` drops the right border.
- **`.pc-layout::after` scanline overlay skipped.** `body::after` (lines 113–126) is `position: fixed; inset: 0;` covering the full viewport already — adding a per-pc-layout overlay would be a double-overlay per D3's "Skip if the body-level scanline already covers this".
- **`.col-party` wrapper dropped (Architect option (a)).** `_party_panel` already provides its own `<div class="panel">` shell, so it now participates directly in `.pc-layout`. The 900 px-breakpoint hide-rule rewrites from `.dash-r1 .col-party` to `.dash-r1 .pc-layout > .panel:first-child`.
- **Right rail flattened.** `.dash-r1 .status-rail` drops the boxed wrapper (transparent bg, no border, no padding); the rail participates in the shared 3-col frame as a plain panel. `.side-tabs` rebuilt as a horizontal mini `.tab-bar` (--d1 bg + ink border-bottom) with `.side-tab` cells styled like `.tab-item` siblings (--d2 bg, --l1 text, hover/active swap to --d1 + --l2). The vertical caps-bar stack form from Step 27 is gone.
- **Right-rail card aesthetic flips dark → light.** `.player-card` rebases to PixelDex light-card form (--l1 bg + 2 px ink border + --d1 text). `.gym-list .gym-row` rebases to PixelDex `.gym-list-item` form (single-line flex, 11 px font, solid `--d2` divider, glyph-prefix `.num` cell). `.gym-row.next` becomes a `.gym-next-highlight` filled bar (--d2 bg + --l2 text, with `margin: 4px -6px` so it bleeds into the panel-body's negative space). `.next-battle` rebases to a `.route-card` light-card skin so the CTA block harmonises with the rest of the rail.
- **`.h3-row` → `.panel-header` (3 occurrences).** Each `<div class="h3-row"><h3>…</h3><span class="count">…</span></div>` rewritten to `<div class="panel-header"><span>…</span><span class="panel-header-sub">…</span></div>` — same content, canonical primitive class names so the canonical `:root`-level rules apply. The `.dash-r1`-scoped `.h3-row` / `h3` / `.count` rules deleted.
- **Each panel body wrapped in `.panel-body` (3 occurrences).** Padding lines up with the rest of the dashboard's panels.
- **Gym list glyphs emitted from ERB, not CSS `::before`.** Chose D5's "OR rewrite the ERB to emit the right glyph" path — `★` for beaten, `▶` for next, `·` for upcoming. Avoids per-row CSS `::before` content rules; keeps the ERB self-explanatory.
- **WAI-ARIA tablist contract preserved.** Every `role="tab"`, `aria-selected`, `aria-controls`, `tabindex`, plus `pixeldex#tablistKeydown`, `pixeldex#numericJump`, `status-rail#keydown`, all controller targets and `data-*` attributes intact across the rebuild.
- **Stale assertions in `responsive_grids_test.rb` updated in lockstep.** Two assertions hard-coded the old `.dash-r1 .col-party` and `.dash-r1 .tab` selector forms; both updated to match the new DOM (`.pc-layout > .panel:first-child`) and class name (`.tab-item`). Same intent; same coverage; matches the Step 27 pattern of updating visual-chrome assertions when the chrome is restyled.

**Files touched:**
- `app/views/dashboard/_tab_bar.html.erb` (class rename + comment header)
- `app/views/dashboard/_title_bar.html.erb` (`.title-right` wrap + comment header)
- `app/views/dashboard/_status_rail.html.erb` (3× `.h3-row` → `.panel-header`, 3× `.panel-body` wrap, gym-row glyph rewrite)
- `app/views/dashboard/show.html.erb` (drop `.col-party` wrapper)
- `app/assets/stylesheets/pixeldex.css` (`.dash-r1` namespace block ~lines 2155–2615 rebuilt)
- `test/integration/dashboard_redesign_test.rb` (+1 new test for `.tab-item` class)
- `test/integration/responsive_grids_test.rb` (2 stale assertions updated)

**Test count:** 782 → **783** (+1). 0 failures, 0 errors, 0 skips.
**Lint:** rubocop clean (203 files, 0 offenses).
**Brakeman:** Clean (same 2 pre-existing weak-confidence warnings on `emulator_controller.rb:79` SendFile + `gym_schedule_discord_update_job.rb:14` FileAccess; zero delta on Step-28-touched files).
**Migrations:** None. **Zero new gem deps. Zero controller / model / service / config / job / channel code touched. Zero canon token changes. Zero JS changes.** Pure presentation-layer rebuild: 1 CSS file modified, 4 view files modified, 2 test files modified.

---

### Step 26 — Rebase design canon `--accent` from `--amber` to `--green-glow` — 2026-05-06
**Status:** Shipped on branch `claude/hungry-cray-ff4938`; FF-merged to `origin/main` and pushed. **No KGs close**, **0 KGs open**.

User feedback driver: "I think the new design is a downgrade from the old styling, can you look at the gym draft view page for the lighter green color and use that as the main color? I like the unified styling but I'm focused on the colors." Step 25 introduced `--accent` as a semantic alias but never propagated it (`grep -c "var(--accent)" pixeldex.css` was `0` pre-Step-26); Step 26 swaps the alias *and* does the propagation.

**Slice A — Token alias:** `pixeldex.css` line 24, `--accent: var(--amber)` → `--accent: var(--green-glow)`. `--success: var(--green-glow)` left intact (semantic distinction preserved in prose; both aliases now resolve to the same Game Boy palette slot). `--amber: #d4b14a` token kept defined as a positional palette token (no live references but available for future opt-in gold surface).

**Slice B — `pixeldex.css` `var(--amber)` sweep:** 60 of 62 references swept to `var(--accent)`. The 2 surviving references are inside `.conflict-warning` (lines 2111-2112) — explicitly out-of-canon per `design_canon.md` § 9 (single-use save-slot warning, intentional gold/yellow alarm). Post-edit grep: `grep -c "var(--amber)" pixeldex.css` → `2`; `grep -c "var(--accent)" pixeldex.css` → `59`.

**Slice C — rgba glow decompositions:** 10 sites of `rgba(212, 177, 74, …)` (`#d4b14a` decomposed) → `rgba(95, 212, 95, …)` (`#5fd45f` decomposed) at lines 1137, 1169, 1170, 1287, 1300, 1308, 1309, 1350, 2449, 2450. Same alpha stops preserved (0.3 / 0.4 / 0.45 / 0.7 / 0). Mechanical bulk replace.

**Slice D — view files:** 4 inline `var(--amber)` → `var(--accent)` swaps:
- `app/views/dashboard/_runs_content.html.erb:33` — HoF "🏆 COMPLETE" pill (border-color + background; color: var(--d1) untouched).
- `app/views/dashboard/_gyms_content.html.erb:52` — NEXT pill (border-color + color).
- `app/views/map/show.html.erb:251` — "↓ NOW · log first encounter" caption (color).
- `app/views/gym_drafts/show.html.erb:194` — coin-flip result text on tiebreak reveal (color).

**Slice E — JS file:** 4 inline-style writes in `app/javascript/controllers/gym_draft_controller.js` (lines 157, 262, 263, 572) updated. Line 263 was `"0 0 0 2px var(--amber)"` (amber embedded in a longer `box-shadow` literal) — bare-token `replace_all` initially missed it; caught by post-edit `grep -rn "var(--amber)" app/views/ app/javascript/` audit and fixed before review submission.

**Slice F — `design_canon.md`:** § 1 Accents table row updated (`--accent (= --green-glow)` `#5fd45f`); new Step 26 note added at top of § 1 documenting the rebase + `--success`/`--accent` shared hex; § 8 Borders parenthetical updated from "4px amber = warn-emphasis" to "4px accent-green = active-emphasis"; opening sentence updated from "dimmed amber accent" to "dimmed green accent".

**Slice G — Test:** `test/integration/design_canon_test.rb` first assertion regex updated from `/--accent:\s*var\(--amber\)/` to `/--accent:\s*var\(--green-glow\)/` plus message updated to "Step 26: --accent rebased to --green-glow". Other 4 design-canon tests unchanged.

**Test count:** 782 → **782** (no count change; the regex on the first assertion changed). 0 failures, 0 errors.
**Lint:** rubocop clean (203 files, 0 offenses).
**Brakeman:** Clean (same 2 pre-existing weak-confidence warnings on `emulator_controller.rb:79` SendFile + `gym_schedule_discord_update_job.rb:14` FileAccess; zero delta on Step-26-touched files).
**Migrations:** None. **Zero new gem deps. Zero controller / model / service / config / migration code.** Pure presentation-layer rebase: 1 CSS file modified, 4 view files modified, 1 JS file modified, 1 Markdown doc modified, 1 test file modified.

**Review:** Richard cleared 0 / 0 / 0 / 0 (Must Fix / Should Fix / Escalate / Nits). All grep + test + visual checks passed.

---

### Step 25 — Site-wide design canon adoption — 2026-05-06
**Status:** Shipped on branch `claude/stupefied-burnell-62b48d`; FF-merged to `origin/main` at `1a5024d` and pushed. **No KGs close**, **0 KGs open**.

Mechanical CSS-only normalization step. One file edit (`app/assets/stylesheets/pixeldex.css`) + one new test file (`test/integration/design_canon_test.rb`). Architect-locked source of truth: `handoff/2026-05-06-design-canon-audit.md` (audit + rationale) + `app/assets/stylesheets/design_canon.md` (locked canon). Six tight slices per the brief:

**Slice 1 — `:root` block extended (lines 5-21 → lines 5-72):** Added 30+ semantic-alias / scale tokens (`--shadow/--ink/--shade/--moss/--canvas/--paper/--accent/--success/--danger`, `--danger-bg/--danger-border/--danger-fg`, `--s-1`..`--s-8`, `--t-micro`..`--t-xl`, `--ls-tight/--ls-default/--ls-wide`, `--lh-tight/--lh-snug/--lh-body`). Existing tokens `--d0/--d1/--d2/--l1/--l2/--white/--amber/--green-glow/--crimson` preserved verbatim — they remain the source of truth; semantic aliases point at them. `--border` family rewritten to use `var(--ink)` (still resolves to `--d1` — value-stable).

**Slice 2 — Danger tokens replace 9 hex values:** `.gb-flash-alert` (3 swaps), `.gb-btn-danger` block (3 swaps + 1 `:hover` background, the `#f0c0c0` hover color stays inline), `.gb-status-dead` (3 swaps).

**Slice 3 — Pill paddings snapped:** 4 sites of `padding: 2px 5px` → `padding: var(--s-1) var(--s-2)` (= `2px 6px`). Sites: `.state-pill`, `.hof-pill`, `.map-r4 .group-card .head .pill`, `.pc-box-r2 .badge-legend .badge`. Post-edit grep confirms 0 remaining matches.

**Slice 4 — Amber CTA paddings unified:** `.dash-r1 .next-battle .draft-cta` (`8px` → `var(--s-3) var(--s-5)` = `8px 12px`) + `.map-r4 .status-bar .jump-btn` (`6px 12px` → same token). Visual delta minor; both share the "small CTA in a narrow strip" role.

**Slice 5 — Letter-spacing tokens:** Converted `letter-spacing: 0.03em` → `var(--ls-tight)` on the 3 `.gb-btn*` sites (`.gb-btn` line 761, `.gb-btn-primary` line 779, `.gb-btn-danger` line 797 — that one folded into the Slice 2 edit). Per Definition of Done ("on `.gb-btn*`"), the 2 non-button uses (`.team-name`, `.box-cell-name`) stayed unchanged.

**Slice 6 — Smoke test:** New `test/integration/design_canon_test.rb` (5 assertions, 5 passes): `--accent` aliased, danger family declared, spacing scale declared, danger-family blocks reference `var(--danger-*)`, `design_canon.md` references the locked tokens.

**Test count:** 777 → **782** (+5 from new `design_canon_test.rb`). 0 failures, 0 errors.
**Lint:** rubocop clean (203 files, 0 offenses).
**Brakeman:** Clean (same 2 pre-existing weak-confidence warnings unchanged).
**Migrations:** None. **Zero view files touched. Zero controller files touched. Zero model files touched. Zero config files touched. Zero migrations.** Only `pixeldex.css` (modified) + `design_canon_test.rb` (added).

---

### Step 24 — R1 Dashboard restructure (Phase 2 R1 of the 2026-05-04 audit; closes Phase 2) — 2026-05-05
**Status:** Shipped on branch `claude/sad-haslett-33d407` — FF-merged to `origin/main` and pushed. **Phase 2 closes.** **No KGs close**, **1 KG opens** (KG-39 — see § Known Gaps).

**Reviewed by Richard:** 0 Must Fix, 4 Should Fix (all fixed inline — see "Should Fixes resolved" appendix in `REVIEW-REQUEST.md`): (1) run-option `tabindex="0"` → `tabindex="-1"` (WAI-ARIA listbox roving-focus contract), (2) `+ START NEW RUN` button gains `role="option"` + matching `tabindex="-1"`, (3) `run_picker_controller.js` ArrowUp/ArrowDown edge case at `currentIndex === -1` (trigger has focus) — explicit guard lands ArrowUp on last option, ArrowDown on first, (4) inline `form: { style: "margin: 0;" }` on the START GYM DRAFT CTA moved to `.dash-r1 .next-battle form { margin: 0; }` in `pixeldex.css` (audit cross-cutting #5 — zero inline styles). Suite still 777/0; rubocop clean (202 files, 0 offenses); brakeman clean (same 2 pre-existing weak-confidence warnings unchanged).

Final Phase 2 redesign per § 5 of `handoff/2026-05-04-ui-audit.md`. Six locked screens in `handoff/2026-05-04-ui-audit-mockup-dashboard.html` (desktop 3-col + slim title + real tablist · right-rail PARTY view · tablet 2-col · phone single column + scrollable tab strip · run-pill open · ARIA spec sheet). Pure frontend ship — 5 view rewrites + 1 CSS section + 1 extended Stimulus controller + 2 new Stimulus controllers + 2 file deletions + 1 controller line addition + 1 controller redirect rewrite. Architect-locked decisions tracked under § Architecture Decisions.

**Architecture decisions (durable — see § Architecture Decisions):**
- **CSS namespace under `.dash-r1`** (Step 22 `.pc-box-r2`, Step 23 `.map-r4` precedent). Every new CSS selector is prefixed `.dash-r1 …` so existing `.title-bar` / `.tab-bar` / `.pc-layout` rules used elsewhere in the app remain untouched. Within `.dash-r1`, the new rules **override** the legacy `.title-bar` (slim row), `.tab-bar` (tablist), `.pc-layout` (3-col) shapes.
- **Run-management controller hoisted to dashboard root.** Pre-Step-24 `_runs_content.html.erb` carried `data-controller="run-management"` scoped to the RUNS tab content. Step 24 hoists it to `app/views/dashboard/show.html.erb`'s outer `.dash-r1` div so the title-bar's `+ START NEW RUN` button reaches `run-management#startRun` via DOM bubbling without spawning a second ActionCable subscription. Inside `_runs_content`, the wrapper `<div>` no longer carries the data attributes — targets resolve up the DOM.
- **Run-pill is anchor-based for switch action; Stimulus only enhances.** Each menu option is a real `<a href="/?run_id=N" role="option">` so switching runs works without JS. `run-picker` Stimulus controller adds toggle (`click->run-picker#toggle`), keyboard nav (↑/↓/Home/End/Enter/Esc via `keydown->run-picker#navigate`), and outside-click close (`document.addEventListener("click", _closeOnOutside)` in `connect()`). `aria-haspopup="listbox"` + dynamic `aria-expanded` ship on the pill button.
- **Tablist activation on focus move (mockup spec).** WAI-ARIA recommends focus-only on ←/→ with Enter/Space to activate, but the mockup explicitly says "←/→ moves between tabs (with wrap), updates `aria-selected` and `tabindex` immediately, **and activates the tab**." `pixeldex#tablistKeydown` calls `target.focus(); target.click()` to honor mockup. If a follow-up wants the WAI-ARIA-strict shape, drop `target.click()` from `tablistKeydown`.
- **`pixeldex#numericJump` window-level binding gated for input focus.** `keydown@window->pixeldex#numericJump` registers globally on `app/views/dashboard/show.html.erb`'s `.dash-r1` wrapper. Skip conditions: `event.target.tagName` in `INPUT` / `TEXTAREA` / `SELECT`; `target.isContentEditable`; any modifier key (`metaKey`/`ctrlKey`/`altKey`/`shiftKey`). Mockup spec.
- **`switchTab` writes URL hash via `history.replaceState`** (Step 23 `#route=` precedent). No back-stack pollution. The existing `#applyHashTab` in `connect()` reads the hash and clicks the matching tab button — round trip preserves tab across reloads.
- **Right-rail consolidation: 3 sub-tabs replace stacked panels.** Old `_map_panel.html.erb` stacked ASCII map + current location card + badge case + GYM LEADERS + recent routes — duplicating MAP and GYMS main-tab content. New `_status_rail.html.erb` collapses this into one card with PARTY / GYMS / MAP sub-tabs; GYMS is default-active per mockup screen 1. PARTY is NEW data (one row per registered player); GYMS is a compact version of the existing GYMS tab content with a START GYM DRAFT CTA; MAP is the old `_map_panel` body MINUS the GYM LEADERS section (now in GYMS sub-tab — closes audit cross-cutting #6 duplication). Mockup-driven.
- **`status-rail` Stimulus controller** drives the sub-tabs: `switch` (click) + `keydown` (←/→/Home/End focus+activate) on `[role="tab"]` buttons. `_activate(tab, { focus })` flips `aria-selected` + `tabindex` and toggles the matching panel's `.hidden` class.
- **`/runs` becomes a 301 redirect to `root_path(anchor: "runs")`.** Cross-cutting #3 from the audit ("Run management exists in two divergent surfaces") resolved here. The dashboard RUNS tab is canonical (it has run/guild context loaded, supports cross-run switching via the chrome run pill, and inherits the dashboard's tablist contract for free). External links / nav links / the emulator page's `GO TO RUNS` button all keep working through the redirect; the 301 is a permanent IA decision so search engines / social previews learn the new URL. `/runs` view file deleted; `app/views/runs/` directory removed.
- **Emulator-ROM affordances added to the dashboard RUNS tab.** Pre-Step-24 the `Generate Emulator ROMs` / `Regenerate ROMs` / `ROMs generating…` status span only existed on `/runs`. Now also on the dashboard RUNS tab in `_runs_content.html.erb`, wired identically to `run-management#generateEmulatorRoms` / `#regenerateEmulatorRoms`. No JS controller changes — the Stimulus targets already exist (`generateRomsButton` / `regenerateRomsButton` / `generateRomsStatus`) and the controller's `render()` method already sets visibility based on `current_run.emulator_status`.
- **Stat strip math fixed inline** (no controller change). Pre-Step-24 title bar showed `@caught_count` for "CAUGHT" and `@caught_count - @dead_count` for "ALIVE", which read as a labeling inversion (controller's `@caught_count = @all_groups.count(&:caught?)` is currently-alive-with-status-caught, not total-ever-caught). Mockup locks the conventional reading: CAUGHT = total ever caught; ALIVE = currently alive; DEAD = currently dead. New view computes `@caught_count + @dead_count` for CAUGHT and `@caught_count` for ALIVE without changing controller semantics. Documented in the view with a WHY comment.
- **`@all_player_teams` is the only new controller variable.** Computed once in `DashboardController#show` with `includes(soul_link_team_slots: { soul_link_pokemon_group: :soul_link_pokemon })` so the PARTY sub-tab renders without per-player N+1. Iterating `SoulLink::GameState.players` and looking up via `index_by(:discord_user_id)` keeps the partial readable.
- **Per-player badge counts on PARTY sub-tab share `@gyms_defeated`** (KG-39). Per-player badge variance is a future feature; for now all 4 player rows show the run's `gyms_defeated`. The YOU pill identifies the current user; the 🏆 HOF pill renders only when `@run.completed? && badges == 8`. Architect-decided ambiguity per the brief.
- **Mobile breakpoints**: existing `@media (max-width: 900px)` extended (`.dash-r1 .pc-layout` to 2-col + `.dash-r1 .col-party { display: none; }` + `.dash-r1 .title-bar` flex-direction column) — left party sidebar disappears, content lives in PARTY main tab. Existing `@media (max-width: 720px)` extended (`.dash-r1 .pc-layout` to 1fr + `.dash-r1 .tab-bar { overflow-x: auto; flex-wrap: nowrap; }` + stat strip pulls top border). Existing `@media (max-width: 520px)` extended (`.dash-r1 .stat-strip { font-size: 7px; gap: 8px; }`). All three breakpoint extensions land inside existing blocks; no new media block. **Zero new design tokens.**
- **Stimulus controller registration is automatic** via `eagerLoadControllersFrom("controllers", application)` in `app/javascript/controllers/index.js`. `pin_all_from "app/javascript/controllers"` in `config/importmap.rb` picks up both new controllers without manual edit.

**Test count:** 755 → 777 (+22). 0 failures, 0 errors.

**Files (new):** 3 —
- `test/integration/dashboard_redesign_test.rb` (~250 lines, 18 tests).
- `app/javascript/controllers/run_picker_controller.js` (~110 lines).
- `app/javascript/controllers/status_rail_controller.js` (~60 lines).
- `app/views/dashboard/_status_rail.html.erb` (~205 lines).

**Files (modified):** 9 —
- `app/views/dashboard/show.html.erb` (full rewrite for `.dash-r1` wrapper + status_rail render + ARIA tabpanel attrs on each tabContent div).
- `app/views/dashboard/_title_bar.html.erb` (full rewrite — slim row + glyph + run-pill + stat strip).
- `app/views/dashboard/_tab_bar.html.erb` (full rewrite — tablist + ARIA + icons + badge dots).
- `app/views/dashboard/_runs_content.html.erb` (added 3 emulator-ROM affordances; removed inner `data-controller="run-management"` wrapper now hoisted to dashboard root).
- `app/controllers/dashboard_controller.rb` (+5 lines — `@all_player_teams` instance variable).
- `app/controllers/runs_controller.rb` (full rewrite — body is now `redirect_to root_path(anchor: "runs"), status: :moved_permanently`).
- `app/javascript/controllers/pixeldex_controller.js` (+~70 lines — `tablistKeydown`, `numericJump`, `switchTab` aria/tabindex/replaceState extensions).
- `app/assets/stylesheets/pixeldex.css` (+~325 lines new R1 section above the RESPONSIVE block; +6 lines extending 900px block; +6 lines extending 720px block; +1 line extending 520px block).
- `test/integration/responsive_grids_test.rb` (+38 lines — 4 new Step 24 R1 assertions).
- `test/integration/confirm_modal_flow_test.rb` (3 `get runs_path` calls converted to `get root_path` for the canonical surface; 1 new `/runs redirects` test added).

**Files (deleted):** 2 —
- `app/views/dashboard/_map_panel.html.erb` (content folded into `_status_rail` MAP sub-tab; `_map_content.html.erb` for the MAP main tab is untouched).
- `app/views/runs/index.html.erb` (canonical content lives in `_runs_content.html.erb`; `/runs` is now a 301 redirect). `app/views/runs/` directory removed.

**Tests added (22 new):**
1. `DashboardRedesignTest`: `.dash-r1` wrapper renders with dashboard + pixeldex + run-management controllers attached.
2. `DashboardRedesignTest`: title-bar renders with the run-pill replacing the legacy `<select>` (no inline `onchange="window.location.href"`; `<button class="run-pill">` + `data-controller="run-picker"` + `aria-haspopup="listbox"` present).
3. `DashboardRedesignTest`: title-bar stat-strip renders 4 inline items (CAUGHT/ALIVE/DEAD/BADGES) with values from a seeded run (1 alive + 1 dead → CAUGHT 2 / ALIVE 1 / DEAD 1 / BADGES 0/8).
4. `DashboardRedesignTest`: tab-bar renders with `role="tablist"` + `aria-label="Dashboard sections"` + per-tab `role="tab"` + `id="tab-<key>"` + `aria-controls="panel-<key>"` for all 7 keys.
5. `DashboardRedesignTest`: active tab has `aria-selected="true"` + `tabindex="0"`; others have `aria-selected="false"` + `tabindex="-1"`. Scoped to the main tab-bar block (right rail also uses `role="tab"`).
6. `DashboardRedesignTest`: PC BOX tab carries a `<span class="badge-dot">` when `@auto_detected_catches.any?`.
7. `DashboardRedesignTest`: PC BOX tab does NOT carry a badge-dot when no auto-detected catches exist.
8. `DashboardRedesignTest`: GYMS tab carries a badge-dot when an active draft exists (`gym_drafts` row with status: "lobby").
9. `DashboardRedesignTest`: right status rail renders `<aside class="status-rail" data-controller="status-rail">` with 3 sub-tabs (PARTY/GYMS/MAP) carrying `data-status-rail-tab-param`.
10. `DashboardRedesignTest`: GYMS sub-tab is the default-active (exactly one `aria-selected="true"` under the rail; key is "gyms").
11. `DashboardRedesignTest`: GYMS sub-tab renders the START GYM DRAFT CTA when `@next_gym && !dashboard_read_only?(@run)`.
12. `DashboardRedesignTest`: GYMS sub-tab does NOT render the START GYM DRAFT CTA when wiped (read-only); shows "RUN ENDED" state instead.
13. `DashboardRedesignTest`: PARTY sub-tab renders one `.player-card` per `SoulLink::GameState.players` entry (4 in test settings).
14. `DashboardRedesignTest`: current user's PARTY sub-tab row has `class="player-card you"` and the YOU pill.
15. `DashboardRedesignTest`: RUNS tab includes the Generate Emulator ROMs button when `emulator_status == :none` (default with no sessions).
16. `DashboardRedesignTest`: RUNS tab includes the Regenerate ROMs button when `emulator_status == :failed` (created via `:soul_link_emulator_session, status: "failed"`).
17. `DashboardRedesignTest`: RUNS tab does NOT include the legacy `/runs` page selector (no `RUN MANAGEMENT` heading; no `class="gb-page-title">RUN MANAGEMENT`).
18. `DashboardRedesignTest`: `/runs` redirects to `root_path` with `#runs` anchor (status 301 or 302; `redirect_url.end_with?("#runs")`).
19. `ResponsiveGridsTest`: `.dash-r1` namespace declared outside any media block.
20. `ResponsiveGridsTest`: 900px breakpoint sets `.dash-r1 .pc-layout { grid-template-columns: minmax(0, 1fr) 280px; }` and `.dash-r1 .col-party { display: none; }`.
21. `ResponsiveGridsTest`: 720px breakpoint drops `.dash-r1 .pc-layout` to `1fr` and sets `.dash-r1 .tab-bar { overflow-x: auto; }`.
22. `ResponsiveGridsTest`: 520/720/900px breakpoints do NOT set `display: none` on `.dash-r1 .tab` or `.dash-r1 .status-rail`.

**Backward-compat invariants exercised:**
- `DashboardController#show` instance variables preserved verbatim; only `@all_player_teams` added (additive).
- `_party_panel.html.erb` (left-col party panel), `_party_detail.html.erb` (PARTY main-tab), `_pc_box_content.html.erb`, `_map_content.html.erb`, `_gyms_content.html.erb`, `_strategy_panel.html.erb`, `_calc_content.html.erb`, `_catch_modal.html.erb`, `_pokemon_modal.html.erb`, `_mark_dead_modal.html.erb`, `_reset_draft_modal.html.erb` all unchanged. The existing tab content + modals render inside the new shell exactly as before.
- `pixeldex_controller.js` actions all preserved verbatim (`switchTab`, `selectPokemon`, `searchSpecies`, `savePokemon`, `evolvePokemon`, `updateNatureLabel`, `closePokemonModal`, all `#initSortables` / `#onDragEnd` / `#saveTeamSlots` / `#updateGroupStatus` / `#openModal` / `#applyHashTab` private helpers). Targets all preserved. Only additions: `tablistKeydown`, `numericJump` actions; `switchTab` body extended (still backward-compat — legacy `.active` class still toggled).
- `run_management_controller.js` action surface unchanged. Targets unchanged. Hoisting the `data-controller` to dashboard root means the same controller instance services both the title-bar's `+ START NEW RUN` button and the RUNS tab's full panel; only one ActionCable subscription per dashboard load.
- `dashboard_controller.js` action surface unchanged.
- `confirm_modal_flow_test.rb`'s 3 legacy tests against `get runs_path` re-pointed at `get root_path` (the canonical surface). The `end-run-page-confirm` modal id is gone with the deleted `/runs` view — the dashboard surface uses `end-run-dashboard-confirm` (Step 20 precedent: distinct ids for distinct surfaces).
- `pc_box_redesign_test`, `map_redesign_test`, `wipe_flow_test`, all gym/team/run/pokemon model tests unaffected.

**Diff scope:** 4 new + 9 modified + 2 deleted files. Inside the brief's stated scope (`Files Bob will touch` table). Zero changes under `app/services/`, `app/jobs/`, `app/channels/`, `db/`, `config/` (except 1 controller body replacement and 1 controller line added per the brief).

**KG closures logged:** none.

**New Known Gaps logged this step:** 1 — KG-39 (per-player badge variance on the PARTY sub-tab). See § Known Gaps.

---

### Step 23 — R4 Map redesign (Phase 2 R4 of the 2026-05-04 audit) — 2026-05-05
**Status:** Built; awaiting Richard's review (`REVIEW-REQUEST.md` posted). **No KGs close** (Phase 2 redesigns are surface-level UX work, not backlog items).

Third Phase 2 redesign per § 5 of `handoff/2026-05-04-ui-audit.md`. Four locked screens in `handoff/2026-05-04-ui-audit-mockup-map.html` (desktop full timeline · sheet open / new catch · sheet open / existing catches · mobile accordion). Pure frontend ship — view + CSS + 1 extended Stimulus controller + 1 extended helper. Architect-locked decisions tracked under § Architecture Decisions.

**Architecture decisions (durable — see § Architecture Decisions):**
- **CSS namespace under `.map-r4`** (Step 22 `.pc-box-r2` precedent). The mockup's class names (`.timeline-frame`, `.node`, `.sheet`, `.accordion-segment`, `.special-cell`, etc.) are fresh — namespace prevents accidental collision with future `.timeline-*` rules elsewhere AND scopes the redesign cleanly.
- **The mockup's right-rail sticky SHEET replaces the old overlay slide-out panel.** No `position: fixed`, no backdrop, no `translateX` transition, no body lock. The sheet sits in a CSS Grid column on desktop (`grid-template-columns: minmax(0, 1fr) 380px`); below 720px the layout drops to single-column and the sheet de-stickifies. Default empty state ("Select a route to view or log catches.") is rendered server-side in the `.empty-state` block, gated visible by JS when no key is selected.
- **Mobile breakpoint = 720px for the timeline → accordion swap; 520px for special-encounters reflow.** Two-tier: 720px hides `.map-r4 .timeline-frame`, shows `.map-r4 .accordion-frame`, drops the layout to single column, drops `.map-r4 .sheet`'s `position: sticky`. 520px also reflows `.map-r4 .special-grid` from 4 cols to 2. **Both breakpoints extend existing blocks; new 720px block is fresh.**
- **`data-controller="timeline dashboard pixeldex"` triple-attached on the wrapper.** Both `dashboard` and `pixeldex` `connect()` methods are benign on `/map`: dashboard has no `connect`; pixeldex's `#initSortables()` is a no-op without on-team grids and `#applyHashTab()` looks for a tab-button matching the hash (no `tab=route_205` button → no-op). The wrapper carries every value attr the dashboard's `<div data-controller="dashboard pixeldex">` carries (`groups-url`, `csrf`, `user-id`, `abilities-data`, `evolutions-data`, `sprite-map`, `natures-data`, `pokemon-update-url`, `group-update-url`, `update-slots-url`). Single source of truth — no parallel modal copies.
- **Pulse-ring + "↓ NOW" pin on the next-uncaught route.** Identification rule (locked): walk `@progression["segments"]` in order, then `(segment["locations"] || []).each`, find the first location whose `location_status(...)` is `"uncaught"` AND whose `loc_data["type"]` is `"route"` (skip cities, dungeons, lakes, special). The first match wins. Cities + dungeons + lakes + specials are skipped because the pin marks "next ROUTE encounter" — late-game runs that have caught every route but no dungeons see no `.next` class anywhere; the JUMP TO NOW button hides via `.hidden` class.
- **Always-visible legend strip** between the status bar and the timeline frame. Five glyphs + labels: caught (●) · dead (☠) · uncaught (○) · special (★) · gym (G). Mockup-verbatim. Not collapsible.
- **Segment dividers between segments.** Helper `MapHelper#segment_divider_label(progression, gym_info, seg_idx)` returns the bare-city label of the UPCOMING segment's gym (e.g. between segment 1 and 2, the divider says `"ETERNA"` because segment 2's gym is `second_gym = eterna_city`). Final divider before the null-gym segment returns `"ELITE FOUR"` (Ava Q3 override; mockup's `"…"` was a truncation artifact).
- **`groups_json_for(groups, current_user_id)` extended additively** (Ava Q1). Per-pokemon: added `id`, `is_mine`, `level`, `ability`, `nature`, `sprite_url`, `types`. Per-group: added top-level `id`, `species_for_user`, `types_for_user`. Existing legacy fields (`species`, `player`, `sprite`) retained so the controller's `buildDetailsHtml` legacy reader (replaced in Step 23 but kept additive for safety) sees what it expects. The signature now requires `current_user_id` as the second arg — only call site is the rewritten map view.
- **Read-only mode JS detection via `hasSheetFormTarget`** (Ava Q5). The view conditionally renders `<form data-timeline-target="sheetForm">` only when `!dashboard_read_only?(@run)`; absent target means read-only mode → JS `_renderSheetGroupList` skips rendering EDIT, MARK DEAD, and `+ ANOTHER ENCOUNTER (DUPES CLAUSE)`. No parallel `readOnlyValue` (Ava Q6 override).
- **JUMP TO NOW button is conditionally hidden via `.hidden` class** (Ava Q3-adjacent). Helper returns `nil` when no uncaught route exists → ERB renders `class="jump-btn hidden"` server-side; the `connect()` method also re-runs the check JS-side as a safety net (`if (!hasNext) this.jumpBtnTarget.classList.add("hidden")`).
- **`.selected` class on `.glyph` replaces inline Tailwind ring-* classes.** CSS owns the visual (`outline: 3px solid var(--amber)`); Stimulus owns the state. Cleaner than inline class manipulation.
- **`#route=<key>` URL hash persistence is JS-only — no integration test.** Step 22's KG-35-style decision: Stimulus hash logic is hard to assert without a headless driver. The hash is read in `connect() → applyHashRoute()` and written in `selectLocation`; cleared in `closePanel`. Documented in the controller; no unit test.
- **The `+ ANOTHER ENCOUNTER (DUPES CLAUSE)` button reuses `submitCatch` verbatim.** Clicking it toggles `.sheet-body` from group-list mode to form mode for the same `loc_key` (`showCatchFormForCurrent` action). No new endpoint, no new modal. The form submits and reloads, the new group appears as an additional card next time the route's sheet opens.
- **Mockup-document chrome stripped from CSS** (Ava nudge). The `.page` / `.page-banner` / `.legend` / `.section-anchor` / `.annotation` / `.phone` / `.phone-bezel` styles in the mockup HTML style the mockup document, not the production component. New CSS keeps only actual component styles.

**Test count:** 712 → 754 (+42). 0 failures, 0 errors.

**Files (new):** 2 —
- `test/integration/map_redesign_test.rb` (217 lines, 13 tests).
- `test/helpers/map_helper_test.rb` (303 lines, 25 tests).

**Files (modified):** 6 —
- `app/views/map/show.html.erb` (full body rewrite, ~280 lines).
- `app/assets/stylesheets/pixeldex.css` (+~545 lines new R4 section above the R2 marker; +6 lines extending `@media (max-width: 520px)`; +7 lines new `@media (max-width: 720px)` block).
- `app/javascript/controllers/timeline_controller.js` (full extension; targets renamed, sheet logic rewritten, `jumpToNow` + `showCatchFormForCurrent` + `applyHashRoute` + `_renderSheetCatchForm` + `_renderSheetGroupList` + `_buildGroupCardHtml` + `_escape` added; ~430 lines total, ~120 new).
- `app/helpers/map_helper.rb` (+~155 lines: 6 new helpers + extended `groups_json_for`; private `bare_city_label` helper).
- `test/integration/responsive_grids_test.rb` (+38 lines: 4 new Step 23 R4 assertions).
- `handoff/BUILD-LOG.md` + `handoff/ARCHITECT-BRIEF.md` (Architect endorsement appended) updated. `handoff/REVIEW-REQUEST.md` posted at end of step.

**Tests added (42 new):**
1–8. `MapHelperTest`: `location_status` (uncaught/caught/dead branches), `primary_group` (caught preference + dead fallback + nil/empty).
9–13. `MapHelperTest`: `next_uncaught_route_key` (first-uncaught-route, skip non-routes, all-caught nil, earlier-segment-wins).
14–16. `MapHelperTest`: `current_segment_label` (FINAL STRETCH for nil, bare-city for next-uncaught-key, ELITE FOUR for null-gym segment).
17–19. `MapHelperTest`: `segment_divider_label` (upcoming bare-city, ELITE FOUR before null-gym, nil after last segment).
20–22. `MapHelperTest`: `segment_progress` (catchable types only in total, caught+dead toward caught total, zero/zero edge case).
23–24. `MapHelperTest`: `segment_open_by_default?` (matches segment containing key, false for nil).
25–26. `MapHelperTest`: `node_status_class` (special only for uncaught specials, fallthrough for non-special).
27–28. `MapHelperTest`: `groups_json_for` blank case + additive per-pokemon `id` / `is_mine` / `level` fields.
29. `MapRedesignTest`: `.map-r4` wrapper + timeline + dashboard + pixeldex controllers attached.
30. `MapRedesignTest`: always-visible legend with all 5 glyph items (caught/dead/uncaught/special/gym).
31. `MapRedesignTest`: next-uncaught route receives `.next` class + `.node-now-pin` (exactly once).
32. `MapRedesignTest`: JUMP TO NOW button is `.hidden` when every route is caught.
33–34. `MapRedesignTest`: status bar renders NEXT GYM + LEVEL CAP + CURRENT SEG; em-dash fallback when 8 gyms earned.
35. `MapRedesignTest`: sheet renders `emptyState` + `groupList` + `sheetForm` targets (with one species input per Soul Link player).
36. `MapRedesignTest`: `data-groups` carries a 2-element JSON array when 2 groups exist on the same location (dupes-clause).
37. `MapRedesignTest`: read-only mode hides `sheetForm` + `+ LOG GROUP`.
38. `MapRedesignTest`: special-encounters bar renders 4 cells (gift / egg / trade / other) all wired to `click->timeline#selectLocation`.
39. `MapRedesignTest`: accordion frame renders one details element per progression segment, with exactly one `[open]` attribute on the segment containing the next-uncaught route; each `.acc-row` carries the click chain.
40. `MapRedesignTest`: pokemon + mark-dead modal partials are rendered on `/map` (`data-pixeldex-target="pokemonModal"`, `data-dashboard-target="markDeadModal"`, `aria-labelledby` matches partial's `<span id>`).
41. `MapRedesignTest`: every timeline node carries `data-action="click->timeline#selectLocation"`.
42. `ResponsiveGridsTest`: `.map-r4` namespace declared outside any media block.
43. `ResponsiveGridsTest`: 720px breakpoint hides `.map-r4 .timeline-frame` + shows `.map-r4 .accordion-frame` + collapses `.map-r4 .layout` to single column.
44. `ResponsiveGridsTest`: 520px breakpoint reflows `.map-r4 .special-grid` to `repeat(2, 1fr)`.
45. `ResponsiveGridsTest`: 520/720/900px breakpoints do NOT collapse `.map-r4 .node`, `.map-r4 .sheet`, `.map-r4 .acc-row` (display: none guard).

**Backward-compat invariants exercised:**
- `MapController#show` is unchanged. All instance variables (`@locations / @progression / @gym_info / @groups_by_location / @players / @gyms_defeated / @pokedex_species / @run`) preserved.
- `_pokemon_modal.html.erb` + `_mark_dead_modal.html.erb` partials are unchanged. They were already ARIA-wired (Step 20) and rendered on the dashboard — rendering them on `/map` reuses the same partial paths (`<%= render "dashboard/pokemon_modal" %>`).
- All existing Stimulus actions on `timeline_controller.js` (`selectLocation`, `submitCatch`, `toggleGym`, `filterSpecies`, `selectSpecies`, `closeAllDropdowns`, `handleKeydown`, `scrollToCurrentProgress`) preserved. Existing `scrollContainerTarget` + `track` + `locationNode` + form targets all preserved with same names. `panel*` family renamed to `sheet*` (deleted from view, deleted from controller, no orphan references).
- `groups_json_for(groups)` → `groups_json_for(groups, current_user_id)`: signature change is required (second arg) but ALL existing fields are retained, ADDITIVE only. Only call site is the map view, which is being rewritten in this step.
- `MapHelper#location_status` / `primary_group` / `timeline_node_size` public API unchanged. Tests added for the previously-untested ones.
- The dashboard MAP tab (`_map_content.html.erb`) is unchanged — out of scope per brief (R1 reshapes the dashboard chrome).

**Diff scope:** 2 new + 6 modified files. Inside the brief's stated scope (≤7 files outside `handoff/`). Zero changes under `app/controllers/`, `app/models/`, `db/`, `app/services/`, `app/jobs/`, `config/`.

**KG closures logged:** none.

**New Known Gaps logged this step:** none. (`#route=<key>` hash JS-only contract documented inline in the controller; not a gap, an architectural choice consistent with Step 22's KG-35 SKIP non-persistence pattern.)

---

### Step 22 — R2 PC Box redesign (Phase 2 R2 of the 2026-05-04 audit) — 2026-05-04
**Status:** Shipped. **No KGs close** (Phase 2 redesigns are surface-level UX work, not backlog items). Two new KGs logged (KG-35, KG-36).

Second Phase 2 redesign per § 5 of `handoff/2026-05-04-ui-audit.md`. Four locked screens in `handoff/2026-05-04-ui-audit-mockup-pc-box.html`. Pure frontend ship — view + CSS + 2 new Stimulus controllers + 1 helper. Architect-locked decisions tracked under § Architecture Decisions.

**Architecture decisions (durable — see § Architecture Decisions):**
- **CSS namespace under `.pc-box-r2`.** Mockup uses `.box-grid` / `.box-cell` / `.sprite` selectors that already exist in pixeldex.css and are referenced from the sidebar partial. The new view wraps in `<div class="pc-box-r2">…</div>` and every new CSS rule is prefixed `.pc-box-r2 …`. Zero impact on legacy surfaces.
- **No backend changes — none.** No new column, no migration, no new endpoint, no model method. The audit's "small migration" hand-wave for `acquired_via` round-trip was explicitly out-of-scope per the prompt. LOG/EDIT route into the existing `+ NEW CATCH` modal pre-filled; SKIP is client-side dismiss only.
- **Action-chain order reversed for LOG/EDIT.** `data-action="click->dashboard#openCatchModal click->review-tray#prefillCatch"` — open first (clears + focuses) THEN prefill (populates). Reverse would have `openCatchModal`'s `this.catchSpeciesTarget.value = ""` wipe the prefill. Discovered during Bob's "Files to verify" pass; brief Constraint #5 corrected inline.
- **Catch modal is keyed by Stimulus targets, not `name=` attributes.** `prefillCatch` looks up `document.querySelector('[data-dashboard-target="catchSpecies"]')` and `[data-dashboard-target="catchLocation"]`. The modal nickname stays empty (auto-catches don't have a user-chosen nickname yet) and the `level` field doesn't exist on the modal — `level` param dropped from prefillCatch.
- **Filter chips are status-only + free-text search (mockup-locked).** Four chips: ALL / ON TEAM / STORAGE / FALLEN with `· N` counts. URL hash (`#team`, `#storage`, `#fallen`, no hash for ALL) preserves state across reloads + Turbo morph. Mockup wins over the prompt's gist that mentioned route/player filters; richer filters logged as KG-36.
- **Recommended-action highlight is computed view-side from badges.** Helper `recommended_review_action(p)` returns `:log` or `:skip`: event_gift / trade_in → `:skip`; else `:log`. View applies `class="primary"` to the matching button. First-encounter visual highlight (`.review-row.first` 3px green-glow border) keys off `first_ids_by_location` independently — and only fires when ALSO recommended `:log` (so a first-encounter trade-in row doesn't get the green border, matching mockup row 2).
- **Empty review tray uses Screen 3's dashed-border ✓ bar, not a hidden empty `<div>`.** Locked copy: `No new parsed catches to review. New saves will land here for confirmation.` Panel-head right side switches from `N TOTAL · K NEW PARSED` to `N TOTAL · ALL CAUGHT-UP`.
- **Mobile breakpoint = 520px (Step 20 contract), not the mockup's 600px prose.** Phone shell at 360px is well below 520; reflow rules apply. Inside `@media (max-width: 520px)`: 3-col grid, stacked review-row actions, single-col badge legend.
- **Type-coverage rail layout is one grid that reflows.** Outside any media block, `.pc-box-r2 .box-layout` is `grid-template-columns: minmax(0, 1fr) 280px;`. Inside `@media (max-width: 900px)`, drops to `1fr` so the rail stacks below.
- **Read-only mode gates LOG/EDIT but keeps SKIP.** `dashboard_read_only?(@run)` hides `+ NEW CATCH` (existing) AND the per-row LOG/EDIT actions (new). SKIP stays — it's client-only with no backend impact.
- **Click affordance on cells stays as today.** `data-action="click->pixeldex#selectPokemon"` opens the existing pokemon modal exactly as before. The new R2 styles add `cursor: pointer` + hover lift purely in CSS.
- **Mockup Screen 2 dim-on-non-active (Should Fix from review).** Wrapper-level `.filter-active` class toggled by Stimulus when filter ≠ ALL; CSS rule `.pc-box-r2.filter-active .filter-chip:not(.active) { opacity: 0.55; }` matches mockup's `style="opacity: 0.55"` annotation.

**Test count:** 697 → 712 (+15). 0 failures, 0 errors.

**Files (new):** 4 —
- `app/javascript/controllers/pc_box_filter_controller.js` (76 lines).
- `app/javascript/controllers/review_tray_controller.js` (38 lines).
- `test/integration/pc_box_redesign_test.rb` (167 lines, 7 tests).
- `test/helpers/pixeldex_helper_test.rb` (29 lines, 4 tests).

**Files (modified):** 5 —
- `app/views/dashboard/_pc_box_content.html.erb` (full body rewrite, 283 lines).
- `app/assets/stylesheets/pixeldex.css` (+265 lines new R2 section above the R3 marker; +12 lines extending the existing `@media (max-width: 900px)` and `@media (max-width: 520px)` blocks).
- `app/helpers/pixeldex_helper.rb` (+11 lines: `recommended_review_action(p)` helper).
- `test/integration/responsive_grids_test.rb` (+34 lines: 4 new Step 22 assertions).
- `handoff/BUILD-LOG.md` + `handoff/SESSION-CHECKPOINT.md` + `handoff/ARCHITECT-BRIEF.md` + `handoff/REVIEW-REQUEST.md` + `handoff/REVIEW-FEEDBACK.md` updated.

**Tests added (15 new):**
1. Wrapper `.pc-box-r2` + dual `data-controller` (pc-box-filter + review-tray) attached.
2. Review tray with `<h3>REVIEW PARSED CATCHES</h3>` + four-row badge legend + per-row LOG/EDIT/SKIP buttons.
3. First-encounter row's LOG button has `class="primary"`; trade-in row's SKIP button has `class="primary"`; one SKIP button per review row.
4. Four filter chips with correct `data-pc-box-filter-status-param` + counts; exactly one chip starts `.active`.
5. Unified grid renders one cell per status (team / storage / fallen), each carrying `data-status`, all preserving `pixeldex#selectPokemon` click action.
6. Type-coverage rail (`<aside class="type-coverage" data-pc-box-filter-target="rail">`) renders.
7. Empty-tray bar + `ALL CAUGHT-UP` status when `@auto_detected_catches.empty?`.
8. Read-only mode hides `+ NEW CATCH` + LOG/EDIT but keeps SKIP.
9. `responsive_grids_test.rb`: `.pc-box-r2` declared outside any media block.
10. 520px breakpoint reflows `.pc-box-r2 .box-grid` to `repeat(3, 1fr)`.
11. 900px breakpoint collapses `.pc-box-r2 .box-layout` to `grid-template-columns: 1fr`.
12. Neither breakpoint sets `display: none` on `.pc-box-r2 .box-cell` or `.pc-box-r2 .review-row`.
13. `recommended_review_action`: event_gift → `:skip`.
14. `recommended_review_action`: trade_in → `:skip`.
15. `recommended_review_action`: ordinary catch → `:log`; event_gift takes precedence over trade_in.

**Backward-compat invariants exercised:**
- The sidebar partial `_pc_box_panel.html.erb` is unchanged — cross-cutting 6 sidebar/main consolidation is out-of-scope for this step (deferred IA decision).
- All `data-group-*` attributes the existing pokemon modal needs are preserved on the new unified-grid cells (`data-group-id`, `data-group-nickname`, `data-group-species`, `data-group-location`, `data-group-status`, `data-group-types`, `data-group-pokemon`).
- The `dashboard_controller.js#openCatchModal` action signature, `_catch_modal.html.erb` partial structure, `pixeldex_controller.js#selectPokemon` flow, and the `_pokemon_modal.html.erb` partial are all untouched.
- Existing `format_move_name(id)` helper is reused for the new in-tray STATS one-liner; the legacy `<details>STATS</details>` block from Step 18 is replaced by the new `.review-row .meta .stats` row.
- `SoulLinkPokemon#broadcasts_refreshes_to ->(p) { [p.soul_link_run, :dashboard] }` continues to drive Turbo morphs on auto-catch arrival; Stimulus controllers re-instantiate on morph and `connect()` re-applies hash-based filter state, so behaviour survives broadcast refreshes.

**Diff scope:** 4 new + 5 modified files. Inside the brief's stated scope. Zero changes under `app/controllers/`, `app/models/`, `db/`, `app/services/`, `app/jobs/`, `config/`.

**KG closures logged:** none.

**New Known Gaps logged this step:** see § Known Gaps below — KG-35 (SKIP non-persistence — client-side dismiss only), KG-36 (filter chips are mockup-locked at status-only; richer filtering deferred).

---

### Step 21 — R3 Save Slots redesign (Phase 2 R3 of the 2026-05-04 audit) — 2026-05-04
**Status:** Built; awaiting Richard's review (`REVIEW-REQUEST.md` posted). **No KGs close** (Phase 2 redesigns are surface-level UX work, not backlog items). Two new KGs logged (KG-33, KG-34) per Ava's answer #3.

First Phase 2 redesign per § 5 of `handoff/2026-05-04-ui-audit.md`. Five locked screens in `handoff/2026-05-04-ui-audit-mockup-save-slots.html`. Net-additive on tokens (+3) + scoped CSS (+~245 lines), full body rewrite of two view partials, JS-controller overhaul, helper extension, +21 tests. Architect-locked decisions are tracked under `## Architecture Decisions` below.

**Architecture decisions (durable — see § Architecture Decisions):**
- **Single colour vocabulary across slots and roster (Ava answer #1).** `state-pill.saved`/`target`/`confirm` apply on BOTH slot cards (semantic: SAVED file / TARGET overwrite / CONFIRM delete) AND roster cards (semantic: READY / PENDING-or-GENERATING / FAILED). Future divergence is a separate redesign step. No parallel `.ready/.pending/.failed` class set.
- **`format_progress_phrase` rule (Ava answer #2 — locked in helper docstring).** Integer-hour truncation, no zero-pad, singular special-case for 1 minute / 1 hour. `60 → "1 minute of progress"`, `120 → "2 minutes of progress"`, `3540 → "59 minutes of progress"`, `3600 → "1 hour of progress"`, `7200 → "2 hours of progress"`, `3h59m → "3 hours of progress"`.
- **HOF pill on slot card placement (Ava answer #4).** After the body rows, before `.slot-actions`. Mockup doesn't depict slot-card HOF, but the audit says "keep functionality, restyle only" — bottom-of-body is the next-best read since the slot card has no head HOF slot.
- **Inline confirm replaces Step 20 modal for save-slot DELETE + CLEAR ALL SLOTS only.** Other Step 20 consumers (END RUN, group DEL, schedule cancel) keep using the shared `_confirm_modal.html.erb` partial untouched. The inline pattern is mockup-locked for the slot column; the shared partial is correct elsewhere.
- **Whole-slot click target replaces the per-slot overlay button in overwrite-pending mode.** The slot wrapper picks up `data-action="click->save-slots#overwriteSlot"` only while in TARGET mode (controller-applied). The amber `.overwrite-target` border + amber `TARGET` pill carry the affordance. The sticky `.pending-banner` is the announcement; the click is the consent.
- **`window.confirm` removed from `overwriteSlot`.** Last native confirm in the file. Banner + amber border + visible TARGET pill is the announcement; clicking a slot is the explicit consent. Step 20 already removed the native confirm from DELETE.
- **Roster-card YOU markers: `.you` class on the wrapper + `.you-badge` span inside `.roster-card-name`.** The `roster_you_marker_controller.js` lifecycle is unchanged; only the selector and class names move. CSS owns the amber 4px border via `.roster-card.you`.
- **TID conflict partner-name lookup is inline N+1 by design (Ava OK'd).** `s.soul_link_run.tid_conflict_groups` returns session ids; the partial maps each partner id → `SoulLinkEmulatorSession.find_by(id:)` → `discord_user_id` → `SoulLink::GameState.player_name(...)`. Max 3 lookups per render, only fires on the conflict path. Broadcast partial has no preload context; the trade-off is acceptable. If `tid_conflict_groups` matches but no usable partner labels surface, falls back to `⚠ TID CONFLICT · re-roll the seed`.
- **Click-to-copy seed via a thin new Stimulus controller (`roster_seed_controller.js`).** ~25 lines. Reads `event.target.textContent`, strips the `Seed: ` prefix, writes to `navigator.clipboard.writeText`, swaps the element to `Copied!` for 1s. CSS owns the hover hint via `.roster-card .seed:hover::after`. Falls back to `window.alert("Could not copy seed — copy it manually.")` on browsers without secure-context clipboard access.
- **Three new design tokens; no others.** `--d0: #0a1a0a` (slot bezel + action button bg + seed monospace bg), `--green-glow: #5fd45f` (ACTIVE pill bg + 4px active-slot border), `--crimson: #c75a5a` (CONFIRM pill + DELETE FOREVER bg + inline-confirm border). Mockup verbatim. The audit explicitly forbade more.

**Test count:** 676 → 697 (+21). 0 failures, 0 errors.

**Files (new):** 1 — `app/javascript/controllers/roster_seed_controller.js`.

**Files (modified):** 7 —
- `app/assets/stylesheets/pixeldex.css` (+~245 lines: 3 tokens in `:root` + new `/* ── R3 Save Slots ── */` section above the `RESPONSIVE` block).
- `app/views/emulator/_save_slots_sidebar.html.erb` (full body rewrite per mockup; outer `data-controller="save-slots"` wrapper preserved).
- `app/views/emulator/_run_sidebar_card.html.erb` (full body rewrite; `s`-only locals contract preserved per Step-9 lock).
- `app/javascript/controllers/save_slots_controller.js` (new targets / new actions / removed `overwriteOverlay` target / removed `window.confirm` / `_actionButtons()` selector retargeted).
- `app/javascript/controllers/roster_you_marker_controller.js` (`gb-card--current-user` → `you`; badge moves into `.roster-card-name` span; inline `style.cssText` dropped).
- `app/helpers/emulator_helper.rb` (new `format_progress_phrase(seconds)` with locked-rule docstring).
- `test/helpers/emulator_helper_test.rb`, `test/integration/responsive_grids_test.rb`, `test/controllers/emulator_controller_test.rb`, `test/models/soul_link_emulator_save_slot_test.rb` (extended; +21 tests).

**Tests added (the 12 buckets in the brief, plus singular minute/hour pinning):**
1. State pills always render (extended `show renders ACTIVE badge…`): asserts `>SAVED<`, `>EMPTY<`, `>ACTIVE<` all in the same render with one filled active + one filled saved + 3 empty.
2. Empty-slot CTA copy: `drop a save here from the emulator` regex on `response.body`.
3. Inline DELETE confirm markup: `data-action="click->save-slots#confirmDelete"` on the trigger (literal `>` because hand-written ERB attributes aren't auto-escaped); `class="confirm-inline" hidden` block in body; `DELETE FOREVER` substring.
4. CLEAR ALL SLOTS inline confirm: `data-action="click->save-slots#confirmClearAll"` on the trigger + `data-save-slots-target="clearAllConfirm"` on the inline block.
5. No `confirm_modal` for save-slot DELETE or CLEAR ALL SLOTS: `assert_no_match` for `id="delete-slot-N-confirm"` (1..5) and `id="clear-all-slots-confirm"`.
6. No peso sign anywhere in the response body: `assert_no_match(/&#8369;/)` and `assert_no_match(/₱/)`.
7. Roster-card structure: `class="roster-card"` + 3 `class="stat"` children + `<details>` + `<summary>STATS</summary>` + `data-controller="roster-seed"`. Existing seed-presence + `data-discord-user-id` assertions preserved.
8. HOF inline pill: `class="hof-pill"` adjacent to player name (regex anchors the pill INSIDE the `.name` span).
9. TID conflict warning band: when 2 sessions share TID/SID, the partial contains `class="conflict-warning"` + `re-roll the seed`. Conflict-absent path asserts the band is missing.
10. `format_progress_phrase` matrix: `nil` / 0 / 30 / 59 / 60 / 120 / 1800 / 3540 / 3600 / 7199 / 7200 / 4h23m / 12h43m / 3h59m → all locked outputs.
11. R3 styles do NOT collapse `.slot` or `.roster-card` content inside the existing 520px or 900px breakpoints; the three new tokens are declared exactly once in `:root`.
12. `.emulator-grid` shape test: `grid-template-columns: 1fr;` outside any media block AND `280px minmax(0, 1fr) 280px;` at the 900px breakpoint.

**Pre-existing roster regression assertions updated:** the two `show roster renders parsed_trainer_name…` and `show roster shows '0 / 8' badges…` tests were checking `Badges:\s*N\s*/\s*8` (Step-16 layout). Step 21 R3 places badges inside a stat tile (`<div class="lbl">BADGES</div><div class="val">N</div>`) with no `/8` suffix — both assertions retargeted at the new shape. The `omits parsed_* lines` test similarly retargeted at the new label markers (`<span class="lbl">TRAINER</span>` etc.) instead of the old "In-game:" / "Time played:" / "Money:" prefixes that no longer render.

**Backward-compat invariants exercised:**
- `_run_sidebar_card.html.erb` still renders standalone with only `s` local — broadcast contract preserved (existing Step-9 test still passes; new structural assertions added on top).
- The page-level `data-controller="save-slots"` wrapper, `data-save-slots-slots-url-value`, `data-save-slots-csrf-value`, `data-save-slots-active-value` — unchanged.
- DOWNLOAD URL, MAKE ACTIVE PATCH path, DELETE DELETE path — all unchanged. Only the markup + the gate that fires before DELETE/CLEAR-ALL changed.
- Step 20 `_confirm_modal.html.erb` partial / helper / Stimulus controller — untouched. Other consumers (END RUN, group DEL, schedule cancel) still wire through it.
- HOF pill functionality preserved on the slot card (restyled to `.hof-pill` per mockup); roster card now also surfaces it inline next to the name.

**Diff scope:** 1 new JS file + 7 modified files (CSS + 2 views + 2 JS controllers + 1 helper + 4 test files extended). Inside the brief's stated scope.

**KG closures logged:** none.

**New Known Gaps logged this step:** see § Known Gaps below — KG-33 (slot card no longer shows "saved Xm ago" footer or byte count; mockup-driven, not a parser regression), KG-34 (roster card no longer shows "Active … ago" or "Save: bytes"; same shape).

---

### Step 20 — Phase 1 cross-cutting safety nets (post-audit) — 2026-05-04
**Status:** Shipped at `fbd51af`. **No KGs close** (the audit's Phase 1 was net-additive infrastructure, not a backlog item). Reviewed by Richard: 0 Must Fix, 0 Should Fix, 2 Nice-to-Have (unused `window.__confirmModals` registry + unreachable cancel-target fallback in `confirm_modal_controller.js`, both intentional defense-in-depth, accepted as-is).

Five buckets per § 5 of `handoff/2026-05-04-ui-audit.md`, all bundled to pay one review tax and unblock the Phase 2 redesigns. The five (A → E → D → B → C build order to keep diffs reviewable):

- **Bucket A — `gb-grid-N` 520px media query.** New `@media (max-width: 520px) { .gb-grid-3 { grid-template-columns: 1fr; } .gb-grid-4 { grid-template-columns: 1fr; } }` block in `pixeldex.css:1061-1064`, immediately after the existing 900px breakpoint. `gb-grid-2` intentionally untouched. Cascades to runs/index, dashboard runs tab, teams/index, gym_ready, map (special encounters), and gym_schedules show.

- **Bucket B — Shared confirm-modal partial + helper + Stimulus controller.** New `app/views/shared/_confirm_modal.html.erb` (mirrors `_mark_dead_modal.html.erb` shape; takes `id` / `title` / `body` / `confirm_label` / `confirm_class` / `confirm_data` / `cancel_label`), new `ConfirmModalHelper#confirm_modal` helper, new `confirm_modal_controller.js` Stimulus controller (per-modal instance, registers in `window.__confirmModals[id]`, `open` reveals + saves prior focus + traps Tab, `close` restores focus). Wired into all 6 destructive trigger sites: dashboard END RUN (`end-run-dashboard-confirm`), /runs END RUN (`end-run-page-confirm`), save-slot DELETE (`delete-slot-#{n}-confirm`), CLEAR ALL SLOTS (`clear-all-slots-confirm`), group DEL (`delete-group-#{group.id}-confirm`), schedule Cancel (`cancel-schedule-confirm`). Each trigger swaps from a direct action to `confirm-modal#open`; the original Stimulus action moves into the modal's confirm button via `confirm_data: { action: "..." }`. Side-cleanups: removed redundant native `window.confirm()` calls from 4 JS controllers (save_slots, clear_save, run_management endRun only, gym_schedule); updated `save_slots_controller.js#_actionButtons()` selector to match the new `[data-confirm-modal-id-param^='delete-slot-']` triggers so overwrite-pending mode still disables them; reworked `species_assignment_controller.js#deleteGroup` to read `groupId` from the confirm-button dataset directly (with closest-fallback for legacy callers).

- **Bucket C — ARIA + focus trap on every existing modal.** New `modal_a11y_controller.js` (sibling Stimulus controller; `#findWrapper()` walks parents looking for `.hidden` or `position: fixed`; MutationObserver on the wrapper's `class` attribute drives open/close transitions; on open saves prior focus, focuses first focusable, attaches Tab-trap; on close restores). Applied `role="dialog" aria-modal="true" aria-labelledby="<id>-title" data-controller="modal-a11y"` to: `_catch_modal`, `_pokemon_modal`, `_mark_dead_modal`, `_reset_draft_modal`, `_quick_calc_modal`, and the inline group modal in `species_assignments/show.html.erb`. Coin-flip modal in `gym_drafts/show.html.erb` got ARIA only (no close button, auto-dismisses post-animation, focus trap on a 1-2s coin animation would be active friction). Bundle-in: `pixeldex.html.erb:28` got `data-controller="escape-close"` to match `application.html.erb` — pre-Step-20 the dashboard modals had no global ESC handler.

- **Bucket D — Gym-schedule Cancel: proposer-only + channel authz.** Two-layer fix. View-side: `gym_schedules/show.html.erb:64` wraps the cancel button + accompanying confirm-modal partial in `<% if @schedule.proposed_by == current_user_id %>`. Channel-side: `gym_schedule_channel.rb#cancel(_data)` early-returns with `transmit({ error: "Only the proposer can cancel this schedule." })` when `current_user_id != @schedule.proposed_by`. Same `transmit({ error: })` shape as the existing `rsvp` rescue path. Per-action call: server-enforce when ownership is unambiguous; KG-28's UI-hide-only contract still applies to read-only mode.

- **Bucket E — `<NEXT` literal cleanup.** `_gyms_content.html.erb:52` replaced `&lt;NEXT` with a styled `type-text` badge: `<span class="type-text" style="border-color: var(--amber); color: var(--amber); margin-left: 4px;">NEXT</span>`. Reuses the existing badge styling, visually consistent with the type-abbreviation badge on the same row.

**Architecture decisions (durable — see § Architecture Decisions):**
- **Shared confirm-modal lookup is via per-instance `idValue` matching, not via global registry.** Every connected `confirm-modal` controller receives the click event when a trigger fires `click->confirm-modal#open`; the `open()` action checks `if (event.params?.id !== this.idValue) return` to filter. The `window.__confirmModals[id] = element` registry IS populated in `connect()` for future programmatic access but is currently dead code (KG-32). Locked over Stimulus outlets because outlets require the trigger element to declare its outlet target, and in this design the trigger lives in completely different DOM contexts from the modals.
- **Per-modal partial render, not a single shared modal element.** Every wire site renders its own `_confirm_modal.html.erb` partial inline (e.g. inside the slot card, inside the group card, etc.) with a unique `id`. The cost is DOM bloat (each modal is a hidden `<div>`) but the win is no cross-controller state plumbing — each modal's confirm button carries its own original action.
- **`modal_a11y_controller.js` discovers the wrapper via parent-walk, not via outlet.** The Stimulus controller is attached to the inner `gb-modal` element (so screen readers see `role="dialog"` on the right element); but the `.hidden` class lives on an outer `position: fixed` wrapper several levels up. `#findWrapper()` walks `parentElement` looking for either `.hidden` or `position: fixed` inline style. Heuristic, but covers every modal in the codebase.
- **Coin-flip modal is ARIA-only.** Architect-locked decision in the brief, confirmed by Richard. No close button + 1-2s animation + auto-dismiss = focus trap is friction, not help. `aria-modal="true"` + the `role="dialog"` announcement is enough for screen-reader users.
- **The shared partial body accepts safe HTML via `raw(body)`.** Trusted call sites only — none of the six wire sites pass user input into the body string. The schedule's `scheduled_at.strftime` value is the only dynamic content in any body, and `strftime` output is safe.

**Test count:** 654 → 676 (+22). 2011 → 2095 assertions, 0 failures, 0 errors.

**Files (new):** 9 — `app/helpers/confirm_modal_helper.rb`, `app/javascript/controllers/confirm_modal_controller.js`, `app/javascript/controllers/modal_a11y_controller.js`, `app/views/shared/_confirm_modal.html.erb`, `test/channels/gym_schedule_channel_test.rb`, `test/factories/gym_schedules.rb`, `test/helpers/confirm_modal_helper_test.rb`, `test/integration/confirm_modal_flow_test.rb`, `test/integration/responsive_grids_test.rb`.

**Files (modified):** 22 — `app/assets/stylesheets/pixeldex.css`, `app/channels/gym_schedule_channel.rb`, `app/javascript/controllers/clear_save_controller.js`, `app/javascript/controllers/gym_schedule_controller.js`, `app/javascript/controllers/run_management_controller.js`, `app/javascript/controllers/save_slots_controller.js`, `app/javascript/controllers/species_assignment_controller.js`, `app/views/dashboard/_catch_modal.html.erb`, `app/views/dashboard/_gyms_content.html.erb`, `app/views/dashboard/_mark_dead_modal.html.erb`, `app/views/dashboard/_pokemon_modal.html.erb`, `app/views/dashboard/_reset_draft_modal.html.erb`, `app/views/dashboard/_runs_content.html.erb`, `app/views/emulator/_save_slots_sidebar.html.erb`, `app/views/gym_drafts/show.html.erb`, `app/views/gym_schedules/show.html.erb`, `app/views/layouts/pixeldex.html.erb`, `app/views/runs/index.html.erb`, `app/views/species_assignments/_group_card.html.erb`, `app/views/species_assignments/show.html.erb`, `app/views/teams/_quick_calc_modal.html.erb`, plus the three handoff/* files.

### Step 19 — Move-name lookup + Discord notifier + Wipe check — 2026-05-04
**Status:** Shipped at `435a1c9`. **KG-17 and KG-24 close.** Reviewed by Richard: 0 Must Fix, 0 Should Fix, 2 Nice-to-Have (rescue list redundancy + view-var inconsistency, both noted as-is). 1 Note escalated and folded in (map-view NEW CATCH form gating).

Three orthogonal "events get observed and surfaced" features bundled into one step. The move-name lookup mirrors the species (KG-20) and met-location (KG-12) lookup pattern. The Discord notifier follows the Step-15 fan-out architecture — coordinators do model state, the notifier does Discord, separation enforced by treating the notifier as a fire-and-forget side effect at the END of each coordinator/controller branch. The wipe coordinator is the third Step-15-style coordinator (alongside `GymBeatenCoordinator`, `HallOfFameCoordinator`, etc.) but is invoked from the controller path (Mark Dead) rather than from `SaveDiffDispatcher` — wipes only fire on manual death transitions in this step (auto-detection of dead Pokemon is logged as KG-29).

**Architecture decisions (durable — see § Architecture Decisions):**
- **Discord notifier is a NEW service, NOT a touch of `discord_bot.rb`.** Project review flagged the 978-LOC `discord_bot.rb` god-object; brief explicitly forbade adding load. New `SoulLink::DiscordNotifier` uses `Discordrb::API::Channel.create_message(token, channel_id, content)` directly — same pattern as `DiscordApi.create_run_channels`. Class-only, six fire-and-forget methods. Full rescue chain (`RestClient::ExceptionWithResponse, RestClient::Exception, SocketError, Errno::*, JSON::ParserError, StandardError`) → `Rails.logger.warn` and return; never raises. Underlying coordinator/controller transactions always commit even when Discord is down.
- **Notifier API surface (six public methods).** `notify_catch(run, uid, species, route, level, off_feed:)`, `notify_death(run, uid, species, route)`, `notify_gym_player_progress(run, gym_number, uid)`, `notify_gym_team_beaten(run, gym_number)`, `notify_wipe(run, uid, route)`, `notify_run_complete(run)`. Each method silently no-ops on nil run / nil channel-id / blank token. Routing: catches → `catches_channel_id`, deaths → `deaths_channel_id`, gym/wipe/HoF → `general_channel_id`.
- **Notifier invocation points (architect-locked).** `CatchCoordinator.create_pokemon_row` (party + box paths, after `create!`, inside the slot transaction). `GymBeatenCoordinator.process` (per-player BEFORE `attempt_auto_mark`, team AFTER if `!was_marked && now_marked` — captures the precondition cleanly). `HallOfFameCoordinator.process` (after `update!(completed_at:)` actually fires; idempotency guarded by existing `completed_at.present?` early return). `PokemonGroupsController#update` (notify_death per linked Pokemon after `mark_as_dead!`, then `WipeCoordinator.process(run)`). `GymProgressController#update` (manual MARK BEATEN = team event by definition; UNMARK fires nothing).
- **`WipeCoordinator` idempotency = outer guard + inner double-check inside `with_lock`.** Outer: `return if run.wiped_at.present?` — fast path for already-wiped runs. Inner: same check inside `run.with_lock { }` — handles two concurrent Mark Dead requests racing. Ruby `do/end` block `return` exits the enclosing method, so the post-lock notifier call is unreachable on the idempotent path. Brand-new-run false-positive prevented by `next unless run.soul_link_pokemon.where(discord_user_id: uid).exists?` — players who haven't caught anything aren't candidates for wiping.
- **HoF wins over wipe in the read-only check.** `SoulLinkRun#read_only? = wiped_at.present? && !completed?`. If both `wiped_at` and `completed_at` are set (defense-in-depth — shouldn't normally happen), `completed?` returns true and `read_only?` returns false — the COMPLETE pill renders, the wipe banner is suppressed, affordances stay visible. Brief edge-case decision.
- **Wipe is reversible via direct AR ONLY.** `run.update!(wiped_at: nil)` is the un-wipe path. No UI for it in this step (mirrors HoF's un-completion path — KG-19). Logged as KG-27.
- **Read-only mode = UI hide-only in v1.** Server-side authz on the affected endpoints is NOT added in Step 19. The buttons hide; if a determined user crafts a request directly, it still goes through. Locked as the v1 contract; server enforcement is logged as KG-28.
- **`broadcast_state` extended with `wiped_at` (forward-looking).** No current JS consumer reads it; the wipe banner is server-rendered via the existing `broadcasts_refreshes_to ->(record) { [ record, :dashboard ] }` Turbo refresh on `SoulLinkRun`. Adds payload bytes per broadcast but unblocks future client-side wipe-state UI without changing the model later.

**Citations:**
- **Move-name source**: PKHeX `PKHeX.Core/Resources/text/other/en/text_Moves_en.txt` lines 2..468 = move IDs 1..467 (line 1 of the source file is the `———` no-move sentinel; brief specified IDs 1..467 explicitly so `move_id == 0` never appears). Cross-checked against pret/pokeplatinum `include/constants/moves.h` — last Platinum move is `MOVE_SHADOW_FORCE = 467`. Header citation at `config/soul_link/move_names.yml`.
- **Discordrb token shape**: `"Bot #{Rails.application.credentials.discord[:token]}"` — same pattern as `app/services/soul_link/discord_api.rb:8`. The bot uses the bot-token authority for outgoing messages; webhook URLs are not used.
- **Soul Link wipe convention**: Project Owner — "If we get all our mons killed in a battle, the run is over." Translated to coordinator logic: any single player has 0 alive Pokemon AND has caught at least one ⇒ wipe.

**Test count:** 596 → 654 (+58). 1906 → 2011 assertions, 0 failures, 0 errors.

**Files (new):** 8 — `app/services/soul_link/discord_notifier.rb`, `app/services/soul_link/wipe_coordinator.rb`, `config/soul_link/move_names.yml`, `db/migrate/20260504000001_add_wiped_at_to_soul_link_runs.rb`, `test/integration/wipe_flow_test.rb`, `test/services/soul_link/discord_notifier_test.rb`, `test/services/soul_link/game_state_move_names_test.rb`, `test/services/soul_link/wipe_coordinator_test.rb`.

**Files (modified):** 21 — `app/controllers/gym_progress_controller.rb`, `app/controllers/pokemon_groups_controller.rb`, `app/helpers/application_helper.rb`, `app/helpers/emulator_helper.rb`, `app/models/soul_link_run.rb`, `app/services/soul_link/catch_coordinator.rb`, `app/services/soul_link/game_state.rb`, `app/services/soul_link/gym_beaten_coordinator.rb`, `app/services/soul_link/hall_of_fame_coordinator.rb`, `app/views/dashboard/_gyms_content.html.erb`, `app/views/dashboard/_pc_box_content.html.erb`, `app/views/dashboard/_pokemon_modal.html.erb`, `app/views/dashboard/_runs_content.html.erb`, `app/views/map/show.html.erb`, `db/schema.rb`, `test/controllers/gym_progress_controller_test.rb`, `test/models/soul_link_run_test.rb`, `test/services/soul_link/catch_coordinator_test.rb`, `test/services/soul_link/gym_beaten_coordinator_test.rb`, `test/services/soul_link/hall_of_fame_coordinator_test.rb`, plus the three handoff/* files.

### Step 18 — Per-Pokémon stats (Nature/IVs/EVs/moves) + PC box parsing — 2026-05-03
**Status:** Shipped at `132fb34`. **KG-21 closes** (PC box parsing now in production; storage block at partition offset `0xCF2C`, size `0x121E4`, box data at `+4`, 18 boxes × 30 slots × 136-byte records). Reviewed by Richard: 1 Must Fix (storage CRC range — fixed inline) + 1 Nice-to-Have (PP rendering label — fixed inline). Two Should Fixes accepted as-is (no real-SRAM smoke test, `caught_off_feed: false` for Step-17 rows is correct semantic).

Extends Step 17's `PkmDecoder` + `PartyParser` foundation with the four per-Pokémon detail fields (Nature, IVs, EVs, moveset) the Soul Link UX needs and adds a sibling `BoxParser` so catches that arrive via box-only diff (caught + deposited between snapshots) surface alongside party catches. The decryption algorithm is unchanged from Step 17 — only new field offsets within the existing 128-byte unshuffled payload.

**Architecture decisions (durable — see § Architecture Decisions):**
- **Eager-decode the new fields, not lazy.** Brief floated lazy decryption (decode on first access); rejected. Decryption cost is fixed-per-record, structs are small, eager is simpler and matches the existing `Pkm` shape. New fields populate during `decrypt`.
- **`Pkm` Struct extended in place.** New keyword fields appended at the end (`nature`, `ivs`, `evs`, `moves`) so Step-17 positional-access callers stay stable. Test locks the declaration order with an explicit member-name assertion.
- **`BoxParser` is a sibling layer to `PartyParser`, not a refactor.** Same pure-function shape, never raises, returns `Array<Pkm>` (size 0..540) or `[]` on any error. Re-uses `PkmDecoder.decrypt` per-record (decoder already accepts the 136-byte box record size — box-only records have `level: nil` because level lives in the party-stats block).
- **Storage block has its own active-block picker.** Storage block can swap partitions independently from the general block (per PKHeX `StorageBlockPosition`). `BoxParser.pick_active_storage_block` reads each partition's storage block, CRC-validates each, picks higher save_counter — does NOT delegate to or assume parity with `PartyParser`'s general-block picker.
- **`BoxedPokemonObservedEvent` is a distinct event class, not a subtype of `PokemonCaughtEvent`.** Distinction surfaces via `caught_off_feed: true` on the row + an OFF-FEED pill in the UI. Same field shape (PID + species + met-location + level + OT + is_egg). No `BoxedPokemonRemovedEvent` — boxes hold Pokémon long-term and "removed from box" isn't a meaningful Soul Link event.
- **Cross-event PID dedup: party events first, box events second, single transaction.** `CatchCoordinator.process` processes catch_events + removal_events + box_events in that order within a single `slot.transaction { }`. The existing `(soul_link_run_id, discord_user_id, pid)` `.exists?` check no-ops the box-side create when a party-side row already exists for the same PID — net: a single catch produces exactly one row regardless of arrival path. Locked by `catch_coordinator_test.rb` "same-snapshot dual-fire" test.
- **Move-name lookup is OUT.** Numeric "Move #N" fallback for v1 — adding all 467 Gen IV moves would be scope creep. Logged as KG-24.

**Citations (KG-21 closure + new field offsets):**
- **Storage block layout (KG-21)**: PKHeX `PKHeX.Core/Saves/SAV4Pt.cs` declares `private const int GeneralSize = 0xCF2C; private const int StorageSize = 0x121E4; // Start 0xCF2C, +4 starts box data`. Storage block CRC body excludes the 20-byte footer per PKHeX `SAV4.cs:113` (`Checksums.CRC16_CCITT(data[..^FooterSize])`) + `SAV4Sinnoh.cs:12` (`FooterSize => 0x14`). Cited inline at `app/services/soul_link/box_parser.rb:21-22, 73-79`.
- **PKM field offsets** (PKHeX `PK4.cs`): EV_HP at 0x18 → unshuffled 0x10 (Block A +0x10); Move1 at 0x28 → unshuffled 0x20 (Block B +0x00); Move1_PP at 0x30 → unshuffled 0x28; Move1_PPUps at 0x34 → unshuffled 0x2C; IV32 at 0x38 → unshuffled 0x30 (Block B +0x10, dword) — already used by Step 17 for egg-bit extraction; Step 18 reuses for IV unpack. Inline citations at `app/services/soul_link/pkm_decoder.rb:113-127`.
- **IV bit packing**: pret/pokeplatinum `include/struct_defs/pokemon.h` order is `hpIV / atkIV / defIV / speedIV / spAtkIV / spDefIV` — shifts (HP=0, ATK=5, DEF=10, SPE=15, SPA=20, SPD=25), 5 bits each, low 30 bits of the IV dword (bit 30 = isEgg, bit 31 = isNicknamed).
- **Nature table**: PKHeX `Nature.cs` 25-entry enum (Hardy=0..Quirky=24). Inline at `app/services/soul_link/natures.rb:11-15`.

**Migrations (2):**
- `db/migrate/20260503184057_add_step_18_columns_to_soul_link_pokemon.rb` — adds `ivs json` (nullable), `evs json` (nullable), `moves json` (nullable), `caught_off_feed boolean default false null false`. The `nature` column already exists from earlier legacy work — NOT re-added.
- `db/migrate/20260503184058_add_parsed_box_data_to_soul_link_emulator_save_slots.rb` — adds `parsed_box_data json` (nullable). Same shape as `parsed_party_data` from Step 17.

**Files created (6):**
- `app/services/soul_link/box_parser.rb` — Layer A walker for the PC box (~190 lines incl. citation header). Pure, never raises. Picks active storage block per-partition (independent of general block), reads CRC-protected body excluding 20-byte footer (matching PKHeX `data[..^FooterSize]`), iterates 18 × 30 = 540 slots calling PkmDecoder per record, filters nils + eggs + species==0.
- `app/services/soul_link/natures.rb` — 25-element frozen array of Gen-IV nature names + `Natures.name(id)` lookup with `"Nature ##{id}"` fallback for out-of-range. Cites PKHeX `Nature.cs` + pret enum order.
- `db/migrate/20260503184057_add_step_18_columns_to_soul_link_pokemon.rb`
- `db/migrate/20260503184058_add_parsed_box_data_to_soul_link_emulator_save_slots.rb`
- `test/services/soul_link/box_parser_test.rb` — 14 tests (empty box, single record, full 30-slot box, multi-box walk, egg filter, corrupt-record isolation, both-CRC-bad → `[]`, one-CRC-bad → use good, higher-counter wins, wrong bytesize, nil/non-String input, all-zero SRAM, source discipline).
- `test/services/soul_link/natures_test.rb` — round-trip lookup tests (PID 0 → Hardy, PID 0xFFFFFFFF → Calm, out-of-range fallback, table size = 25).

**Files modified (11):**
- `app/services/soul_link/pkm_decoder.rb` — `Pkm` Struct extended with `:nature, :ivs, :evs, :moves` (appended after Step-17 fields). New unshuffled offset constants + extractors for nature (PID % 25), IVs (4-byte dword unpacked into 6-key Hash), EVs (6 bytes at unshuffled 0x10..0x15 unpacked into Hash), moves (4 × u16 IDs at 0x20..0x27 + 4 × u8 PP at 0x28..0x2B + 4 × u8 PP-up at 0x2C..0x2F unpacked into Array of `{id:, pp:, pp_up:}` Hashes). Citation comments cite PKHeX `PK4.cs` accessors.
- `app/services/soul_link/save_diff.rb` — `BoxedPokemonObservedEvent` Struct, `box_events:` keyword field on `Result` (default `[]`) + `Result#empty?` extension, `prev_box:` / `curr_box:` keyword args on `between(...)`, `diff_box(prev, curr)` helper mirroring `diff_party` shape (PID-keyed set difference; defensive nil-guard returns `[]`). `PokemonCaughtEvent` Struct extended with `:nature, :ivs, :evs, :moves` keyword fields populated from the entry hash.
- `app/services/soul_link/save_diff_dispatcher.rb` — passes `prev[:box_data]` / `curr[:box_data]` into `SaveDiff.between` as `prev_box:` / `curr_box:`. Combined fan-out: `CatchCoordinator.process(slot, catch_events + removal_events + box_events)` when any are non-empty.
- `app/services/soul_link/catch_coordinator.rb` — new `when SoulLink::SaveDiff::BoxedPokemonObservedEvent` branch dispatches to `handle_box_observed`. New method mirrors `handle_caught` exactly except sets `caught_off_feed: true` on the create. `handle_caught` extended with explicit `caught_off_feed: false` (column is NOT NULL).
- `app/jobs/soul_link/parse_save_data_job.rb` — calls `SoulLink::BoxParser.parse(slot.save_data).map(&:to_h)` on success; persists JSON-serialized box data via `update_columns(parsed_box_data: ...)` (same write that already covered Step-16/17 parsed_*). Extended `capture_state` to include `:box_data => slot.parsed_box_data`. Failure path UNCHANGED — KG-13 invariant: only stamps `parsed_at`. New parse-failure test stubs `BoxParser.parse` to flunk if called, asserting it never runs on the failure path.
- `app/views/dashboard/_pc_box_content.html.erb` — added OFF-FEED pill alongside 1ST / TRADE-IN / EVENT (renders only when `caught_off_feed: true`). Below `box-cell-loc`, added a `<details><summary>STATS</summary>` collapsible block showing Nature, IVs, EVs, and Moves — guarded by `.present?` so Step-17 rows (all-nil for the new fields) collapse the entire `<details>` block. PP rendering uses `PP X · ↑Y` (PP value · PP-Ups consumed) per Richard's Nice-to-Have to disambiguate from a denominator.
- `db/schema.rb` — auto-updated by migrations.
- `test/services/soul_link/pkm_decoder_test.rb` — extended with Nature/IVs/EVs/moves round-trip tests (PID 0 → 0/Hardy, PID 0xFFFFFFFF → 20/Calm, all-31s IV dword `0x3FFFFFFF`, known EVs round-trip, 4-move round-trip with PP + PP-up). Member-name assertion locks Pkm Struct field order.
- `test/services/soul_link/save_diff_test.rb` — extended with box-diff tests (empty/empty, new-PID-in-curr, stable PID, prev-only PID, nil-prev, nil-curr, string-keyed entries, PokemonCaughtEvent carries nature/ivs/evs/moves through).
- `test/services/soul_link/save_diff_dispatcher_test.rb` — extended `with_stubbed_coordinators` for box wiring; new tests for box-event fan-out, baseline rule for box, single combined CatchCoordinator call.
- `test/services/soul_link/catch_coordinator_test.rb` — extended with box-observed event tests (new PID → row created, `caught_off_feed: true`; existing-PID → no-op; same-snapshot dual-fire → exactly one row, `caught_off_feed: false`; event-met / trade-in precedence preserved on box path).
- `test/jobs/soul_link/parse_save_data_job_test.rb` — extended with box-parse persistence test, parse-failure preserves `parsed_box_data`, BoxParser stubbed to flunk on failure path, pre-Step-18 `parsed_party_data` legacy-row roundtrip (no exceptions, no spurious events).

**Tests:** 547 → 596 (+49). 0 failures, 0 errors. 1737 → 1906 assertions (+169).
**Lint:** `bundle exec rubocop` clean (184 files, 0 offenses; +6 from Step 17's 178 — 2 services + 2 migrations + 2 new test files).
**Brakeman:** Clean (no new warnings; pre-existing weak-confidence File Access warnings unchanged).

**Backward-compat invariants exercised:**
- Step-17 `Pkm` callers (positional-access) keep working — new fields appended at the end of the Struct declaration, never inserted in the middle. Member-name assertion in `pkm_decoder_test.rb` locks the order.
- Pre-Step-18 `parsed_party_data` JSON (no `nature/ivs/evs/moves` keys) runs through `SaveDiff.between` cleanly — `hash_get` returns nil for absent keys; `PokemonCaughtEvent` Struct's keyword args default to nil. Test exercises the legacy-row path explicitly.
- The view's `<details>` block collapses cleanly when all four new fields are nil — Step-17 rows render exactly as they did at `eefcbbe`.
- All existing Step-15/16/17 tests pass UNCHANGED — Bob extended each test file by appending new tests, no rewrites.
- KG-13 invariant preserved — `ParseSaveDataJob` failure path stamps ONLY `parsed_at`. `parsed_box_data` is preserved across CRC-failed saves; BoxParser is stubbed to flunk if called on the failure path.

**Walks (the same shape Step 15/16/17 used):**
- **PkmDecoder walk (extended):** Step 17's existing decrypt + unshuffle + checksum-verify path. After unshuffle: extract Nature from `pid % 25`; extract IVs by unpacking the IV dword's low 30 bits as 6 × 5-bit values; extract EVs as 6 bytes at unshuffled `0x10..0x15`; extract Moves as 4 × u16 + 4 × u8 + 4 × u8. All extractors fall back to a sentinel structure (Hash with zeros / Array of zero-id moves) on slice failure rather than nil — keeps the view's `.present? / .is_a?(Hash)` guards simple.
- **BoxParser walk:** Validate full 0x80000-byte SRAM input, pick active storage block (read save_counter from each partition's storage footer at `STORAGE_FOOTER_OFFSET = 0x121D0`, CRC-verify each over `[0..STORAGE_FOOTER_OFFSET)` per PKHeX `data[..^FooterSize]`, take higher-counter valid block — returns nil if both partitions fail), iterate 540 slots from `STORAGE_OFFSET + 4` slicing 136 bytes per record, call PkmDecoder per record, filter nils + eggs + species==0. Top-level `rescue StandardError → []`.
- **CatchCoordinator walk (extended):** Step 17's transaction + early-return + dispatch-by-event-class shape. Box branch mirrors caught branch exactly except sets `caught_off_feed: true` and `caught_off_feed: false` on the catch branch (column is NOT NULL). PID dedup `.exists?` check fires for both branches. Same-snapshot dual-fire creates exactly one row (party processed first → row inserted in the open transaction → SELECT visible to subsequent INSERT attempt → dedup no-ops the box create).

**Diff scope:** 2 migrations + 2 new services + 1 modified decoder + 1 modified diff + 1 modified dispatcher + 1 modified coordinator + 1 modified job + 1 modified view + 2 new test files + 4 extended test files. Inside the brief's stated diff scope.

**KG closures logged:** KG-21 closes (PC box parsing).

**New Known Gaps logged this step:** see § Known Gaps below — KG-24 (no Move ID → Move name lookup; renders "Move #N"), KG-25 (no real-SRAM smoke test for `BoxParser` + extended `PkmDecoder` field reads — synthetic test builder uses the same constants the production code does, so a regression of the storage-CRC fix would be caught only by a real-save audit).

---

### Step 17 — PkmDecoder + PartyParser + catches+routes — 2026-05-03
**Status:** Built; awaiting Richard's review. **KG-11 closes** (party block offset `0xA0` pinned to PKHeX `SAV4Pt.cs` `GetSAVOffsets()`). **KG-12 closes** (Platinum met-location enum sourced from PKHeX `text_hgss_00000_en.txt` + special IDs from `Locations.cs`).

Ships category 3 of the SRAM auto-tracking audit (catches + routes) on top of the new Gen-IV PKM decryption infrastructure. The infrastructure is split into two pure-function layers (`PkmDecoder` + `PartyParser`) that mirror `SaveParser`'s shape and contract — both never raise, return nil/[] on any failure, no AR, no I/O. Step 18 (Nature/IVs/EVs/movesets) and category 2 (gym battle teams) reuse the same Layer-A infrastructure with no changes — they just add fields to the `Pkm` Struct.

**Architecture decisions (durable — see § Architecture Decisions):**
- **Two new pure-function layers (Layer A).** `SoulLink::PkmDecoder` decrypts a single 236-byte PKM record (PID-shuffle + double LCG + checksum verify); `SoulLink::PartyParser` walks the SRAM party block and calls PkmDecoder per slot. Same shape as `SaveParser`: pure function, returns Struct on success / nil-or-[] on any failure, never raises, no AR, no I/O.
- **One new side-effect coordinator (Layer B).** `SoulLink::CatchCoordinator` mirrors `GymBeatenCoordinator` / `HallOfFameCoordinator`. Wraps creates in `slot.transaction { }`. Filters eggs, dedupes by PID scoped to (run, player), detects trade-ins (event TID/SID vs slot's parsed TID/SID), filters event-met-locations to `acquired_via: 'event_gift'`. PokemonRemovedEvent is log-only (mirrors `BadgeLost` no-op).
- **Three-layer dispatch unchanged.** `SaveDiff` extends with `catch_events:` + `removal_events:` keyword fields on `Result` plus `prev_party:` / `curr_party:` keyword args on `between(...)`; `SaveDiffDispatcher.dispatch` wires party data into the `between` call and fans out to `CatchCoordinator`. Backward compat: Step-15/16 callers without party kwargs keep working unchanged.
- **Egg handling (locked).** PartyParser filters eggs before return → eggs never enter `parsed_party_data` and never hit the diff. When an egg hatches, the next parse sees the now-non-egg PID as "new" → fires PokemonCaughtEvent at hatch time. Net behavior: an egg is invisible to the auto-tracker until it hatches.
- **No partner-linking.** Step-17 rows have `soul_link_pokemon_group_id: nil`. The existing manual 4-player Catch modal flow is the only path that creates groups. Step 18+ will handle pairing.
- **Dashboard surface: PC BOX tab extension only.** New "AUTO-DETECTED CATCHES" section on `_pc_box_content.html.erb`, scoped to current_user_id + the active run. First-encounter-per-route badge computed live in the view (no controller-side precomputation). Trade-in + event-gift pills.

**Citations (KG closures):**
- **KG-11 (Party block offset = 0xA0)**: PKHeX `PKHeX.Core/Saves/SAV4Pt.cs` `GetSAVOffsets()` method assigns `Party = 0xA0` alongside `Trainer1 = 0x68` and `Extra = 0x2820`. Inline at `app/services/soul_link/party_parser.rb:30-44` header comment + `PARTY_OFFSET_IN_GENERAL_BLOCK = 0xA0` constant.
- **KG-12 (Met-location enum)**: PKHeX `PKHeX.Core/Resources/text/locations/gen4/text_hgss_00000_en.txt` (235 entries, 0-indexed; entries 0-126 are Sinnoh-relevant). Special IDs from PKHeX `PKHeX.Core/Game/Locations/Locations.cs`: 2000=Daycare4, 2001=LinkTrade4NPC, 2002=LinkTrade4, 3001=Ranger4, 3002=Faraway4. Inline header comment at `config/soul_link/met_locations.yml:1-39`.
- **PKM crypto**: pret/pokeplatinum `src/pokemon.c:4861-4924` (`BoxPokemon_GetDataBlock` PID-shuffle switch, 24 unique cases plus 8 mirrored cases 24..31), `src/pokemon.c:317-349` (`Pokemon_EnterDecryptionContext` showing the two-region dual-key encryption: blocks A-D keyed by checksum, party stats keyed by PID), `src/math_util.c:217-234` + `include/math_util.h:8-9` (LCG: `LCRNG_MULTIPLIER = 1103515245 = 0x41C64E6D`, `LCRNG_INCREMENT = 24691 = 0x6073`, `seed = seed*mult + inc; ks = seed >> 16`). Cross-checked against PKHeX `PokeCrypto.Decrypt45` / `Shuffle45` / `BlockPosition` table (identical algorithm). Cited inline at `app/services/soul_link/pkm_decoder.rb:24-65` header.
- **PKM field offsets**: pret/pokeplatinum `include/struct_defs/pokemon.h:16-149` — Block A species @0x00, otID @0x04 (TID lo + SID hi); Block B IV/Egg dword @0x10 (isEgg bit 30); Block B `MetLocation_PtHGSS` @0x1E; Block D `metLevel:7` @0x1C; PartyPokemon `level` u8 at absolute record offset 0x8C (party-only block, encrypted with PID-LCG).

**Migrations (2):**
- `db/migrate/20260503160001_add_step_17_columns_to_soul_link_pokemon.rb` — adds `pid` (bigint), `met_location_id` (integer), `ot_id` (integer), `ot_sid` (integer), `trade_in` (boolean default false null false), `acquired_via` (string). Compound non-unique index `(soul_link_run_id, discord_user_id, pid)`. Additive; manual catches keep validating with pid nil.
- `db/migrate/20260503160002_add_parsed_party_data_to_soul_link_emulator_save_slots.rb` — adds `parsed_party_data` (json, nullable). Same shape as Step 16's parsed_* additions.

**Files created (8):**
- `app/services/soul_link/pkm_decoder.rb` — Layer A decryptor (~245 lines incl. citation header). Pure, never raises. PID-shuffle table inline as 32-entry constant; LCG inline; double-region decrypt (chk for blocks, PID for party stats); checksum verify; Block-A/B/D field extraction post-unshuffle.
- `app/services/soul_link/party_parser.rb` — Layer A walker (~140 lines). Reads count + 6 records from `slot_offset + 0xA0`; calls PkmDecoder per slot; filters eggs + zero-species. Same active-slot-picker logic as SaveParser (replicated, not delegated, to keep the parsers loosely coupled).
- `app/services/soul_link/catch_coordinator.rb` — Layer B coordinator (~190 lines). `process(slot, events)` symmetric to `GymBeatenCoordinator`; transaction-wrapped creates; PID dedup; trade-in detection; event-met filtering; route name resolution via GameState with "Met-Location #N" fallback.
- `config/soul_link/met_locations.yml` — 127 entries (Sinnoh routes + cities + dungeons + 5 special pseudo-IDs). Cites pret + PKHeX in header. Closes KG-12.
- `db/migrate/20260503160001_add_step_17_columns_to_soul_link_pokemon.rb`
- `db/migrate/20260503160002_add_parsed_party_data_to_soul_link_emulator_save_slots.rb`
- `test/services/soul_link/pkm_decoder_test.rb` — 9 tests (round-trip, all 24 PID-shuffle orderings, checksum mismatch, boundary errors, egg bit, species=0 sentinel, box-only record, slot_index propagation).
- `test/services/soul_link/party_parser_test.rb` — 10 tests (empty, 1/3/6 mons, eggs filtered, corrupt PKM dropped, wrong size, nil input, no-CRC-valid-slot, out-of-bounds count fallback).
- `test/services/soul_link/catch_coordinator_test.rb` — 17 tests (egg/zero-PID/empty drops, no-op on missing session/run/uid, removed-event log-only, dedup, cross-run dedup boundary, trade-in flag, event-met flag, unknown met-id fallback, event_gift precedence, transaction wrap, no-baseline trade-in defaults).
- `test/services/soul_link/game_state_met_locations_test.rb` — 11 tests (mirrors maps test shape: file absent, known ID, unknown ID, nil input, string coercion, event flag predicate, reload!, production-file canary on gym towns + Routes 201/230 + key dungeons + event flags).

**Files modified (7):**
- `app/services/soul_link/save_diff.rb` — added `Pkm` struct (re-declared for the diff layer's contract), `PokemonCaughtEvent` / `PokemonRemovedEvent` structs, `catch_events:` / `removal_events:` Result fields with extended `Result#empty?`, `prev_party:` / `curr_party:` keyword args on `between(...)`, `diff_party` helper that handles both symbol-keyed and string-keyed (post-JSON-roundtrip) entries.
- `app/services/soul_link/save_diff_dispatcher.rb` — wired prev/curr party_data into `SaveDiff.between` kwargs; fan-out to `CatchCoordinator` when catch/removal events present (single combined call passing both arrays).
- `app/services/soul_link/game_state.rb` — `MET_LOCATIONS_PATH` constant, `met_locations` (memoized YAML loader), `met_location_name(id)`, `event_met_location?(id)` predicate; extended `reload!` to clear the new `@met_locations` ivar.
- `app/jobs/soul_link/parse_save_data_job.rb` — calls `SoulLink::PartyParser.parse(save_data).map(&:to_h)` on success; persists JSON-serialized party data via `update_columns(parsed_party_data: ...)` (same write that already covered the parsed_* columns, so the after_update_commit re-fire is still suppressed). Extended `capture_state` to include `:party_data => slot.parsed_party_data`. Failure path unchanged (KG-13 invariant: only stamps `parsed_at`).
- `app/controllers/dashboard_controller.rb` — loads `@auto_detected_catches` (run.soul_link_pokemon scoped to current_user_id, `pid IS NOT NULL`, `soul_link_pokemon_group_id IS NULL`, ordered `caught_at: :desc`).
- `app/views/dashboard/_pc_box_content.html.erb` — new "AUTO-DETECTED CATCHES" section above ON TEAM, conditionally rendered when `@auto_detected_catches.any?`. First-encounter badge (`1ST`) computed live by grouping catches by location and picking the earliest by caught_at. Trade-in pill (`TRADE-IN`), event pill (`EVENT`).
- `app/services/soul_link/save_diff.rb` (already noted above; counted once).

**Files extended (2 test files):**
- `test/services/soul_link/save_diff_test.rb` — added 9 new tests (Step 17 backward compat, party diff combinations: empty/empty, new PID, stable PID, removed PID, both-nil, one-nil, string-keyed entries, Result#empty? with catches).
- `test/services/soul_link/save_diff_dispatcher_test.rb` — extended `with_stubbed_coordinators` to cover `CatchCoordinator`; updated existing 7 tests' `assert_equal` hashes to include the new `:catch` key (always 0 for pre-Step-17 cases); added 4 new tests (PokemonCaughtEvent fan-out, PokemonRemovedEvent fan-out, stable PIDs no-op, baseline rule for catches).
- `test/jobs/soul_link/parse_save_data_job_test.rb` — added 5 new tests (parsed_party_data persists on success, parse-failure preserves prior parsed_party_data + skips PartyParser, integration 1→2 party transition creates SoulLinkPokemon row with PID + route, re-running same job produces no duplicate via PID dedup, CatchCoordinator retry-safety mirrors Step-15 retry test shape).

**Tests:** 461 → 527 (+66). 0 failures, 0 errors. Per-file:
- pkm_decoder_test.rb: 9 (220 assertions)
- party_parser_test.rb: 10 (19 assertions)
- catch_coordinator_test.rb: 17 (52 assertions)
- game_state_met_locations_test.rb: 11 (29 assertions)
- save_diff_test.rb: +9 over Step 16 baseline (+24 assertions)
- save_diff_dispatcher_test.rb: +4 over Step 16 baseline; existing 7 tests' assertion hashes extended (+catch key)
- parse_save_data_job_test.rb: +5 over Step 16 baseline (+33 assertions)
Total +66 net (66 = 9 + 10 + 17 + 11 + 9 + 4 + 5 + 1 backward-compat test in save_diff already counted within +9; rounding by file).

**Lint:** `bundle exec rubocop` clean (178 files, 0 offenses; +9 from Step 16's 169 — 2 migrations + 3 services + 4 new test files ≈ 9 new files).
**Brakeman:** Clean (no new warnings; the 2 weak-confidence pre-existing File Access warnings — `EmulatorController#rom` `send_file` and `GymScheduleDiscordUpdateJob` Discord URL — are unchanged).

**Backward-compat invariants exercised:**
- Step-15-style `SaveDiff.between(prev_badges:, curr_badges:)` returns Result with empty `catch_events` + `removal_events` arrays. Test: `save_diff_test.rb:233`.
- Step-16-style `SaveDiff.between(... prev_tid:, curr_tid:, ...)` continues to work with no party kwargs; existing 16 Step-16 SaveDiff tests pass unchanged.
- `SaveDiffDispatcher.dispatch(slot, prev:, curr:)` continues to work whether `prev[:party_data]` / `curr[:party_data]` are present or nil; existing Step-16 tests validate the no-party path.
- `ParseSaveDataJob` failure-path still ONLY stamps `parsed_at` (KG-13 invariant) — `parsed_party_data` is preserved across CRC-failed saves. Test: `parse_save_data_job_test.rb` "Step 17: parse failure does not write parsed_party_data".
- Existing manual `SoulLinkPokemon` Catch flow continues to work (validations unchanged; pid nullable). The 17 CatchCoordinator tests build new rows alongside; no existing model tests broke.

**Walks (the same shape Step 15/16 used):**
- **PkmDecoder walk:** Validate input length (136 or 236), read PID + checksum, slice off the 128-byte blocks region, XOR with the LCG keystream seeded by the checksum, sum the decrypted halfwords and verify against stored checksum (mismatch → nil), unshuffle blocks per `((PID >> 13) & 0x1F) % 24` lookup into the 32-entry `SHUFFLE_TABLE` (cases 24..31 mirror cases 0..7 per pret), for party records also XOR-decrypt the 100-byte party stats block with PID-keyed LCG to extract `level @0x8C+0x04`, build the `Pkm` Struct from canonical-block field reads. Top-level `rescue StandardError → nil`.
- **PartyParser walk:** Validate full 0x80000-byte SRAM input, replicate SaveParser's CRC-based active-slot picker (read save_counter from each slot's footer, CRC-verify each, take the higher-counter valid slot), slice the 0x408-byte party block at slot-offset+0xA0 (8-byte header + 6 × 236-byte records), read `currentCount` u32 (clamp out-of-bounds to 6), iterate slots calling PkmDecoder per record, filter nils + eggs + species==0. Top-level `rescue StandardError → []`.
- **CatchCoordinator walk:** Early-return on empty events / nil slot / missing session / missing run, open `slot.transaction { }`, iterate events: for PokemonCaughtEvent skip eggs + zero-PID, exit if session unclaimed, dedup by `(soul_link_run_id, discord_user_id, pid)` exists check, resolve route via `GameState.met_location_name` with "Met-Location #N" fallback, resolve species via memoized `pokemon_base_stats` lookup with "Species #N" fallback, classify acquired_via (event_gift > trade_in > catch precedence), call `SoulLinkPokemon.create!`. PokemonRemovedEvent: just `Rails.logger.info`.

**Diff scope:** 2 migrations + 3 new services + 1 new yml + 1 modified service (game_state) + 1 modified diff (save_diff) + 1 modified dispatcher + 1 modified job + 1 modified controller + 1 modified view + 4 new test files + 3 extended test files. Inside the brief's stated diff scope.

**KG closures logged:** KG-11 closes (party block offset 0xA0). KG-12 closes (met-location enum + special IDs).

**New Known Gaps logged this step:** see § Known Gaps below — KG-20 (species-id resolution depends on pokemon_base_stats table being populated), KG-21 (PC box parsing not implemented; deposit-then-re-catch round-trips through the box invisibly), KG-22 (no Discord notification on auto-detected catch), KG-23 (no UI for "this catch is wrong, please undo").

---

### Step 14.3 — Hotfix: gym-draft candidate cards show all 4 linked pokemon — 2026-05-03
**Status:** Shipped + merged to main.

PO bug report: candidate cards in the nominating phase showed only one pokemon's species, reading as "just my pokemon" to viewers. Root cause: `gym_draft_controller.js:304` rendered `group.pokemon[0].species` — but `g.soul_link_pokemon` has no default order, so the visible species was non-deterministic ("whichever player happened to be saved first"). Fix: render each linked pokemon as `<player>: <species>` on its own line, mirroring the existing gym-result snapshot pattern at `_gyms_content.html.erb:81`. ~10 lines of JS, single file.

**Tests:** 397 → 400 (parallel work landed +3 tests with the gym-leader YAML fixes; this hotfix adds none — JS-only rendering change with no JS test infrastructure in the project, same shape as Step 14.1 / 14.2 hotfixes). Rubocop clean.

---
### Step 16 — Non-decryption SRAM expansion: TID/SID + Pokédex counts + Hall of Fame — 2026-05-03
**Status:** Built; awaiting Richard's review. **KG-14 closes** (Pokédex offsets pinned to PKHeX `SAV4Pt.cs` + pret/pokeplatinum `include/pokedex.h` primary sources, cited inline in code comments).

Bundles the three highest-ROI SRAM additions that don't pay decryption cost, all on top of the Step 15 SaveDiff infra: (1) TID/SID surfacing for save-mix-up detection, (2) Pokédex caught/seen counters (closes KG-14), (3) Hall of Fame run-completion detection. Refactors `ParseSaveDataJob` to hand off to a new `SoulLink::SaveDiffDispatcher` so the job stays a "pure parser + persist" facade and per-category branching lives in one place — opens the door for future categories without rewriting the job again.

**Architecture decision (durable — see § Architecture Decisions):**
- **Dispatcher extracted.** `SoulLink::SaveDiffDispatcher.dispatch(slot, prev:, curr:)` owns the baseline rule (skip on first-ever parse) and the empty-diff short-circuit. Job builds two state-snapshot Hashes (pre/post) and hands them to the dispatcher; dispatcher computes the diff and fans out to four coordinators.
- **Three new coordinators (TID, Pokédex, HoF) — symmetric pattern.** TID and Pokédex are log-only (the user-visible value comes from parser-persisted columns + view reads). HoF is the side-effect coordinator: when 4/4 sessions report `parsed_hof_count >= 1`, sets `run.completed_at = Time.current`. Mirrors `GymBeatenCoordinator`'s all-4 AND-gate.
- **TID-mix-up detection is read-side.** `SoulLinkRun#tid_conflict_groups` returns groups of session-ids sharing the same `(parsed_trainer_id, parsed_secret_id)` pair. The view renders a "⚠ TID CONFLICT" pill on each affected card. No coordinator action — the player resolves manually.
- **No auto-deactivation of completed runs.** PO follow-on call. `active` flag stays as-is. Logged in Known Gaps.
- **HoF block CRC.** Same CRC16-CCITT-FALSE variant as the general block (verified against PKHeX `Dendou4.cs` `Checksums.CRC16_CCITT(GetRegion()[..^2])` and reused the existing `crc16_ccitt` helper). On CRC fail or any error → `parsed_hof_count = nil` (NEVER false-positive a "Run complete").

**KG-14 closure citation (in code comments at `app/services/soul_link/save_parser.rb:75-99`):**
- PKHeX `PKHeX.Core/Saves/SAV4Pt.cs`: `private const int PokeDex = 0x1328;`
- PKHeX `PKHeX.Core/Saves/Substructures/PokeDex/Zukan4.cs`: `SIZE_REGION = 0x40`, `var ofs = 4 + (region * SIZE_REGION) + (index >> 3)` — "Region 0: Caught flags / Region 1: Seen flags"
- pret/pokeplatinum `include/pokedex.h` `struct Pokedex`: `u32 magic; u32 caughtPokemon[DEX_SIZE_U32]; u32 seenPokemon[DEX_SIZE_U32]; ...` with `DEX_SIZE_U32 = 16` — identical layout
- Defensive cap: popcount > `POKEDEX_BIT_LIMIT` (493 = `NATIONAL_DEX_COUNT` per pret) → returns nil for that field, mirroring `safe_map_id`'s graceful degradation

**HoF block citation (in code comments at `app/services/soul_link/save_parser.rb:101-138`):**
- PKHeX `PKHeX.Core/Saves/SAV4Pt.cs`: `ExtraBlocks => [ new(0, 0x20000, 0x2AC0), // Hall of Fame, ... ]`
- PKHeX `PKHeX.Core/Saves/Substructures/Gen4/Dendou4.cs`: layout `Dendou4Record[30]` (each 0x16C bytes), then `u32 IndexNextOverwrite` at 0x2AA8, then `u32 ClearCount` at 0x2AAC; footer at 0x2AB0 (16 bytes); CRC at 0x2ABE
- pret/pokeplatinum `include/savedata/save_table.h` + `src/savedata/save_table.c`: `EXTRA_SAVE_TABLE_ENTRY_HALL_OF_FAME = 0` registered via `HallOfFame_SaveSize`/`HallOfFame_Init`
- Both partition mirrors (primary 0x20000, secondary 0x60000) read; higher CRC-valid `ClearCount` wins. Both corrupt → nil.

**Migrations (2):**
- `db/migrate/20260503135725_add_step_16_parsed_columns_to_soul_link_emulator_save_slots.rb` — adds `parsed_trainer_id`, `parsed_secret_id`, `parsed_pokedex_caught`, `parsed_pokedex_seen`, `parsed_hof_count` (all `:integer`, nullable, no defaults). Avoided `limit: 2` to prevent uint16 upper-half overflow.
- `db/migrate/20260503135726_add_completed_at_to_soul_link_runs.rb` — adds `completed_at :datetime` + index.

**Files created (7):**
- `app/services/soul_link/save_diff_dispatcher.rb` — new fan-out service.
- `app/services/soul_link/tid_observation_coordinator.rb` — log-only.
- `app/services/soul_link/pokedex_progress_coordinator.rb` — log-only.
- `app/services/soul_link/hall_of_fame_coordinator.rb` — side-effect (sets `completed_at`).
- `test/services/soul_link/save_diff_dispatcher_test.rb` — 7 tests (baseline rule, empty diff, per-category dispatch, all-4 fan-out).
- `test/services/soul_link/tid_observation_coordinator_test.rb` — 4 tests (empty events, log assertion, orphan slot, no AR side effects).
- `test/services/soul_link/pokedex_progress_coordinator_test.rb` — 4 tests (same shape as TID).
- `test/services/soul_link/hall_of_fame_coordinator_test.rb` — 7 tests (4/4 sets completed_at, 3/4 no-op, idempotency, inactive run, 0 sessions, missing active slot, empty events).

**Files modified (8):**
- `app/services/soul_link/save_parser.rb` — extended `Result` struct with 5 new fields; added Pokédex + HoF constants with primary-source citations; added `read_uint16_le`, `count_pokedex_bits`, `safe_hof_count`, `extract_hof_count` helpers; populated TID/SID/Pokédex/HoF in the `parse(...)` Result. Top-level `rescue StandardError → nil` preserved.
- `app/services/soul_link/save_diff.rb` — added `TidObserved`/`PokedexProgress`/`HallOfFameEntered` structs; extended `Result` with `tid_events:`, `pokedex_events:`, `hof_events:` keyword fields; extended `between(...)` with new keyword args (default `nil`); refactored per-dimension diff helpers. Backward compat: Step-15-style call signature returns Result with all 4 event arrays populated correctly.
- `app/jobs/soul_link/parse_save_data_job.rb` — refactored to "pure parser + persist". `capture_state(slot)` builds prev/curr snapshots before/after the parsed_* write; dispatcher receives both. Step 15's diff/dispatch logic relocated to `SaveDiffDispatcher`. KG-13 contract preserved (parse failure stamps only `parsed_at`, no dispatch).
- `app/models/soul_link_run.rb` — added `broadcasts_refreshes_to ->(record) { [ record, :dashboard ] }` (mirrors Step 15 GymResult pattern); added `completed?` and `tid_conflict_groups` methods.
- `app/views/emulator/_run_sidebar_card.html.erb` — appended TID/SID line, Pokédex line, HoF pill, TID-conflict pill after the existing badges line. Conflict computation runs inline per card render (cheap because `includes(:save_slots)` eager-loaded; no controller-context-needing helper extraction).
- `app/views/emulator/_save_slots_sidebar.html.erb` — mirrored TID/SID, Pokédex, HoF pill on the player's own slot column. Skipped TID conflict pill (player's own slots can't conflict with themselves).
- `app/views/dashboard/_runs_content.html.erb` — added "🏆 COMPLETE" pill next to the existing "ACTIVE" pill in the run header; added "COMPLETED" timestamp tile as a row below the gb-grid-4 stats (chose row-below over gb-grid-5 to keep CSS untouched and the layout readable on narrow viewports — brief allowed either).
- `test/services/soul_link/save_parser_test.rb` — extended `build_slot` with `trainer_id`, `secret_id`, `pokedex_caught_bits`, `pokedex_seen_bits` kwargs; extended `build_sram` with `hof_a`/`hof_b` kwargs and pads to full 0x80000 size; added `build_hof_block(clear_count:, valid_crc:)` and `bytes_with_n_bits_set(n, byte_length)` helpers. Added 14 new tests (TID/SID parse, Pokédex popcount, defensive cap, HoF count, HoF CRC fail, HoF dual-partition picking, backward-compat smoke).
- `test/services/soul_link/save_diff_test.rb` — added 16 new tests (Step-16 backward compat with Step-15 signature, Result#empty?, TidObserved 5 cases, PokedexProgress 4 cases, HallOfFameEntered 5 cases).
- `test/jobs/soul_link/parse_save_data_job_test.rb` — extended success-path test to assert all 5 new columns populate; replaced the KG-13 dispatch-suppression test's stub target from `GymBeatenCoordinator.process` to `SaveDiffDispatcher.dispatch` (the call site moved); added a `SaveDiffDispatcher.dispatch` call-args test (asserts prev/curr snapshot shape + values); added a 4-session HoF integration test (only 4th save sets `run.completed_at`).
- `test/models/soul_link_run_test.rb` — added 7 new tests (completed?, tid_conflict_groups: empty / unique TIDs / 2-of-4 share / 4-of-4 share / nil-zero TID excluded / TID-only-match no-conflict).

**Tests:** 461/461 (was 400). +61 over Step 15 baseline. 0 failures, 0 errors.
**Lint:** `bundle exec rubocop` clean (169 files, 0 offenses; +10 from Step 15's 159 — 2 migrations + 1 dispatcher + 3 coordinators + 4 new test files; 1 inline `_ = noop` smell autocorrected pre-commit by removing the unused literal).
**Brakeman:** Clean (no new warnings; the 2 weak-confidence pre-existing File Access warnings are unchanged).

**Backward-compat invariants exercised:**
- Step-15-style call `SaveDiff.between(prev_badges: 0, curr_badges: 1)` returns `Result.new(badge_events: [BadgeGained.new(gym_number: 1)], tid_events: [], pokedex_events: [], hof_events: [])` and the existing 8 Step-15 SaveDiff tests pass unchanged.
- `SaveParser::Result.new(trainer_name: "X", money: 0, play_seconds: 0, badges_count: 0, map_id: nil)` (the Step-15 form used in 7 existing job tests) still works because `keyword_init: true` defaults missing fields to nil.
- `GymBeatenCoordinator` body is untouched. The dispatcher relocates the *call* to `process(slot, diff.badge_events)` — no change to all-4 gate, suppression, idempotency, or transaction-wrap semantics.
- Step 15's retry-safety regression test (`coordinator raise on first run does not double-fire on the retry`) still passes — the dispatcher refactor moved call sites but not invariants.

**Walks (the same shape Step 15 used):**
- **HoF coordinator walk:** `process(slot, events)` returns early if `events.empty?`. Resolves `run = slot.session&.run`; returns if run is nil, inactive, or already completed (idempotency guard). Calls `all_players_in_hall_of_fame?(run)` which returns false for empty session sets (mirroring `GymBeatenCoordinator.all_players_have_badge?`'s same guard) and uses `s.active_slot&.parsed_hof_count.to_i >= 1` for nil-safe checks. Only on the all-4 pass: `run.update!(completed_at: Time.current)` + info log line.
- **TID-conflict-group walk:** `tid_conflict_groups` filter_maps over `soul_link_emulator_sessions.includes(:save_slots)`, dropping nil active slots and slots with TID 0 (unparsed). Groups by `[tid, sid]` pair, keeps only groups of size ≥ 2, returns the session-id arrays. Pair key is `[tid, sid]` so two players with the same TID but different SIDs are NOT flagged (different save anyway).
- **HoF block walk:** `safe_hof_count(bytes)` reads both partition mirrors (primary at 0x20000, secondary at 0x60000), CRC-validates each (CRC16-CCITT over the data region except the last 2 bytes), takes the higher of the valid `ClearCount` values. Returns nil if both partitions fail CRC (NEVER 0 — the `>= 1` check on a nil-coerced-to-0 then correctly fails the all-4 gate, never false-positives a "Run complete").

**Diff scope:** 2 migrations + 1 modified parser + 1 modified diff + 1 new dispatcher + 3 new coordinators + 1 modified model + 1 modified job + 3 modified views + 4 new test files + 4 extended test files. Inside the brief's stated diff scope.

**KG closure logged:** KG-14 closes — Pokédex offsets cited from primary sources in code comments. **No new KGs added by this step.**

**New Known Gaps logged this step:** see § Known Gaps below — KG-16 (auto-deactivation of completed runs deferred), KG-17 (Discord notification on HoF deferred — could be a 1-liner inside `HallOfFameCoordinator`), KG-18 (TID conflict resolution flow — pill is informational only, no UI to resolve), KG-19 (HoF "uncomplete" path — direct AR edit only, no UI).

**Rebase note:** branch was based on Step 15 + corrigendum (`e556671`); main advanced through Step 14.3 hotfix (`c845e8a`) before Step 16 landed. Rebase resolved one trivial conflict in `BUILD-LOG.md` (Current Status replaced; Step 14.3 entry preserved below the new Step 16 entry).

---

### YAML correction — Platinum gym order + level caps — 2026-05-03
**Status:** Shipped to main. Supersedes the gym data shipped 2026-05-02 in commit `23253e1` (audit doc `handoff/2026-05-02-yml-and-sram-expansion.md`).

PO flagged that the prior YAML fix had gym 3/4/5 in **Diamond/Pearl** order (Maylene/Wake/Fantina) instead of **Platinum** order (Fantina/Maylene/Wake — the "Fantina shuffle"). Several level-cap values were also wrong: gym-3 cap, gym-6 cap (39 was the BDSP value, not Platinum's 41), gym-7 cap (Abomasnow 42 vs actual highest Froslass 44), gym-8 cap (Luxray 49 was the DP value, Platinum has Electivire 50). All values re-verified against `https://pokemondb.net/platinum/gymleaders-elitefour` and shipped.

**Corrected table (Platinum, pokemondb-verified):**
| Gym | Leader | City | Cap | Cap-defining mon |
|---|---|---|---|---|
| 1 | Roark | Oreburgh | 14 | Cranidos |
| 2 | Gardenia | Eterna | 22 | Roserade |
| 3 | **Fantina** | **Hearthome** | **26** | Mismagius |
| 4 | **Maylene** | **Veilstone** | 32 | Lucario |
| 5 | **Crasher Wake** | **Pastoria** | 37 | Floatzel |
| 6 | Byron | Canalave | **41** | Bastiodon |
| 7 | Candice | Snowpoint | **44** | **Froslass** *(highest; Abomasnow at 42 is the canonical "ace" but not the cap-defining mon)* |
| 8 | Volkner | Sunyshore | **50** | **Electivire** *(highest; Luxray at 48 is the canonical "ace")* |

The Platinum cap progression is monotonic: 14 → 22 → 26 → 32 → 37 → 41 → 44 → 50. (My 2026-05-02 commit produced an erroneous 14 → 22 → 32 → 37 → 40 → 39 → 42 → 49 sequence and I incorrectly framed the resulting non-monotonicity as a Platinum oddity. It wasn't — it was bad data.)

**Files modified (4):**
- `config/soul_link/gym_info.yml` — full rewrite of slots 3-5 (Fantina-shuffle), level fixes for slots 6-8, ace-species fixes for slots 7-8 (Froslass, Electivire). Updated header comment to pin `ace` field semantics ("cap-defining mon, may differ from canonical signature") and to cite pokemondb. Per-entry comments on slots 7 and 8 explaining the Froslass/Abomasnow and Electivire/Luxray distinction so future re-edits don't "fix" them back to the signatures.
- `config/soul_link/progression.yml` — three segment-to-gym key references re-pointed: Hearthome segment `gym: fifth_gym` → `gym: third_gym`; Veilstone `third_gym` → `fourth_gym`; Pastoria `fourth_gym` → `fifth_gym`. The `*_gym` keys are positional in `GYM_KEYS` (game_state.rb:42), so these reference updates are required to keep the timeline view's gym associations correct.
- `config/soul_link/locations.yml` — `gym_number:` flags on three cities updated: hearthome_city 5→3, veilstone_city 3→4, pastoria_city 4→5. (This field is documentation-as-data — not consumed by any code today — but kept in sync for future readers.)
- `handoff/2026-05-02-yml-and-sram-expansion.md` — corrigendum note appended at the top of the doc pointing forward to this BUILD-LOG entry. Body of the doc is left as the historical snapshot of architect-phase reasoning at that point in time; the SRAM expansion section (§ 3) was not affected and stands as written.

**Why the corrigendum, not a delete-and-rewrite:** the audit doc captures a frozen snapshot of architect reasoning, including the SRAM expansion brainstorm that's still load-bearing for the Step 16 recommendation. Deleting it would lose that. A top-of-file warning + pointer to the corrected data in this BUILD-LOG entry preserves both.

**No code paths touched.** Step 15's `SaveDiff` and `GymBeatenCoordinator` use `parsed_badges` as a population count of set bits, **not** as a bitfield — count → gym number is a sequential mapping, so the in-game gym order shuffle has no effect on auto-mark logic. Verified by reading `app/services/soul_link/save_diff.rb:42-51` and `gym_beaten_coordinator.rb:68-71`.

**No tests touched.** No test asserts on a specific `max_level` integer or on monotonic-progression invariants (verified via `grep "max_level\|monoton" test/`). Step 15's tests assert on `gyms_defeated` (run-state counter), which is unrelated to the YAML config.

**Diff scope:** 3 YAML edits + 1 audit-doc corrigendum + this BUILD-LOG entry. Single commit, FF-merged.

---

### Step 15 — SaveDiff Infrastructure + Category 1 (Gyms-Beaten Auto-Detection) + KG-13 fix — 2026-05-02
**Status:** Shipped + pushed to main.

Ships the shared `SoulLink::SaveDiff` pure-function diff layer plus `SoulLink::GymBeatenCoordinator` (the all-4 AND-gate dispatcher) on top of it, wires the dispatch into `ParseSaveDataJob`, adds a `gym_auto_mark_suppressions` table for the manual-UNMARK escape hatch, and folds the KG-13 prerequisite (parse-failure path zeroing `parsed_badges`) into the same pass. This is category 1 of the SRAM auto-tracking audit (`handoff/2026-05-02-sram-auto-tracking-audit.md`); categories 2 (gym battle teams) and 3 (catches+routes) are deferred to a future step that pays the Gen-IV PKM decryption cost.

**New surfaces introduced this step (durable architecture — see § Architecture Decisions):**
- **`SoulLink::SaveDiff`** — pure function (`app/services/soul_link/save_diff.rb`) that turns two `parsed_badges` snapshots into a structured `Result` of `BadgeGained` / `BadgeLost` events. No AR, no logger, no `Time.current`. Extension point for categories 2 (`catch_events:`) and 3 (`evolution_events:`) — they add keyword fields without rewriting consumers.
- **`SoulLink::GymBeatenCoordinator`** — pure-static service (`app/services/soul_link/gym_beaten_coordinator.rb`) that consumes `SaveDiff` events for one slot, runs the all-4 AND-gate, respects per-gym suppressions, and creates `gym_results` + bumps `gyms_defeated` in a single transaction. Three guards in priority order: (a) `gym_results.exists?` (idempotency), (b) `gym_auto_mark_suppressions.exists?` (suppression), (c) `all_players_have_badge?` (the AND-gate). BadgeLost events log at info level and are no-ops (no auto-unmark — manual policy).
- **`GymAutoMarkSuppression`** — new table (`gym_auto_mark_suppressions`) + model. Per-(run, gym) record created when a player manually UNMARK-s a gym from the dashboard. While present, blocks auto-mark for that gym. Cleared by a manual MARK BEATEN on that same gym, or by completing a draft for that gym number. Unique index on `(soul_link_run_id, gym_number)`.

**Migrations (1):**
- `db/migrate/20260502191439_create_gym_auto_mark_suppressions.rb` — creates the suppressions table with the unique composite index. Additive; no backfill needed.

**Files modified (5):**
- `app/jobs/soul_link/parse_save_data_job.rb` — KG-13 fix: failure branch now updates ONLY `parsed_at` (was: zeroing every other parsed_*). Added: capture `prev_parsed_at` and `prev_badges` before update; after success, build `SaveDiff.between(prev, curr)` and dispatch to `GymBeatenCoordinator.process(slot, events)` IFF `prev_parsed_at.present?` (baseline rule — first-ever parse is silent so importing a save doesn't fire N events).
- `app/models/gym_result.rb` — added `broadcasts_refreshes_to ->(record) { [ record.soul_link_run, :dashboard ] }` so manual mark/unmark, post-draft mark-beaten, and the new auto-mark path all broadcast a Turbo refresh to other open dashboards in the run.
- `app/models/soul_link_run.rb` — added `has_many :gym_auto_mark_suppressions, dependent: :destroy`.
- `app/controllers/gym_progress_controller.rb` — UNMARK branch now creates the suppression via `find_or_create_by!` (idempotent against double-clicks); MARK branch now destroys any matching suppression after the create. Stacks cleanly on top of Step 14.1's content-type branching (`json_request?` / `respond_with_error`); the suppression touchpoints sit between the existing `existing.destroy!` / `gym_results.create!` lines and the `notice = ...` line.
- `app/controllers/gym_drafts_controller.rb` — `mark_beaten` now destroys any matching suppression after creating the `gym_results` row (completing a draft is an explicit re-engagement signal). Stacks on top of Step 14.2's `redirect_to root_path(anchor: "gyms")` change.

**Files created (5):**
- `app/models/gym_auto_mark_suppression.rb` — minimal AR model. `belongs_to :soul_link_run`, validates gym_number presence + 1..8 + uniqueness scoped to run.
- `app/services/soul_link/save_diff.rb` — the pure diff function + `Result`/`BadgeGained`/`BadgeLost` structs.
- `app/services/soul_link/gym_beaten_coordinator.rb` — the static coordinator with `.process`, `.attempt_auto_mark`, `.all_players_have_badge?`.
- `test/factories/gym_auto_mark_suppressions.rb` — minimum-viable factory; cycles `gym_number` 1..8.
- `test/services/soul_link/save_diff_test.rb` — 8 tests covering nil prev, nil curr, equal values, +1, +2 sequential, -1, full reset (8 BadgeLost), full claim (8 BadgeGained).
- `test/services/soul_link/gym_beaten_coordinator_test.rb` — 10 tests covering 4/4 satisfy → create, 3/4 satisfy → no-op, idempotency, suppression respected, BadgeLost no-op, inactive run guard, 0-sessions guard, missing-active-slot guard, transaction wrapping, multi-event sequence (gym 1 then gym 2 in one process call).

**Tests modified:**
- `test/jobs/soul_link/parse_save_data_job_test.rb` — REPLACED the stale "writes nil-attrs and parsed_at when parser returns nil" test (which asserted the OLD KG-13-bug behavior) with the new KG-13 contract: parse failure leaves every parsed_* alone and only stamps `parsed_at`. ADDED 5 new tests: KG-13 no-spurious-diff dispatch on failure, first-ever-parse skip (baseline rule), badges-unchanged → no auto-mark, badges-+1-with-4/4 → 1 gym_results row, end-to-end integration (4 player saves landing in sequence; 4th triggers exactly 1 auto-mark).
- `test/controllers/gym_progress_controller_test.rb` — ADDED 2 tests: unmark creates a suppression row, mark clears any matching suppression. Both tests use `as: :json` since Step 14.1's JSON contract is what these new assertions extend; the HTML redirect path remains tested by Step 14.1's existing assertions.
- `test/controllers/gym_drafts_controller_test.rb` — ADDED 1 test: `mark_beaten` clears matching suppression after creating the gym_results row. Sits alongside Step 14.2's two new anchor-redirect tests; total of 3 new tests in this file across 14.2 + 15.

**Post-review test additions (Should Fix resolutions, see Current Status above):**
- `test/services/soul_link/gym_beaten_coordinator_test.rb` — REWORKED the transaction-rollback test to stub `update!` raising `RuntimeError` (propagates through `transaction`) instead of `ActiveRecord::Rollback` (silently swallowed); replaced the dead `begin/rescue ActiveRecord::Rollback` with `assert_raises(RuntimeError)`. Now correctly proves the transaction wraps both writes — the test would fail if the implementation did `create!; update!` outside a transaction block.
- `test/jobs/soul_link/parse_save_data_job_test.rb` — ADDED 1 retry-safety regression test (~50 lines) pinning reviewer focus area #11. Stubs `GymBeatenCoordinator.process` to raise on first call and `flunk` on a second; asserts the retry attempt completes silently because `prev_badges == curr_badges` after the first job's `update_columns` write makes the diff empty before the dispatch line.

**Tests:** Step 15 added +27 over its base. Pre-rebase the base was 370 (post-Step 14); the parallel hotfix sweeps (14.1 +1, 14.2 +2) advanced it to 373 on main. Post-rebase, the suite count is 373 + 27 = 400. 0 failures, 0 errors at commit time.

**Lint:** `bundle exec rubocop` clean (0 offenses). New file count: 152 (post-Step 14) + 7 (Step 15: 1 migration + 1 model + 1 factory + 2 services + 2 service-test files) = 159.

**KG-13 fix surface:** the failure branch went from 7 lines (zeroing every parsed_* field) to 1 line (`slot.update_columns(parsed_at: Time.current)` + `return`). Per the brief's constraint flag, the failure branch now branches on `result.nil?` (not `attrs.values.any?(&:nil?)` or anything fragile). The `Result.nil?` branch returns immediately so the diff dispatch never runs on a parse failure — both the KG-13 contract AND reviewer focus area #7 (no spurious BadgeLost from the failure path) are covered.

**Idempotency walk:** `attempt_auto_mark` runs guards in the brief's exact priority order: (a) `gym_results.exists?(gym_number: N)`, (b) `gym_auto_mark_suppressions.exists?(gym_number: N)`, (c) `all_players_have_badge?(run, N)`. Each early-returns. The `gym_results.exists?` guard means even if every save fires N events, the `create!` only ever runs once per (run, gym) — and the unique index on `(soul_link_run_id, gym_number)` is the belt-and-suspenders if guard (a) somehow races.

**Transaction walk:** `attempt_auto_mark` wraps `gym_results.create!` + `run.update!(gyms_defeated: ...)` in `run.transaction`. If the counter bump raises (stale-run race, validation flake, anything), the `gym_results` row is rolled back too — no half-applied state. Test 16 (`attempt_auto_mark wraps create + counter bump in a transaction`) stubs `update!` to raise `RuntimeError` (post-review fix from `ActiveRecord::Rollback`, which `transaction { }` silently swallows) and asserts no `gym_results` row persists.

**All-4 gate semantics:** `all_players_have_badge?` calls `sessions.all? { |s| s.active_slot&.parsed_badges.to_i >= gym_number }`. The `&.` chain handles "session has no active_slot set yet" → `nil.to_i = 0`, which fails the `>= gym_number` check correctly for any gym ≥ 1. The `sessions.empty?` short-circuit at the top returns false (so a 0-session run never triggers — `.all?` on `[]` returns true, which is the wrong default here). Reviewer focus area #2 covers both branches with explicit tests (`session with no active_slot → all_players_have_badge? returns false` and `0 sessions → all_players_have_badge? returns false (no auto-mark)`).

**One-time backfill consideration (per brief Out-of-Scope):** existing slots in production already have `parsed_at` set + `parsed_badges = 0` (because nobody has played far enough yet). Their NEXT parse will run the diff against `prev_badges = 0`. If a save with N>0 badges lands, that fires N events through the all-4 gate. This is the expected migration behavior and matches the audit's analysis: any in-flight run is either (a) freshly imported with 0 badges (correct) or (b) already mid-run with auto-detection wanted (also correct). The PO can RESET DRAFT or manually UNMARK to recover from any spurious event. No backfill code added.

**Manual smoke:** the parse-job integration test (`integration: 4 player saves landing in sequence, 4th triggers the auto-mark`) is the live-fire end-to-end harness — it stands up 4 sessions + 4 slots, walks each one through `ParseSaveDataJob.perform_now` with the parser stubbed to return `badges_count: 1`, and asserts:
- after slot 1 parses → 0 gym_results
- after slot 2 parses → 0 gym_results
- after slot 3 parses → 0 gym_results
- after slot 4 parses → 1 gym_results (gym_number: 1) + `gyms_defeated == 1`

This exercises the full chain: parse job → SaveDiff.between → GymBeatenCoordinator.process → all-4 gate → gym_results.create! → run.update!. No browser flow needed for this step — the surface is server-side detection, not UI.

**Diff scope:** 1 migration + 1 new model + 2 new services + 1 modified job + 2 modified models + 2 modified controllers + 1 new factory + 2 new test files + 3 modified test files + 4 handoff files. Inside the brief's stated diff scope.

**Rebase note:** branch was based on Step 14 (`141e706`); main advanced through hotfixes 14.1 / 14.2, the SRAM auto-tracking audit (`b8a769e`), and the YAML+SRAM-expansion commit (`23253e1`) before Step 15 landed. Rebase resolved two trivial conflicts: `gym_progress_controller.rb` (Step 15 suppression touchpoints stacked cleanly on top of Step 14.1's content-type branching), and `BUILD-LOG.md` (Step 15's Current Status replaced the stale Step 14.2 status; Step History entries from main are preserved below).

**Known Gaps logged this step:** none. Categories 2 and 3 of the audit remain deferred — they're future-step territory, not gaps from this step.

---

### YAML data fixes + SRAM scope expansion brainstorm — 2026-05-02
**Status:** Shipped to main.

Architect-phase deliverable. PO asked: any reference-data mismatches in the YAML files (especially gym names + level caps), and what else in the `.sav` is worth surfacing beyond the three categories the prior audit (`b8a769e`) covered? Full report in `handoff/2026-05-02-yml-and-sram-expansion.md`.

**Files modified (1):**
- `config/soul_link/gym_info.yml` — fixed `second_gym.name` (`"Eterna City Gym"` → `"Eterna Gym"` to match in-game sign + the rest of the file's `"<City> Gym"` pattern). Corrected six `max_level` values to canonical Platinum aces: gym 3 (26→32), gym 4 (32→37), gym 5 (37→40), gym 6 (41→39), gym 7 (44→42), gym 8 (50→49). Added `ace: "<species>"` field per entry as documentation-as-data (not consumed by any view today). Added file-header comment explaining `max_level` semantics. Cross-referenced against pret/pokeplatinum trainer data; six unambiguous data fixes, zero ambiguous-style judgment calls deferred to PO.

**Files added (1):**
- `handoff/2026-05-02-yml-and-sram-expansion.md` — three-section report: § Half 1 YAML audit findings (locations.yml / maps.yml / progression.yml clean; gym_info.yml fixes detailed); § Half 2 level-cap placement decision (folded into existing `max_level`, no new file); § Half 3 SRAM expansion candidates (15 fields catalogued by trainer-block / item-bag / party-PKM tier, with offset citations and S/M/L effort + KG-14, KG-15 noted as speculative offsets pending real-save validation).

**No code paths touched.** Step 15 (SaveDiff + auto-mark) on parallel worktree is uninterrupted. No tests changed (no test asserts a specific `max_level` integer; verified via `grep "max_level" test/`). No view templates changed; corrected values render automatically on next page load via existing `gym["max_level"]` reads.

**Recommended Step 16 follow-on (per § Recommendations of the report):** bundle Hall of Fame detection + TID/SID surfacing + Pokédex counter into a single non-decryption-gated step on top of Step 15's SaveDiff pattern. Decryption-gated items (held items / IVs / nature) wait for Step 17+.

**Diff scope:** 1 YAML edit + 1 new handoff doc + this BUILD-LOG entry. Single commit, FF-merged.

---

### Step 14.2 — Hotfix sweep: remaining Gyms-tab anchor losses + unrouted-redirect fix — 2026-05-02
**Status:** Shipped + merged to main.

Diagnosis: `handoff/2026-05-02-dashboard-route-audit.md` — full dashboard route + action audit done first; this commit applies the four 🟡 findings as a single sweep. No separate brief; the audit IS the brief.

**Files modified (4):**
- `app/controllers/gym_drafts_controller.rb:75` — replaced `redirect_to gym_drafts_path` (which has no GET handler — `resources :gym_drafts, only: [:create, :show, :destroy]`, no `:index`) with `redirect_to root_path(anchor: "gyms")`. Was a real routing-error dead-end on direct curl / stale form submissions to the not-yet-complete-draft branch.
- `app/controllers/gym_drafts_controller.rb:100` — `redirect_to root_path` → `redirect_to root_path(anchor: "gyms")` so completing a draft + marking the gym beaten lands on the Gyms tab instead of the default PC BOX.
- `app/javascript/controllers/dashboard_controller.js` — `confirmResetDraft` sets `window.location.hash = "gyms"` before `window.location.reload()` so the Gyms tab survives the post-reset reload.
- `app/javascript/controllers/gym_backfill_controller.js` — same hash-set-before-reload pattern in the `save` action so the + ADD TEAM backfill flow preserves the Gyms tab.

**Files added (none).**

**Tests modified (1):**
- `test/controllers/gym_drafts_controller_test.rb` — 2 new tests: `mark_beaten on complete draft redirects to dashboard Gyms tab` (asserts the success-path anchor) and `mark_beaten on incomplete draft redirects to dashboard Gyms tab (not to unrouted gym_drafts_path)` (locks in the fix for the previously-broken error branch).

**Tests:** 371 → 373 (+2). 0 failures, 0 errors.

**Lint:** rubocop clean (152 files, 0 offenses).

**Reviewer skim (lightweight, in-thread):** both controller redirects updated symmetrically, both JS reloads use the same hash-set pattern with inline references to the Step 14.1 `applyHashTab()` mechanism, no regressions in the wider suite. No TMT round trip needed for this scale.

**Diff scope:** 2 controller edits + 2 JS edits + 1 test file extension + 1 BUILD-LOG entry. Single commit, FF-merged.

---

### Step 14.1 — Hotfix: Mark Beaten redirect + Gyms-tab persistence — 2026-05-02
**Status:** Shipped + merged to main.

User reported that clicking MARK BEATEN (or UNMARK) on the Gyms tab landed them on a "different view" — diagnosis: `GymProgressController#update` returned `render json: { gyms_defeated: N }` for ALL callers, and the `button_to ... data: { turbo: false }` form on the Gyms tab posted as plain HTML, so the browser rendered the JSON response body as the page text. Pre-existing since before Step 13; the JSON contract is consumed by `timeline_controller.js:342` on the map page (real XHR caller).

**Files modified (3):**
- `app/controllers/gym_progress_controller.rb` — content-type branch. Helper `json_request? = request.content_type == "application/json"` distinguishes the timeline XHR (which sets `Content-Type: application/json`) from the dashboard's HTML form posts. JSON consumers keep `render json: { gyms_defeated: N }`; HTML consumers now `redirect_to root_path(anchor: "gyms")` with a `notice` (success) or `alert` (error). Both error early-returns also branched via a new `respond_with_error(message)` private helper.
- `app/javascript/controllers/pixeldex_controller.js` — new private `#applyHashTab()` called from `connect()`. Reads `window.location.hash`, finds the matching `tabButton`, and clicks it. Replays the existing switchTab flow without touching `switchTab` itself. Combined with the controller's `root_path(anchor: "gyms")`, the user lands back on the Gyms tab after the redirect instead of the default PC BOX.
- `test/controllers/gym_progress_controller_test.rb` — 4 existing tests updated to assert redirect-with-flash for HTML (was asserting `:success`/`:unprocessable_entity` against the JSON path). 1 new test added: `JSON request returns gyms_defeated count without redirect` (uses `as: :json`, asserts the JSON contract is preserved).

**Tests:** 370 → 371 (+1). 0 failures, 0 errors.

**Lint:** rubocop clean (152 files, 0 offenses). Same as Step 14.

**Diff scope:** 1 controller + 1 JS + 1 test + handoff updates. Single commit, FF-merged.

---

### Step 14 — Gym Draft Final-2 Picks: Unified Nominate-or-Endorse Model — 2026-05-01
**Status:** Awaiting review.

Major rewire of the gym-draft nominating phase from the old "submit nomination → up/down vote → resolve" round-robin loop into a single 4-pick "nominate or endorse" pass. Each player makes exactly one pick; the pick is auto-detected as either a NEW candidate or an ENDORSEMENT of an existing candidate. After all 4 picks, the top-2 most-endorsed candidates fill slots 5 and 6, with a TCG-coin tiebreak modal driving the visual reveal when the slot boundary lands on a tie. Closes audit Bugs 1, 2, 3, and 5 in one shot.

**New surfaces introduced this step:**
- **Avatar caching layer.** `SoulLinkRun#player_avatars` JSON column maps `discord_user_id` → Discord CDN URL. `SessionsController#create` upserts on every successful login. View helper `player_avatar_image(run, uid)` renders `<img>` when cached, deterministic colored-initial fallback otherwise. Stimulus `buildAvatar(uid)` mirrors the helper for client-rendered piles.
- **60-second skip grace.** `current_turn_started_at` ISO timestamp on `state_data` drives a per-second JS countdown. Inside grace: only the current nominator can skip themselves. Outside grace: any player may skip the stalled nominator. Channel-side `skip_turn!(requester_uid)` enforces both rules.
- **TCG-coin tiebreak modal.** New `.tcg-coin` CSS component (preserve-3d with two faces, gold-edged shadow, `tcgCoinFlip` keyframe rotating `0deg → 1980deg` over 1.8s). Pokeball front face via radial+linear gradient. Animation modal blocks UI during the ~4s reveal then auto-closes. Server is the source of truth for tiebreak.winners; client only animates.

**Migrations (2):**
- `db/migrate/20260501192916_add_player_avatars_to_soul_link_runs.rb` — adds JSON column.
- `db/migrate/20260501192917_cleanup_current_nomination_from_inflight_drafts.rb` — strips the now-defunct `current_nomination` JSON sub-key from any draft parked in `nominating`. Idempotent (the `next unless data.key?` guard makes a second run a no-op). Down is a documented no-op.

**Files modified (8):**
- `app/models/gym_draft.rb` — REMOVED `current_nomination` accessor, `submit_nomination!`, `vote_on_nomination!`, `resolve_nomination!` (singular). ADDED `candidates`, `tiebreak`, `current_turn_started_at`, `grace_elapsed?`, `current_nominator_id`, `nomination_picks_made`, `nominate!(picker_uid, group_id)` (unified action), `resolve_nominations!` (plural — greedy-fill voter-count-desc with same-count-group tiebreak detection). `make_pick!` and `skip_turn!` now seed/maintain `current_turn_started_at`. `skip_turn!` now takes a `requester_uid` and enforces nominator-OR-grace-elapsed. `broadcast_state` drops `current_nomination`, adds `candidates`/`current_nominator_id`/`current_turn_started_at`/`nomination_picks_remaining`/`tiebreak`.
- `app/channels/gym_draft_channel.rb` — REMOVED `vote_nomination` action. `nominate` now calls `@draft.nominate!`. `skip` passes `current_user_id`.
- `app/controllers/sessions_controller.rb` — calls `run.upsert_avatar!(discord_user_id, avatar_url)` after session is set, gated on `avatar_url.present?`.
- `app/models/soul_link_run.rb` — adds `avatar_for(uid)` and `upsert_avatar!(uid, url)`. The upsert is idempotent (early return if URL unchanged) and treats blank URL as "delete entry."
- `app/views/gym_drafts/show.html.erb` — nominating panel rewritten: pick-order strip, status + grace countdown line, candidates row, pokemon grid with NOMINATE/ENDORSE labels. TCG coin-flip modal added at bottom inside the controller wrapper. Q5 fix: complete-panel "BACK TO GYM READY" demoted to `gb-btn` (was `gb-btn-primary`); MARK BEATEN remains the single primary CTA.
- `app/javascript/controllers/gym_draft_controller.js` — REMOVED `approveNomination`, `rejectNomination`, legacy `nominatePokemon`. ADDED `nominateOrEndorse`, `renderNomOrderStrip`, `renderCandidates`, `renderNomGraceCountdown`, `renderNomPokemonGrid`, `runCoinFlipAnimation`, `maybeShowCoinFlip`, `buildAvatar`. New targets: `nomOrderStrip`, `nomGraceCountdown`, `nomSkipButton`, `nomCandidatesList`, `coinFlipModal`, `coinFlipMessage`, `coinFlipCoin`, `coinFlipResult`. Removed targets: `nomVoteArea`, `nomVotePrompt`. New value: `playerAvatars: Object`. Coin flip dedupes via `coinFlipShownFor = JSON.stringify(state.tiebreak)` so it only animates once per resolution.
- `app/assets/stylesheets/pixeldex.css` — adds `.gb-avatar` family (32/24, --initial, --c0..c3 deterministic palette), `.gb-avatar-pile`, `.gb-candidate-card` + `--leading` variant, `.tcg-coin` + faces + `tcgCoinFlip` keyframe.
- `test/factories/gym_drafts.rb` — unchanged (existing `:lobby` trait covers all the new tests).

**Files created (2):**
- `app/helpers/gym_draft_helper.rb` — `player_avatar_image(run, uid, size: 32)` helper. Image-tag when URL cached, deterministic colored-initial circle (`uid % 4` → c0..c3) otherwise.
- `test/helpers/gym_draft_helper_test.rb` — 5 helper tests (image branch, fallback branch, deterministic-color sanity check, nil-player_avatars handling, custom size).

**Tests modified/created:**
- `test/models/gym_draft_test.rb` — REMOVED 6 stale tests (`submit_nomination ...`, `vote_on_nomination records vote`, `nomination approved with majority`, `nomination rejected clears nomination ...`, `six total picks transitions to complete`). ADDED 17 new tests covering all 5 tally splits (3/1, 2/2, 2/1/1, 1/1/1/1, 4/0 consensus), the `current_turn_started_at` write on transitions + `nominate!`, the 60s grace authorization for `skip_turn!` (3 cases: pre-grace non-nominator raises, current nominator any time, post-grace non-nominator), endorsement / double-endorsement / not-your-turn / already-picked guards, and broadcast_state Step-14 fields + integer-storage assertion.
- `test/channels/gym_draft_channel_test.rb` — REMOVED stale `vote_nomination action records vote` test. ADDED 5 new tests: nominate-creates-new-candidate, nominate-endorses-existing, skip-rejected-pre-grace, skip-allowed-post-grace, vote_nomination-action-removed (asserts via `GymDraftChannel.action_methods` because ActionCable's test perform silently no-ops on missing actions).
- `test/models/soul_link_run_test.rb` — ADDED 6 new avatar-cache tests covering nil default, store-new, update-existing, no-op-on-unchanged-URL (`updated_at` doesn't churn), blank-URL-deletes-entry, and blank-uid-noop.

**Tests:** 343 → 370 (+27). 0 failures, 0 errors. In the brief's 25-30 range.

**Lint:** `bundle exec rubocop` clean (0 offenses across 152 files; +4 files = the 2 migrations + 1 helper + 1 helper test).

**TCG-coin path:** Primary attempt landed within budget. The modal uses a real two-face 3D coin: pokeball-front via stacked radial + linear gradients (red top, white bottom, black equator + central button), gold-edged via inset box-shadow, character-back as a gold disc with a star glyph (didn't burn time on Pikachu SVG craft — the star reads in-universe and matches the GameBoy palette). 1.8s `rotateY 0 → 1980deg` keyframe with cubic-bezier easing and a 12px translateY bounce in the last 200ms. NOT the fallback escape hatch.

**Manual smoke:** ran a `rails runner` harness (with `RAILS_ENV=test`) that walks lobby → voting → drafting → nominating → complete for all 5 tally splits using the real model methods. Output:
- 3/1 → status=complete, picks=6, tiebreak=nil ✓
- 2/2 → status=complete, picks=6, tiebreak=nil ✓
- 2/1/1 → status=complete, picks=6, tiebreak={"type"=>"second_place", "tied_group_ids"=>[B,C], "winners"=>[one of B/C]} ✓
- 1/1/1/1 → status=complete, picks=6, tiebreak={"type"=>"n_way", "tied_group_ids"=>[all 4], "winners"=>[2 of 4]} ✓
- 4/0 consensus → status=complete, picks=5 (slot 6 empty by design), tiebreak=nil ✓
- skip auth → non-nominator pre-grace raises with the expected message; current nominator and post-grace non-nominator both succeed (covered in unit tests too).
- broadcast_state → keys include `:candidates`, `:current_nominator_id`, `:current_turn_started_at`, `:nomination_picks_remaining`, `:tiebreak`; voters are stringified; `:current_nomination` key gone.

**Browser smoke gap (per Step 13 known issue):** `bin/dev` did not run cleanly in the sandbox (foreman/tailwind-v4 quirk that surfaced last step), so the live channel + JS + CSS animation was NOT exercised in a real browser this cycle. The TCG-coin animation, the per-second grace countdown tick, and the avatar pile image-vs-initial branch all benefit from browser eyeballing — Reviewer should flag whether this is acceptable for Step 14's surface area or whether an additional in-browser pass is required before merge. Coverage we DO have: the channel-test broadcast confirms the JSON shape the Stimulus controller depends on; the helper test confirms the server-rendered avatar HTML; the model tests confirm tiebreak payloads; the smoke harness confirms the resolution algorithm end-to-end.

**Key decisions (locked by Architect, executed verbatim):**
- **Unified `nominate!` action does both new-candidate and endorsement.** Server detects via `cands.find { |c| c["group_id"] == ... }`. Channel API takes only `{ group_id }`.
- **`Array#sample` is the resolution policy.** No weighted shuffles or seeded RNG. Tests assert tiebreak.winners is a subset of tied_group_ids, not a specific value.
- **1-candidate consensus (4/0) → 5-strong team intentionally.** Slot 6 stays empty. No "redo round" path.
- **Voters stored as integers in state_data; stringified only in broadcast_state.** Test asserts both directions (`broadcast_state stores voter ids as integers in state_data`).
- **Coin flip dedupes via `coinFlipShownFor`.** `render()` fires on every state update; the modal animates exactly once per resolution.
- **Skip auth in BOTH branches.** Inside grace: only nominator. Outside grace: anyone. Test covers both.
- **`current_turn_started_at` updated on every turn change.** `make_pick!` (transition into nominating), `nominate!` (each non-terminating call), `skip_turn!` (both drafting→nominating transition AND nominating-skip). Missing one breaks grace logic — verified in tests.

**Diff scope:** 1 model + 1 channel + 1 controller + 2 view files (1 major rewrite, 1 minor Q5 fix in the same file — all in show.html.erb) + 1 stylesheet + 1 helper (NEW) + 1 Stimulus + 1 SoulLinkRun model + 2 migrations + 4 test files (2 modified, 1 extended, 1 NEW) + 4 handoff files. Matches the brief's stated scope.

**Known Gaps logged this step:** none beyond the in-browser smoke gap above (which is a continuation of the Step 13 sandbox limitation, not a Step 14 regression).

---

### Step 13 — Undo Affordances on Gyms Tab: UNMARK + RESET DRAFT — 2026-05-01
**Status:** Awaiting review.

Two related "let me undo a mistake" affordances on the dashboard's Gyms tab:
- **UNMARK** button on the highest defeated gym row — backend was already in `GymProgressController#update` (toggles based on `GymResult` existence with a "highest only" guard). Step 13 is purely the UI surface.
- **RESET DRAFT** button in the Gyms-tab panel header (gated on an active draft) plus a confirmation modal mirroring `_mark_dead_modal.html.erb`. Backend is greenfield: new `GymDraftsController#destroy` with status guard + auth scoping via `run.gym_drafts.find_by(id:)`.

**Files created (3):**
- `app/views/dashboard/_reset_draft_modal.html.erb` — overlay + gb-modal scaffold byte-for-byte mirroring `_mark_dead_modal.html.erb`. Only copy + button labels + Stimulus action names + targets differ. Body copy is calm (matter-of-fact "This deletes the current draft and all picks") because the action is recoverable, unlike permadeath.
- `test/controllers/gym_progress_controller_test.rb` — NEW file (closes a pre-existing test gap; the controller had zero coverage). 5 tests: requires-login, mark gym beaten, unmark beaten, unmark-non-highest rejected, invalid gym number rejected. Same `login_as(GREY)` setup pattern as the rest of `test/controllers/`.

**Files modified (6):**
- `app/views/dashboard/_gyms_content.html.erb` — RESET DRAFT button in panel header gated on `@active_draft.present?`; UNMARK button on the defeated gym row gated on `num == @gyms_defeated` (the only gym the controller permits unmarking). Layout conditional: when UNMARK shows, the `Lv.` span uses `margin-left: 6px` so UNMARK eats the auto-margin slot; otherwise `Lv.` keeps `margin-left: auto`.
- `app/views/dashboard/show.html.erb` — one-line addition rendering the new modal partial.
- `app/controllers/dashboard_controller.rb` — load `@active_draft` next to other gym data (`@gym_results`). Same query as `GymDraftsController#create`: `run.gym_drafts.where(status: %w[lobby voting drafting nominating]).first`.
- `app/controllers/gym_drafts_controller.rb` — new `destroy` action. Auth via `run.gym_drafts.find_by(id:)` (mirrors `mark_beaten`). Status guard: `draft.status.in?(%w[lobby voting drafting nominating])`. Returns JSON `{ ok: true }` on success; 404 for missing/cross-guild; 422 for complete drafts.
- `app/javascript/controllers/dashboard_controller.js` — added 3 targets (`resetDraftModal`, `resetDraftStatus`, `resetDraftId`) and 3 methods (`openResetDraftModal`, `closeResetDraftModal`, `confirmResetDraft`). Mirrors the Mark Dead block byte-for-byte structurally; only the URL is hardcoded to `/gym_drafts/${draftId}` (no Stimulus value pre-wired for this single endpoint, and adding one would be over-engineering for a stable Rails convention).
- `config/routes.rb` — `:destroy` added to `resources :gym_drafts`. The `member { post :mark_beaten }` block stays unchanged.
- `test/controllers/gym_drafts_controller_test.rb` — extended with 3 new tests: destroy active draft (success), destroy complete draft (status guard 422), destroy cross-guild draft (404 via `run.gym_drafts.find_by` scoping).

**Key decisions (locked by Architect, executed verbatim):**
- **No confirm modal on UNMARK.** Light affordance; the action is recoverable (just re-mark beaten). Title attr is the only "are you sure?" hint.
- **RESET DRAFT uses `gb-btn-danger`** because destroying 4-6 rounds of picks is real data; the modal's CONFIRM RESET also uses `gb-btn-danger` to mirror the Mark Dead pattern.
- **UNMARK uses `gb-btn`** (default), not danger. Recoverable action — not signaling permadeath.
- **Status guard is belt-and-suspenders.** View gates via `@active_draft` (non-complete only); controller gates via `status.in?(%w[lobby voting drafting nominating])`. Both must remain — direct-curl bypass on a complete draft would otherwise nullify the `gym_results` foreign key.
- **Page reload after destroy, not turbo-stream.** Reset is a one-shot user action; full page reload picks up `@active_draft = nil` cleanly. `broadcasts_refreshes_to` on `GymDraft` is logged as future work, not Step 13 scope.
- **GymProgressController NOT modified.** The unmark backend already exists and is correct. The brief explicitly forbade touching it. The pre-existing JSON-response-on-HTML-form quirk (Mark Beaten returning `{"gyms_defeated":N}` rendered as a page in some browsers) is also out of scope per the brief.

**Tests:** 335 → 343 (+8). 0 failures, 0 errors. New tests:
- 5 in `gym_progress_controller_test.rb` (NEW file)
- 3 in `gym_drafts_controller_test.rb` (extension)

**Lint:** `bundle exec rubocop` clean (0 offenses across 148 files; +1 file = the new test file).

**Manual smoke:** verified all four flow steps via an ad-hoc render-condition harness (login + integration session + render at multiple data states). [A] 1 defeated → UNMARK appears on gym 1 row, no RESET DRAFT button, modal partial in DOM ready to open. [B] 2 defeated → UNMARK appears exactly once, positioned after GARDENIA's row marker (the gym 2 leader, not gym 1 ROARK). [C] lobby draft created → RESET DRAFT button appears in panel header with `data-draft-id` and `data-draft-status="lobby"` correctly populated. [D] draft set to complete → RESET DRAFT button disappears (the `@active_draft` view gate working). Backend behavior verified by the new controller tests; the JS reload-on-success path is covered by the response status (200 OK on destroy → `window.location.reload()` in the Stimulus action).

**Diff scope:** 1 new view, 1 new test file, 3 modified views, 2 modified controllers, 1 modified route, 1 modified JS, 1 extended test file, 4 handoff files. Matches the brief's stated diff scope exactly.

---

### Step 12 — KG-6: Map ID → Name Lookup (SRAM Phase 1 finish) — 2026-05-01
**Status:** Awaiting review.

Closes Knowledge Gap KG-6 from `handoff/PROJECT-REVIEW-2026-04-30.md`: render human-readable map names ("Eterna City") wherever the SRAM-parsed `parsed_map_id` surfaces in the UI. The architect estimated ~1 hour and called it the finish line for SRAM Phase 1's user-visible work.

**Pre-flight scope correction:** target-file reads revealed `parsed_map_id` is currently NOT rendered in any view (`grep -rn parsed_map_id app/views/` returns zero). It's stored in the DB and exposed via `slot_payload` JSON, but no template displays it. So Step 12 actually does both: (a) builds the lookup infrastructure and (b) wires the field into the existing run-roster + slot-card surfaces. Documented in REVIEW-REQUEST.

**Files created (3):**
- `config/soul_link/maps.yml` — Pokémon Platinum map header IDs → `{ name: "..." }` hashes. Header comment cites pret/pokeplatinum disassembly as the source and explicitly notes the IDs are unvalidated against a real `.sav` (KG-7 territory). 51 seed entries: 18 cities/towns, 18 routes (201-218), 15 dungeons/story locations, 2 special.
- `test/services/soul_link/game_state_maps_test.rb` — 8 tests using the same `Tempfile + with_maps_path` hermetic setup pattern as `game_state_cheats_test.rb`. Covers known/unknown/nil lookups, string→int coercion, missing-file fallback to `{}`, memoization (counted via `File.exist?` stub since Bootsnap intercepts `YAML.load_file`), `reload!` cache clear, and a sanity check that the real `maps.yml` ships with at least the gym towns (8 → "Eterna City", 7 → "Oreburgh City", 14 → "Snowpoint City").
- `test/helpers/emulator_helper_test.rb` — 9 tests. 5 backfill the existing `format_play_time` doc-comment examples as real assertions (including the negative-clamp-to-zero case that wasn't covered). 4 cover the new `format_map_name`: nil input, known ID via `GameState.stub`, unknown ID falls back to "Map #N", and the fallback works with small integer IDs.

**Files modified (4):**
- `app/services/soul_link/game_state.rb` — added `MAPS_PATH` constant alongside the others; added `maps` (file-existence-gated YAML loader) and `map_name(map_id)` (returns name or nil; coerces input via `to_i`); extended `reload!` to clear `@maps`. Methods placed between `location_name` and `players` to group thematically with location lookup.
- `app/helpers/emulator_helper.rb` — added `format_map_name(map_id)` next to `format_play_time`. Returns nil for nil input, the canonical name for known IDs, and `"Map ##{id}"` for unknown — informative enough for v1, also signals which entries to add to `maps.yml` as new IDs surface.
- `app/views/emulator/_run_sidebar_card.html.erb` — new "Map: <name>" line slotted between Money and Badges, gated on `active_slot&.parsed_map_id`. Renders only when the parser populated the field (currently never, until KG-7 validates the offset).
- `app/views/emulator/_save_slots_sidebar.html.erb` — same line in the slot card body, between Money and Badges, gated on `slot.parsed_map_id`.

**Key decisions:**
- **YAML hash shape `{ name: "..." }` over flat `id: name`.** The hash leaves room for future fields (`region:`, `dungeon: bool`) without breaking the API. Mirrors `locations.yml` and `gym_info.yml`.
- **Place lookup in `EmulatorHelper`, not in views directly.** Views call `format_map_name(slot.parsed_map_id)`; the helper handles nil, canonical name, and fallback in one place. Tests can stub `GameState.map_name` and exercise all branches.
- **Fallback string `"Map #N"`** — short, clear, matches the codebase's brevity (Badges shows as "Badges: 4 / 8", Money as "₱12,345"). Not "Unknown map (N)" (verbose) or just "#N" (ambiguous).
- **`maps.yml` IDs are best-effort, not authoritative.** The header comment ties this to KG-7 (real-save offset verification). When KG-7 lands, both validations happen together; until then, the fallback gracefully handles ID mismatches.
- **`map_name(map_id)` accepts integer or numeric-string input.** `.to_i` coercion handles JSON/params cases. Tests cover this.
- **Memoize test uses `File.exist?` counting**, not `YAML.load_file` counting. Bootsnap's `CompileCache::YAML::Psych4::Patch` is `prepend`ed onto `Psych`, intercepting `YAML.load_file` ahead of any singleton-class stub. Same workaround as `game_state_cheats_test.rb`. Documented inline.

**Tests:** 318 → 335 (+17). 0 failures, 0 errors.

**Lint:** `bundle exec rubocop` clean (0 offenses across 147 files). Same end state as Step 11 plus the new test files and the new helper method.

**Diff scope:** 1 new YAML, 1 model edit, 1 helper edit, 2 view edits, 2 new test files, 4 handoff files. Matches the brief.

---

### Step 11 — Enforce "One Active SoulLinkRun Per Guild" Invariant — 2026-05-01
**Status:** Awaiting review.

Closes a Tier-1-adjacent risk from `handoff/PROJECT-REVIEW-2026-04-30.md` Soft Point #3: `SoulLinkRun.current(guild_id)` previously relied on a soft contract (the `start_run` flow always deactivates the current run before creating a new one). The Step 6 fixture-coexistence pain and a potential race in `RunChannel#start_run` were both symptoms. Step 11 enforces the invariant at the database layer.

**Files created (1):**
- `db/migrate/20260501064907_enforce_single_active_run_per_guild.rb` — the migration. Three sections: (1) backfill check that raises `ActiveRecord::IrreversibleMigration` with a clear remediation message if any guild has multiple active runs; (2) `add_column :active_guild_id, :bigint, as: "(CASE WHEN active = 1 THEN guild_id END)"` — MySQL 8 virtual generated column; (3) `add_index :active_guild_id, unique: true`. NULLs (inactive rows) don't conflict in unique indexes, so multiple inactive runs per guild remain fine.

**Files modified (4):**
- `app/models/soul_link_run.rb` — added `validate :no_other_active_run_for_guild, if: -> { active? }` (friendly error counterpart to the DB constraint) and simplified `self.current(guild_id)` from `active.for_guild(guild_id).order(run_number: :desc).first` to `find_by(guild_id: guild_id, active: true)`. With the invariant, the order-and-first dance is unnecessary.
- `db/schema.rb` — auto-regenerated by Rails. Added `t.virtual "active_guild_id", type: :bigint, as: "(case when (...) end)"` and the unique index entry. Verified `db:rollback && db:migrate` produces the same dump.
- `test/models/soul_link_run_test.rb` — 8 new tests: validation rejects duplicate-active, validation accepts after deactivate, validation accepts different guilds, validation allows self-update without conflict, DB-level constraint catches raw-SQL bypass, `.current` returns the single active, `.current` returns nil for no-active, `.current` returns nil for unknown guild.
- `.rubocop.yml` — added per-cop `Exclude: ['db/schema.rb']` for `Layout/SpaceInsideArrayLiteralBrackets` because the Rails schema dumper produces tight `["foo"]` arrays that trip the omakase cop. Hand-formatting schema.rb is futile (every `db:migrate` regenerates it). Per-cop exclude is the cleanest fix.

**Key decisions:**
- **MySQL 8 virtual generated column over advisory locks or triggers.** Postgres has partial unique indexes (`UNIQUE INDEX ... WHERE active = true`) but MySQL doesn't. The CASE-expression virtual column + unique index achieves the same semantics. Cleaner than triggers (declarative), stronger than advisory locks (catches raw SQL too).
- **Backfill check raises hard.** If duplicates exist, the migration aborts with a message naming the offending `guild_id` and the cleanup query. The Project Owner decides which run to keep — the migration doesn't auto-coerce. Verified end-to-end locally: artificially created two active runs for guild 555..., ran migrate, observed the IrreversibleMigration with: "Cannot enforce one-active-run-per-guild: guild_id=555555555555555555: 2 active runs. Deactivate the extras manually before re-running, e.g. SoulLinkRun.where(guild_id: <id>, active: true).order(:run_number).limit(<n - 1>).update_all(active: false)". Cleaned up the test data and re-ran migrate cleanly.
- **Did NOT add a transaction wrapper around `RunChannel#start_run`.** The deactivate-then-create flow already produces the right outcome on the happy path. The new DB constraint catches the rare race. Adding an explicit transaction is a follow-up; not Step 11 scope.
- **Did NOT change `discord_bot.rb` or `lib/tasks/soul_link.rake` create-run flows.** Both follow the same deactivate-then-create pattern; the new constraint catches any bypass without code changes there.
- **Per-cop Exclude over AllCops:Exclude for `db/schema.rb`.** Tried `AllCops:Exclude: [db/schema.rb]` first, but the entry didn't take effect when inheriting from rails-omakase (its `inherit_mode: merge: [Exclude]` declaration didn't propagate as expected from a child config). The per-cop Exclude under `Layout/SpaceInsideArrayLiteralBrackets` works directly.

**Tests:** 310 → 318 (+8 invariant tests). 0 failures, 0 errors.

**Lint:** `bundle exec rubocop` clean (0 offenses across 145 files). Same as Step 10's end state plus the new migration and the schema dump.

**Migration verified:** ran `db:migrate → db:rollback → db:migrate` cycle in dev. Schema dump round-trips. Backfill safety belt verified by artificially creating dupe data.

**Diff scope:** 1 new migration + 1 model edit + 1 test edit + 1 schema dump + 1 rubocop config edit + 4 handoff files. The `.rubocop.yml` edit is one item beyond the brief's stated scope; it's a fallout of the Rails schema dumper's formatting choices, documented in REVIEW-REQUEST.

---

### Step 10 — UX Batch 2: Tier-B/C/D/E + YOU-badge follow-up + KG-5 — 2026-04-30
**Status:** Awaiting review.

Drew its punch-list from the unfinished items in `handoff/PROJECT-REVIEW-2026-04-30.md`. Ships 9 items: 1 Tier-B, 1 Tier-B, 1 Tier-C, 1 Tier-C, 1 Tier-D, 1 Tier-E, 1 Tier-E, 1 follow-up KG, 1 lint sweep KG.

**Pre-flight scope reductions (Architect):** during target-file reads, six PROJECT-REVIEW items turned out to already be handled in the codebase (the review was based on an earlier scan): B.6 (gym-draft button disable — all six handlers already disable buttons or set pointer-events on click), B.8 (run_management auto-dismiss — already at line 56), B.9 (no empty state for gym drafts — there's no index route, only show-by-ID after create), B.11 (no "no species assigned" placeholder — the per-player rows already show "Drop your species here"/"waiting..."), C.12 (form-label `for` mismatch — input already has matching `id`), and D.16 (save-slot hard-reload → turbo_stream — meaningful work, deferred). Documented in REVIEW-REQUEST.

**Items shipped:**

- **B.7 — Cancel button opacity.** Dropped misleading `style="opacity: 0.6;"` from the Cancel button in `gym_schedules/show.html.erb:66`. The button looked disabled but was fully clickable.
- **B.10 — Gym schedule form silent vanish.** Added an explanatory hint card when `@schedules.any?` so the propose-form doesn't disappear without context. Copy: "A schedule is already active. Cancel the active one below before proposing a new time."
- **C.13 — Avatar alt text.** `alt="avatar"` → `alt="<%= current_username %>'s avatar"` in `app/views/layouts/application.html.erb`.
- **C.14 — Modal close `aria-label`.** Added `aria-label="Close modal"` to all four `.gb-modal-close` buttons (pokemon modal, catch modal, species modal, quick-calc modal) plus `aria-label="Close panel"` to the map-show timeline panel close button (different control, equivalent semantic).
- **D.15 — Emulator mobile breakpoint.** Extracted `display: grid; grid-template-columns: 280px minmax(0, 1fr) 280px;` from inline-style into a new `.emulator-grid` class in `pixeldex.css`. Below 900px the grid stacks (`grid-template-columns: 1fr`); above 900px the three-column desktop layout returns. Players on mobile no longer see a negative-width canvas.
- **E.17 — Mark Dead custom modal.** Replaced the native `confirm()` in `dashboard_controller.js#markDead`. New partial `_mark_dead_modal.html.erb` (modeled on `_pokemon_modal.html.erb` structure: overlay + gb-modal + close button + content + actions). Wired three Stimulus actions: `openMarkDeadModal(event)` populates + shows, `confirmMarkDead()` fires the PATCH, `closeMarkDeadModal()` hides without firing. The pokemon modal's MARK DEAD button now calls `openMarkDeadModal` instead of the old `markDead`. Modal copy emphasizes Nuzlocke-permadeath ("Nuzlocke runs are irreversible") with the group nickname highlighted in `#e8a0a0` (danger-text palette).
- **E.18 — FALLEN tooltip.** Added `title="Pokemon that died this run"` to the `box-section-label` div in both `_pc_box_content.html.erb` and `_pc_box_panel.html.erb`. Two-line edits.
- **YOU-badge restoration (Step 9 follow-up KG).** New file `app/javascript/controllers/roster_you_marker_controller.js` — small Stimulus controller mounted on the run-sidebar wrapper. On `connect()` and on `turbo:before-stream-render` it walks `[data-discord-user-id]` cards and decorates the matching one with a YOU badge + `gb-card--current-user` CSS class (4px-border). The roster card partial gained `data-discord-user-id="<%= s.discord_user_id %>"`. Solves the Step 9 regression cleanly client-side without passing `current_user_id` into a model callback. Step 9's broadcast-test partial-render assertion was extended to verify the data attribute survives.
- **KG-5 — Rubocop autocorrect sweep.** Ran `bundle exec rubocop -a` (safe autocorrect only, NOT `-A`). 144 files inspected, 121 offenses corrected. Most are `Layout/SpaceInsideArrayLiteralBrackets` (the rails-omakase preference for `[ a, b ]` over `[a, b]`). Post-sweep: **0 offenses** across the entire codebase. 310/310 tests still green.

**Files modified (52):**
- View edits (manual, 11 files): `gym_schedules/show.html.erb`, `gym_schedules/index.html.erb`, `layouts/application.html.erb`, `dashboard/_pokemon_modal.html.erb`, `dashboard/_catch_modal.html.erb`, `dashboard/_pc_box_content.html.erb`, `dashboard/_pc_box_panel.html.erb`, `dashboard/show.html.erb`, `species_assignments/show.html.erb`, `teams/_quick_calc_modal.html.erb`, `map/show.html.erb`, `emulator/show.html.erb`, `emulator/_run_sidebar.html.erb`, `emulator/_run_sidebar_card.html.erb`
- JS edits (manual, 1 file): `app/javascript/controllers/dashboard_controller.js` (Mark Dead flow)
- CSS edits (manual, 1 file): `app/assets/stylesheets/pixeldex.css` (emulator-grid + .gb-card--current-user)
- Tests (1 file): `test/models/soul_link_emulator_save_slot_test.rb` (extended partial-render test)
- Rubocop autocorrect: 38 additional Ruby files (see git diff for full list — diffs are pure whitespace / style)

**Files created (2):**
- `app/views/dashboard/_mark_dead_modal.html.erb` — Mark Dead confirmation modal
- `app/javascript/controllers/roster_you_marker_controller.js` — YOU-badge restoration controller

**Key decisions:**
- **`window.alert()` carry-over.** Step 9's Tier-A error toasts use `window.alert()`. Step 10 didn't add new alerts; the Mark Dead custom modal supersedes the worst confirm()-based UX. A styled toast component is still a future polish item.
- **Mark Dead modal lives in the dashboard layout, not the pokemon modal.** Two separate modals, both reachable. The pokemon modal's MARK DEAD button just opens the new modal; both modals can be open simultaneously (the Mark Dead modal has higher z-index 60 vs pokemon modal's 50). Closing the Mark Dead modal returns the user to the pokemon modal context.
- **YOU-badge controller injects the badge dynamically rather than rendering it server-side.** This keeps the broadcast-rendered partial context-free (no current_user_id needed in model callbacks). The badge gets re-applied on each `turbo:before-stream-render` so it survives broadcasts.
- **Rubocop autocorrect on `if / else / end` patterns produces visually-awkward (but functionally identical) indentation in a few files** (e.g., `discord_bot.rb:251-261`). The `Layout/EndAlignment` cop fixed `else`/`end` alignment to match the `if` opener, but didn't reindent the bodies between them. Code is correct; tests pass; visually less readable in those spots. Logged as a follow-up cleanup item below.
- **Pre-existing rubocop offenses fully closed.** The Step 1 BUILD-LOG known gap noted "133 across 127 files"; Step 10 brought that to **0**. Future CI gating on rubocop is now a small lift.

**Tests:** 310/310 passing (no test count change). 0 failures, 0 errors. The extended `run_sidebar_card partial renders standalone` test now also asserts `data-discord-user-id=` is present.

**Lint:** `bundle exec rubocop` reports 0 offenses across 144 files. Down from ~133 pre-Step-10.

**Diff scope:** 50 files changed (~13 manual + 38 autocorrect + 4 handoff docs). 2 new files.

---

### Step 9 — UX Batch: Tier-A Silent-Failure Fixes + KG-1/2/3/4 — 2026-04-30
**Status:** Awaiting review.

Drew its punch-list directly from `handoff/PROJECT-REVIEW-2026-04-30.md`. Ships 9 items in one focused step:

**Tier-A silent-failure fixes (5 items):**
- **A.1 — `save_slots_controller.js` user-facing toasts.** Every error branch in `makeActive`, `deleteSlot`, `overwriteSlot` (5 `console.error` sites) now also fires `window.alert(...)` with an actionable message ("contact the run creator").
- **A.2 — `gym_draft_controller.js` error banner.** `handleMessage` now calls a new `showError(message)` method that renders `errorBannerTarget` for 8 seconds, falling back to `alert()` if the target isn't present. Added `errorBanner` to the static targets and a `<div data-gym-draft-target="errorBanner" hidden>` in `gym_drafts/show.html.erb`.
- **A.3 — `team_builder_controller.js` pixeldex status classes.** Replaced Tailwind `text-yellow-400`/`green-400`/`red-400` (which were silently no-ops in the dashboard layout) with semantic `team-builder-status--saving`/`saved`/`error` modifiers wired through new `.team-builder-status` rules in `pixeldex.css`. Save status is now visible.
- **A.4 — Save-slot action buttons disabled in overwrite-pending mode.** `_enterOverwriteMode` and `_exitOverwriteMode` now toggle `disabled` on every `[data-action*='save-slots#makeActive'], [data-action*='save-slots#deleteSlot']` button via a new `_actionButtons()` helper. Tab-focus + screen-reader paths can no longer trigger Delete during an overwrite flow.
- **A.5 — Pokemon modal SAVE button disable in-flight.** `pixeldex_controller.js#savePokemon(event)` now disables the click target before the first PATCH and re-enables on every error-return path. Success path leaves it disabled (page reloads anyway). `evolvePokemon` (KG-3 below) gets the same treatment.

**Knowledge Gap closures:**
- **KG-1 — Real-time roster sidebar.** Extracted `app/views/emulator/_run_sidebar_card.html.erb` (single-session card) from `_run_sidebar.html.erb`. Wrapped each session render in `turbo_frame_tag "emulator_roster_session_#{s.id}"`. Added `turbo_stream_from @run, :emulator` to the emulator show page. `SoulLinkEmulatorSaveSlot` gained `after_create_commit :broadcast_roster_card_on_create` and `after_update_commit :broadcast_roster_card_on_update, if: :saved_change_to_parsed?` — both call a shared `broadcast_roster_card` helper that issues `Turbo::StreamsChannel.broadcast_replace_to([run, :emulator], target: "emulator_roster_session_#{session.id}", partial: "emulator/run_sidebar_card", locals: { s: session })`. After the SRAM parse job writes a slot's parsed_* fields, every viewer's emulator page sees that session's roster card refresh without a full page reload (which would tear down the running emulator iframe).
- **KG-2 — Real-time dashboard.** Added `broadcasts_refreshes_to ->(record) { [ record.soul_link_run, :dashboard ] }` to `SoulLinkPokemon` and `SoulLinkPokemonGroup`. Dashboard show page subscribes via `turbo_stream_from @run, :dashboard` and configures `turbo_refreshes_with method: :morph, scroll: :preserve` so the page morphs in place rather than full-reloading. Pokemon edits / group status changes propagate across all open dashboards in the run.
- **KG-3 — EVOLVE button loading state.** `evolvePokemon(event)` now disables the button + sets text to "EVOLVING..." on click; re-enables + restores text on error-return paths. Success path reloads.
- **KG-4 — `--amber` palette token.** Added `--amber: #d4b14a;` to `:root` in `pixeldex.css`. Replaced the inline `#d4b14a` literal in `_run_sidebar.html.erb` (status-pill background for pending/generating sessions) with `var(--amber)`. The new `team-builder-status--saving` class also references it.

**Files modified (12):**
- `app/javascript/controllers/save_slots_controller.js` — A.1 toasts + A.4 button disable in overwrite mode + helper method
- `app/javascript/controllers/gym_draft_controller.js` — A.2 errorBanner target + showError method
- `app/javascript/controllers/team_builder_controller.js` — A.3 pixeldex modifier classes
- `app/javascript/controllers/pixeldex_controller.js` — A.5 SAVE disable + KG-3 EVOLVE loading state
- `app/models/soul_link_emulator_save_slot.rb` — KG-1 broadcast callbacks (two distinct method names to avoid Rails callback dedup; documented inline)
- `app/models/soul_link_pokemon.rb` — KG-2 broadcasts_refreshes_to
- `app/models/soul_link_pokemon_group.rb` — KG-2 broadcasts_refreshes_to
- `app/views/emulator/show.html.erb` — KG-1 turbo_stream_from
- `app/views/emulator/_run_sidebar.html.erb` — KG-1 frame wrap + KG-4 amber token (also dropped YOU badge / 4px-border, see Known Gap below)
- `app/views/dashboard/show.html.erb` — KG-2 turbo_refreshes_with + turbo_stream_from
- `app/views/gym_drafts/show.html.erb` — A.2 errorBanner target div
- `app/assets/stylesheets/pixeldex.css` — KG-4 amber token + A.3 team-builder-status classes

**Files created (1):**
- `app/views/emulator/_run_sidebar_card.html.erb` — single-session card partial that renders cleanly with only `s` (the session) as a local

**Test changes (2 files):**
- `test/models/soul_link_emulator_save_slot_test.rb` — added 5 new tests for KG-1 broadcasts: create broadcasts to `[run, :emulator]`, update on parsed_* broadcasts, update_columns does NOT broadcast (callbacks bypassed), update on non-parsed field does NOT broadcast, partial renders standalone with only `s` local. Pulled in `Turbo::Broadcastable::TestHelper` (with explicit `require "turbo/broadcastable/test_helper"`).
- `test/controllers/emulator_controller_test.rb` — renamed "show roster renders player names, YOU badge, and Unclaimed entries" to "show roster renders player names and Unclaimed entries"; dropped the `assert_match(/>YOU</)` line + comment explaining why (Known Gap, see below).

**Key decisions:**
- **`broadcasts_refreshes_to` for pokemon + group, but `broadcast_replace_to` for save_slot.** Different scope: pokemon/group changes affect many areas of the dashboard, so a Turbo morph refresh is right. Save-slot updates only affect the per-session roster card on the emulator page; a page refresh would tear down the running emulator iframe, so we use targeted frame replacement.
- **Two distinct callback method names on `SoulLinkEmulatorSaveSlot` (`broadcast_roster_card_on_create` vs `broadcast_roster_card_on_update`).** Rails dedupes callback registrations by method name across lifecycle events: registering the SAME method on both `after_create_commit` and `after_update_commit` keeps only the second registration. Splitting into two methods that delegate to a shared helper is the workaround. Documented inline.
- **Turbo test helper requires explicit require + include.** `Turbo::Broadcastable::TestHelper` isn't auto-loaded; the test file explicitly `require "turbo/broadcastable/test_helper"` and `include`s it. Tests that diff "before vs after" broadcast count (because `assert_turbo_stream_broadcasts` captures the entire test's broadcast history, not just the block) use `capture_turbo_stream_broadcasts` and explicit count math.
- **YOU badge / 4px-border dropped from the run roster.** Preserving them across Turbo Stream broadcasts would require either passing `current_user_id` into a model callback (a layer violation) or rendering markers outside the frame in DOM-fragile ways. The `player_label` still disambiguates which card is theirs. Logged as Known Gap below.
- **`window.alert()` for Tier-A toasts.** Smallest user-facing change that closes the silent-failure gap. A proper styled toast component is out of scope; future polish step can replace.

**Tests:** 305 → 310 (+5 broadcast tests for save_slot model). 0 failures, 0 errors.

**Lint:** `bundle exec rubocop` clean on all 5 touched Ruby files (3 models, 2 tests).

**Diff scope:** 12 modified, 1 created (the new partial), plus `handoff/PROJECT-REVIEW-2026-04-30.md` (created in the prior session, committed here as it's the input doc for Step 9), and the four handoff docs (`ARCHITECT-BRIEF.md`, `BUILD-LOG.md`, `REVIEW-REQUEST.md`, `REVIEW-FEEDBACK.md`).

---

### Step 8 — Final Sweep: Delete Fixtures + Drop Hybrid Convention — 2026-04-30
**Status:** Awaiting review.

**Files deleted (7 fixture YAMLs):**
- `test/fixtures/gym_drafts.yml`
- `test/fixtures/gym_results.yml`
- `test/fixtures/soul_link_pokemon.yml`
- `test/fixtures/soul_link_pokemon_groups.yml`
- `test/fixtures/soul_link_runs.yml`
- `test/fixtures/soul_link_team_slots.yml`
- `test/fixtures/soul_link_teams.yml`

`test/fixtures/files/` (ActiveStorage attachment dir) preserved.

**Files modified:**
- `test/test_helper.rb` — dropped the `fixtures :all` line + the comment block above it; updated the FactoryBot-syntax comment to no longer mention "Legacy fixture-based tests" coexistence (no longer true). Also fixed 1 pre-existing rubocop offense on line 36 (`Layout/SpaceInsideArrayLiteralBrackets` on the Faraday stub `fake_response` line) to satisfy the touched-files-clean acceptance criterion.
- `CLAUDE.md` — Testing-conventions section: replaced the 2-bullet "New tests / Legacy tests" hybrid note with a single bullet "All tests use FactoryBot factories from `test/factories/`. Fixtures (`test/fixtures/*.yml`) were removed during the 2026-04-30 conversion sweep." Factories-minimum-viable bullet preserved.
- `handoff/BUILD-LOG.md` — durable § Architecture Decisions § Carried over: replaced the legacy-fixture line with "All tests use FactoryBot factories from `test/factories/`. Fixtures and the `fixtures :all` test_helper line were removed in Step 8 (2026-04-30)."
- 7 controller tests (`emulator`, `save_slots`, `species_assignments`, `teams`, `pokemon`, `pokemon_groups`, `gym_drafts`) — removed the dead `SoulLinkRun.where(guild_id: LoginHelper::GUILD_ID).destroy_all` line from each setup. Removed the explanatory 4-line comment block from `emulator_controller_test.rb`. Also removed the dead in-test `SoulLinkTeam.where(discord_user_id: GREY).destroy_all` line + comment from `teams_controller_test.rb`'s "show creates team if none exists" test.

**Files renamed:**
- `handoff/parked-plans/factorybot-conversion.md` → `handoff/archive/2026-04-30-factorybot-conversion.md` via `git mv`. Added `> Status: COMPLETE` marker at top with commit references for Steps 4-8. The original discovery-doc body is preserved as historical record. `handoff/parked-plans/` is now empty.

**Files modified (handoff):**
- `handoff/ARCHITECT-BRIEF.md` — Step 8 brief (overwritten from Step 7)
- `handoff/REVIEW-REQUEST.md` — Step 8 review request
- `handoff/REVIEW-FEEDBACK.md` — Reviewer's Step 8 verdict

**Key decisions:**
- **`git mv` for the parked-plan archive** so the move shows as a rename in `git log --follow`. Matches the existing archive convention (`2026-04-12-pixeldex-calculator.md`, `2026-04-29-emulator-deploy-and-polish.md`) — date-prefixed, descriptive filename.
- **Pre-existing rubocop offense in `test_helper.rb:36` fixed.** Same lesson as Step 5/6/7 — when a file is touched, fix any rubocop offenses surfaced on it. Pre-existing offenses outside touched files remain (Known Gap from Step 1).
- **Bulk fixture deletion via `git rm`** so the deletions show as deletions in the diff (vs untracked-removal). User explicitly OK'd these — "the fixture deletions are bulk file removals from a versioned directory — that IS the work, not a destructive accident."
- **`parallelize(workers: :number_of_processors)` preserved** in test_helper. The Step 5/6/7/8 conversion work doesn't change parallelization semantics; only fixture loading was removed.
- **`test/fixtures/files/.keep` preserved.** Standard Rails ActiveStorage attachment fixture dir; unrelated to the YAML conversion.

**Tests:** 305/305 passing. Per-file counts unchanged from Step 7.

**Flake check:** 20 reps total. 19 clean reps, 1 transient failure on the very first rep (seed 13579) that did not reproduce when re-run with the same seed or across 19 subsequent runs (5 fresh + 10 more + 5 more). The lost stacktrace prevented identifying the specific test, but the failure-rate dropped to 0/19 ≈ 0% post-discovery, suggesting a one-time timing artifact (possibly fresh-cache or disk contention from the earlier rubocop run / file-write boundary) rather than a systemic race. The `parallelize(workers: :number_of_processors)` setup uses Rails' default per-worker test database isolation, so cross-fork uniqueness conflicts on `(guild_id, run_number)` shouldn't manifest. Documented for transparency; not a Condition.

**Lint:** `bundle exec rubocop` clean on all 8 touched test files (test_helper.rb + 7 controller tests). The pre-existing offense in test_helper.rb:36 was fixed (4-character whitespace change).

**Diff scope:** 7 controller test files modified, `test/test_helper.rb` modified, 7 fixture YAMLs deleted, `CLAUDE.md` modified, `handoff/BUILD-LOG.md` modified (durable section + Step 8 entry), `handoff/REVIEW-REQUEST.md` modified, `handoff/REVIEW-FEEDBACK.md` modified, `handoff/ARCHITECT-BRIEF.md` modified, parked plan moved from `handoff/parked-plans/` to `handoff/archive/2026-04-30-factorybot-conversion.md`. App code, factories, channel test, ActiveStorage `files/` dir all untouched.

**Conversion summary:** Steps 4-8 converted the entire test suite from fixture-based to FactoryBot:
- Step 4 (`6e2c8c8`): built 6 missing factories with traits matching every fixture row
- Step 5 (`efcc659`): converted 3 model unit tests (gym_draft, gym_result, soul_link_pokemon)
- Step 6 (`f7203b0`): converted 8 controller tests + 1 missed model test (soul_link_pokemon_group); discovered + handled the fixture-coexistence constraint
- Step 7 (`a18a27f`): converted 1 channel test (gym_draft_channel)
- Step 8 (this commit): deleted fixtures, dropped `fixtures :all`, updated CLAUDE.md + durable BUILD-LOG decision, removed dead defensive code from Step 6, archived parked plan, ran 20-rep flake check

305/305 tests pass; suite is FactoryBot-only.

---

### Step 7 — Convert Channel Test from Fixtures to FactoryBot — 2026-04-30
**Status:** Awaiting review.

**Files modified (1):**
- `test/channels/gym_draft_channel_test.rb` — setup replaced with the proven Step 5 pattern: `@run = create(:soul_link_run)`, `@groups = %i[route201..route206].map { |t| create(:soul_link_pokemon_group, t, soul_link_run: @run) }`, `@draft = create(:gym_draft, :lobby, soul_link_run: @run)`. The channel-specific `stub_connection(current_user_id: GREY)` line stays at the end of setup. All 9 test bodies + 3 private helpers (`move_to_voting!` / `move_to_drafting!` / `move_to_nominating!`) unchanged. Also fixed 1 pre-existing rubocop offense on line 8 (`Layout/SpaceInsideArrayLiteralBrackets` on `ALL_PLAYERS = [GREY, ARATY, SCYTHE, ZEALOUS]`). Test count: 9 (unchanged).

**Files modified (handoff):**
- `handoff/ARCHITECT-BRIEF.md` — Step 7 brief (overwritten from Step 6)
- `handoff/BUILD-LOG.md` — this entry
- `handoff/REVIEW-REQUEST.md` — Step 7 review request
- `handoff/REVIEW-FEEDBACK.md` — Reviewer's Step 7 verdict

**Key decisions:**
- **No `destroy_all` guild guard.** Channel tests bypass HTTP — `stub_connection(current_user_id: GREY)` sets the connection identifier directly, the channel looks up the draft via `params[:draft_id]`, never goes through `SoulLinkRun.current(guild_id)`. The Step 6 controller-coexistence guard would be cargo-cult here. Architect brief explicitly forbade it; Builder verified by running the test green without it.
- **Setup pattern is identical to Step 5's `gym_draft_test.rb`** (the model unit test for the same draft state machine). Only difference is the trailing `stub_connection` line. This matches the architect's "channel tests have a distinct subscribe + perform setup" guidance — the data setup is the same, only the channel test machinery differs.
- **Pre-existing rubocop fix.** `ALL_PLAYERS = [GREY, ARATY, SCYTHE, ZEALOUS].freeze` → `[ GREY, ARATY, SCYTHE, ZEALOUS ]`. Same offense + same fix as Step 5's `gym_draft_test.rb`. Two-character whitespace change.

**Tests:** 305/305 passing across the full suite. Per-file: 9/9 (unchanged). 0 failures, 0 errors.

**Lint:** `bundle exec rubocop test/channels/gym_draft_channel_test.rb` clean.

**Diff scope:** 1 test file + 4 handoff files. App code, fixtures, factories, test_helper.rb, all other test files untouched.

**Fixture-helper grep verification:** zero matches in the converted file. **Across the entire `test/` tree, ZERO files use fixture helpers** — Step 7 closes out the test-side conversion. Step 8 is now purely mechanical: delete `test/fixtures/*.yml`, drop `fixtures :all` from `test_helper.rb`, update `CLAUDE.md`'s testing convention section, run a flake check.

---

### Step 6 — Convert 8 Controller Tests + 1 Missed Model Test — 2026-04-30
**Status:** Awaiting review.

**Files modified (9):**
- `test/models/soul_link_pokemon_group_test.rb` — setup creates `@run`, `@group` (route201 trait), and 4 player pokemon (`:route201_grey/aratypuss/scythe461/zealous`). Required for `species_for` and `complete?` tests. 7 tests, unchanged.
- `test/controllers/emulator_controller_test.rb` — setup destroys fixture run for guild + creates factory run. 44 tests, unchanged. Heaviest controller file by test count.
- `test/controllers/save_slots_controller_test.rb` — same destroy-then-create setup pattern. 33 tests, unchanged.
- `test/controllers/species_assignments_controller_test.rb` — setup pattern + inline seed of route201 group + grey-pokemon in the duplicate-rejection test. 5 tests, unchanged.
- `test/controllers/teams_controller_test.rb` — setup pattern + inline group/pokemon seeds in `update_slots saves valid group ids` and `update_slots rejects more than 6`. The "rejects more than 6" test seeds 6 groups with grey-pokemon + 1 group without (so the 7th gets filtered by `allowed_ids`, mirroring the fixture-era invariant where `.limit(7).pluck(:id)` returned 6). Also fixed 1 pre-existing rubocop offense on a non-touched line for acceptance criterion. 6 tests, unchanged.
- `test/controllers/pokemon_controller_test.rb` — setup pattern + inline route201 group + grey/aratypuss seeds in two tests. 5 tests, unchanged.
- `test/controllers/pokemon_groups_controller_test.rb` — setup pattern + inline route206 group in two tests. 6 tests, unchanged.
- `test/controllers/gym_drafts_controller_test.rb` — setup builds `@run`, `@draft` from `:lobby` trait; "type analysis" test seeds 6 groups via `%i[route201..route206].map`. Same pattern as Step 5's gym_draft model test. 5 tests, unchanged.

**Files modified (handoff):**
- `handoff/ARCHITECT-BRIEF.md` — Step 6 brief (overwritten from Step 5)
- `handoff/BUILD-LOG.md` — this entry
- `handoff/REVIEW-REQUEST.md` — Step 6 review request
- `handoff/REVIEW-FEEDBACK.md` — Reviewer's Step 6 verdict

**Key decisions:**
- **Discovered constraint: fixture run still loads via `fixtures :all` and shares guild_id with the factory.** Two `active: true` runs for guild 999... coexist; `SoulLinkRun.current(guild_id)` orders by `run_number desc` and returns the factory run (run_number 1000+n) by default — but tests that deactivate `@run` and expect "no active run" fall back to the fixture (run_number 1) instead. Fix applied in every controller test's setup: `SoulLinkRun.where(guild_id: LoginHelper::GUILD_ID).destroy_all` before `create(:soul_link_run)`. Step 8 deletes the fixtures and the destroy_all becomes a no-op. The model test (`soul_link_pokemon_group_test`) doesn't go through HTTP, so it doesn't need this guard.
- **`teams_controller_test` "update_slots rejects more than 6" test honesty.** The original fixture-era test asserted SUCCESS while named "rejects more than 6" — relying on the fact that `.limit(7).pluck(:id)` returned only 6 IDs (only 6 groups existed) and thus passed under MAX_SLOTS. Direct conversion (seeding 7 groups with grey-pokemon) made `allowed_ids` = 7 and the controller correctly returned 422. Fixed by seeding 6 groups with grey-pokemon + 1 group without — the 7th gets filtered by `allowed_ids`, leaving 6 valid IDs that fit under MAX_SLOTS. Preserves test name, assertion, and intent (the controller silently caps via filter, not 422).
- **`soul_link_pokemon_group_test`'s `set_position auto-increments` test** asserts `g2.position > g1.position`. Pre-conversion the run had 6 fixture groups so the new ones got positions 7+8. Post-conversion only @group exists (position 1) so the new ones get positions 2+3. Assertion `3 > 2` still holds.
- **One pre-existing rubocop offense fixed** in `teams_controller_test.rb:65` (`Layout/SpaceInsideArrayLiteralBrackets`). Same lesson as Step 5 — fix to satisfy "rubocop clean" acceptance criterion. Documented as 2-character whitespace change.

**Tests:** 305/305 passing across the full suite. Per-file: 7 / 44 / 33 / 5 / 6 / 5 / 6 / 5 = 111 across the 8 controller/model files (the brief's preliminary counts undercounted emulator at 36 and teams at 5; actuals are 44 and 6 respectively, both unchanged from pre-conversion). 0 failures, 0 errors.

**Lint:** `bundle exec rubocop` clean on all 8 modified files (model + 7 controllers).

**Diff scope:** 9 test files + 4 handoff files. App code, fixtures, factories, test_helper.rb, channel test all untouched.

**Fixture-helper grep verification:** zero matches in the 9 converted files. After Step 6, the only remaining fixture-helper user in `test/` is `test/channels/gym_draft_channel_test.rb` (Step 7 target).

---

### Step 5 — Convert Model Unit Tests from Fixtures to FactoryBot — 2026-04-30
**Status:** Awaiting review.

**Files modified (3, all under `test/models/`):**
- `soul_link_pokemon_test.rb` — added `setup` block creating `@run` / `@group_201` / `@group_202` / `@pokemon`; replaced 9 fixture-helper calls with ivar references; renamed "fixture pokemon is valid" → "factory pokemon is valid" per brief. Test count preserved at 7.
- `gym_draft_test.rb` — replaced `setup` block with factory creates: `@run = create(:soul_link_run)`, `@groups = %i[route201..route206].map { |t| create(:soul_link_pokemon_group, t, soul_link_run: @run) }`, `@draft = create(:gym_draft, :lobby, soul_link_run: @run)`. The 22 test bodies (Architect's brief said 21 — it was always 22; minor undercount, not a deviation) and 3 private helpers (`move_to_voting!` / `move_to_drafting!` / `move_to_nominating!`) unchanged. Fixed 2 pre-existing rubocop offenses (`Layout/SpaceInsideArrayLiteralBrackets` on lines `ALL_PLAYERS = [ ... ]` and `assert_includes [ GREY, ARATY ], ...`) since the brief required clean lint.
- `gym_result_test.rb` — added `@groups` array creation in `setup` (parallels gym_draft pattern), inline-seeded 6 pokemon (one per group via `:routeNNN_grey` traits) inside the `snapshot_from_groups` test so `.limit(2)` finds groups with pokemon regardless of DB row order. Test count preserved at 4.

**Files modified (handoff):**
- `handoff/ARCHITECT-BRIEF.md` — Step 5 brief (overwritten from Step 4)
- `handoff/BUILD-LOG.md` — this entry
- `handoff/REVIEW-REQUEST.md` — Step 5 review request
- `handoff/REVIEW-FEEDBACK.md` — Reviewer's Step 5 verdict (added during this same session)

**Key decisions:**
- **Inline pokemon seeding in `gym_result_test.rb` snapshot test, not setup.** The test was the only one needing pokemon. Inline keeps the setup block clean for the other 3 tests in the file. Used `each_with_index` over the trait list to seed all 6 groups (matches fixture-era state where every group had pokemon — the original `.limit(2)` worked because all groups had pokemon, regardless of which 2 were picked).
- **Did NOT add `.order(:id)` to the snapshot test's `.limit(2)` query.** Brief said preserve assertions/queries. Seeding all 6 groups removes the ordering dependency without touching the test's query shape. First attempt (seed only `@groups[0]` and `@groups[1]`) failed because `.limit(2)` returned different groups; the all-6-seed fix is more robust and keeps the original query untouched.
- **Renamed "fixture pokemon is valid" → "factory pokemon is valid"** (per brief). All other test names unchanged.
- **Fixed 2 pre-existing `Layout/SpaceInsideArrayLiteralBrackets` offenses** in gym_draft_test (lines 8 + 83). Pre-existing in the file before Step 5; brief required rubocop clean on touched files. Two-line whitespace adjustment.
- **Did NOT touch fixtures, factories, test_helper.rb, or any other test file.** Step 6 will handle those.

**Tests:** 305/305 passing (file-level: 7 + 22 + 4 = 33; full suite 305). 0 failures, 0 errors. Ran each file individually post-conversion (per brief sequencing) and full suite at the end.

**Lint:** `bundle exec rubocop test/models/soul_link_pokemon_test.rb test/models/gym_draft_test.rb test/models/gym_result_test.rb` clean.

**Diff scope check:** `git status` shows only `handoff/ARCHITECT-BRIEF.md` + 3 test files modified (plus this BUILD-LOG and the two REVIEW docs as the step closes). App code, fixtures, factories, test_helper.rb, other test files all untouched per brief.

**Fixture-helper grep verification:** `grep -nE "soul_link_pokemon\(|soul_link_runs\(|soul_link_pokemon_groups\(|gym_drafts\(|gym_results\(" test/models/{soul_link_pokemon,gym_draft,gym_result}_test.rb` returns zero matches.

---

### Step 4 — Build All Missing FactoryBot Factories — 2026-04-30
**Status:** Complete, committed `6e2c8c8`, pushed to `origin/claude/gallant-bell-cb4390`. Test-only — no deploy required.

**Files created (6, all under `test/factories/`):**
- `soul_link_pokemon_groups.rb` — base factory + 6 named traits (`:route201`–`:route206`). Each trait sets `nickname`/`location`/`status` via attribute assignment and uses `after(:create) update_columns(position:, caught_at:)` to **override** the model's `before_create :set_position` and `:set_caught_at` callbacks (fixtures bypass these via raw SQL; the override reproduces fixture state exactly).
- `soul_link_pokemon.rb` — base factory + **24 metaprogrammed traits** (`:route201_grey`, `:route201_aratypuss`, …, `:route206_zealous`). Inner loop closes over a per-iteration `trait_species`/`trait_uid`/`trait_location` to avoid late-binding bugs. Data tables (`SOUL_LINK_POKEMON_PLAYERS`, `SOUL_LINK_POKEMON_ROUTES`) sit at top of file as constants for parity with the fixture's ERB shape.
- `soul_link_teams.rb` — base factory + `:grey_team` trait. Base uses `sequence(:discord_user_id)` to dodge the `(soul_link_run_id, discord_user_id)` uniqueness constraint when tests build multiple teams.
- `soul_link_team_slots.rb` — `:slot_1` / `:slot_2` traits only. **No association defaults** — the brief specifies callers pass `soul_link_team:` and `soul_link_pokemon_group:` explicitly (`create(:soul_link_team_slot, :slot_1, soul_link_team: t, soul_link_pokemon_group: g)`).
- `gym_drafts.rb` — base factory + `:lobby` trait. Both pin `status: "lobby"`, `current_round: 0`, `current_player_index: 0`, `pick_order: []`, `state_data: { ready_players, first_pick_votes, picks }` to match fixture and the model's `after_initialize :set_defaults` shape.
- `gym_results.rb` — base factory only (fixture is empty). `sequence(:gym_number) { |n| ((n - 1) % 8) + 1 }` cycles 1..8 to honor the `(soul_link_run_id, gym_number)` uniqueness constraint without colliding for the first 8 calls per run.

**Files modified:** none. Per the brief, Step 4 is purely additive — fixtures, tests, and app code are all left untouched. Step 5 will convert tests; Step 6 deletes fixtures.

**Key decisions:**
- **Pokemon factory metaprogramming pattern.** 24 traits hardcoded would be unreadable. Used a nested `each_with_index` loop, captured each trait's bindings into local variables (`trait_species`, `trait_uid`, `trait_location`) BEFORE entering the trait block to avoid the classic Ruby-closure late-binding bug where every trait would resolve to the final loop iteration's data.
- **Group factory's `after(:create) update_columns` is intentional.** The model has `before_create :set_position` (assigns max+1) and `before_create :set_caught_at` (assigns Time.current). Without `update_columns`, calling `create(:soul_link_pokemon_group, :route201)` would produce a record whose `position` reflects creation order, not the fixture's hardcoded `1`. `update_columns` skips callbacks/validations and writes raw — the same effect fixtures achieve via raw SQL INSERT.
- **Gym draft trait redundant with base.** Both base factory and `:lobby` trait set the same five attributes. The brief said "the trait pins those values explicitly to keep the trait's intent self-documenting"; followed verbatim. Future Step 5 conversions will likely call `create(:gym_draft, :lobby)` — the trait surfaces intent at the call site even when the values match the default.
- **Team slot factory has no association defaults.** Brief decision: caller-provided is correct because slot rows only make sense when bound to a specific team and group already constructed in the test's setup. A factory default would either create orphan associations or shadow the test's intended team/group references.
- **`gym_result.gym_number` sequence wraps modulo 8.** Strictly the model only requires `inclusion: { in: 1..8 }`; a sequence that never wraps would still satisfy validity for one call. But cycling lets a single test create multiple results within the same run — useful for "all 8 gyms beaten" scenarios in Step 5 conversions — without each call needing an explicit `gym_number:` override.

**Tests:** 305/305 still passing — no regressions. Fixtures untouched, so legacy fixture-based tests continue to pull from YAML; new factory files are inert (FactoryBot loads them at boot but no test uses them yet).

**Spot-check:** Wrote `/tmp/factory_smoke.rb` (Rails runner) that creates one record per factory and trait, asserting field-by-field match against the fixture data. All 32 records (6 group traits + 24 pokemon traits + 1 grey_team + 2 slots + 1 lobby_draft + 1 gym_result) build successfully and match the corresponding fixture row exactly. Output:

```
OK group :route201 → ROY / route_201 / pos 1
OK group :route202 → TOMMY / route_202 / pos 2
OK group :route203 → RACHEL / route_203 / pos 3
OK group :route204 → SPIKE / route_204 / pos 4
OK group :route205 → LUNA / route_205 / pos 5
OK group :route206 → BLAZE / route_206 / pos 6
OK 24 pokemon traits each match fixture (species/uid/location/status/name)
OK team :grey_team → uid 153665622641737728
OK team_slot :slot_1 → pos 1, :slot_2 → pos 2
OK gym_draft :lobby → state matches fixture
OK gym_result → gym_number 1, beaten_at <ts>
ALL FACTORY SMOKE CHECKS PASSED
```

**Lint:** `bundle exec rubocop` clean on all 6 files.

---

### Step 3 — Save Slots (5 per session) — 2026-04-30
**Status:** Complete, committed `29186e6`, deployed to `4luckyclovers.com`

**Files created:**
- `db/migrate/20260430143102_create_soul_link_emulator_save_slots.rb` — slots table + `active_save_slot` pointer on session; data-preservation INSERT migrates existing per-session save into slot 1; columns dropped with type args so rollback is reversible (data lost on rollback per Project Owner acceptance)
- `app/models/soul_link_emulator_save_slot.rb` — model with GzipCoder reuse, slot_number 1..5 validation + uniqueness, after_create_commit + after_update_commit parse-enqueue
- `app/controllers/save_slots_controller.rb` — index/create/update/destroy/restore/download. Authorization via `set_session` resolving to current_user_id-owned session; cross-player URLs return 404
- `app/views/emulator/_save_slots_sidebar.html.erb` — left column partial, 5 cards, banner for overwrite-pending mode, per-slot Download/MakeActive/Delete actions, Clear-All at bottom
- `app/javascript/controllers/save_slots_controller.js` — Stimulus controller; listens for `save-slots:overwrite-needed` and `save-slots:saved` window events; click overlays for overwrite mode; calls `window.EJS_emulator.gameManager.getSaveFile()` at click time to grab fresh bytes for the PATCH (Approach 2 per brief — stateless)
- `test/models/soul_link_emulator_save_slot_test.rb` — 18 tests (validations, gzip coder round-trip, parse callbacks)
- `test/controllers/save_slots_controller_test.rb` — 33 tests covering all 6 actions + cross-player authz
- `test/factories/soul_link_emulator_save_slots.rb` — factory with `:filled` and `:parsed` traits

**Files modified:**
- `app/models/soul_link_emulator_session.rb` — `has_many :save_slots dependent: :destroy`, new `active_slot` association method, removed `serialize :save_data` and the parse callback (moved to slot model). GzipCoder module retained on this class for shared use.
- `app/jobs/soul_link/parse_save_data_job.rb` — operates on a `SoulLinkEmulatorSaveSlot` parameter, not a session
- `app/controllers/emulator_controller.rb` — DELETE save_data wipes all slots + clears active_save_slot; GET reads from `@session.active_slot.save_data`; PATCH branch removed entirely; `set_session` no longer applies to PATCH route. `show` action eager-loads `:save_slots` and pre-fetches `@save_slots` for the sidebar partial.
- `app/javascript/controllers/emulator_controller.js` — added `saveSlotsUrl` Stimulus value; `_uploadSave` now POSTs to that URL; on 409 dispatches `save-slots:overwrite-needed` window event with the JSON body as detail; on 201 dispatches `save-slots:saved`
- `app/views/emulator/show.html.erb` — three-column grid (`280px minmax(0, 1fr) 280px`); save-slots sidebar on left; canvas in middle; run roster on right; canvas wrapper now also has `data-emulator-save-slots-url-value`
- `app/views/emulator/_run_sidebar.html.erb` — drops the inline Clear-Save button (moved to slot column); drops parsed-info display from the YOU card (visible in slot column); keeps parsed info on OTHER players' cards (sourced from their `active_slot`); removed `clear-save` Stimulus mount from this partial
- `config/routes.rb` — removed `patch :save_data`; nested `resources :save_slots, only: [...], param: :slot_number` under `:emulator` with `member { post :restore; get :download }`
- `lib/tasks/soul_link/debug_save.rake` — `reparse_all_saves` and `debug_save_offsets` now iterate `SoulLinkEmulatorSaveSlot.where.not(save_data: nil)`, not sessions
- `lib/tasks/emulator_cleanup.rake` — counts non-nil save bytes via `session.save_slots.where.not(save_data: nil).count`; destroys all slots; clears `active_save_slot` on inactive runs (transitively required by the schema migration)
- `test/controllers/emulator_controller_test.rb` — removed all PATCH save_data tests; updated GET save_data tests to source from active slot; updated DELETE tests to assert all slots wiped + active pointer cleared; parsed-roster tests now create slots on OTHER players (not on YOU, per the YOU-card-no-parsed change)
- `test/models/soul_link_emulator_session_test.rb` — removed save_data gzip + parse callback tests (moved to save slot model test); added save_slots association + active_slot resolution tests
- `test/jobs/soul_link/parse_save_data_job_test.rb` — exercises against a slot, not a session
- `test/lib/tasks/emulator_cleanup_test.rb` — seeds slots instead of `save_data:` on session; updated assertions to check `session.save_slots.count` and `active_save_slot`

**Key decisions:**
- Reused `SoulLinkEmulatorSession::GzipCoder` directly via `serialize :save_data, coder: SoulLinkEmulatorSession::GzipCoder` (per brief — no concern extraction yet).
- Added `after_create_commit :enqueue_parse_if_save_present` ALONGSIDE `after_update_commit :enqueue_parse_if_save_changed` on the slot model. The brief only specified after_update_commit, but the controller creates slots via `@session.save_slots.create!(slot_number:, save_data:)` — there is no update event on creation, so without the after_create_commit no parse would fire on the first save into an empty slot. Without it, slot cards would show "no parsed data" until something else triggered a parse. Worth Reviewer's eyes.
- `slot_payload`'s `saved_bytes` calculation: freshly-created records return `ActiveModel::Type::Binary::Data` from `read_attribute_before_type_cast`, not a String. Normalized via `.to_s.bytesize` so the 201-Created JSON response carries the correct on-disk size without forcing a reload.
- Migration: column drops use the type-arg form (`remove_column ..., :type, ...`) so rollback is reversible at the schema level. Brief listed bare `remove_column` — I added types to make a hypothetical `db:rollback` work cleanly (data still lost; matches Project Owner acceptance per brief).
- Run roster sidebar: parsed metadata for other players now sources from their `active_slot` (vs. the old per-session parsed_* columns). The card omits parsed lines when `active_slot` is nil OR has nil parsed fields. The YOU card no longer shows parsed info at all (slot column on the left covers it).
- Stimulus overwrite path: implemented Approach 2 from the brief — slot controller calls `window.EJS_emulator.gameManager.getSaveFile()` at click time to grab fresh SRAM bytes. Stateless; small in-game drift on overwrite-click is documented in the controller comment per brief.
- `_save_slots_sidebar.html.erb` reuses the existing `clear_save_controller` for the Clear-All button. The clear-save controller's DELETE-then-IDB-wipe-then-reload flow is unchanged; only its mount location moved.

**Tests:** 263 → 305 (+42 across model 18, controller 33, session-changes 4, parse job 7 unchanged, plus emulator-controller test rewrites). 0 failures, 0 errors.

**Lint:** `bundle exec rubocop` clean on all 16 touched files.

**Migration verified:** Ran `db:migrate` + `db:rollback` + `db:migrate` cycle in dev. Rollback reverts schema cleanly (data not preserved — accepted). Re-migrate is idempotent.

**Review:** Richard — APPROVED (no Conditions, no Escalations). Verified: migration order + raw-SQL data preservation, authorization scoping at every endpoint via `set_session`, `active_save_slot` consistency across all four mutation paths (create / overwrite / destroy-of-active / restore), Approach 2 stateless overwrite (slot Stimulus calls `gameManager.getSaveFile()` at click time, no JS-side stash), no setInterval/setTimeout re-introduction, layout regression-free.

**Deploy:** GitHub Actions run 25193821050 — test + deploy both succeeded. Migration ran cleanly on prod via the deploy script's `bin/rails db:migrate`; existing 2 saves on prod migrated to slot 1 with `active_save_slot = 1` automatically.

### Step 2 — Auto-Persist In-Game Saves to Server — 2026-04-30
**Status:** Complete, committed `2e9e934`, deployed to `4luckyclovers.com`

**Files modified:**
- `app/javascript/controllers/emulator_controller.js` — re-enabled `_fetchSave()` on `connect()`; added `window.EJS_defaultOptions = { "save-save-interval": "30" }` before loader.js boot; replaced diagnostic `EJS_ready` with: register `saveSaveFiles` listener first, then inject existing save if present, then log `"Emulator: hooks attached"` once with `hasExistingSave`/`hasEmulator` flags; added null/0-byte guard at top of `_uploadSave`; cleared `EJS_defaultOptions` in `disconnect()`. `EJS_onSaveSave` retained (manual export). `_injectExistingSave` body untouched.

**Key decisions:**
- Centralized null/0-byte guard inside `_uploadSave` so both call paths (`EJS_onSaveSave` event payload, `saveSaveFiles` direct bytes) share it. Brief asked for "defensive layering"; placing the guard in the function-under-call makes it impossible to bypass.
- Listener registration ordered BEFORE inject inside `EJS_ready` per the brief's race-condition warning (`gm.loadSaveFiles()` could trigger an auto-save tick between attach points).
- `EJS_defaultOptions` set FIRST in `connect()`, before `EJS_player`/`EJS_gameUrl`/etc. The brief said "before any EJS_* global is set"; obeyed literally to keep the ordering guarantee tight in case loader.js evolves to read globals at any point during script-tag append.

**Tests:** 255/255 pass. No backend change; suite count unchanged from Step 1.

**Lint:** No new Ruby. JS controller has no lint configured (Importmap project, no Node toolchain). Pre-existing rubocop offenses (133 across 127 files) are unrelated; documented previously in Known Gaps.

**Review:** Richard — APPROVED (no conditions, no escalations). All six Architect focus areas verified: listener order in `EJS_ready`, null/0-byte guard centralization, `EJS_defaultOptions` set position, `EJS_onSaveSave` retained, `disconnect()` cleanup, scope discipline (single code file).

**Deploy:** GitHub Actions run 25143303161 — test job 50s (255/255 pass), deploy job 17s (VPS SSH, asset precompile, web + bot service restart). All green.

---

### Step 1 — SRAM Phase 1: Trainer Block Parsing — 2026-04-29
**Status:** Complete, committed `62be21e`

**Files created:**
- `app/services/soul_link/save_parser.rb` — pure parser: slot selection (CRC16-CCITT poly 0x1021, init 0xFFFF, MSB-first), English Gen IV char decode (64 entries, 0xFFFF terminator, 0x0000 skip, U+FFFD fallback), returns nil on any error
- `app/jobs/soul_link/parse_save_data_job.rb` — async parse + `update_columns` write (skips after_update_commit recurse); sets `parsed_at` on both success and failure paths
- `app/helpers/emulator_helper.rb` — `format_play_time` helper
- `db/migrate/20260429215107_*` — 6 new columns on `soul_link_emulator_sessions`

**Files modified:**
- `app/models/soul_link_emulator_session.rb` — `after_update_commit :enqueue_parse_if_save_changed` callback (gated on `saved_change_to_attribute?("save_data")` and non-blank)
- `app/views/emulator/_run_sidebar.html.erb` — 4 new rendered fields gated on column presence; badges line gated on `parsed_trainer_name.present?` (not `parsed_at`) so failed parses don't render "Badges: 0/8"

**Key decisions:**
- Schema columns (Option A) for cached parsing; not on-demand
- English-only char table; Phase 2-5 (party, PC boxes, multi-language, map names) deferred
- Real-save offset verification NOT performed this session — offsets cited from Project Pokemon docs + pret/pokeplatinum + PKHeX (read-only). MAP_ID_OFFSET specifically is a placeholder; `safe_map_id` returns nil on zero so sidebar omits cleanly
- Architect tightened the badges gate from `parsed_at` → `parsed_trainer_name.present?` post-Bob to honor the brief's :failed → "—" contract (parsed_badges defaults to 0, would otherwise render "0/8" on failed parse)

**Tests:** 34 new (18 parser + 7 job + 6 callback + 3 controller); 221 → 255, 0 failures, 4 clean parallel runs.

**Review:** Richard — PASS_WITH_OBSERVATIONS (3 minor: badges gate UX [resolved by Architect inline], off-by-one in Bob's count breakdown [cosmetic], pre-existing rubocop offenses in `delete_rom_file` tests [not introduced by this step]).

**Open Architect rulings (escalated by Richard):**
1. Real-save offset verification still outstanding — Architect ruled "ship as-is" since infra is correct + failure modes honest. Logged as Known Gap below.
2. MAP_ID_OFFSET placeholder — same call.

---

## Known Gaps
*Durable. Items logged here instead of expanding the current step. Persists across sessions until addressed.*

### Closed in Steps 9-19 (2026-04-30 → 2026-05-04)
- ~~**KG-17: Discord notification on Hall of Fame**~~ — closed in Step 19 (`SoulLink::DiscordNotifier.notify_run_complete(run)` fires from `HallOfFameCoordinator.process` AFTER the `update!(completed_at: ...)` actually persists; idempotency guarded by the existing `completed_at.present?` early return so re-running the coordinator on an already-completed run does NOT re-fire. Channel: `general_channel_id`. Message format: `"🏆 HALL OF FAME — Run #N complete!"`).
- ~~**KG-22: No Discord notification on auto-detected catch**~~ — closed in Step 19 (`SoulLink::DiscordNotifier.notify_catch(run, uid, species, route, level, off_feed:)` fires from `CatchCoordinator.create_pokemon_row` AFTER the `SoulLinkPokemon.create!`, inside the existing `slot.transaction { }`. Channel: `catches_channel_id`. Box-observed catches set `off_feed: true` and append `[off-feed]` to the message).
- ~~**KG-24: No Move ID → Move name lookup**~~ — closed in Step 19 (`config/soul_link/move_names.yml` ships with 467 entries — IDs 1..467 contiguous, no gaps. Sourced from PKHeX `PKHeX.Core/Resources/text/other/en/text_Moves_en.txt` lines 2..468 (line 1 is the `———` no-move sentinel; ID 0 intentionally absent). Cross-checked against pret/pokeplatinum `include/constants/moves.h` `MOVE_SHADOW_FORCE = 467`. `SoulLink::GameState.move_name(id)` returns the name with integer coercion + nil safety; `EmulatorHelper#format_move_name(id)` provides the `"Move ##{id}"` fallback for unknown IDs (mirrors `format_map_name`'s shape). View consumer: `_pc_box_content.html.erb` STATS expander.).
- ~~**KG-21: PC box parsing not implemented**~~ — closed in Step 18 (`SoulLink::BoxParser` walks the storage block at partition offset `0xCF2C` size `0x121E4` — both per PKHeX `SAV4Pt.cs` — with box data starting at `+4` inside the storage block, 18 boxes × 30 slots × 136-byte records. Independent active-block picker per partition because storage and general blocks can swap partitions independently per PKHeX's `StorageBlockPosition` behavior. CRC body excludes the 20-byte footer per PKHeX `SAV4.cs:113` `Checksums.CRC16_CCITT(data[..^FooterSize])` + `SAV4Sinnoh.cs:12` `FooterSize => 0x14` — caught a Must Fix in review where the range covered only the 2-byte CRC field, which would have silently failed every real Platinum save. Catches landing via box-only diff fire `BoxedPokemonObservedEvent`, processed by `CatchCoordinator.handle_box_observed` with `caught_off_feed: true`, dedupe-safe against the existing party-side `(run, user, pid)` `.exists?` check. Citations at `app/services/soul_link/box_parser.rb:21-22, 73-79`.)
- ~~**KG-11: Party block offset within the SRAM slot not yet pinned**~~ — closed in Step 17 (`PARTY_OFFSET_IN_GENERAL_BLOCK = 0xA0` cited from PKHeX `PKHeX.Core/Saves/SAV4Pt.cs` `GetSAVOffsets()` method which assigns `Party = 0xA0` alongside `Trainer1 = 0x68` and `Extra = 0x2820`. Cross-checked against pret/pokeplatinum `include/party.h` Party struct shape (`int capacity; int currentCount; Pokemon[MAX_PARTY_SIZE]`) and `include/struct_defs/pokemon.h` Pokemon struct (BoxPokemon 136 bytes + PartyPokemon 100 bytes = 236 bytes per slot). Inline citation at `app/services/soul_link/party_parser.rb:30-44`.)
- ~~**KG-12: Met-location ID → route-name table not yet sourced**~~ — closed in Step 17 (`config/soul_link/met_locations.yml` shipped with 127 entries: all Sinnoh routes 201-230 + all gym towns + key Platinum-only dungeons (Distortion World, Spear Pillar, Stark Mountain, etc.) + 5 special pseudo-IDs flagged event:true (Daycare4=2000, LinkTrade4NPC=2001, LinkTrade4=2002, Ranger4=3001, Faraway4=3002). Sources: PKHeX `PKHeX.Core/Resources/text/locations/gen4/text_hgss_00000_en.txt` (235-entry canonical Gen-IV table; entries 0-126 are Sinnoh-relevant) + PKHeX `PKHeX.Core/Game/Locations/Locations.cs` (special IDs). Header citation at `config/soul_link/met_locations.yml:1-39`. `SoulLink::GameState` extended with `met_locations` / `met_location_name(id)` / `event_met_location?(id)` helpers; missing IDs surface as "Met-Location #N" via `CatchCoordinator.resolve_route_name` graceful-degradation fallback.)

- ~~**KG-1: No real-time updates on the run roster sidebar**~~ — closed in Step 9 (targeted frame replacement on save-slot parsed_* updates)
- ~~**KG-2: No real-time broadcast of species change to other players' dashboards**~~ — closed in Step 9 (`broadcasts_refreshes_to` on `SoulLinkPokemon` + `SoulLinkPokemonGroup`)
- ~~**KG-3: No loading state on EVOLVE button**~~ — closed in Step 9 (button disable + "EVOLVING..." text)
- ~~**KG-4: `#d4b14a` amber color inline**~~ — closed in Step 9 (promoted to `--amber` palette token)
- ~~**KG-5: 133 pre-existing rubocop offenses**~~ — closed in Step 10 (`rubocop -a` autocorrect; codebase now 0 offenses across 147 files)
- ~~**KG-6: Map ID → name lookup**~~ — closed in Step 12 (`config/soul_link/maps.yml` + `SoulLink::GameState.map_name` + `EmulatorHelper#format_map_name` + view edits in run-roster + slot-card surfaces)
- ~~**KG-13: Parse-failure path zeroes parsed_badges**~~ — closed in Step 15 (`ParseSaveDataJob` failure branch now updates ONLY `parsed_at`; every other parsed_* field keeps its prior value, so a CRC-bad save sandwiched between two good ones never produces spurious BadgeLost events through the new `SaveDiff` pipeline)
- ~~**KG-14: Pokédex caught/seen flag offsets not yet validated against a real Platinum save**~~ — closed in Step 16 (`POKEDEX_OFFSET = 0x1328`, `POKEDEX_CAUGHT_OFFSET = 0x132C`, `POKEDEX_SEEN_OFFSET = 0x136C` cited from PKHeX `SAV4Pt.cs` `private const int PokeDex = 0x1328` + `Zukan4.cs` `SIZE_REGION = 0x40` region layout + pret/pokeplatinum `include/pokedex.h` `struct Pokedex { u32 magic; u32 caughtPokemon[16]; u32 seenPokemon[16]; ... }`. Defensive cap: popcount > `POKEDEX_BIT_LIMIT = 493` (`NATIONAL_DEX_COUNT`) returns nil for that field. Citations in code comments at `app/services/soul_link/save_parser.rb:75-99`.)
- ~~**YOU-badge restoration follow-up (logged in Step 9)**~~ — closed in Step 10 (new `roster_you_marker_controller.js` decorates the matching `[data-discord-user-id]` card on `connect()` + `turbo:before-stream-render`)
- ~~**Soft Point #3: SoulLinkRun.current(guild_id) lacks a hard invariant**~~ — closed in Step 11 (DB-level virtual-column unique index on `active_guild_id`)
- ~~**Convert legacy fixture-based tests to FactoryBot**~~ — closed in Steps 4-8 (FactoryBot conversion shipped)

### From earlier work (Evolve Button feature)
- Co-evolution of soul-link partners on evolution (deliberate; revisit if Project Owner wants paired evolution)
- No level/method gating on EVOLVE button (always available; player owns in-game timing)

### Outstanding from Step 9 (2026-04-30)
- **`window.alert()` for Tier-A error toasts** (Step 9). Smallest user-facing change that closed the silent-failure gap; a styled toast component (matching the `gb-flash gb-flash-alert` palette) would be cleaner. Track if alerts feel intrusive in real use.
- **Bot-process broadcasts not yet supported.** The async cable adapter is in-process; Discord modal updates (which run in the bot process via `rake soul_link:bot`) don't propagate to web clients in real time. Switching to a redis cable adapter would unlock this.
- **Pre-existing soft points from `handoff/PROJECT-REVIEW-2026-04-30.md`** — 20 items, ranked by ROI in that document. Top-priority structural cleanups: (1) `discord_bot.rb` god-object decomposition; (2) zero test coverage on services/channels; (3) `SoulLinkRun.current(guild_id)` lacks a hard "one active per guild" invariant; (4) `DashboardController#show` needs presenter extraction; (5) `SoulLinkEmulatorSession::GzipCoder` should move to a concern. None of these are urgent — Tier-1 refactor work, fresh-session candidate.

### New — From Step 24 (2026-05-05)
- **KG-39: Per-player badge counts on the dashboard PARTY sub-tab share `@gyms_defeated`.** Step 24 R1's PARTY sub-tab in `_status_rail.html.erb` renders `<%= @gyms_defeated %> BADGES` for every player row — there is no per-player badge variance because the run only tracks gyms_defeated as a single integer at the run level. Mockup screen 2 shows "BOB 8 BADGES" while the other 3 sit at 2/3 — that's the future feature. To ship per-player variance: extend `SoulLinkRun` (or `SoulLinkTeam`) with per-player gym progress, add a partial `:player_badges_count(uid)` lookup (or compute from `gym_results` × `team_snapshot`), and replace the shared `@gyms_defeated` reference in the PARTY sub-tab partial. The HOF-pill currently fires on `@run.completed? && badges == 8`; once per-player variance lands, switch the conditional to per-player HoF state. Architect-decided ambiguity in Step 24 brief.

### New — From Step 22 (2026-05-04)
- **KG-35: SKIP in the PC BOX REVIEW PARSED CATCHES tray does not persist.** Step 22 R2's per-row SKIP button toggles a `.dismissed` class on the row (opacity 0.4 + count decrement), client-side only. Reload resurfaces the row. Mockup-driven: the mockup shows opacity-dim styling but no backend round-trip; the audit's "small migration" hand-wave for `acquired_via` / `caught_off_feed` round-trip was explicitly out-of-scope per the Step 22 brief (no schema / controller / endpoint changes). Future v2 if SKIP feedback proves persistent: add a `skipped_at:datetime` column on `soul_link_pokemon`, hide SKIPped rows from `@auto_detected_catches`, surface an "UNDO SKIP" affordance somewhere. Adjacent to KG-23.
- **KG-36: PC BOX filter chips are status-only — no route, player, or species filters.** The Step 22 R2 mockup ships four chips (`ALL` / `ON TEAM` / `STORAGE` / `FALLEN`) plus a free-text search; the prompt's gist mentioned "route / status / player" filters but the locked mockup doesn't. Mockup wins (Step 21 precedent). If a future redesign needs richer filtering — e.g. "show me only fallen catches from Eterna Forest" — extend the chip strip. The new `pc_box_filter_controller.js` is structured to take additional chip targets without a rewrite (just add new `data-status="..."` cell tags + new chip with matching `data-pc-box-filter-status-param`).

### New — From Step 21 (2026-05-04)
- **KG-33: Slot card no longer shows "saved Xm ago" or byte count.** Step 21 R3's mockup omits the `time_ago_in_words` "saved … ago" footer + the `number_to_human_size` byte count from the per-slot card. Mockup-driven decision (Ava answer #3), not a parser regression — `slot.updated_at` and `save_data.bytesize` are still queried by the controller and persisted; they're just not rendered on the slot column. If anyone misses the time-since-last-save signal, surface again in a follow-up. Adjacent to KG-34.
- **KG-34: Roster card no longer shows "Active … ago" or "Save: bytes".** Same shape as KG-33 — Step 21 R3 redesign drops both rows from the run-roster card. The `<details>STATS</details>` block now houses TRAINER / MAP / MONEY / TID-SID / DEX-SEEN; the time-since + bytes signals don't fit the new hierarchy. Mockup-driven, not a parser regression. Surface again if the Project Owner misses them.

### New — From Step 20 (2026-05-04)
- **KG-31: Existing `_mark_dead_modal.html.erb` and `_reset_draft_modal.html.erb` retain their bespoke implementations.** Step 20 introduced a shared `_confirm_modal.html.erb` partial used by all 6 newly-gated destructive sites, but the two pre-existing destructive modals (Mark Dead and Reset Draft) keep their own templates because converting them would touch Step-19-shipped read-only guards and the gym-draft reset flow. Future cleanup can fold them onto the shared partial; cost-zero today.
- **KG-32: `confirm-modal` Stimulus controller's `window.__confirmModals` registry is unused dead code.** `connect()` populates `window.__confirmModals[idValue] = element`; nothing reads from it. The `open()` action discriminates by `event.params?.id !== this.idValue` instead. Kept for now — earns its keep if a future external script wants programmatic modal access by id. If no such consumer materializes, drop the registry on the next pass through this file.

### New — From Step 19 (2026-05-04)
- **KG-26: No real-SRAM smoke test for `move_names.yml` lookup.** All Step-19 tests for `SoulLink::GameState.move_name(id)` use the production YAML directly + lock the boundary IDs (1=Pound, 33=Tackle, 467=Shadow Force). A move-ID landing in a real Platinum SRAM that doesn't match the YAML would only be caught against a known-good dump. Same parity argument as KG-25 (synthetic test data uses the same lookup the production code does). Recommendation: bundle into the same `BoxParser` real-save audit when a real Platinum `.sav` is available.
- **KG-27: No UI to un-wipe a run.** `run.update!(wiped_at: nil)` is the only un-wipe path. A premature wipe-fire (e.g., a player accidentally Mark-Dead'd their last alive Pokemon and wants to recover) requires direct AR access. Mirrors KG-19 (HoF un-completion). If a PO discovers a need, this is a small button in the dashboard runs panel.
- **KG-28: No server-side authz for read-only-mode-disabled endpoints.** Step-19's read-only mode (`run.read_only?`) hides UI affordances (NEW CATCH, MARK DEAD, MARK BEATEN, UNMARK, START GYM DRAFT, map-view NEW CATCH) but does NOT block the corresponding controller actions. A determined user crafting a request directly could still mutate state on a wiped run. UI-hide only is the v1 contract; server enforcement (e.g., `before_action :reject_when_read_only` returning 422) is a follow-up. Locked decision: Step-19 ships UI-hide only.
- **KG-29: No auto-detect of dead Pokémon from save diff.** A Pokemon disappearing from BOTH the party and the box between snapshots could be a release, a trade-out, OR a death. Without confirmation UX the auto-tracker would generate false-positive Mark-Dead transitions. Brief explicitly out-of-scoped this. Future inference step would need: (a) heuristic — multiple Pokemon disappearing in same parse + level cap reached recently is more likely a wipe-and-reset than a release; (b) confirmation UX — surface "DETECTED MISSING: <species>; was this a death?" prompt to the player. WipeCoordinator currently runs only on manual Mark Dead transitions.
- **KG-30: `broadcast_state[:wiped_at]` has no current consumer.** Step-19 added the key to `SoulLinkRun#broadcast_state` for forward-looking client-side wipe-state UI. Current dashboard refresh path goes through `broadcasts_refreshes_to ->(record) { [ record, :dashboard ] }` Turbo morph (server re-renders on wipe). If a future step wants reactive client-side wipe handling, the key is already in the payload. Minor payload bloat on every run mutation; not worth removing.

### New — From Step 18 (2026-05-03)
- **KG-24: No Move ID → Move name lookup.** `_pc_box_content.html.erb`'s STATS expander renders `MOVE n: #N · PP n · ↑n` for each of the 4 moves. Adding a `config/soul_link/moves.yml` with all ~467 Gen IV moves (sourced from PKHeX `text_moves_en.txt`) would lift this to readable names. Out of scope for Step 18 per brief. Adjacent to KG-20 (species lookup); both are static-data lookups deferred to a future polish step.
- **KG-25: No real-SRAM smoke test for `BoxParser` and extended `PkmDecoder` field reads.** All Step-18 tests use synthetic SRAM/PKM builders that recompute CRCs and LCG-encrypt payloads using the same constants the production code does. A regression of the storage-CRC fix (Must Fix #1 from review) would only be caught by running `BoxParser.parse` against a known-good Platinum dump. Same shape as Step 16/17's open audit task. Recommendation: capture a real Platinum `.sav` from the Project Owner's emulator, compress, drop into `test/fixtures/files/`, wire one integration test through `BoxParser.parse` + `PkmDecoder.decrypt` for IVs / EVs / moves field reads. Not blocking — the parity argument with `SaveParser` is strong — but durable.

### New — From Step 17 (2026-05-03)
- **KG-20: Species ID → species name resolution depends on `pokemon_base_stats` table being populated.** `CatchCoordinator.resolve_species_string(species_id)` reads from the `pokemon_base_stats.national_dex_number` column; if the table is empty (e.g. fresh dev DB without the seed task), the row gets a `"Species #N"` fallback string. Acceptable for v1 (the species column is `null: false` so we can't store nil; the fallback at least carries the dex ID forward). A future improvement: cache the inverse map at boot from `config/soul_link/pokedex.yml` if a numeric-id-keyed source becomes available, or run the Pokemon-data seed in CI.
- **KG-21: PC box parsing not implemented.** Step 17 only walks the party block (offset 0xA0). A Pokemon deposited into a PC box and then withdrawn back into the party round-trips with the same PID, so `CatchCoordinator`'s PID-dedup check correctly no-ops the "re-catch" — but a Pokemon that's deposited and never withdrawn is invisible to the auto-tracker (and a Pokemon caught directly into the PC box, which Pokemon Platinum auto-does when the party is full, never appears at all). Future Step 19+ could extend `PartyParser` to walk the box block (18 boxes × 30 slots × 136-byte box-PKM records = 73,440 bytes per slot half).
- **KG-23: No UI for "this auto-catch is wrong, please undo".** Auto-detected SoulLinkPokemon rows can be edited via the existing dashboard pokemon modal (same modal as manual catches), but there's no dedicated "this is a false positive, dismiss" flow. If the PartyParser ever miscategorizes (e.g. the species lookup falls back to "Species #387" because `pokemon_base_stats` is empty), the player can rename via the modal but can't easily re-trigger detection. Could be a small "RE-DETECT" button in a future polish step.

### New — From Step 16 (2026-05-03)
- **KG-16: Auto-deactivation of completed runs.** `HallOfFameCoordinator` sets `run.completed_at = Time.current` when 4/4 sessions reach HoF, but does NOT flip the `active` flag. PO follow-on call (locked decision in the brief). The dashboard renders a "🏆 COMPLETE" pill alongside the existing "ACTIVE" pill so the state is visible; un-completing requires direct AR write (`run.update!(completed_at: nil)`). Future: PO may want a "WRAP UP RUN" button on the dashboard that flips `active` to false.
- **KG-18: TID conflict resolution flow.** The "⚠ TID CONFLICT" pill is informational only. Two players uploading the same `.sav` produces a pill on each affected card with no UI to resolve (the player must figure out which save belongs where and re-upload). Future: a per-slot "this isn't my save" / "this is mine" prompt to clarify.
- **KG-19: HoF "uncomplete" path.** Direct AR `update!(completed_at: nil)` is the only way to undo run-completion (e.g., if the auto-detection fired prematurely on a save-state shenanigan). No UI for it; if a PO discovers a need, this is a small button in the dashboard runs panel.

### New — From Step 13 (2026-05-01)
- **`test/controllers/dashboard_controller_test.rb` does not exist.** The Step 13 brief listed render-condition tests (UNMARK button visibility, RESET DRAFT button gating) as *optional* and explicitly said "creating the whole controller test file from scratch is scope expansion — log as Known Gap." Manual render-smoke verified all four data states ([A] 1 defeated, [B] 2 defeated, [C] lobby draft, [D] complete draft) but the assertions were not committed to a permanent test file. A future step that stands up `dashboard_controller_test.rb` should fold these in.
- **`broadcasts_refreshes_to` on `GymDraft` not added.** Step 13 uses page-reload-after-Stimulus-fetch for the reset flow. A future step could broadcast on draft create/destroy so other open dashboards in the run pick up the state change in real time. Not urgent; cross-player draft real-time already flows through `GymDraftChannel` (the WebSocket) for the draft show page itself.
- **Pre-existing JSON-response-on-HTML-form quirk in `GymProgressController#update`.** When MARK BEATEN or UNMARK fires from the dashboard via `data: { turbo: false }`, Rails renders the JSON `{"gyms_defeated":N}` as a page (the user sees raw JSON briefly until they hit back). The user has been working with this for MARK BEATEN successfully; UNMARK inherits the same wiring. Brief explicitly forbade touching this in Step 13. Future step: respond with `respond_to do |format|` and a `redirect_back` for HTML, or convert the buttons to Stimulus fetch + reload (mirrors mark-dead/reset-draft).
- **Reset-draft surface only on the dashboard's Gyms tab.** A reset button on `gym_drafts/show.html.erb` would be redundant per the brief and would need different Stimulus controller scope. If users discover the gyms-tab path is non-obvious during a stuck draft, consider exposing it on the draft show page in a follow-up.

### New — From Step 10 (2026-04-30)
- **Visual indentation in a few autocorrected files is awkward.** `Layout/EndAlignment` autocorrect fixed `else`/`end` alignment to match the `if` opener but didn't reindent the bodies between them — for `<var> = if cond \n  body \n else \n  body \n end` patterns the body is now visibly under-aligned vs. the keywords. Specific spots: `app/services/soul_link/discord_bot.rb` lines around 251-261, 353-369, 383-394. Code is correct, tests pass — purely cosmetic. A 5-minute manual cleanup pass would resolve.
- **D.16 (save-slot operations hard-reload) deferred.** `window.location.reload()` after slot ops loses emulator in-memory state. Compounds with KG-1's broadcast plumbing — a follow-up step could turn the slot column into a turbo_stream-receiving frame and broadcast on slot create/update/destroy.
- **KG-6 (Map ID → name lookup) deferred.** The SRAM parser's `parsed_map_id` (when populated) renders as a number; `config/soul_link/maps.yml` with Gen IV Platinum map IDs would let the sidebar render "Eterna City" etc. ~1 hour of work, separate session.

### From the emulator deploy + polish session (2026-04-29)
- **Tier 2 SRAM parsing** for in-game info (character name, time-played, money, party count, current map, badges earned) — separate feature, real engineering effort (Gen IV character set decoder + checksum/slot logic)
- **No automated browser test harness** — smoke tests are manual; Project Owner verifies UI changes
- **Randomizer settings file** (`random_basic_1.rnqs`) is small/basic — heavier randomization (abilities, types-per-move, evolutions) requires re-export from the GUI and re-scp
- **Destructive regenerate** wipes save_data for ready/claimed sessions when status is `:failed`. Acceptable v1 tradeoff; future iteration could selectively preserve `:ready` sessions.
- **`error_message` column at varchar(255)** — widen to text only if real-world stack traces prove limiting
- **Channel-layer guild authz cached at login** — if user joins a new guild mid-session without re-logging-in, they won't see it. Acceptable for current use.

### From SRAM Phase 1 (2026-04-29)
- **Real-save offset verification outstanding.** Trainer-block offsets in `SoulLink::SaveParser` cited from Project Pokemon docs + pret/pokeplatinum + read-only PKHeX. Adjust constants if first real save reveals divergence. `MAP_ID_OFFSET = 0x1234` is the least-confident placeholder; `safe_map_id` returns nil on zero so sidebar omits cleanly. When Project Owner has a real `.sav`, verify all 5 fields decode to known values.
- **Pre-existing rubocop offenses** in `test/models/soul_link_emulator_session_test.rb:220, 258` (4 "Use space inside array brackets" inside `delete_rom_file` tests). Not introduced by SRAM work. Clean with `rubocop -a` in a dedicated cleanup step.
- **Phase 2 deferred:** map_id → map name lookup (config/soul_link/maps.yml or similar) so sidebar shows "Eterna City" instead of `426`
- **Phase 3 deferred:** multi-language char tables (Japanese, Korean, etc.); current parser is English-only
- **Phase 4 deferred:** Pokemon party data (encrypted/PRNG-scrambled blocks A-D, requires Pokemon-internal descrambling — significant effort)
- **Phase 5 deferred:** PC boxes (same scrambling as party + box-level layout)

---

## Architecture Decisions
*Durable. Locked decisions that cannot be changed without breaking the system. Persists across sessions.*

### Emulator infrastructure (locked 2026-04-29)
- **In-game SRAM saves are persisted via the `saveSaveFiles` event, NOT `saveSave`.** `saveSave` (loader.js auto-wires `EJS_onSaveSave`) only fires on the manual "Save File" export button. The internal SRAM commit lifecycle uses `saveSaveFiles`, fired by `gameManager.saveSaveFiles()` after every `cmd_savefiles` flush. We register `window.EJS_emulator.on("saveSaveFiles", cb)` inside `EJS_ready` and set `EJS_defaultOptions["save-save-interval"] = "30"` so the auto-save tick covers in-game saves. `EJS_onSaveSave` is retained as belt-and-suspenders for the manual button. Server is the source of truth on load: `_injectExistingSave` runs in `EJS_ready` after the listener is attached. `_uploadSave` short-circuits null / 0-byte payloads — `getSaveFile(false)` returns null pre-first-save, and an empty SRAM PATCH would clobber a real server save.
- **PokeRandoZX must be invoked with `cli` as the first arg after `-jar`.** CLI mode auto-seeds; do NOT pass `-seed`. Without the `cli` subcommand, the JAR launches a Swing GUI which fails on headless servers with `HeadlessException` but exits 0 — silent generation failure.
- **`save_data` column is gzip-compressed** via `SoulLinkEmulatorSession::GzipCoder` (custom serializer). Reads/writes are transparent. Use `read_attribute_before_type_cast("save_data")` for raw compressed bytes (e.g. for size display); regular `save_data` accessor triggers decompression.
- **Inbound PATCH `save_data` is capped at 2MB raw** (`EmulatorController::MAX_SAVE_DATA_BYTES`). Pokemon Platinum SRAM is ~512KB; cap is a generous DoS bound enforced via `request.content_length` check + post-read `bytesize` check.
- **`RunChannel#subscribed`** rejects when `params[:guild_id]` doesn't match `connection.session[:guild_id]`. Single check, applies to every channel action.
- **`RunChannel#generate_emulator_roms` and `#regenerate_emulator_roms`** wrap their idempotency check + enqueue in `run.with_lock` — prevents the channel-layer race where two concurrent clicks both pass `:none` and both enqueue.
- **Subprocess pattern: `Process.spawn` + `waitpid(WNOHANG)` poll loop + TERM→KILL on deadline.** `Open3.capture3 + Timeout.timeout` is banned (raises in calling thread but leaves child Java running — zombie leak).
- **`emulator_session.rom_path` is server-derived** — only ever set by `RomRandomizer` via `Pathname#relative_path_from(Rails.root)` of a path constructed under `OUTPUT_DIR`. Never user input. If a future writer changes this, `EmulatorController#rom`'s `send_file` becomes a file-read-anywhere primitive and needs an explicit `path.start_with?(OUTPUT_DIR)` guard.

### SRAM auto-tracking (locked 2026-05-02, extended 2026-05-03 + 2026-05-03 Step 17 + 2026-05-03 Step 18)
- **Three-layer dispatch pattern (Step 16 update).** SRAM-derived state changes flow through (a) `SoulLink::SaveDiff` (pure function on parsed values, returns a structured `Result` with per-category event arrays), (b) `SoulLink::SaveDiffDispatcher` (owns the baseline rule + empty-diff short-circuit + fan-out to coordinators), and (c) per-category coordinators (`GymBeatenCoordinator`, `TidObservationCoordinator`, `PokedexProgressCoordinator`, `HallOfFameCoordinator`). The diff layer NEVER touches AR, `Rails.logger`, or `Time.current`; the coordinator owns all side effects. `ParseSaveDataJob` is now a "pure parser + persist" facade — it captures pre/post snapshots and delegates to the dispatcher. Adding new categories does NOT require touching the job or the dispatcher: extend `SaveDiff::Result` with a new `*_events:` keyword field, register a new coordinator in the dispatcher's fan-out, ship the coordinator. Step 17/18 (PKM-decryption-gated catches + gym teams) follows this pattern.
- **`SaveDiff::Result` is the extension point for categories 2 and 3.** Future categories add new keyword fields to the Result struct (`catch_events:`, `evolution_events:`) WITHOUT rewriting existing call sites. Existing consumers that only read `badge_events` keep working untouched. This is the architectural promise from the SRAM auto-tracking audit (`handoff/2026-05-02-sram-auto-tracking-audit.md` § 4).
- **All-4 AND-gate is the auto-mark policy for category 1.** `GymBeatenCoordinator.all_players_have_badge?(run, gym_number)` returns true only when `run.soul_link_emulator_sessions.all? { |s| s.active_slot&.parsed_badges.to_i >= gym_number }` AND the session set is non-empty. Manual MARK BEATEN bypasses this entirely (different controller path, never hits the coordinator). PO decision (option (b) from audit § 1) — locked.
- **`gym_auto_mark_suppressions` is the manual-UNMARK escape hatch.** When a player UNMARK-s a gym from the dashboard, `GymProgressController#update` creates a `(soul_link_run_id, gym_number)` row via `find_or_create_by!`. While that row exists, `GymBeatenCoordinator.attempt_auto_mark` refuses to re-mark, even when the all-4 gate would otherwise pass. Suppression clears on (a) manual MARK BEATEN of the same gym, (b) post-draft `GymDraftsController#mark_beaten` (explicit re-engagement signal). Unique index on `(soul_link_run_id, gym_number)` enforces single-row-per-gym at the DB level.
- **Down events (`BadgeLost`) log only.** A player loading an older save state produces BadgeLost events through `SaveDiff.between`; the coordinator logs at info level (for traceability — this is normal user behavior, not an error) and never auto-unmarks. PO decision — no auto-unmark policy until/unless explicitly designed.
- **Baseline rule: first-ever parse skips the diff dispatch entirely.** `ParseSaveDataJob` captures `prev_parsed_at` BEFORE writing the new parse, then gates the dispatch on `prev_parsed_at.present?`. A slot whose first-ever successful parse lands with N>0 badges does NOT fire N gym-beaten events (which would be wrong for a mid-run save import). Only diffs against a known prior baseline count.
- **KG-13 fix: parse-failure path updates ONLY `parsed_at`.** Every other parsed_* field keeps its prior value. This prevents a CRC-bad save from appearing as "lost all badges" to the diff layer. The slot card still renders the most recently successful parse (no UI regression). The failure path also skips the diff dispatch entirely (returns immediately after `update_columns(parsed_at: ...)`).
- **Step 16: Pokédex offsets pinned (KG-14 closed).** `POKEDEX_OFFSET = 0x1328` from PKHeX `SAV4Pt.cs` `private const int PokeDex = 0x1328`; layout (u32 magic, then 4 regions of 0x40 bytes each = caught/seen/genderFirst/genderSecond) from PKHeX `Zukan4.cs` and pret/pokeplatinum `include/pokedex.h struct Pokedex`. Caught region at `0x132C` (64 bytes, bit-per-species), seen region at `0x136C` (64 bytes, bit-per-species). Defensive cap: popcount > `POKEDEX_BIT_LIMIT = 493` (`NATIONAL_DEX_COUNT`) → returns nil for that field, mirroring `safe_map_id`'s graceful degradation when an offset is wrong.
- **Step 16: Hall of Fame block layout pinned.** Absolute file offsets — primary at `0x20000`, secondary mirror at `0x60000` (= primary + 0x40000 partition size). Block total size `0x2AC0` = data (`0x2AB0`) + footer (`0x10`). Within the data: `Dendou4Record[30]` (each `0x16C` bytes) followed by `u32 IndexNextOverwrite` then `u32 ClearCount` (the field we read at `0x2AAC`). Footer at `0x2AB0`; CRC at `0x2ABE` covers everything before it. Same CRC16-CCITT-FALSE variant as the general block — reused the existing `crc16_ccitt` helper. Source: PKHeX `SAV4Pt.cs` `ExtraBlocks` table + `Dendou4.cs` + pret/pokeplatinum `include/savedata/save_table.h` `EXTRA_SAVE_TABLE_ENTRY_HALL_OF_FAME = 0`.
- **Step 16: HoF count semantics (locked).** `parsed_hof_count == ClearCount` (number of times the player has entered the HoF). `>= 1` means "this player has reached the Hall of Fame at least once" — that's all the run-completion AND-gate cares about. Higher values (1 → 2 → ...) are repeat clears; the diff layer suppresses them as not-interesting (`HallOfFameEntered` only fires on 0/nil → ≥1 transitions). On CRC fail OR any error → `parsed_hof_count = nil` (NEVER 0) so a corrupted HoF block can't false-positive a "Run complete" — `nil.to_i = 0` in the coordinator's `>= 1` check correctly fails the all-4 gate.
- **Step 16: HoF run-completion is the only side-effect-bearing Step 16 coordinator.** When 4/4 sessions in a run report `parsed_hof_count >= 1`, `HallOfFameCoordinator.process` sets `run.completed_at = Time.current`. Idempotent: skips if `completed_at` is already set (the un-completion path is a direct AR `update!(completed_at: nil)` — no UI). The `active` flag is NOT auto-flipped (PO follow-on call — KG-16). The dashboard renders a "🏆 COMPLETE" pill alongside the existing "ACTIVE" pill.
- **Step 16: TID-mix-up detection is read-side only.** `SoulLinkRun#tid_conflict_groups` returns groups of session-ids whose active slots share the same `(parsed_trainer_id, parsed_secret_id)` pair (sessions with nil/zero TID excluded as "unparsed, not conflict"). The view renders a "⚠ TID CONFLICT" pill on each affected card. No coordinator action — the player resolves manually (could be a legitimate save-reset, not a mix-up). `TidObservationCoordinator` exists for symmetric pattern adherence and traceability (log-only).
- **Step 17: Gen-IV PKM decryption is split into two pure-function layers (Layer A).** `SoulLink::PkmDecoder` decrypts a single 236-byte (party) or 136-byte (box) PKM record. Algorithm: (1) read PID at 0x00 + checksum at 0x06; (2) XOR-decrypt the 128-byte block region (0x08..0x87) with the LCG keyed by the checksum; (3) verify post-decrypt checksum (sum of all 64 u16 words mod 0x10000 == stored checksum); (4) un-shuffle the 4 × 32-byte blocks per `((PID >> 13) & 0x1F) % 24` lookup into a 32-entry permutation table; (5) for party records, XOR-decrypt the 100-byte party stats block (0x88..0xEB) with a SECOND LCG keyed by PID. Returns `Pkm` Struct on success, nil on any error (never raises). `SoulLink::PartyParser` walks the SRAM party block at offset `0xA0` (within the general/small block, picked via the same CRC-validated active-slot logic as SaveParser), reads the count u32 at +0x04 of the 8-byte party header, calls PkmDecoder per occupied slot, filters eggs + species==0 sentinels, returns Array<Pkm>. Both layers are reusable by Step 18 (Nature/IVs/EVs/movesets just adds new fields to the `Pkm` Struct) and by category 2 (gym battle teams).
- **Step 17: Party block offset = 0xA0 (KG-11 closed).** Within the general/small block. Cited from PKHeX `PKHeX.Core/Saves/SAV4Pt.cs` `GetSAVOffsets()` method (`Party = 0xA0` alongside `Trainer1 = 0x68` and `Extra = 0x2820`). Cross-checked against pret/pokeplatinum `include/party.h` Party struct (`int capacity; int currentCount; Pokemon[6]` → 8-byte header + 6 × 236-byte records = 0x408 bytes total).
- **Step 17: PKM crypto constants (cited from primary sources).** PID-shuffle table = 32-entry array (cases 24..31 mirror cases 0..7), indexed by `((PID >> 13) & 0x1F)`, transcribed from pret/pokeplatinum `src/pokemon.c:4861-4924` `BoxPokemon_GetDataBlock` switch statement. LCG: multiplier `0x41C64E6D` (= 1103515245), increment `0x6073` (= 24691), from pret/pokeplatinum `include/math_util.h:8-9` (`LCRNG_MULTIPLIER` / `LCRNG_INCREMENT`). LCG operation: `seed = seed*mult + inc; ks = seed >> 16` (high 16 bits) per `src/math_util.c:217-234` `EncodeData` + `LCRNG_NextFrom`. Checksum verify: sum of all 64 little-endian u16 words in the decrypted 128-byte payload mod 0x10000 must equal stored checksum at 0x06; mismatch → decoder returns nil. Cross-checked against PKHeX `PokeCrypto.Decrypt45` / `Shuffle45` (identical algorithm).
- **Step 17: Met-location enum (KG-12 closed).** `config/soul_link/met_locations.yml` ships 127 entries (Sinnoh routes 201-230 + cities + dungeons + 5 special pseudo-IDs). Sourced from PKHeX `PKHeX.Core/Resources/text/locations/gen4/text_hgss_00000_en.txt` (235-entry canonical Gen-IV table; entries 0-126 are Sinnoh-relevant) + PKHeX `PKHeX.Core/Game/Locations/Locations.cs` (special IDs: Daycare4=2000, LinkTrade4NPC=2001, LinkTrade4=2002, Ranger4=3001, Faraway4=3002, all flagged event:true). Different enum from `maps.yml` (which is map-header IDs). `SoulLink::GameState` exposes `met_locations` / `met_location_name(id)` / `event_met_location?(id)`; missing IDs surface as "Met-Location #N" via `CatchCoordinator.resolve_route_name` graceful-degradation.
- **Step 17: Egg handling (locked).** PartyParser filters eggs (Block-B IV-dword bit 30, OR species==0 sentinel) before return. Eggs never enter `parsed_party_data` and never hit the diff. When an egg hatches, the next parse sees a "new" PID → fires PokemonCaughtEvent at hatch time. Net behavior: an egg in the party is invisible to the auto-tracker; it materializes as a "caught" event the moment it hatches.
- **Step 17: CatchCoordinator filters & dedup (locked).** (1) Skip eggs (defense in depth — already filtered by PartyParser). (2) Skip zero-PID events (corrupt/empty slot). (3) Skip when session has no claimed discord_user_id. (4) PID dedup: skip if `SoulLinkPokemon.exists?(soul_link_run_id:, discord_user_id:, pid:)` is true (covers deposit-and-re-catch round-trip even though we don't parse the PC box in Step 17). (5) Trade-in detection: compare event TID/SID against the slot's `parsed_trainer_id` / `parsed_secret_id`; if either differs → set `trade_in: true` AND `acquired_via: 'trade_in'`. (6) Event-met filtering: if the met-location is event-flagged → set `acquired_via: 'event_gift'` (precedence over trade_in). (7) Default → `acquired_via: 'catch'`. Row creation wrapped in `slot.transaction { }`. PokemonRemovedEvent is log-only (no auto-mark-dead).
- **Step 17: No partner-linking.** Step-17 `SoulLinkPokemon` rows have `soul_link_pokemon_group_id: nil`. The existing manual 4-player Catch modal flow (which creates `SoulLinkPokemonGroup` + 4 linked rows) is the only path that creates groups. Step 18+ will add automatic partner-pairing logic. Reviewer should flag any Step-17 code that auto-creates groups or auto-assigns to existing groups.
- **Step 18: Per-Pokémon stats — `Pkm` Struct extended in place, eager-decoded.** `nature` (Integer 0..24 from `pid % 25`), `ivs` (Hash with `:hp/:atk/:def/:spe/:spa/:spd` keys, 0..31 each, unpacked from the IV dword's low 30 bits in 5-bit fields), `evs` (Hash same keys, 0..255 each, 6 bytes at unshuffled `0x10..0x15`), `moves` (Array of 4 Hashes `{id:, pp:, pp_up:}`, 4 × u16 IDs at unshuffled `0x20..0x27` + 4 × u8 PP at `0x28..0x2B` + 4 × u8 PP-up at `0x2C..0x2F`). New keyword fields appended after the Step-17 fields so positional-access callers stay stable. Cited from PKHeX `PK4.cs` `Move1` (PK4-absolute 0x28, equivalently unshuffled 0x20 in Block B), `IV32` (PK4 0x38, unshuffled 0x30), `EV_HP..EV_SPD` (PK4 0x18..0x1D, unshuffled 0x10..0x15) — moves are in **Block B**, not Block C as the Step 18 input brief stated (correction caught against PKHeX; brief was an upstream typo). Eager decode rejected lazy as needless state — decryption cost is fixed-per-record.
- **Step 18: PC box parsing layer (KG-21 closed).** `SoulLink::BoxParser` is a sibling to `PartyParser`, not a refactor — same pure-function shape, never raises, returns `Array<Pkm>` (size 0..540) or `[]`. Storage block at partition offset `0xCF2C` (PKHeX `SAV4Pt.cs` `GeneralSize`), size `0x121E4` (PKHeX `StorageSize`); box data starts at `+4` inside the storage block (PKHeX `// Start 0xCF2C, +4 starts box data`). 18 boxes × 30 slots × 136 bytes per record = 0x11EE0 bytes of box-PKM. **Storage block has its own active-block picker independent of the general block** — they can swap partitions independently per PKHeX's `StorageBlockPosition` behavior. CRC body excludes the entire 20-byte footer per PKHeX `SAV4.cs:113` `Checksums.CRC16_CCITT(data[..^FooterSize])` + `SAV4Sinnoh.cs:12` `FooterSize => 0x14` — caught a Must Fix in review where `STORAGE_CRC_RANGE_END` covered only `STORAGE_SIZE - 2` (the 2-byte CRC field) instead of `STORAGE_FOOTER_OFFSET = STORAGE_SIZE - 0x14` (the full footer). Same lesson `SaveParser` learned the hard way for the general block (cited at `save_parser.rb:46-49`). Real Platinum saves would have silently failed CRC on every parse if the bug had shipped — synthetic test builder mirrored the same wrong constant, hiding it.
- **Step 18: `BoxedPokemonObservedEvent` is distinct from `PokemonCaughtEvent`.** Distinction surfaces via `caught_off_feed: true` on the row (NOT NULL boolean default false) + an OFF-FEED pill in the auto-catches grid. Same field shape as the catch event. **No `BoxedPokemonRemovedEvent`** — boxes hold Pokémon long-term; "removed from box" isn't a meaningful Soul Link signal (a withdraw is already covered by the party diff; a release/trade-out is no-op per the existing PokemonRemovedEvent policy).
- **Step 18: Cross-event PID dedup — party first, box second, single transaction.** `CatchCoordinator.process` iterates `catch_events + removal_events + box_events` in that order within a single `slot.transaction { }`. The existing `(soul_link_run_id, discord_user_id, pid)` `.exists?` check no-ops the box-side create when a party-side row already exists for the same PID. Locked by a same-snapshot dual-fire test that asserts exactly one row created with `caught_off_feed: false` (party wins). Net: a single catch produces exactly one `SoulLinkPokemon` row regardless of arrival path.
- **Step 18: Move-name lookup explicitly OUT of scope.** Numeric "Move #N" fallback for v1. Adding `config/soul_link/moves.yml` with all ~467 Gen IV moves is logged as KG-24, adjacent to KG-20 (species ID fallback).
- **Step 17: Dashboard surface = PC BOX tab extension only.** New "AUTO-DETECTED CATCHES" section on `_pc_box_content.html.erb`, scoped to `current_user_id` AND the active run, filtered to `pid IS NOT NULL` AND `soul_link_pokemon_group_id IS NULL`. Per-row render shows species + route + level + first-encounter badge (`1ST`) + trade-in pill (`TRADE-IN`) + event pill (`EVENT`). First-encounter computed live in the view (no controller-side precomputation; the array is per-player so the in-memory group-by is cheap). Real-time refresh inherited from the existing `broadcasts_refreshes_to` on `SoulLinkPokemon` (model line 25; Step 9 surface).
- **Step 19: Discord notifier is a NEW service, NOT a touch of `discord_bot.rb`.** Project review flagged `discord_bot.rb` as a 978-LOC god-object; brief explicitly forbade adding load. New `SoulLink::DiscordNotifier` is class-only, uses `Discordrb::API::Channel.create_message(token, channel_id, content)` directly — same pattern as `DiscordApi.create_run_channels` (`app/services/soul_link/discord_api.rb:8`). Six fire-and-forget public methods: `notify_catch / notify_death / notify_gym_player_progress / notify_gym_team_beaten / notify_wipe / notify_run_complete`. Full rescue chain: specific REST/socket exceptions enumerated for documentation, terminating in `StandardError`. On failure: `Rails.logger.warn` + return; never raises. The underlying coordinator/controller transaction always commits even when Discord is down. Channel routing: catches → `catches_channel_id`, deaths → `deaths_channel_id`, gym/wipe/HoF → `general_channel_id`. Silent no-op when channel-id is blank or run is nil. Token resolved at call-time from `Rails.application.credentials.discord[:token]` and prefixed `"Bot "`. The bot god-object decomposition remains a future step.
- **Step 19: Notifier invocation is at coordinator/controller granularity, NOT pub/sub.** No ActiveSupport::Notifications. No event-bus indirection. Each coordinator/controller path that can mutate observable state ends with a direct `SoulLink::DiscordNotifier.notify_*` call. Specifically: `CatchCoordinator.create_pokemon_row` (party + box paths, after `create!`, inside slot transaction); `GymBeatenCoordinator.process` (per-player on every `BadgeGained`, team on `!was_marked && now_marked` precondition flip); `HallOfFameCoordinator.process` (after `update!(completed_at:)` actually persists; idempotency from existing `completed_at.present?` guard); `PokemonGroupsController#update` (notify_death per linked Pokemon after `mark_as_dead!`, then `WipeCoordinator.process(run)`); `GymProgressController#update` (manual MARK BEATEN = team event by definition; UNMARK fires nothing). The notifier itself is dumb — it doesn't filter or dedupe; the call site decides whether to invoke.
- **Step 19: `WipeCoordinator` idempotency = outer guard + inner double-check inside `with_lock`.** Outer: `return if run.wiped_at.present?` (fast path for already-wiped runs). Inner: same check inside `run.with_lock { }` (handles two concurrent Mark Dead requests racing). Ruby `do/end` block `return` exits the enclosing method, so the post-lock notifier call is unreachable on the idempotent path. Brand-new-run false-positive prevented by `next unless run.soul_link_pokemon.where(discord_user_id: uid).exists?` — players who haven't caught anything aren't candidates for wiping. Wipe trigger: any single player has 0 alive Pokemon (`status: 'caught'` count) AND has caught at least one. Mirrors the user's exact convention: "If we get all our mons killed in a battle, the run is over."
- **Step 19: HoF wins over wipe in `read_only?`.** `SoulLinkRun#read_only? = wiped_at.present? && !completed?`. If both `wiped_at` and `completed_at` are set (defense-in-depth — shouldn't happen via auto-paths since `WipeCoordinator` runs only on Mark Dead transitions and `HallOfFameCoordinator` runs only on save-diff transitions, but possible via direct AR), the COMPLETE pill renders, the wipe banner is suppressed, and affordances stay visible. The semantic argument: HoF means a player actually finished, even if a partner wiped after. Locked decision.
- **Step 19: Read-only mode = UI hide-only in v1.** Server-side authz on the affected endpoints is NOT added in Step 19. The buttons hide via `<% unless dashboard_read_only?(@run) %>` guards; if a determined user crafts a request directly, it still goes through. Locked as the v1 contract; server enforcement (e.g., `before_action :reject_when_read_only` returning 422) is logged as KG-28. The single-source-of-truth helper `ApplicationHelper#dashboard_read_only?(run)` keeps all gating decisions in one place.
- **Step 19: Wipe is reversible via direct AR ONLY.** `run.update!(wiped_at: nil)` is the un-wipe path. No UI for un-wiping in this step. Once cleared, the next dead-state transition can re-fire wipe normally. Mirrors HoF's un-completion path (KG-19). Logged as KG-27.
- **Step 19: Move-name lookup mirrors `met_locations.yml` exactly.** Integer-keyed YAML at `config/soul_link/move_names.yml`, loaded once via `SoulLink::GameState.move_names`, accessed via `move_name(id)`. Unknown / nil → returns nil; caller falls back to `"Move ##{id}"` via `EmulatorHelper#format_move_name(id)` (mirrors `format_map_name`'s shape). Source: PKHeX `text_Moves_en.txt` lines 2..468 (line 1 is the `———` no-move sentinel; ID 0 intentionally absent — the view filters via `m["id"].to_i.positive?`). Cross-checked against pret/pokeplatinum `MOVE_SHADOW_FORCE = 467`. 467 entries, IDs 1..467 contiguous.

### Carried over (still load-bearing)
- Discord user IDs are `bigint` in DB columns, `String` in Stimulus values, coerced at the controller boundary
- All tests use FactoryBot factories from `test/factories/`. Fixtures and the `fixtures :all` test_helper line were removed in Step 8 (2026-04-30).
- **One active SoulLinkRun per guild** is enforced by a virtual-column unique index on `soul_link_runs.active_guild_id` (added in Step 11, 2026-05-01). The column is `(CASE WHEN active = 1 THEN guild_id END)` — value is `guild_id` on active rows, NULL on inactive rows. NULLs don't conflict in unique indexes; multiple inactive runs per guild remain fine. The DB constraint catches any path (controller, channel, raw SQL, manual tampering) that produces a second active run for a guild. `SoulLinkRun.current(guild_id)` is a `find_by` lookup that relies on this invariant.
- **`GymResult` broadcasts a Turbo refresh on every change** (`broadcasts_refreshes_to ->(record) { [ record.soul_link_run, :dashboard ] }`, added Step 15). Covers manual MARK/UNMARK via `GymProgressController`, post-draft mark-beaten via `GymDraftsController#mark_beaten`, and the new auto-mark path from `SoulLink::GymBeatenCoordinator` — all three create through `gym_results.create!` so the broadcast covers every path uniformly. Mirrors the Step 9 KG-2 pattern on `SoulLinkPokemon` and `SoulLinkPokemonGroup`.
