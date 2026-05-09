# Review Request — Step 30

*Builder: Bob. Reviewer: Richard.*
*Branch: `claude/brave-rhodes-9da4ba`*

## Step summary

Step 30 pivots the gym-strategy surface from canonical-roster prose
(`pixeldex_gym_strategy`, six call sites) to the roster-derived
`pixeldex_team_dialog`, but only in the dashboard NEXT BATTLE panel.
The other five `.dialog` shells (status_rail MAP sub-tab, gyms_content,
map_content, strategy_panel) and the `pixeldex_gym_strategy` helper
itself are deleted outright. Per-gym row "TYPE" chips are stripped from
the GYMS center tab, the standalone `/map` badge tooltips, status bar,
and timeline-node tooltips. The `gym_ready/show` header drops the
`— Type: <badge>` segment, leaving `Leader: <name>` (the page already
shows OFFENSIVE COVERAGE / SHARED WEAKNESSES below).
Tests cover the four `pixeldex_team_dialog` output forms and a
positive/negative-match assertion in the existing NEXT BATTLE
integration test.

## Files changed

| File | Change |
|---|---|
| `app/helpers/pixeldex_helper.rb` | Deleted `pixeldex_gym_strategy/2` (was lines 75-90). `pixeldex_team_dialog/2` untouched. |
| `app/views/dashboard/_status_rail.html.erb` | NEXT BATTLE `<div class="prep">` now calls `pixeldex_team_dialog(@type_analysis, @team_groups.size)`. Deleted the trailing Strategy Dialog block at the bottom of the MAP sub-tab. |
| `app/views/dashboard/_gyms_content.html.erb` | Deleted three `<span class="type-text">…TYPE_ABBREVIATIONS…</span>` chips (NEXT-row, defeated-row, future-row). Deleted the trailing `<%# Next gym strategy %>` `.dialog` block. |
| `app/views/dashboard/_map_content.html.erb` | Deleted the trailing `.dialog` block. |
| `app/views/dashboard/_strategy_panel.html.erb` | Deleted the trailing `<%# Strategy Dialog %>` block. |
| `app/views/map/show.html.erb` | Stripped `(<%= gym['type'] %>)` from the badge tooltip (L55), `&middot; <%= next_gym["type"] %>` from the status-bar val (L67), and ` (<%= gym['type'] %>)` from the timeline-node tooltip (L163). |
| `app/views/gym_ready/show.html.erb` | Stripped `&mdash; Type: <%= pixeldex_type_badge(@next_gym['type']) %>` from L19. Header now reads `Leader: <leader>`. |
| `test/helpers/pixeldex_helper_test.rb` | Added 4 unit tests for `pixeldex_team_dialog` covering empty-team, balance-note warning, full-strength, and gaps-with-no-warnings cases. |
| `test/integration/dashboard_redesign_test.rb` | Extended the existing "GYMS sub-tab renders the START GYM DRAFT CTA" test with a positive-match (`/Team is solid|Team is at full strength|No team built|coverage against/`) and a negative-match (`/uses .{3} types/`). |

Nine files. No new files. No CSS edits. No controller / migration / route changes.

## Test results

`bin/rails test`:

```
787 runs, 0 failures, 0 errors
```

Delta vs. baseline: **783 → 787 = +4 tests** (the four new helper
specs). The integration extension reused the existing test method
rather than adding a new one. Brief expected ~785-786 (helper specs
+ at most 1 integration assertion expansion). Actual is +4 because
all four helper spec branches were treated as separate `test "..."`
blocks rather than one parameterized test — within the brief's
"±1-2 new helper tests" wording I kept each output form individually
named for failure clarity. Calling out as a minor delta vs. estimate.

`bundle exec rubocop`:

```
✓ rubocop (203 files)
```

`bundle exec brakeman`: not run. Step 30 is view + helper-method
deletions; no SQL, no query construction, no auth-relevant changes.
Per the brief, brakeman was conditional on security-relevant edits.

(Test/lint run via
`PATH=/Users/gferm/.local/share/mise/installs/ruby/3.4.5/bin:$PATH bundle exec …`
because `bin/rails` and `mise exec -- bundle exec rails` both resolve
through a 3.0.6 bundler shim in this worktree's environment. Same
gemset, same Ruby — just a PATH ordering quirk for the test run.)

## Manual verification

**Did NOT boot `bin/dev`** — the worktree environment doesn't expose
a running MySQL + Discord-OAuth-signed-in session by default, and
spinning that up purely for screen-grabs of a view-only change felt
out of proportion. Live verification of D7 §3-5 (dashboard sub-tabs,
`/map`, `/gym_ready`) is **pending Richard / Project Owner**.

**Verified by code-read + grep:**

