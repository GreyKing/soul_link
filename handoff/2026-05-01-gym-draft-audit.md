# Gym Draft Workflow — Audit & Redesign Proposal
*2026-05-01 · Architect (Ava) · Investigation only — no code changes in this turn.*
*Pair this report with `handoff/2026-05-01-gym-draft-redesign.html` (visible in the Launch preview panel).*

The Project Owner reported three pain points after running the draft a few times:

> "ties not working properly, no feed back on who's voted and not voted, just some unclear UI."

This document maps the workflow end-to-end, names the actual bugs, surfaces a handful of quieter UI gaps, and proposes two paths forward (a small-fix path and a re-spec path) with a recommendation.

---

## § 1. Current State Machine

### Phases (from `app/models/gym_draft.rb:5,7`)
```
lobby → voting → drafting → nominating → complete
```

| Phase | Trigger to next | Resolves via |
|---|---|---|
| **lobby** | all 4 players ready | `mark_ready!` → `all_players_ready?` (`gym_draft.rb:71-80`) |
| **voting** | all 4 votes cast | `cast_vote!` → `resolve_votes!` (`gym_draft.rb:82-91, 206-227`) |
| **drafting** | 4 individual picks made | `make_pick!` (`gym_draft.rb:93-116`) |
| **nominating** | 6 total picks (4 + 2) | `vote_on_nomination!` → `resolve_nomination!` (`gym_draft.rb:156-171, 229-263`) |
| **complete** | terminal | — |

### Wire-up
- WebSocket via `GymDraftChannel` (`app/channels/gym_draft_channel.rb`) — every action `@draft.reload`s, mutates, `broadcast_state`s.
- Stimulus controller `gym_draft_controller.js` subscribes, re-renders the matching panel on each state update.
- View `app/views/gym_drafts/show.html.erb` has five hidden panels (`lobbyPanel`, `votingPanel`, `draftingPanel`, `nominatingPanel`, `completePanel`); the Stimulus controller toggles `.hidden`.

### Per-phase state shape (lives on `state_data` JSON column)
- `ready_players` → array of uids (lobby)
- `first_pick_votes` → `{ voter_uid_str => voted_for_uid_int }` (voting)
- `pick_order` → array of uids, captain first (set on entering drafting)
- `picks` → array of `{ round, group_id, picked_by }` (drafting + nominating)
- `current_nomination` → `{ nominator_id, group_id, votes: { uid_str => bool } }` (nominating; cleared between attempts)
- `current_player_index` → integer index into `pick_order` for both drafting and nominating

---

## § 2. Bugs

Findings are ranked by user-impact. File:line refs throughout.

### 🔴 Bug 1 — Rejected nomination keeps the same nominator; no rotation
**Location:** `app/models/gym_draft.rb:259-262` (`resolve_nomination!` rejection branch)

```ruby
else
  # Rejected — clear nomination
  update_data!("current_nomination" => nil)
end
```

`current_player_index` is **never advanced** in the rejection branch. Compare to the `skip_turn!` path (line 148) which DOES advance. So when a nomination is voted down, the same nominator gets the next attempt — and can keep nominating bad picks indefinitely.

**Test that should have caught it:** `gym_draft_test.rb:187-200` (`nomination rejected clears nomination without adding pick`) only asserts `picks` size and nil nomination. It does NOT assert that `current_player_index` advanced. The bug is unspecified.

**User experience:** "I keep voting NO and nothing changes — Glenn keeps re-nominating." Reads as "ties not working properly" because the user can't tell if the rejection registered.

### 🔴 Bug 2 — `skip_turn!` has no auth check; any player can skip the current nominator's turn
**Location:** `app/channels/gym_draft_channel.rb:44-50`, `app/models/gym_draft.rb:132-154`, `app/javascript/controllers/gym_draft_controller.js:363-384`

```ruby
def skip(_data)
  @draft.reload
  @draft.skip_turn!         # ← no current_user_id passed in
  broadcast_state
end
```

The skip button is shown to every player after 30s (`gym_draft_controller.js:371-383`), and the channel passes the skip through to the model without checking the requester is the current nominator. A non-nominator clicking the skip button silently advances someone else's turn.

