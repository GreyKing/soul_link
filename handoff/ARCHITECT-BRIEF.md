# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 30 — Pivot gym strategy to roster-only (Option C-V2)

Rip out canonical-roster gym strategy (`pixeldex_gym_strategy/2`). Replace with the roster-derived `pixeldex_team_dialog` in the NEXT BATTLE panel only. Strip the canonical "Type: WTR" labels from per-gym list rows and the gym_ready header. Tidy the now-empty `.dialog` shells.

**Finding 5 decision (locked):** Reuse `pixeldex_team_dialog` **verbatim**. No rename. No prose rewrite. Its three output forms ("Team is solid. Watch out for ICE and FGT types." / "Team is at full strength! Full type coverage achieved." / first-balance-note warning) all read correctly in a gym-prep moment — "watch out" is the right register before pressing START GYM DRAFT.

### D1 — Delete `pixeldex_gym_strategy/2` and all six call sites

Helper definition:
- `app/helpers/pixeldex_helper.rb:75-90` — delete the method.

Call sites (all six render the identical canonical-roster string and ALL get removed; D2 reuses one of them as the new TYPE READINESS host):
- `app/views/dashboard/_status_rail.html.erb:167` — inside the NEXT BATTLE panel `prep` div. **Replaced** by D2 (not deleted — repurposed).
- `app/views/dashboard/_status_rail.html.erb:250-253` — Strategy Dialog footer at the bottom of the MAP sub-tab. Delete the entire `<div class="dialog">…</div>` block (lines 250-253).
- `app/views/dashboard/_gyms_content.html.erb:131-134` — `<%# Next gym strategy %>` block. Delete the comment line + the `<div class="dialog">…</div>`.
- `app/views/dashboard/_map_content.html.erb:48-50` — `<div class="dialog">…</div>` after the location list. Delete entire block.
- `app/views/dashboard/_strategy_panel.html.erb:60-63` — `<%# Strategy Dialog %>` block at the bottom of the panel body. Delete the comment line + the `<div class="dialog" style="margin-top: 14px;">…</div>`.

### D2 — Wire roster-derived TYPE READINESS into the NEXT BATTLE panel

**Host file:** `app/views/dashboard/_status_rail.html.erb:167`. The `<div class="prep">` currently wraps `pixeldex_gym_strategy(...)`. Replace the helper call with `pixeldex_team_dialog(@type_analysis, @team_groups.size)` — **same wrapper div, same class, just swap the helper invocation.**

Inputs (already available in this partial — both are set by `DashboardController#index`):
- `@type_analysis` — set at `app/controllers/dashboard_controller.rb:48`.
- `@team_groups` — used elsewhere in the partial; `.size` is the Team-page slot count.