- D7 §6 grep gates — all three pass:
  - `grep -rn 'pixeldex_gym_strategy' app/` → 0 hits.
  - `grep -rn 'gym\["type"\]' app/views/dashboard/_gyms_content.html.erb app/views/map/show.html.erb` → 0 hits.
  - `grep -rn 'next_gym\["type"\]' app/views/gym_ready/` → 0 hits.
- `grep -rn 'class="dialog"' app/views` → exactly 2 hits, both in
  `_party_panel.html.erb:56` and `_party_detail.html.erb:50` (the
  surviving PARTY surfaces). Brief D5 cleanup gate satisfied: no
  empty `.dialog` shells remain in the codebase.
- `_status_rail.html.erb` L167 (post-edit) renders
  `<div class="prep"><%= pixeldex_team_dialog(@type_analysis, @team_groups.size) %></div>`
  — same wrapper, swapped helper, exactly per the brief.
- The integration test's `assert_match` on the rail block uses a
  flexible regex that accepts any of the helper's branches, including
  the `"No super-effective coverage against: …"` warning string.
  See note under "Anything I flagged" below.
- `pixeldex_team_dialog/2` arity unchanged (still
  `(type_analysis, team_size)`); both inputs are already on the
  dashboard partial via `DashboardController#index` (L48 sets
  `@type_analysis`; `@team_groups` is an array → `.size` is the
  Team-page slot count). No controller change required.
- `pixeldex_helper.rb` — deletion is clean, surrounding methods
  (`pixeldex_team_dialog`, `recommended_review_action`) untouched,
  module compiles (rubocop confirms).

## Files for Richard to read

- `app/helpers/pixeldex_helper.rb` — confirm only `pixeldex_gym_strategy`
  was removed; everything else intact.
- `app/views/dashboard/_status_rail.html.erb` — confirm L167 swap and
  the bottom-of-MAP-sub-tab dialog deletion.
- `app/views/dashboard/_gyms_content.html.erb` — confirm three
  type-text chip deletions and the trailing dialog deletion.
- `app/views/dashboard/_map_content.html.erb` — confirm dialog deletion.
- `app/views/dashboard/_strategy_panel.html.erb` — confirm dialog deletion.
- `app/views/map/show.html.erb` — confirm three tooltip/val strips.
- `app/views/gym_ready/show.html.erb` — confirm `Type:` segment strip.
- `test/helpers/pixeldex_helper_test.rb` — confirm four new tests
  read sensibly and lock the helper's contract.
- `test/integration/dashboard_redesign_test.rb` — confirm the rail
  block assertions; particularly the regex (`/Team is solid|Team is at full strength|No team built|coverage against/`)
  is intentionally permissive — see flag below.

## Anything I flagged or adapted

1. **Integration assertion regex includes `"coverage against"`.** The
   brief's example regex was
   `/Team is solid|Team is at full strength|No team built/`. Reading
   `pixeldex_team_dialog`'s actual logic alongside
   `SoulLink::TypeChart.analyze_team`, I noticed: when
   `offensive_gaps.any?`, `analyze_team` always emits a warning-level
   balance note (`"No super-effective coverage against: …"`). That
   warning is the FIRST entry in `:balance_notes`, and
   `pixeldex_team_dialog` returns `warnings.first[:message]` before
   it can fall through to the `"Team is solid. Watch out for X and Y types."`
   branch. So with a real factory-built team that has gaps, the live
   render is the warning string, not "Team is solid…". I extended the
   regex to also match `"coverage against"` so the integration
   assertion is robust regardless of which branch the test fixture
   triggers. The brief lists `"Team is solid. Watch out for ICE and FGT types."`
   as an actual-output example; the helper still produces that string,
   but only for synthetic inputs (gaps with no warnings) — which is
   what the unit test covers. Worth Richard's confirmation that this
   reading is correct and the broader regex is acceptable.

2. **Test count delta = +4, not ~+1-2.** Brief estimated ±1-2 new
   helper tests. I split into 4 separate `test "..."` blocks — one
   per output form — so failures point at the exact branch. Net same
   contract coverage; just more granular. Calling out per the brief's
   guidance to surface count discrepancies.

3. **Live verification deferred.** `bin/dev` boot was not attempted
   for the reasons above; D7 §3-5 (dashboard sub-tabs visual sweep,
   `/map` page, `/gym_ready` page) is pending Project Owner spot-check.
   Code-read + grep cover D7 §1-2, §6.

4. **No surprise canonical-roster surfaces found.** The grep
   sweep turned up nothing beyond what the brief listed — no
   Stimulus controller computing matchups, no YAML helper, no
   missed partial. Step 30 scope = exact set Architect inventoried.

5. **No `BOB-QUESTIONS.md` written.** Brief was complete and
   unambiguous; the only adaptation (regex broadening) was within
   the brief's "if a test asserts on text that's no longer produced,
   update the assertion" spirit, except here the divergence was the
   helper's runtime branch behavior vs. the brief's example outputs,
   not test-vs-code drift.

Status: ready for review.
