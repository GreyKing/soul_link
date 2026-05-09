# Review Feedback — Step 30

*Reviewer: Richard. Builder: Bob. Branch: `claude/brave-rhodes-9da4ba`.*

## Verdict

**STEP 30 IS CLEAR** — Ava can ship.

The build matches the brief item-by-item. The two findings rolled up from the prior review (canonical Type label at `gym_ready/show.html.erb:19`, empty `.dialog` shell risk) are both fully resolved. Tests pass, rubocop is clean, no stale references survive in the codebase. Bob's one in-flight adaptation (broadening the integration regex to also match `coverage against`) is correct and well-reasoned — verified against `SoulLink::TypeChart#analyze_team`.

Findings: **0 Blocker · 0 Major · 0 Minor · 2 Nit.**

---

## Findings

### Nit 1 — Empty-team unit test could exercise its precedence more pointedly

**Where:** `test/helpers/pixeldex_helper_test.rb:33-36`

**Claim:** The empty-team test passes `balance_notes: []` and `offensive_gaps: []` along with `team_size: 0`. Because the `team_size == 0` early-return fires first, neither of those keys is read.

**What I found:** The test correctly asserts the early-return string, but it doesn't *prove* the early-return takes precedence over warnings/gaps. A version that passed `team_size: 0` with non-empty `balance_notes` and `offensive_gaps` would lock the precedence ordering more tightly.

**What should change:** Optional. Brief D6 only required the four output forms be covered, and they are. File this as polish for a future helper-test pass; not a blocker for ship.

### Nit 2 — Integration test only hits the empty-team branch

**Where:** `test/integration/dashboard_redesign_test.rb:179-194`

**Claim:** The new `assert_match` regex is permissive (matches any of four branches), but the test setup (`create(:soul_link_run)` with no team) only ever triggers the "No team built yet…" branch.

**What I found:** The assertion is meaningful — it locks the contract that the prep div renders team-dialog output rather than the deleted canonical-strategy phrasing. But the other three helper branches are only exercised by the unit tests, not end-to-end. That's a sensible split (integration test is "is the helper invoked here at all?", units are "does the helper produce the right strings?"), and matches the brief's split-of-concerns.

**What should change:** Nothing for Step 30. If a later step expands the dashboard fixture to include factory-built teams, this assertion will start exercising the warning branch automatically — the regex is already broad enough.

---

## Verification I ran

### Brief compliance, item by item

- **D1 (delete `pixeldex_gym_strategy/2` + 6 call sites):** PASS.
  - `app/helpers/pixeldex_helper.rb` — method gone (file now jumps from `pixeldex_team_dialog` at L75 to `recommended_review_action` at L100; old method was at 75-90). Surrounding helpers untouched.
  - `app/views/dashboard/_status_rail.html.erb:167` — repurposed to `pixeldex_team_dialog(@type_analysis, @team_groups.size)`. Bottom-of-MAP-sub-tab dialog block deleted (file now ends RECENT ROUTES → close `panel-body` directly).
  - `app/views/dashboard/_gyms_content.html.erb` — trailing `<%# Next gym strategy %>` block deleted (file now ends with the GYM LEADERS route-card → close panel-body).
  - `app/views/dashboard/_map_content.html.erb` — trailing `.dialog` block deleted (file now ends with ROUTES IN CURRENT SEGMENT route-card).
  - `app/views/dashboard/_strategy_panel.html.erb` — trailing `<%# Strategy Dialog %>` block deleted (file now ends with the BALANCE NOTES section).

- **D2 (wire `pixeldex_team_dialog` into NEXT BATTLE):** PASS. `_status_rail.html.erb:167` swapped helper, same wrapper div, same `class="prep"`. Inputs (`@type_analysis`, `@team_groups.size`) match what the brief specified.

- **D3 (remove canonical TYPE chips):** PASS.
  - `_gyms_content.html.erb` — only one `type-text` span remains, at L51, and its content is `NEXT` (the state marker the brief said to keep), not a type abbreviation. The three deleted chips at the former L51/70/124 positions are gone.
  - `map/show.html.erb:55` — title now `<%= gym['name'] %> &mdash; <%= gym['leader'] %> &mdash; Lv. <%= gym['max_level'] %>` (no `(type)`).
  - `map/show.html.erb:67` — val is just `<%= next_gym["leader"] %>` (no `· type`).
  - `map/show.html.erb:163` — title now `<%= gym['name'] %> &mdash; <%= gym['leader'] %>` (no `(type)`).
  - `_status_rail.html.erb:152` — verified clean per brief no-op.