Combined with **Bug 1**, this might be the user's actual workaround — they're skipping people's turns to break out of stuck nominator loops, but the UI doesn't make that legible.

### 🟡 Bug 3 — No vote-progress feedback during a nomination
**Location:** `app/javascript/controllers/gym_draft_controller.js:207-254` (`renderNominating`)

The nominating panel shows:
- `${nominator?.display_name} nominated "${groupName}"` (line 220)
- `${slotsRemaining} slot${slotsRemaining > 1 ? "s" : ""} remaining` in `phaseInfo` (line 213)

It never renders `nomination.votes` — the per-player yes/no/pending state is in the broadcast payload but not surfaced. The user has no idea who has voted, who's pending, or what the running tally is.

The voting phase has a partial version of the same bug (`renderVoting` shows count `2/4 votes` at line 171 but not WHO voted) — minor, but shares the pattern.

**This is the user's "no feedback on who's voted" complaint, exactly.**

### 🟡 Bug 4 — UI disables vote buttons after click; the model permits a vote change
**Location:** `app/javascript/controllers/gym_draft_controller.js:96-104` vs `app/models/gym_draft.rb:156-171`

```js
approveNomination() {
  this.subscription.perform("vote_nomination", { approve: true })
  this.nomVoteAreaTarget.querySelectorAll("button").forEach(btn => { btn.disabled = true })
}
```

The model just overwrites the existing entry in `nom["votes"]` — no "already voted" guard. So a user could change their mind. But the JS disables the buttons, and the panel re-renders into the "hasVoted" branch (line 224), which hides the vote area entirely (`this.nomVoteAreaTarget.classList.add("hidden")` at line 231). Vote is final from the user's perspective.

If a user clicks NO by accident, there's no recovery. Minor on its own; combines with Bug 1 (rejected → same nominator → user's regret-vote sticks them in a loop with no way back).

### 🟡 Bug 5 — Voting-phase tiebreak resolves silently with `winners.sample`
**Location:** `app/models/gym_draft.rb:206-227` (`resolve_votes!`)

```ruby
max_count = tally.values.max
winners = tally.select { |_, count| count == max_count }.keys
first_pick = winners.sample      # ← silent random tiebreak
```

The model handles ties correctly (one of the tied players is randomly chosen as captain). The UI never tells anyone a tie happened. The user sees their friend become captain "for no reason." `gym_draft_test.rb:74-85` asserts the result is one of the tied candidates — confirms behaviour, but doesn't address the UI silence.

This may be part of why the user said "ties not working properly" — they hit a tied first-pick vote, the system picked a captain, and the user couldn't reconcile it with their expectation.

### 🟢 Bug 6 — Approve-threshold is "2/3 of NON-nominators", which produces counter-intuitive outcomes
**Location:** `app/models/gym_draft.rb:229-234` (`resolve_nomination!`)

```ruby
other_ids = player_ids.map(&:to_s) - [ nom["nominator_id"].to_s ]
approvals = other_ids.count { |id| nom["votes"][id] == true }
approved = approvals >= (other_ids.size / 2.0).ceil
```

With 4 players, the nominator's auto-yes is excluded; threshold is `>= ceil(3/2.0) = 2` of the other 3 (so 67% of the rest). So:
- 2-yes / 1-no among others (1 NO total) → approved
- 1-yes / 2-no among others (1 YES + 1 nominator-yes = 2 YES total, 2 NO) → rejected even though it's a 2-2 split when you include the nominator

The user's mental model (and the audit's recommendation) is "all 4 players vote, the nominator's auto-yes counts." Today's 2-of-3-others rule is mathematically equivalent in three of four scenarios, but the rejection-on-2-2 case is the surprise, and there's no UI to explain it.

**Not strictly a bug** — it's a design decision — but it's the math behind the user's "ties not working" frustration.

### 🟢 Bug 7 — Race: `submit_nomination!` raises if a nomination is pending; UI gates this purely on local state
**Location:** `app/models/gym_draft.rb:121` raises `"Already have a pending nomination"`; `gym_draft_controller.js:250` gates the click via `canNominate = !nomination && isMyTurnToNominate`