**Example renders Bob will see (must match these — they ARE the helper's actual output today):**
- "Team is solid. Watch out for ICE and FGT types." (gaps case)
- "Team is at full strength! Full type coverage achieved." (no-gaps case)
- balance-note warning string, e.g. "Multiple team members weak to GROUND" (warnings case)
- "No team built yet. Visit the Team page!" (empty-team case)

Do NOT reuse `pixeldex_team_dialog` anywhere else in this step. The PARTY-panel and PARTY-detail call sites stay exactly as they are (deduping the prose dialogs is a separate future step — see Flags).

### D3 — Remove canonical "TYPE" labels from per-gym list rows

`app/views/dashboard/_gyms_content.html.erb`:
- Line 51 — delete the `<span class="type-text" style="border-color: var(--l1);">…TYPE_ABBREVIATIONS[gym["type"]]…</span>` (the NEXT-row type chip). Keep the `NEXT` accent badge on line 52 — that's not type info, it's a state marker.
- Line 70 — delete the `<span class="type-text">…TYPE_ABBREVIATIONS[gym["type"]]…</span>` in the defeated-gym row.
- Line 124 — delete the `<span class="type-text">…TYPE_ABBREVIATIONS[gym["type"]]…</span>` in the future-gym row.

`app/views/map/show.html.erb`:
- Line 55 — `title="<%= gym['name'] %> &mdash; <%= gym['leader'] %> (<%= gym['type'] %>) &mdash; Lv. <%= gym['max_level'] %>"`. Strip the `(<%= gym['type'] %>) ` segment so the tooltip becomes `<%= gym['name'] %> &mdash; <%= gym['leader'] %> &mdash; Lv. <%= gym['max_level'] %>`.
- Line 67 — `<span class="val"><%= next_gym["leader"] %> &middot; <%= next_gym["type"] %>...</span>` in the status bar. Strip ` &middot; <%= next_gym["type"] %>` so the val becomes just `<%= next_gym["leader"] %>`.
- Line 163 — timeline-node tooltip `title="<%= gym['name'] %> &mdash; <%= gym['leader'] %> (<%= gym['type'] %>)"`. Strip ` (<%= gym['type'] %>)`.

`app/views/dashboard/_status_rail.html.erb:152`:
- **Verified clean (no-op).** Line 152 is `<span class="name"><%= gym["leader"]&.upcase %></span>` — leader name only, no type. Proposal and review both flagged this as already-absent. Confirmed by Architect grep. **No edit required.**

### D4 — Strip canonical type from `gym_ready/show.html.erb` header (Finding 1)

`app/views/gym_ready/show.html.erb:19`:
```erb
Leader: <%= @next_gym['leader'] %> &mdash; Type: <%= pixeldex_type_badge(@next_gym['type']) %>
```

**Decision: delete the `&mdash; Type: …` segment.** Keep `Leader: <%= @next_gym['leader'] %>`. Do NOT replace it with a TYPE READINESS line — `gym_ready` already renders OFFENSIVE COVERAGE pills and SHARED WEAKNESSES rows below this header (lines 67-116), which is the same readiness signal in a richer form. Adding a prose line here would duplicate what the page already shows ten lines down.

Resulting line:
```erb
Leader: <%= @next_gym['leader'] %>
```

### D5 — Empty `.dialog` shell cleanup

D1 deletes the `<div class="dialog">…</div>` wrappers entirely at all four center-tab call sites (status_rail:250-253, gyms_content:131-134, map_content:48-50, strategy_panel:60-63) — these blocks were standalone wrapper + helper-call only, so deleting the wrapper IS the cleanup. **No empty `<div class="dialog">` shells will remain in the codebase after D1.**

`.dialog` CSS at `app/assets/stylesheets/pixeldex.css:753-770` (border, background, padding, margin-top: 10px, plus `::after` blinking-arrow pseudo-element) **stays untouched** — the class is still used by the surviving PARTY dialogs at `_party_panel.html.erb:57` and `_party_detail.html.erb:51`. Do not delete the CSS rules.

Cleanup checklist:
1. After D1, grep `grep -rn 'class="dialog"' app/views` — expect exactly two hits (`_party_panel.html.erb`, `_party_detail.html.erb`). If more, you missed a deletion in D1 — go back.
2. Boot `bin/dev`, navigate to dashboard → switch through GYMS / MAP / STRATEGY center tabs. Confirm no leftover bordered box with a blinking ▼ arrow at the bottom of any of those panels.
3. The NEXT BATTLE panel's `<div class="prep">` does NOT use `class="dialog"` — it has its own `.prep` styling. Leave that alone.

### D6 — Test plan

Existing test reality (Architect verified — proposal/review estimates were wrong):
- **No existing helper specs** for `pixeldex_gym_strategy` or `pixeldex_team_dialog`. `test/helpers/pixeldex_helper_test.rb` covers only `recommended_review_action` (4 tests). **Nothing to delete.**
- **No existing view/integration tests** assert on strategy text. Only `test/integration/dashboard_redesign_test.rb:185` references the NEXT BATTLE panel, and it only checks `class="next-battle"` presence — that assertion stays green.

New test work (additive only):
1. Add helper tests in `test/helpers/pixeldex_helper_test.rb` for `pixeldex_team_dialog`. Cover the four output forms: empty team → "No team built yet…"; balance-note warning present → returns `warnings.first[:message]`; gaps with no warnings → "Team is solid. Watch out for X and Y types."; no gaps → "Team is at full strength!". This locks the contract D2 depends on.
2. Add an integration assertion in `test/integration/dashboard_redesign_test.rb` (in the existing NEXT BATTLE panel test): the rail block contains the team-dialog readiness output (use a flexible match like `assert_match(/Team is solid|Team is at full strength|No team built/, rail_block)`) and does NOT contain the deleted canonical-strategy phrasing (`assert_no_match(/uses .{3} types/, rail_block)`).

Test count today: **783 / 0 failures / 0 errors** (verified via BUILD-LOG/SESSION-CHECKPOINT — do NOT re-run before starting). Expected after Step 30: **~785-786** (±1-2 new helper tests + at most 1 integration assertion expansion; no test deletions). State actual count in REVIEW-REQUEST.md.

Lint: `bundle exec rubocop` — clean.

### D7 — Verification (Bob runs before signing REVIEW-REQUEST.md)

1. `bundle exec rubocop` — clean.
2. `bin/rails test` — passes; new total in expected range above.
3. `bin/dev` boot, sign in, dashboard load (`http://localhost:3000`):
   - **NEXT BATTLE panel (right rail GYMS sub-tab):** shows leader name + city + level cap + a roster-derived prose line (one of the four `pixeldex_team_dialog` outputs) + START GYM DRAFT button. **Must NOT show** any "Crasher Wake uses WTR types" / "Consider adjusting your team" / "Your team has good coverage" phrasing — those strings should grep-zero in the codebase after D1.
   - **GYMS center tab:** per-gym rows show leader + level only. No `WTR/ICE/FGT/etc.` chip. No bordered dialog box at the bottom of the panel.
   - **MAP center tab:** location list renders. No bordered dialog box at the bottom.
   - **STRATEGY center tab:** OFFENSIVE COVERAGE pills, NO COVERAGE pills, SHARED WEAKNESSES rows, NOTES — all still render. **No bordered dialog box at the bottom** (the helper-driven one is gone).
   - **MAP right-rail sub-tab:** location/objective info renders. No bordered dialog box at the bottom.
4. `/map` standalone page: badge-strip tooltips show `Name — Leader — Lv. NN` (no `(Type)`). Status bar NEXT GYM val shows leader name only (no `· Water`). Timeline node tooltips show `Name — Leader` (no `(Type)`).
5. `/gym_ready`: header reads `Leader: Crasher Wake` (or whichever leader is next). Below it: OFFENSIVE COVERAGE / SHARED WEAKNESSES / TYPE DISTRIBUTION / AVAILABLE ROUTES sections all render unchanged. No "Type: WTR" badge in the header.
6. Final grep sanity-check (Bob runs, expects zero hits in `app/`):
   - `grep -rn 'pixeldex_gym_strategy' app/` → 0
   - `grep -rn 'gym\["type"\]' app/views/dashboard/_gyms_content.html.erb app/views/map/show.html.erb` → 0
   - `grep -rn "next_gym\['type'\]\|next_gym\[\"type\"\]" app/views/gym_ready/` → 0

### Files in scope

| File | Change |
|---|---|
| `app/helpers/pixeldex_helper.rb` | Delete `pixeldex_gym_strategy/2` (lines 75-90). Leave `pixeldex_team_dialog` (lines 93-111) untouched. |
| `app/views/dashboard/_status_rail.html.erb` | L167 — swap `pixeldex_gym_strategy(...)` for `pixeldex_team_dialog(@type_analysis, @team_groups.size)`. L250-253 — delete the Strategy Dialog `<div class="dialog">…</div>` block + its `<%# Strategy Dialog %>` comment. |
| `app/views/dashboard/_gyms_content.html.erb` | L51, L70, L124 — delete the three `<span class="type-text">…</span>` chips that render `TYPE_ABBREVIATIONS[gym["type"]]`. L131-134 — delete the trailing `<%# Next gym strategy %>` block. |
| `app/views/dashboard/_map_content.html.erb` | L48-50 — delete the `<div class="dialog">…</div>` block. |
| `app/views/dashboard/_strategy_panel.html.erb` | L60-63 — delete the `<%# Strategy Dialog %>` block. |
| `app/views/map/show.html.erb` | L55 — strip ` (<%= gym['type'] %>)` from the badge tooltip. L67 — strip ` &middot; <%= next_gym["type"] %>` from the status-bar val. L163 — strip ` (<%= gym['type'] %>)` from the timeline-node tooltip. |
| `app/views/gym_ready/show.html.erb` | L19 — strip ` &mdash; Type: <%= pixeldex_type_badge(@next_gym['type']) %>`, leave `Leader: <%= @next_gym['leader'] %>`. |
| `test/helpers/pixeldex_helper_test.rb` | Add 4 tests covering the four `pixeldex_team_dialog` output forms. |
| `test/integration/dashboard_redesign_test.rb` | Extend the existing NEXT BATTLE rail-block assertion: positive-match a `pixeldex_team_dialog` output, negative-match the deleted `uses .{3} types` phrasing. |

Nine files. No new files. No CSS edits. No layout changes. No controller changes. No migrations.

### Flags

- **Reuse-verbatim is final.** Architect chose to reuse `pixeldex_team_dialog` as-is (Finding 5 decision above). Do NOT rewrite the helper's prose unilaterally — if you read its output and feel "Watch out for ICE and FGT types" sounds wrong in NEXT BATTLE, **pause and escalate** before editing the helper. The defensive framing was deliberately accepted as fitting the gym-prep moment.
- **Helper rename: do not.** The proposal §4 floated renaming `pixeldex_team_dialog` → something gym-aware. Architect rejected. Same helper, two render contexts (PARTY and NEXT BATTLE), is correct — its output describes the team's readiness, which is meaningful in both surfaces. If you find yourself wanting to rename mid-build, escalate.
- **Scope creep: dedup of PARTY dialogs.** Proposal §6a recommends also dropping the `pixeldex_team_dialog` calls in `_party_panel.html.erb:57` and `_party_detail.html.erb:51` to avoid same-screen prose duplication. **Out of scope for Step 30.** Will be filed as a Known Gap candidate after this ships. Do not touch those two call sites.
- **Scope creep: dead `_pc_box_panel.html.erb`.** Proposal §2g flags the file as dead code (no `render` references it). **Out of scope for Step 30.** Do not delete it here — separate sweep.
- **Surprise canonical-roster surface?** If grep turns up a `gym["type"]` / `next_gym["type"]` reference Architect did not list (e.g., a Stimulus controller computing matchups client-side, a YAML-driven helper, a partial Architect missed), **STOP** — do not expand scope to fold it in unilaterally. Surface the find, the file:line, and propose. The intent of Step 30 is "the canonical-roster claims Architect inventoried." Newly-discovered ones get triaged before they're touched.
- **`.dialog` CSS:** stays. The class survives via PARTY dialogs. Do NOT delete `pixeldex.css:753-770`.