- **D4 (`gym_ready/show.html.erb:19` Type label deletion — Finding 1):** PASS. Line 19 now reads `Leader: <%= @next_gym['leader'] %>` with no trailing `&mdash; Type: …` segment. Surrounding markup (the `gb-card-dark` row with gym number, name, level cap below) still parses cleanly — no orphan `&mdash;`, no dangling separator. Layout is still sensible: name on L17, leader on L19, level cap on L21.

- **D5 (empty `.dialog` cleanup — Finding 2):** PASS — **the highest-risk regression is fully handled.** Verified via `grep -rn 'class="dialog"' app/views`:
  - `_party_panel.html.erb:56` — wraps `pixeldex_team_dialog(@type_analysis, @team_groups.size)` (real content, kept per brief).
  - `_party_detail.html.erb:50` — wraps `pixeldex_team_dialog(@type_analysis, @team_groups.size)` (real content, kept per brief).
  - **No empty `.dialog` shells anywhere.** At every former call site, Bob deleted the wrapper div *along with* the helper invocation — not just the call. The CSS at `pixeldex.css:753-770` is preserved (the class is still alive via the two PARTY usages above).

- **D6 (test plan):** PASS.
  - 4 helper specs added (`test/helpers/pixeldex_helper_test.rb:33-66`), one per output form. Each is hermetic (no factory deps in the assertion paths), uses literal hash inputs, and asserts the exact return string. Coverage of the four branches is complete.
  - Integration assertion expansion at `test/integration/dashboard_redesign_test.rb:188-193` adds the positive-match (broadened to also include `coverage against` — see "Bob's adaptation" below) and the negative-match for the deleted `uses .{3} types` phrasing.
  - Stale-reference grep — `grep -rn 'gym_strategy\|Crasher Wake\|uses Water' test/` returns zero hits. No stale tests survived.

- **D7 (verification):** PASS for §1, §2, §6 (rubocop, tests, grep gates). §3-5 (live `bin/dev` boot) remains deferred — see "Live verification gap" below.

### Two findings rolled up from prior review

- **Finding 1 (`gym_ready/show.html.erb:19`):** Resolved per D4. The `Type: <badge>` segment is gone; `Leader: <leader>` remains. Below it the file still renders OFFENSIVE COVERAGE (L72), SHARED WEAKNESSES (L97), TYPE DISTRIBUTION (L120), AVAILABLE ROUTES (L141) — all intact. No replacement TYPE READINESS prose was inserted, matching the brief's "delete the badge entirely, no replacement" decision.

- **Finding 2 (empty `.dialog` shells):** Resolved per D5. Verified by greping `class="dialog"` across `app/views` and confirming both surviving hits wrap real `pixeldex_team_dialog` content. Bob deleted wrapper-and-content together at every center-tab call site rather than leaving the wrapper behind.

### Bob's adaptation (regex broadening) — accepted

Bob added `coverage against` to the integration regex beyond the brief's literal `/Team is solid|Team is at full strength|No team built/`. I confirmed his reading by reading `app/services/soul_link/type_chart.rb:115-120`: when `offensive_gaps.any?`, `analyze_team` always pushes a `:warning` balance note as the first entry (`"No super-effective coverage against: …"`). Because `pixeldex_team_dialog` returns `warnings.first[:message]` before falling through to the "Team is solid…" branch, the "Team is solid…" string is unreachable from a real factory-built team — only synthetic test inputs hit it (which is what the unit test does). Without Bob's broadening, the integration regex would silently fail in any future scenario where the test fixture grows to include a real team. The adaptation is correct and within the brief's "if a test asserts on text that's no longer produced, update it" spirit.

### Test count delta

