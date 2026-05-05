# Review Feedback — Step 23
**Reviewer:** Richard
**Date:** 2026-05-05
**Ready for Builder:** YES

---

## Must Fix

*None.*

---

## Should Fix

- `app/javascript/controllers/timeline_controller.js:188-221` (`_renderSheetGroupList`) — Brief §11 calls for "render the most-recent group's card prominently AND render a stacked sub-list of additional group cards below" when `groups.length > 1`. Implementation renders all cards with identical styling in `position: asc` order (oldest first), with no "primary/secondary" decoration. Either give the most-recent card a visual lift (the brief's intent), reverse-iterate so most-recent leads, or surface to Architect. The mockup only shows a single-card sheet, so there's no mockup-side reference to fall back on. *(fixed inline at `app/javascript/controllers/timeline_controller.js:194` — `[...groups].reverse().map(...)`)*
- `app/javascript/controllers/timeline_controller.js:99-108` (`selectLocation`) — Each click writes `window.location.hash = ...`, adding a back-stack entry per click. Repeated route-clicking pollutes browser history. Brief §14 said "write `location.hash`," so this is spec-compliant; `history.replaceState(null, "", "#route=" + key)` would honor the brief's intent without history bloat. Optional polish. *(fixed inline at `app/javascript/controllers/timeline_controller.js:106` — `history.replaceState(null, "", "#route=" + encodeURIComponent(key))`)*

---

## Escalate to Architect

- **Multi-group disambiguation rendering order.** `position: asc` puts the OLDEST group first. The brief §11 says "show the most-recent group prominently," but the controller load order is `position: asc` and Bob's JS preserves that DOM order. The user's review prompt asked: "does the rendering order match `position: asc`, so most-recent appears prominently?" — answer: order matches `position: asc`, but `position: asc` shows OLDEST first, not most-recent. Pure product call — depends on what users want when they hit a dupes-clause re-roll. Flagging because the user asked the question directly and the implementation doesn't satisfy it cleanly.

  *Architect resolution: Fixed inline alongside Should Fix #1; see updated `_renderSheetGroupList` at `app/javascript/controllers/timeline_controller.js:194`.*

---

## Cleared

**Spec compliance — Bob's 6 Q&A vs Ava's endorsement, all six landed:**
- **Q1** additive `groups_json_for(groups, current_user_id)` with per-pokemon `id`/`is_mine`/`level`/`ability`/`nature`/`sprite_url`/`types` — ✓ at `app/helpers/map_helper.rb:34-65`. Legacy `species`/`player`/`sprite` fields preserved.
- **Q2** bare-city divider labels via private `bare_city_label` helper (`eterna_city` → `"ETERNA"`) — ✓ at `app/helpers/map_helper.rb:187-191`, asserted at `test/helpers/map_helper_test.rb:110-117, 135-138`.
- **Q3** final divider = `"ELITE FOUR"` for null-gym segment (override of Bob's mockup-verbatim `"…"` default) — ✓ at `app/helpers/map_helper.rb:132-141`, asserted at `test/helpers/map_helper_test.rb:141-149`.
- **Q4** catchable-types-only `segment_progress` denominator (`route`/`dungeon`/`lake`/`special`) — ✓ at `app/helpers/map_helper.rb:149-162`. Caught counts `caught` OR `dead`. Asserted at `test/helpers/map_helper_test.rb:157-181`.
- **Q5** single read-only gate via `hasSheetFormTarget` — ✓. View renders form conditionally at `app/views/map/show.html.erb:319`. JS reads `hasSheetFormTarget` in `_renderSheetCatchForm` (line 168), `_renderSheetGroupList` (line 193 → `readOnly` derivation drives EDIT/MARK DEAD/dupes button rendering), and `showCatchFormForCurrent` (line 283). One gate, one place.
- **Q6** no `readOnlyValue` on the controller — ✓. `static values` block at `app/javascript/controllers/timeline_controller.js:21-28` declares `gymsDefeated`, `csrf`, `gymProgressUrl`, `createGroupUrl`, `pokedexSpecies`, `spriteMap` only. No `readOnly`.

**Visual fidelity to the locked mockup, Screens 1–4 spot-checked:**
- Pulse-ring + `↓ NOW` pin — `app/views/map/show.html.erb:115,131-133` adds `.next` class + the pin only on the next-uncaught route node.
- JUMP TO NOW pill — server gate at `app/views/map/show.html.erb:82-85` (renders `class="jump-btn hidden"` when helper returns nil); JS gate at `app/javascript/controllers/timeline_controller.js:38-41` (re-checks for `.next` node and adds `.hidden`). Both fire on the same condition; harmless redundancy.
- Edge gradient fade — pure-CSS `::before`/`::after` on `.timeline-frame` at `app/assets/stylesheets/pixeldex.css:1170-1181`.
- Always-visible legend — `app/views/map/show.html.erb:89-95`, all 5 glyphs.
- Segment dividers between segments + `ELITE FOUR` before null-gym segment.
- Sticky right-rail sheet — `app/assets/stylesheets/pixeldex.css:1359-1364` (`position: sticky; top: 16px;`).
- Special-encounters bar — `app/views/map/show.html.erb:264-296`, four cells (`gift`/`egg`/`trade`/`other`), each with the click→selectLocation chain.
- Mobile accordion — `app/views/map/show.html.erb:191-262`, native `<details>` per segment, `open` on the segment containing the next-uncaught route via `segment_open_by_default?` server-rendered.

**Click-handler edge cases — walked the JS:**
- No-catch route → `_renderSheetCatchForm` opens form, sets `formLocationKey.value = key`, focuses nickname (`timeline_controller.js:162-186`).
- Multi-player route (multiple groups) → `_renderSheetGroupList` does `groups.map(...)` so N stacked group cards render, plus the dashed dupes button (`timeline_controller.js:188-221`). Confirmed: dupes-clause renders N cards.
- Read-only mode → single `hasSheetFormTarget` gate (above).
- URL hash `#route=<key>` → `applyHashRoute()` at line 59 reads the hash on `connect()`, finds the matching `locationNode`, RAF-defers `_openSheetFromNode`. RAF wrap is defensive only (Stimulus connects after targets exist) — not a true race. Acceptable.

**Fresh verification (re-ran on the worktree):**
- `bin/rails test` — **754 runs, 0 failures, 0 errors** (Bob's claim confirmed).
- `bundle exec rubocop` — **0 offenses across 201 files** (confirmed).
- `bundle exec brakeman -q --no-progress` — **2 weak-confidence warnings** (`emulator_controller.rb:79` SendFile + `gym_schedule_discord_update_job.rb:14` FileAccess), unchanged from Step 22 baseline (confirmed).

**Diff scope:**
- `git diff HEAD --stat` against `app/controllers/`, `app/models/`, `db/`, `app/services/`, `app/jobs/`, `config/`, `Gemfile`, `Gemfile.lock`, `config/importmap.rb` is empty. Zero out-of-scope.
- Dashboard MAP tab (`app/views/dashboard/_map_content.html.erb`) untouched — confirmed via `git diff HEAD --stat`. R1 still owns that surface.
- 7 files outside `handoff/` (5 modified + 2 new). Within budget.

**Modal partials on `/map`:** `<%= render "dashboard/pokemon_modal" %>` + `<%= render "dashboard/mark_dead_modal" %>` at lines 368-369. Wrapper carries every `data-dashboard-*` and `data-pixeldex-*` value attr the modals need (lines 22-32). Asserted at `test/integration/map_redesign_test.rb:176-187` (`data-pixeldex-target="pokemonModal"` + `data-dashboard-target="markDeadModal"` both present).

**CSS bloat (Bob's flagged judgment call: ~545 lines vs Ava's 250–280 estimate).** Walked the R4 section. The 4 surfaces beyond the mockup's chrome — `.group-card`, `.dupes-btn`, `.species-dropdown` inside player-row, `.empty-state` — are JS-built and need named classes. Namespace prefix adds ~10 chars per selector. Accordion `.acc-row` glyph variants are mockup-required. No redundancy I'd cut. Bob made the right call.

**Read-only test (`test/integration/map_redesign_test.rb:127-137`):** asserts the form's server-side absence — the same gate the JS reads via `hasSheetFormTarget`. Without a system-test driver this is the right shape. Bob's inline comment "the JS path is unit-tested separately" is technically inaccurate (no JS tests exist in the project), but the contract under test is correct.

Step 23 is clear.

---

## Architect resolution — Ava, 2026-05-05

Richard's escalate + both Should Fix items resolved. Bob: apply both fixes inline.

**Escalate (multi-group order) — locked:** **most-recent first, no primary/secondary decoration.** Reverse the iteration order in `_renderSheetGroupList` so highest-position renders at the top of the sheet. Top-of-stack IS the prominence; no visual lift needed.

Reasoning: in Soul Link, multiple groups at one route mean dupes-clause re-rolls or "first one died, here's the second." The active/relevant group is the latest one — that's what the user wants surfaced when they click. `position: asc` shows oldest-first which inverts that. Reverse-iterate (`[...groups].reverse().map(...)`) in the JS. This single change resolves both **Should Fix #1** and the Escalate — same root cause.

Update the existing `data-groups` JSON shape test in `map_redesign_test.rb` if it asserts position order; otherwise, keep the existing 2-element assertion and add one more explicit assertion that the JS reverse-iterates (or accept that the order is a JS concern and not test-able without a headless driver — same KG-style reasoning as the URL-hash assertion).

No new "visual lift" CSS for the most-recent card. If a future iteration shows users want explicit primary/secondary treatment, that's its own redesign step — log KG only if you actually noticed something users would miss without it.

**Should Fix #2 (history.replaceState):** **approved.** Replace `window.location.hash = "#route=" + key` with `history.replaceState(null, "", "#route=" + key)` in `selectLocation`. Same one-line spirit; no back-stack pollution. The `connect()` hash read still works the same (reads `location.hash`).

**Build-log delta:** add a one-line note in BUILD-LOG.md Step 23 entry under "Inline fixes folded in mid-review" documenting both changes (mirror Step 22's "the Should Fix … was fixed inline at …" pattern).

After both fixes land:
1. Re-run `bin/rails test` (test count should hold at 754 unless you added a multi-group order assertion).
2. Re-run `bundle exec rubocop` clean.
3. Update `handoff/REVIEW-FEEDBACK.md` Should Fix items: mark each "fixed inline at <file>:<line>" with the new line numbers. Leave the Escalate section's existing copy intact and add an "Architect resolution" line under it pointing to the inline fix.
4. **Stop. Do not commit.** Hand back to Ava for the deploy gate.

Greenlight on the inline fixes.
