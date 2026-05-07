# Session Checkpoint
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*
*Session-scoped — archived to `handoff/archive/` at session end.*

---

## Where We Stopped

Step 28 (Rebuild the dashboard against `designs/04-pixeldex.html` as the canonical reference) shipped on the worktree branch `claude/confident-kare-0d3dab` at `afb39f4`, FF-merged to `origin/main`, and pushed. Awaiting next brief from the Project Owner.

Step 28 follows Step 27 (Restyle the four Phase-2 redesigns to the old `gb-*` idiom). Step 27 made the canon ELEMENTS rarer; Step 28 makes the dashboard READ as the same family as `designs/04-pixeldex.html` — the original PC-Box-inspired UI variation (committed 2026-04-05 in the `designs/` folder) whose `:root` palette literally became the project's `pixeldex.css` tokens.

---

## What Was Built

**Step 28 — Rebuild the dashboard against `designs/04-pixeldex.html`.** Pure visual rebuild. Functional behavior unchanged. Backend / controllers / models / Stimulus targets / WAI-ARIA tablist contract / token palette all untouched.

**Architect prep (Halves 1 + 2):**
- `handoff/2026-05-06-pixeldex-source-extraction.md` — locks the PixelDex source spec (`designs/04-pixeldex.html`'s 849-line file) and diffs the live dashboard against it. Becomes the directive table for Bob's mechanical rebuild.
- `handoff/ARCHITECT-BRIEF.md` — Step 28 brief with 7 directives (D1 title-bar, D2 tab-bar, D3 3-col layout, D4 status-rail, D5 right-rail cards, D6 status-rail markup, D7 show.html.erb) plus test guidance.

**Builder execution (Half 3):** dashboard chrome rebuilt under `.dash-r1` namespace in `pixeldex.css`. 4 ERB views updated mechanically (`_title_bar`, `_tab_bar`, `_status_rail`, `show`). 2 test files touched (1 new assertion + 2 stale assertions retargeted).

**Restyle scope:**
- Title bar adopts PixelDex `--d2` band (1-line `--d2` row with `--l2` text + 3 px ink border-bottom).
- Stat-strip rebuilt to PixelDex `.title-stat` block-grid form via CSS-only flex `column-reverse` (DOM stays — existing test assertions pass unchanged).
- Run-pill restyled to label-on-d2-band form (transparent bg, `--l2` text, 2 px `--l1` underline) so it reads as part of the title bar.
- Tab-bar cells stack icon-above-label per source: `.tab` → `.tab-item`, `.icon` → `.tab-icon`, 20 px glyph block above 13 px label.
- 3-col layout adopts shared-frame form: `gap: 0`, `background: var(--l2)`, per-panel `border-right: var(--border)`.
- `.col-party` wrapper dropped; `_party_panel` participates directly in `.pc-layout`.
- Right rail flattened (transparent wrapper, no boxed inset). `.side-tabs` rebuilt as a horizontal mini `.tab-bar` mirroring the main tab strip.
- Right-rail card aesthetic flips dark → light: `.player-card`, `.gym-list .gym-row`, `.next-battle` rebased to PixelDex light-card form (`--l1` bg + `--border-thin` 2 px). `.gym-row.next` becomes a `.gym-next-highlight` filled bar.
- `.h3-row` → `.panel-header` (× 3); each panel body wrapped in `.panel-body` (× 3).

**Counts:** 782 → 783 tests (+1 new `.tab-item` class assertion). 0 failures / 0 errors / 0 skips. Rubocop clean (203 files). Brakeman: same 2 pre-existing weak-confidence warnings (`emulator_controller.rb:79` SendFile, `gym_schedule_discord_update_job.rb:14` FileAccess); zero delta on Step-28-touched files.

**Files:** `pixeldex.css` (`.dash-r1` namespace block ~lines 2155-2615); 4 ERB views; 2 integration tests; 4 handoff docs (extraction, brief, build log entry, review feedback).

**Review:** Richard cleared 0 / 0 / 0 (Must Fix / Should Fix / Escalate). Spot-checked all 7 directives D1–D7; verified WAI-ARIA tablist contract intact; verified test scoping (new `.tab-item` assertion uses `id="tab-#{key}"` to avoid colliding with status-rail's `status-tab-` ids); verified all CSS hunks fall inside `.dash-r1` namespace; verified `--accent` retained on `.player-card.you` and `.gym-row.beaten .name`.

---

## What Was Decided This Session

- **PixelDex source (`designs/04-pixeldex.html`) is the canonical reference for the dashboard.** Earlier visual decisions (Step 24 mockup-driven, Step 25 design canon, Step 27 chrome-reduction) all sit on top of this base. The dashboard now reads as the same visual family as the source: `--d2` title band, 2-line stacked tabs, shared-frame 3-col layout, light cards in the rail.
- **Run-pill stays functional but visually subordinated.** PixelDex source has run number as static `.title-sub` text; the project keeps the clickable run-picker but restyles it as a label-on-band rather than a stamped-on button. Functional value (run-switching, START NEW RUN) preserved; visual prominence reduced per Step 27 chrome-reduction philosophy.
- **Stat-strip DOM unchanged; visual flip via CSS `flex-direction: column-reverse`.** Existing dashboard_redesign_test assertion `<div class="item"><span>LABEL</span><span class="val">N</span></div>` keeps passing — the LABEL span is first in DOM but renders below the `.val` because of column-reverse. Avoids touching the test scaffolding for a purely visual change.
- **`.col-party` wrapper dropped.** `_party_panel` already provides its own `<div class="panel">` shell; the redundant wrapper was eliminated to match the source structure 1:1. The 900 px breakpoint hide-rule retargets to `.dash-r1 .pc-layout > .panel:first-child`.
- **`.h3-row` → `.panel-header`.** Status-rail sub-panels now use the canonical `.panel-header` primitive at `:root` level (lines ~349–367) rather than the `.dash-r1`-scoped `.h3-row` / `h3` / `.count` rules. Rules deleted in `pixeldex.css`. The canonical rules already match PixelDex source.
- **Side-tabs become horizontal mini `.tab-bar`.** Step 24 added a vertical caps-bar stack; Step 27 restyled to look like stacked `gb-section-header`s; Step 28 rebuilds them as a horizontal strip matching the main tab-bar's `.tab-item` form. Visual rhyme with the main tab-bar — the rail reads as a smaller version of the main 3-panel layout.
- **Right-rail cards flip dark → light.** `.player-card` was `--d2` bg + `--white` text (Step 24 form); now `--l1` bg + `--d1` text matching `.route-card`. `.you` accent border preserved per Step 27 § 11.3. `.gym-list .gym-row` simplified from grid to flex with glyph-prefix `.num`. `.next-battle` rebased from `--d2` block to `.route-card` skin.
- **Body-level scanline overlay covers the dashboard.** No new `.pc-layout::after` overlay needed — D3's "Skip if the body-level scanline already covers this" applied. Avoids double-overlay.
- **Gym list glyphs emitted from ERB, not CSS `::before`.** D5 offered both paths; Bob chose ERB-side glyph emission. Cleaner ERB; no per-row CSS `::before` content rules needed.
- **Stale `responsive_grids_test.rb` assertions updated in lockstep.** Two assertions hard-coded the old `.dash-r1 .col-party` and `.dash-r1 .tab` selector forms; both retargeted to match the new DOM (`.pc-layout > .panel:first-child`) and class (`.tab-item`). Same intent / same coverage / matches the Step 27 pattern of updating visual-chrome assertions when the chrome is restyled.
- **No token values changed.** Step 25's `design_canon_test.rb` keeps passing without modification.
- **No accent changes.** Step 26's `--accent: var(--green-glow)` untouched. PixelDex source uses no accent — accent remains rare per Step 27.

---

## Known Gaps / Future Work

*See `handoff/BUILD-LOG.md` Known Gaps — running list maintained there.*

Step 28 closed nothing — it was a visual rebuild, not a backlog item. No new gaps logged. Two architect-flagged candidates from the diff doc were judgement calls Bob resolved cleanly (no follow-up needed):
- KG-A (Architect-flagged): `.tab` vs `.tab-item` rename — resolved (renamed everywhere; no fallout).
- KG-B (Architect-flagged): right-rail single-panel-header vs sub-tabs — resolved (sub-tabs preserved structurally per Step 24; rebuilt visually as horizontal mini tab-bar).

KG-7, KG-19, KG-20, KG-23, KG-25, KG-26, KG-27, KG-28, KG-29, KG-30, KG-31, KG-32, KG-33, KG-34, KG-35, KG-36, KG-37, KG-38, KG-39 still open from earlier steps.

---

## Resume Prompt

Copy and paste this to resume:

---

You are Ava (Architect) on Soul Link — Three Man Team.
Read handoff/SESSION-CHECKPOINT.md, then handoff/BUILD-LOG.md.
Confirm status and next action. Then wait for direction.

---