If two clients see the panel transition simultaneously and the current nominator double-clicks, the second click hits the channel's `transmit({ error: e.message })` branch (`gym_draft_channel.rb:38-41`). That error renders via `showError` → 8s banner. Cosmetic but jarring.

### 🟢 Bug 8 — `state_data` JSON has no schema constraint; any malformed broadcast crashes the JS
**Location:** `app/models/gym_draft.rb:175-193` (`broadcast_state`) and the JS render functions

If the JSON gets out of sync (e.g., a backfill script writes a `picks` entry with no `picked_by`), `findPlayer(undefined)` returns `undefined` and the slot renders blank (`gym_draft_controller.js:264-292`). No telemetry. Low risk; called out for the catalog.

---

## § 3. UI Gaps (not bugs — opportunity flags)

These are things the audit noticed while reading the code. Some pair with bugs above.

| # | Gap | File:line |
|---|---|---|
| **G1** | No "captain" visual after the voting phase resolves. The user who "won" the first-pick vote is just first in `pick_order`; the UI never marks them visually. | `gym_draft_controller.js:188-205` |
| **G2** | Drafting phase shows `Round X/6` (line 199) — implies 6 rounds, but only 4 are individual picks; rounds 5-6 are nominations. Confusing copy. | `gym_draft_controller.js:199` |
| **G3** | Nominating phase shows `slots remaining`, drafting shows `round X/6`. Inconsistent framing. | `gym_draft_controller.js:213` vs `:199` |
| **G4** | After rejection, the nomination card disappears with no transition. User sees "X to nominate again" with no indication of what just happened. | `gym_draft_controller.js:233-243` |
| **G5** | Skip button styling is `gb-btn-danger` (`gym_draft_controller.js:374`). Reads as a destructive action; it's actually a polite "I forfeit my turn." | `gym_draft_controller.js:371-383` |
| **G6** | Lobby `ready` button uses Tailwind classes (`bg-green-600`, `bg-gray-600`) that don't exist in the project's Tailwind setup — the visual switch on line 70 silently no-ops. | `gym_draft_controller.js:70` |
| **G7** | Pokemon grid mixes Tailwind (`bg-gray-900/50 rounded-lg`) and project tokens. Visual style drifts from the rest of the app. | `gym_draft_controller.js:308-312` |
| **G8** | `findPlayer` / `findGroupById` (lines 386-393) iterate full arrays per render. Fine at 4 players × 6 picks, but the file is the controller's most edited and could use a Map. | `gym_draft_controller.js:386-393` |
| **G9** | The "BACK TO GYM READY" button on the complete panel (`show.html.erb:168`) is `gb-btn-primary` — same weight as MARK BEATEN. The high-stakes action shouldn't share weight with the navigation action. | `gym_drafts/show.html.erb:158-168` |
| **G10** | No way to view a completed draft's history — once mark-beaten fires, the draft show page still works but there's no surfaced "view all past drafts" route. (Aside; not in user's reported pain.) | n/a |

---

## § 4. Proposed Redesign

The mockup at `handoff/2026-05-01-gym-draft-redesign.html` shows the redesigned UX in full. It commits to the existing GameBoy palette + Press Start 2P typography, leans into "control room" energy with LED-indicator vote panels, and makes the implicit rules of the draft visible.

### Headline changes (vs. current)

1. **Live vote LED row** during nominations — 1 cell per player, color-coded yes/no/pending, with the nominator marked AUTO and the captain marked ★. Replaces the silent "do you agree?" buttons.
2. **Live tally + threshold copy** — `YES · 2 · NO · 1 · PENDING · 1 — needs 3/4 to pass`. Tells users why a vote went the way it did.
3. **Tiebreak story** — change the rule: all 4 players vote (nominator auto-yes), 3/4 to approve, 2/4 is a tie, captain ★ casts the deciding vote. Mockup section 3E shows the captain-only deciding-vote panel.
4. **Rejection auto-rotates** — rejected nominations advance to the next pick-order seat with a visible breakdown + countdown. After all 4 nominate-and-fail, slot escalates to a captain unilateral pick (mockup section 3F). Always terminates.
5. **Skip restricted to the current nominator** — not visible to other players. Channel checks `current_user_id == current_drafter_id`.
6. **Change-vote allowed pre-resolution** — JS supports re-clicking; resolution only fires on last vote.
7. **Pick-order strip in drafting** — the four players shown horizontally with done / active / upcoming states (mockup phase 3). Replaces "It's your turn" / "Waiting for X."
8. **Captain ★ marker** — persists from voting → drafting → nominating, narratively threading the captain's role.

### Two paths

#### Path A — Surgical fix (recommended)

Keep the current state machine. Fix the bugs, surface the UX. Rough scope:

| Item | Files | Risk | Effort |
|---|---|---|---|
| Auto-rotate on rejection (Bug 1) | `gym_draft.rb:259-262`, `gym_draft_test.rb` | low | 1-line code, 2 new tests |
| Skip auth check (Bug 2) | `gym_draft.rb:132-154`, `gym_draft_channel.rb:44-50`, `gym_draft_controller.js:363-384` | low | ~10 LOC + tests |
| Vote LED row + live tally (Bug 3) | `gym_drafts/show.html.erb` (new vote panel), `gym_draft_controller.js:207-254` (renderNominating) | medium | ~80 LOC of view + JS, no model change |
| Allow change-vote (Bug 4) | `gym_draft_controller.js:96-104, 224-231` | low | ~5 LOC |
| Captain marker (G1) + pick-order strip (G2/G3) | `gym_drafts/show.html.erb`, `gym_draft_controller.js` | medium | ~60 LOC |
| Voting tiebreak surface (Bug 5) | `gym_draft_controller.js:167-186`, model exposes `tied?` flag | low | ~20 LOC |
| Skip button restyling (G5) | `gym_draft_controller.js:374` | trivial | 1 line |

**Path A leaves Bug 6 (the 2/3-of-others threshold) alone.** That's a deliberate design call — changing the threshold is a rule change, not a fix.

**Estimated total:** 2-3 focused steps, ~250 LOC + tests. No DB migrations. Each step independently shippable.

#### Path B — Re-spec (bigger lift, optional)

Switch to "all-nominate-then-vote":

1. Each of 4 players nominates one pokemon (in pick-order).
2. Each player ranks their top 2 of the 4 candidates.
3. Top 2 vote-getters fill slots 5+6.
4. Tiebreak: random or captain-decides for 3rd-place ties.

**Why this is cleaner:** ties become first-class (real plurality voting), the rejection-loop disappears (every nomination is a candidate, not a referendum), and the UX maps directly to "a vote with results." The "captain has more weight" narrative still works as a tiebreak.

**Why it's a bigger lift:** new state machine sub-phases (`nominating` splits into `nominating` + `ranking`), new actions on the channel (`rank_picks` instead of `vote_nomination`), schema for the candidates list. Probably 1-2 sessions of work.

Path B is worth considering only if Path A's surgical fixes still don't satisfy the user's mental model after a few real runs. Default recommendation: Path A.

---

## § 5. Migration / Build Order

Suggested ship order if Path A goes forward. Each row is a step that can land independently — none is a hard prereq for the next, but the order minimises rework.

### Step ⓐ — Bug fixes (smallest, fastest)
- Rotate on rejection (Bug 1).
- Skip auth check (Bug 2).
- Allow change-vote (Bug 4).
- Tests for all three.

**Surface area:** model + channel + JS one-liners + tests. Very low risk. ~2 hours of work for Bob. **Ship this first.**

### Step ⓑ — Vote LED row + tally + breakdown banner
- New `_nomination_vote_panel.html.erb` partial (or inline in show view).
- `renderNominating` extension to populate the LED row, the tally bar, the change-vote button.
- Approval / rejection / tied banners (mockup sections 3C, 3D, 3E).
- After-rejection rotation banner with countdown.

**Surface area:** view + JS. No model changes. ~150 LOC. Closes Bug 3 + G4 visually.

### Step ⓒ — Captain marker + pick-order strip + voting-phase tiebreak surface
- Captain ★ marker rendered persistently after voting resolves.
- Pick-order horizontal strip in drafting phase.
- Voting-phase tiebreak banner (Bug 5 surface).
- Round-counter copy normalisation (G2/G3).

**Surface area:** view + JS. No model changes. ~100 LOC.

### Step ⓓ — (Optional) Captain-decides tiebreak rule
Change the threshold from "2/3 of others approves" to "3/4 of all approves; 2/2 ties go to captain." This is the rule change behind mockup section 3E.

**Surface area:** model `resolve_nomination!` + new test cases for tied + captain-decides + tests for the captain-only UI gate. ~50 LOC.

This is the only step that changes draft rules — keep it separate from the cosmetic fixes in case the user wants to A/B the math.

### Step ⓔ — (Optional, lowest priority) Tailwind cleanup in the gym-draft Stimulus controller (G6, G7)
Replace stray Tailwind classes with the project's `gb-*` tokens. Visual consistency. No behaviour change.

---

## § 6. Open Questions for Project Owner

These are decisions that change the spec; flagging them so you can pick before we ship.

1. **The rule change in Step ⓓ.** Today's "2/3 of others" threshold has the surprising "1-yes-1-no-among-others-but-2-2-overall = rejected" case. The redesign proposes "3/4 of all + captain breaks ties." Want to ship the rule change or just the cosmetic clarity?
2. **Stalemate fallback (mockup section 3F).** Today the rejection loop is bounded only by "skip" and is broken (Bug 1). The redesign proposes "after 4 nominations all rejected, captain picks unilaterally." Acceptable, or do you want a different escalation (re-vote round? reroll the whole nominating phase?)?
3. **Skip semantics.** Currently anyone can skip anyone (Bug 2). Tighten to "only the current nominator can skip their own turn"? Or "any player can skip after a 60s grace period"? The mockup shows the strict version.
4. **Tiebreak in voting phase.** Currently `winners.sample` (random). Want to surface that with an animated coin-flip reveal, or change the rule (e.g., "tied → re-vote among tied candidates")? The mockup shows the random outcome with a reveal banner — same rule, surfaced.
5. **Mark-beaten button on draft complete page.** Out of audit scope but spotted in G9 — the "BACK TO GYM READY" navigation button uses the same weight (`gb-btn-primary`) as the destructive "MARK GYM N AS BEATEN" CTA. Worth de-emphasising while the area is open.

---

## § 7. Files Worth Re-reading During Implementation

If/when Path A goes forward, these are the files that will be edited (in roughly Step ⓐ→ⓒ order):

- `app/models/gym_draft.rb` — `resolve_nomination!` (rotation), `skip_turn!` (auth), maybe `resolve_votes!` (tied flag).
- `app/channels/gym_draft_channel.rb` — `skip` action auth check.
- `app/javascript/controllers/gym_draft_controller.js` — `renderVoting`, `renderNominating`, `approveNomination`/`rejectNomination`, `startSkipTimer`.
- `app/views/gym_drafts/show.html.erb` — new vote panel structure inside the nominating phase, new banners, captain marker.
- `test/models/gym_draft_test.rb` — new tests for rotation + skip auth + (optional) captain-decides tiebreak.
- `test/channels/gym_draft_channel_test.rb` — auth checks on skip.

The rest of the app is unaffected. No migrations.

---

## § 8. Out of Scope for This Audit

- The `mark_beaten` flow (separate concern, just shipped Step 13's unmark button for it).
- Cross-guild auth on the channel (subscribed-via-`draft_id` is the existing pattern; not regressed).
- Discord bot integration of draft status (the bot doesn't surface drafts today; out of audit scope).
- The strategy panel and type-chart analysis on the draft show page (untouched by this redesign).

---

*End of audit. Next action: Project Owner picks Path A vs Path B (or a subset of Path A's steps); Architect drafts the next ARCHITECT-BRIEF accordingly.*
