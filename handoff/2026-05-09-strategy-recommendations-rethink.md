# Strategy / Recommendations — Rethink for Randomizer Runs
*Architect (Ava) — 2026-05-09 — proposal doc, no code changes.*

---

## 1. TL;DR

The dashboard mixes two genuinely different things under the umbrella of "strategy." One — **type-coverage / shared-weakness analysis of the user's own roster** — is universally valid in any run, randomized or not. The other — **leader-specific advice** ("CRASHER WAKE uses WTR types. Consider adjusting your team for better matchups.") — reads canonical Platinum gym data that is wrong in every randomized run. The bad advice is concentrated in **one helper, one line**: `pixeldex_gym_strategy/2` in `app/helpers/pixeldex_helper.rb:75-90`. It's rendered identically from four surfaces (status rail × 2, gyms tab, map tab, strategy tab). Coverage % and shared-weakness data is genuinely duplicated four ways too — but that's a presentation problem, not a correctness problem.

**One-line recommendation: rip out `pixeldex_gym_strategy` entirely, keep the `TypeChart.analyze_team` outputs, and consolidate the four "coverage / weaknesses / balance notes" surfaces into one canonical home (the STRATEGY tab) plus one compact stat in the always-visible PARTY sidebar.**

---

## 2. Inventory — every strategy / recommendation surface