Brief estimate: 783 → ~785-786 (±1-2 helper tests + 1 integration assertion).
Actual: 783 → 787 (+4). The +2 over estimate is because Bob split the four output forms into four separate `test "..."` blocks rather than one parameterized test. Net contract coverage is identical; failure granularity is better. Within the brief's tolerance.

### Live verification gap

`bin/dev` boot was deferred (no MySQL/OAuth in worktree). D7 §3-5 (visual sweep of dashboard sub-tabs, `/map`, `/gym_ready`) remains pending Project Owner spot-check. I did the layout-integrity check by reading the rendered output paths:

- `_status_rail.html.erb:167` — `<div class="prep">` swap is in-place. No structural change to NEXT BATTLE panel; same parent, same siblings.
- `_status_rail.html.erb` MAP sub-tab — last `<div class="route-card">` is RECENT ROUTES (L232-248); panel-body closes cleanly at L250. No dangling separator, no orphan column.
- `_gyms_content.html.erb:51` — `NEXT` chip kept (state marker, not type info), per brief.
- `_gyms_content.html.erb:66-82` (defeated row) and `:118-124` (future row) — leader name + level on each row. No stray spacers where the type chip used to be.
- `map/show.html.erb:55,67,163` — surrounding `&mdash;` separators are still in their original positions; no dangling `—` orphans.
- `gym_ready/show.html.erb:19` — single line, single value (`Leader: <leader>`); no trailing separator. Lines 17/19/21 form a clean three-line label/leader/levelcap stack.

### Commands run

```
PATH=/Users/gferm/.local/share/mise/installs/ruby/3.4.5/bin:$PATH bundle exec rubocop
  → ok ✓ rubocop (203 files)

PATH=/Users/gferm/.local/share/mise/installs/ruby/3.4.5/bin:$PATH bundle exec rails test
  → 787 runs, 0 failures, 0 errors

grep -rn 'pixeldex_gym_strategy' app/ test/ config/
  → 0 hits

grep -rn 'class="dialog"' app/views
  → 2 hits (_party_panel.html.erb:56, _party_detail.html.erb:50, both wrap real content)

grep -rn 'gym\["type"\]' app/views/dashboard/_gyms_content.html.erb app/views/map/show.html.erb
  → 0 hits

grep -rn "next_gym\['type'\]\|next_gym\[\"type\"\]" app/views/gym_ready/
  → 0 hits

grep -rn 'gym_strategy\|Crasher Wake\|uses Water' test/
  → 0 hits

grep -rn 'TYPE_ABBREVIATIONS' app/views/dashboard/_gyms_content.html.erb app/views/map/show.html.erb
  → 0 hits

grep -n '\.dialog' app/assets/stylesheets/pixeldex.css
  → still present at L753, L763 (preserved per brief)
```

The same Ruby-3.0.6-bundler PATH issue Bob reported is present on my end too; same workaround used.

---

## What Bob got right

1. **The empty-`.dialog` regression risk was fully neutralized.** Verified by grepping `class="dialog"` across `app/views` and confirming every surviving hit wraps real `pixeldex_team_dialog` content. At all four center-tab call sites Bob deleted the wrapper-and-content together rather than leaving an orphan div.

2. **The regex-broadening adaptation was the right call and was flagged transparently.** Reading `SoulLink::TypeChart#analyze_team:115-120` confirms his reasoning: with real factory data, the "Team is solid…" branch is unreachable because `analyze_team` always emits a warning first when gaps exist. Without his broadening, the integration assertion would silently misfit reality.

3. **No scope creep.** The brief explicitly out-of-scoped the PARTY-dialog dedup and `_pc_box_panel.html.erb` cleanup; both are untouched. The grep sweep also confirms no surprise canonical-roster surfaces were folded in unilaterally.

4. **Helper specs are hermetic and per-branch.** Four `test "..."` blocks instead of one parameterized — gives clean failure pinpointing if a future regression hits one branch. Inputs are literal hashes; no factory coupling.

5. **`gym_ready/show.html.erb:19` cleanup is surgical.** Just the `&mdash; Type: …` segment was stripped; the surrounding three-line stack still reads cleanly. Layout below (OFFENSIVE COVERAGE / SHARED WEAKNESSES / TYPE DISTRIBUTION / AVAILABLE ROUTES) is untouched.