All paths are absolute-from-repo-root for grep convenience. Classification key:
- **C** = canonical-roster (reads `gym_info.yml` leader/type → broken in randomizer)
- **U** = user-roster (reads the player's caught Pokémon → still valid)
- **T** = pure type-chart (constants only → universally valid)
- **M** = mixed (mixes C inputs into U computation)

### 2a. The problem function

| File:line | What it does | Class |
|---|---|---|
| `app/helpers/pixeldex_helper.rb:75-90` `pixeldex_gym_strategy(next_gym, type_analysis)` | Builds the literal "CRASHER WAKE uses WTR types. Your team has good coverage / Consider adjusting your team..." string. Reads `next_gym["leader"]`, `next_gym["type"]` from `gym_info.yml`. | **C** |

Used from:
- `app/views/dashboard/_status_rail.html.erb:167` — GYMS sub-tab "NEXT BATTLE" panel `prep` line (the screenshot's right-rail callout)
- `app/views/dashboard/_status_rail.html.erb:252` — MAP sub-tab "Strategy Dialog" footer
- `app/views/dashboard/_gyms_content.html.erb:133` — Center GYMS tab dialog footer
- `app/views/dashboard/_map_content.html.erb:49` — Center MAP tab dialog footer
- `app/views/dashboard/_strategy_panel.html.erb:62` — Center STRATEGY tab dialog footer

→ **Five render sites, identical output**. (Six if you count both `_status_rail` calls.)

### 2b. Roster-aware "team dialog" — sounds canonical, isn't

| File:line | What it does | Class |
|---|---|---|
| `app/helpers/pixeldex_helper.rb:93-111` `pixeldex_team_dialog(type_analysis, team_size)` | "Team is solid. Watch out for ICE and FGT types." — pulls only from `type_analysis[:offensive_gaps]` and `[:balance_notes]`. No gym data. | **U** |

Used from:
- `app/views/dashboard/_party_panel.html.erb:57` — PARTY sidebar dialog
- `app/views/dashboard/_party_detail.html.erb:51` — Center PARTY tab dialog

→ Two render sites, both valid in randomizer runs.

### 2c. Coverage stats / pills / gaps

All five surfaces below feed off the same `@type_analysis = SoulLink::TypeChart.analyze_team(@team_pokemon)` (`app/controllers/dashboard_controller.rb:48`). They differ only in **rendering granularity**.

| File:line | Surface | Renders |
|---|---|---|
| `app/views/dashboard/_party_panel.html.erb:50-53` | Sidebar PARTY stat row | `COVERAGE 9/17` (fraction) |
| `app/views/dashboard/_party_detail.html.erb:45` | Center PARTY tab stat row | `COVERAGE 9/17` (fraction, identical) |
| `app/views/dashboard/_pc_box_content.html.erb:249-285` | PC BOX right rail "TYPE COVERAGE" card | `COVERED · 9` pills, `GAPS · 8` pills, top-3 `SHARED WEAKNESSES` pills |
| `app/views/dashboard/_strategy_panel.html.erb:7-48` | STRATEGY tab body | OFFENSIVE COVERAGE pills + NO COVERAGE pills + SHARED WEAKNESSES rows + BALANCE NOTES |
| `app/views/dashboard/_pc_box_panel.html.erb:84-112` | **(dead code — see §2g)** | Old sidebar TYPE COVERAGE block |

→ Class **U/T** (pure type-chart over the user's roster). Universally valid, but visually duplicated.

### 2d. Gym-leader list views (canonical, but differently broken)

| File:line | Surface | Renders | Class |
|---|---|---|---|
| `app/views/dashboard/_status_rail.html.erb:124-156` | Right-rail GYMS sub-tab list | `ROARK` / `Lv 14` rows w/ glyph | **C** (level cap is the leader's highest mon — randomized too) |
| `app/views/dashboard/_status_rail.html.erb:158-171` | Right-rail "NEXT BATTLE" panel — **the panel in the screenshot** | leader name + city + level cap + `pixeldex_gym_strategy` blurb + START GYM DRAFT CTA | **M** (level cap C + strategy line C; CTA itself U) |
| `app/views/dashboard/_gyms_content.html.erb` (whole file) | Center GYMS tab — badge case + per-gym list w/ `type` badge + level cap + dialog footer | leader name, type badge `WTR/ICE/...`, level cap, MARK BEATEN | **C** for type/leader/level; user roster only via `gym_results.team_snapshot` |
| `app/views/dashboard/_map_content.html.erb:14-22` | Center MAP tab "Current Location" card | "Next objective: CRASHER WAKE" | **C** (leader name only) |
| `app/views/map/show.html.erb:48-91` | Standalone /map page badge strip + status bar | per-gym tooltip w/ `type` + `Lv. 14`; status bar "NEXT GYM Crasher Wake · Water · LEVEL CAP 37" | **C** |
| `app/views/gym_drafts/show.html.erb:158` | Draft "MARK BEATEN" button label | `MARK GYM 5 — CRASHER WAKE AS BEATEN` | **C** (name only — for identification, not strategy) |
| `app/views/gym_ready/show.html.erb:11-28` | /gym_ready header card | "Leader: Crasher Wake — Type: WTR — Level Cap: 37" | **C** |
| `app/services/soul_link/discord_bot.rb:144-150, 411-419` | Discord `!next_gym` text command | embed showing `gym['name']` + `recommended_level` | **C** (read-only — no strategy advice, just metadata) |

### 2e. /gym_ready full page (separate from dashboard)

`app/views/gym_ready/show.html.erb`:
- Lines 67-116 — OFFENSIVE COVERAGE pills + SHARED WEAKNESSES rows. **U/T**.
- Lines 118-136 — TYPE DISTRIBUTION + balance notes. **U/T**.
- Lines 139-205 — AVAILABLE ROUTES (per-segment progression). **U** (catches by location).

Whole page wired up by `app/controllers/gym_ready_controller.rb:12,27,39`. Crucially, gym_ready does **not** render `pixeldex_gym_strategy` — it's clean of leader-specific advice. The header just labels which gym is next; everything analytical is roster-only.

### 2f. Gym-draft analysis (per-player)

`app/controllers/gym_drafts_controller.rb:57-65` builds a `@type_analysis_by_player` hash but **`app/views/gym_drafts/show.html.erb` never renders it.** Grep returns no `type_analysis` hits in that view file. Either the controller pre-loads data the view dropped during a redesign, or it was wired up via JS that's since gone. Either way: **dead-ish** — no user-visible strategy here. Class **U** (computed but not rendered).

### 2g. Dead code

- `app/views/dashboard/_pc_box_panel.html.erb` — full file. Has its own TYPE COVERAGE block (lines 84-112). **No `render` call points at it anywhere in the codebase** (`grep "pc_box_panel"` only finds doc-comments). This is a leftover from the pre-Step-28 sidebar redesign; live dashboard uses `_party_panel` for the sidebar. Mark as: **delete in a separate sweep** (KG candidate).

### 2h. What I expected to find but didn't

- **No "what to bring vs. Crasher Wake" recommended-team service.** The advice in the screenshot is the entire universe of leader-specific text — a single line of ternary in a helper. There is no `app/services/soul_link/recommendation_service.rb`, no `RecommendedTeamBuilder`, no Stimulus controller computing matchups client-side. Good news: removing the leader-specific advice is a one-helper, six-call-site delete. Bad news: there is no scaffolding to repurpose if we wanted to keep some form of leader strategy.
- **No Discord cross-post of strategy text.** The bot's `!next_gym` command is metadata only (gym name, recommended level). Removing dashboard strategy doesn't ripple to the bot.
- **No catch-time recommendation.** The catch modal does not surface "this fills your Electric gap" advice. PC-box review-tray's `recommended_review_action` (`pixeldex_helper.rb:118-122`) is unrelated — it picks LOG vs. SKIP for auto-detected catches based on `event_gift` / `trade_in`, not type strategy.
- **No client-side strategy in Stimulus.** `grep "type_analysis|coverage|strategy" app/javascript/controllers/*.js` returns nothing.

---

## 3. Duplication map

### 3a. The "Crasher Wake uses WTR types" line — six copies, identical content

| Render site | Visible context |
|---|---|
| `_status_rail.html.erb:167` (NEXT BATTLE prep) | Inside the "↓ NEXT BATTLE" panel, between leader/level metadata and the START GYM DRAFT button |
| `_status_rail.html.erb:252` (MAP sub-tab dialog) | Bottom of the right-rail MAP sub-tab |
| `_gyms_content.html.erb:133` | Bottom of center GYMS tab |
| `_map_content.html.erb:49` | Bottom of center MAP tab |
| `_strategy_panel.html.erb:62` | Bottom of center STRATEGY tab |

All five are `<div class="dialog">` footers calling the same helper with the same args. **Pure duplication, zero divergence.**

### 3b. The "team dialog" line — two copies, identical content

| Render site | Visible context |
|---|---|
| `_party_panel.html.erb:57` | Sidebar PARTY dialog under stats |
| `_party_detail.html.erb:51` | Center PARTY tab dialog under stats |

Identical helper call — `pixeldex_team_dialog(@type_analysis, @team_groups.size)`. The center-tab and sidebar are usually visible together (sidebar is always-on per Step 28), so the user reads the same sentence twice on the same screen.

### 3c. Coverage % stat — three live copies, one dead

- `_party_panel.html.erb:52` — `COVERAGE 9/17` (sidebar, always visible)
- `_party_detail.html.erb:45` — `COVERAGE 9/17` (center PARTY tab — same screen as sidebar)
- `_pc_box_content.html.erb:257` — `COVERED · 9` (pill count in PC BOX rail)
- `_pc_box_panel.html.erb:87-95` — dead code

The fraction format (`9/17`) and pill-count format (`9 of 17 pills`) are visually different but encode the same number. Sidebar + center PARTY tab show **the exact same string at the same time** when the user is on the PARTY tab.

### 3d. Coverage gap pills — two live copies

- `_pc_box_content.html.erb:268-275` — "GAPS · 8" + each pill
- `_strategy_panel.html.erb:20-31` — "NO COVERAGE: " + each pill

Different label ("GAPS" vs. "NO COVERAGE:"), same data. Strategy tab adds a 9-px explainer line ("Types your team can hit super effectively"); PC BOX rail adds an explainer about "computed against your 6-slot team — switch to ON TEAM to focus." The PC BOX explainer is the better one.

### 3e. Shared weaknesses — three places, three densities

- `_pc_box_panel.html.erb:106-111` — top 1 only, `WEAKNESS: ICE x3` (dead code)
- `_pc_box_content.html.erb:277-284` — top 3, pill format `ICE ×3`
- `_strategy_panel.html.erb:36-48` — full list, `count/team_size` format with `!` if majority
- `gym_ready/show.html.erb:96-115` — full list, fraction format, on a separate page

All four pull from `@type_analysis[:shared_weaknesses]` — same source array, sliced differently.

### 3f. Balance notes — two live places

- `_strategy_panel.html.erb:51-58` — full balance_notes list with `!`/`+` prefix
- `gym_ready/show.html.erb:127-135` — same full list, same prefix

Identical render. Strategy tab is dashboard-internal; gym_ready is a separate full page reachable via top nav.

### 3g. Gym leader list — three live places

- `_status_rail.html.erb:125-156` — compact ★ / ▶ / · row list (right-rail GYMS sub-tab)
- `_gyms_content.html.erb:42-128` — expanded list with team_snapshot collapse and MARK BEATEN button (center GYMS tab)
- `/map/show.html.erb:48-60` — badge-strip with leader tooltip on hover

The right-rail and the center tab are both keyed off `@gym_info` and stay in sync mechanically. They differ in interaction surface (center has buttons, rail is read-only). The dead code in `_pc_box_panel.html.erb` does **not** include a gym list — that's already been deduped (audit comment at `_status_rail.html.erb:184` confirms a previous pass closed "audit cross-cutting #6 duplication").

---

## 4. Options

Each option is sized in days assuming Bob is implementing solo, with Richard's review.

### Option A — Delete leader-specific strategy entirely

- **Removed:** `pixeldex_gym_strategy/2` helper. Six call-sites. The "↓ NEXT BATTLE" `prep` line in the screenshot. The five footer "dialog" boxes in GYMS/MAP/STRATEGY/MAP-rail/STRATEGY-tab.
- **Kept:** Everything else. NEXT BATTLE panel still shows `LEADER · CITY · Lv 37` (those are facts, not advice — even in randomizer the leader's name and the level cap are correct from the game's badge bitfield). All coverage / weakness / balance-notes surfaces stay (they read user roster). `gym_ready` page is untouched. Discord bot untouched.
- **Added:** Nothing.
- **User-visible change:** Right-rail NEXT BATTLE loses its 2-line strategy paragraph; gains nothing. The four "dialog" footers across GYMS/MAP/STRATEGY/MAP-rail just disappear. The dashboard feels marginally emptier on those tabs but the actually-useful surface (the NEXT BATTLE CTA, plus the START GYM DRAFT button) is preserved.
- **Effort:** ~0.5 days (helper delete + 6 call-site removals + spec updates + a small CSS tidy where empty `.dialog` divs leave dead margins).

**Honest read of the resulting emptiness:** the screenshot's right rail NEXT BATTLE panel becomes `LEADER · CITY · Lv 37` + a CTA button. That's a perfectly reasonable card — pure facts plus the action the user actually wants to take. The four center-tab dialog footers (GYMS/MAP/STRATEGY/MAP-rail) were always afterthoughts; deleting them would not be missed.

### Option B — Replace canonical with user-entered scouting

- **Removed:** Canonical `gym_info.yml` `type` and `ace` fields as inputs to strategy text (level cap and leader name kept as labels — they're load-bearing).
- **Kept:** Everything Option A keeps.
- **Added:** A "SCOUT GYM LEADER" surface where the user inputs: leader name override (optional), 1-6 mons (species + level), then strategy reads from that. New schema (`gym_scouts` table or a JSON column on `gym_results`/`soul_link_runs`), new modal, new helper that computes coverage gaps **vs. the scouted team** (using `TypeChart.weaknesses_for` already in the codebase).
- **User-visible change:** Per-leader data-entry chore before each gym. New "SCOUT" button on the GYMS tab.
- **Effort:** ~3-4 days (schema + migration + modal UI + Stimulus species autocomplete reuse + helper rewrite + spec coverage).

**The Project Owner's brief explicitly flags this kind of friction as a non-starter ("manually maintaining a per-leader roster table before strategy can be useful is a non-starter"). Confirming that read: pre-battle data entry across four players, eight gyms, every run reset, is exactly the chore the brief rejects. Strike this.**

### Option C — Pivot to roster-only strategy (recommended core)

- **Removed:** `pixeldex_gym_strategy/2` (same as A). Plus: the "TYPE" labels on per-gym list rows — those say "WTR" / "ICE" — across `_status_rail.html.erb:152` (currently absent — only level), `_gyms_content.html.erb:51,70,124`, `/map/show.html.erb:55,67,163`. These are the same canonical-Platinum claim wearing a different costume.
- **Kept:** All `TypeChart.analyze_team` outputs (coverage, gaps, shared weaknesses, balance notes, type distribution). All gym leader names + level caps (factual — driven by badge count, not by leader rosters). MARK BEATEN flow. /gym_ready full page.
- **Added:** A pure-roster "TYPE READINESS" callout in the NEXT BATTLE panel, computed from `@type_analysis` only — e.g., "TEAM HAS GAPS: ICE, FGT" or "FULL OFFENSIVE COVERAGE." This is what `pixeldex_team_dialog` already produces; we'd reuse it verbatim in NEXT BATTLE instead of `pixeldex_gym_strategy`.
- **User-visible change:** NEXT BATTLE shows the same advice the PARTY dialog already shows, but inside the gym-prep panel. The visible "what types should I pack" message stays — it just no longer pretends to know what the leader has.
- **Effort:** ~1 day (helper consolidation: rename `pixeldex_team_dialog` → something gym-aware, swap call sites; remove `type` columns from gym list rows; spec updates).

### Option D — Mode toggle (Vanilla / Randomized / Scouted)

- **Removed:** Nothing structural.
- **Kept:** Everything.
- **Added:**
  - `soul_link_runs.gym_mode` enum column (`vanilla`, `randomized`, `scouted`) + migration. Default `randomized` since that's the user's actual mode.
  - Branching in `pixeldex_gym_strategy` (and the per-gym list type label): `vanilla` → today's behavior; `randomized` → roster-only output; `scouted` → reads a new `gym_scouts` table (Option B's surface).
  - A "RUN SETTINGS" UI row on the runs management surface (`_runs_content.html.erb`) — toggle.
  - Backfill / migration for existing runs (default to `randomized`? or keep them on `vanilla` and force the user to opt out? — adds a Project-Owner decision).
- **User-visible change:** New settings affordance per run. Same dashboard otherwise unless the user picks `vanilla`.
- **Effort:** ~3-5 days (schema + migration + backfill story + 3 branches in the helper + settings UI + tests). And: keeps the bad code path alive forever, gated on a flag almost no one will flip back to.

**This is the "don't decide" option. It encodes both the broken behavior and the correct behavior in one codebase, leans on a setting nobody will tune, and adds three permutations to every future strategy-related change. Strike unless the PO genuinely believes vanilla-roster runs are a real audience for this app.**

### Option E — Auto-scout via SRAM (defer, do not ship now)

- **Inspiration:** `handoff/2026-05-02-sram-auto-tracking-audit.md` already documents how to read the player's PARTY block from a save. The same machinery, applied to a **post-gym save** (after the badge bit just flipped), could capture the leader's roster only if Soul Link battles produced a "last opponent team" SRAM trace. **They don't.** The SRAM stores the player's mons, not the opponent's. There is no realistic SRAM offset that records "what Crasher Wake's team looked like." This option is a dead end.
- **Adjacent feasible idea — auto-snapshot the *player's* team at gym-beat moment:** category 2 of the SRAM audit (lines 82-122 of that file) already covers this. It writes `gym_results.team_snapshot` automatically when `parsed_badges` increments. That gives "what mons beat this gym" — a record of *your* victory, not strategic foresight. Useful, but **doesn't solve the "what should I bring" problem** the user is asking about.
- **Removed / Kept / Added / Effort:** N/A — flagging only so the PO doesn't have to ask. Auto-roster-detection of opponents is not on the table without a randomizer-output data feed (e.g., the user uploads their Universal Pokémon Randomizer settings/log file). That's a feature unto itself and is out of scope for this rethink.

---

## 5. Recommendation

**Ship Option C. Sequence: deletion first, then a small consolidation.**

The user's literal words include "Maybe just get rid of it?" and that read is correct. The leader-specific advice is wrong half the time in a randomizer run, the helper that produces it is six lines of ternary, and the helper that produces *correct* roster-only advice (`pixeldex_team_dialog`) already exists and is already wired into PARTY dialogs. We're not removing strategy — we're removing the half of strategy that lies. The half that's true gets a stronger home in the NEXT BATTLE panel where the user is actually staring before they push START GYM DRAFT.

The reason I'm picking C over A is small but load-bearing: the screenshot shows the user has a real question at the moment they're looking at NEXT BATTLE — "am I ready?" — and answering "you have full offensive coverage" or "you have ICE and FGT gaps" is a real, true answer in a randomizer run. Pure deletion (A) leaves that panel with metadata + a CTA, which is fine but slightly less useful than C. C reuses code we already have; the marginal cost over A is rounding error.

I'm rejecting D firmly. A "vanilla" mode is dead-weight optionality the user has never asked for, and the PO's brief is the opposite of "let me toggle the broken thing back on." Single source of truth, randomized-by-default, ship it.

I'm rejecting B per the brief itself.

E is a future feature waiting on a data source we don't have, not a candidate for this rethink.

---

## 6. Dedup proposal (separate from the gym question)

Done independently of which gym option lands; these stand on their own.

### 6a. Coverage / weaknesses — pick ONE canonical home

**Canonical: the STRATEGY tab (`_strategy_panel.html.erb`).** That's the tab named for it, it already shows the deepest version of every analysis (coverage pills, gaps, shared weaknesses with team-size context, balance notes), and it's a deliberate destination — the user clicks STRATEGY when they want this view.

**Reduce:**
- **Sidebar PARTY (`_party_panel.html.erb:50-57`):** keep the tiny `COVERAGE 9/17` stat row. Drop the dialog box at line 56 (`pixeldex_team_dialog`) — it duplicates what center PARTY shows when active and doesn't pull weight in the always-visible rail.
- **Center PARTY tab (`_party_detail.html.erb:42-52`):** keep the four-stat row (`SURVIVAL / COVERAGE / CAUGHT / DEAD`). Drop the dialog box at line 50 — already in sidebar, will be in STRATEGY tab.
- **PC BOX rail (`_pc_box_content.html.erb:249-285`):** keep. This is genuinely a different context — the user is browsing the box thinking about who to swap in, and an inline coverage hint is the right place. It does have an explainer line that the STRATEGY tab lacks ("computed against your 6-slot team — switch to ON TEAM to focus") — keep that, lift it up to STRATEGY tab too.
- **Dead `_pc_box_panel.html.erb`:** delete the file in a tidy-up sweep. Filed as a known gap candidate (see §8).

**Net result:** STRATEGY tab is the canonical detailed home. PC BOX gets a contextual sidebar copy. PARTY surfaces show the compact `9/17` only. The user reads the full coverage picture in one place; the compact stat in two; the prose dialog never twice on the same screen.

### 6b. The strategy "dialog" boxes

After Option C, only the PARTY dialogs survive the gym-strategy purge. Per §6a, both of those drop too — leaving zero `.dialog` boxes labelled "team dialog." If we want the prose form anywhere, it lives **once**, at the top of the STRATEGY tab body, replacing the bottom-of-panel `pixeldex_gym_strategy` call we'll have already removed.

### 6c. Gym list

Keep the right-rail compact list (`_status_rail.html.erb`) and the center-tab full list (`_gyms_content.html.erb`) — they are not redundant: the rail is read-only navigation, the center is interactive (MARK BEATEN, team_snapshot review). The duplicate "TYPE" badge labels (Option C removes these anyway — they're canonical-roster claims) is the only overlap.

### 6d. /gym_ready full page

This page (`app/views/gym_ready/show.html.erb`) is a near-superset of the dashboard STRATEGY tab — same balance notes, same coverage pills, same weakness rows — plus an AVAILABLE ROUTES progression view the dashboard doesn't have. Question for the PO (see §7): is gym_ready still a real destination, or has the dashboard subsumed it? If the latter, archive the page; if the former, leave it alone — its `@type_analysis` is per-player (current user), the dashboard's is too, so there's no behavioral drift.

---

## 7. Open questions for the Project Owner

Three. No more.

1. **Confirm randomizer-only.** Are there any vanilla Platinum runs in the user base today (e.g., a "tutorial" or "first-timer" run that uses unmodified rosters)? If yes — Option D becomes worth considering. If no — ship C as-is. **My read of the brief is "no."**
2. **Keep `/gym_ready` page or fold it in?** The page has a unique "AVAILABLE ROUTES" panel (per-segment progression) that the dashboard MAP tab handles differently. Two valid product calls: (a) leave it as a focused "battle prep" deep-link from the top nav, (b) archive it and migrate AVAILABLE ROUTES into the STRATEGY tab. Either is fine; pick one so we can drop the duplicate analysis code. **My recommendation: (a) — leave it. It's a separate URL with a distinct narrative ("am I ready?") and removing it loses a top-nav entry point users may have bookmarked.**
3. **Coverage explainer copy.** Once consolidated (per §6a), the STRATEGY tab will show coverage pills under a single header. The current explainer lines diverge across surfaces:
   - PC BOX rail: "computed against your 6-slot team — switch to ON TEAM to focus"
   - STRATEGY tab today: "Types your team can hit super effectively."
   Pick one phrasing for the canonical home. **My recommendation: lift the PC BOX phrasing — it's clearer about what's being measured.**

---

*Citations spot-checked against grep output 2026-05-09. All file:line refs reflect current `main` (commit `f30b87c`).*
