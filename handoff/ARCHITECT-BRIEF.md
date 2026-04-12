# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 2 — Gym Draft Playability Fixes

Context: 4 trusted friends, no adversarial threat model. Focus is on game-rule correctness, UI resilience, and not getting stuck.

### Decisions
- Nomination turn tracking reuses the existing `pick_order` and `current_player_index` from the drafting phase (already set when transitioning to nominating at `gym_draft.rb:102-107`)
- Skip-turn is a simple model method callable by any player — no server-side timers, no background jobs. Client shows a SKIP button after 30 seconds of the current phase (drafting/nominating only). Timer resets on each state broadcast.
- innerHTML replaced with safe DOM construction (textContent for user data) — not a security concern with friends, but special chars in nicknames (e.g. `<3`, `Tom & Jerry`) will break rendering
- The nominator's auto-vote (`votes[nominator_id] = true`) is already excluded from `resolve_nomination!` approval counting via `other_ids`, so nominator re-voting is a non-issue. Do NOT change this.

### Build Order

**1. Model: Add nomination turn enforcement (`app/models/gym_draft.rb`)**

In `submit_nomination!` (line 117), add a guard after the phase check:
```ruby
raise "Not your turn to nominate" unless pick_order[current_player_index % pick_order.size] == nominator_uid.to_i
```

In `resolve_nomination!` (line 203), when nomination is **approved**, advance the turn:
```ruby
# After adding to new_picks and before the if/update block:
next_nominator_index = (current_player_index + 1) % pick_order.size
```
Include `current_player_index: next_nominator_index` in both the complete and continue update calls.

When nomination is **rejected**, do NOT advance — same player nominates again (line 231-232 stays as-is, just clearing the nomination).

**2. Model: Add skip-turn mechanism (`app/models/gym_draft.rb`)**

New method `skip_turn!(uid)`:
- In **drafting** phase: advance `current_player_index` by 1. Do NOT add a pick. If `current_player_index >= INDIVIDUAL_ROUNDS`, transition to nominating.
- In **nominating** phase: advance `current_player_index` by 1 (mod pick_order size). Clear any pending nomination.
- Raise error if not in drafting or nominating phase.
- Any player can call this (not just the current drafter) — friends policing each other.

**3. Channel: Add skip action (`app/channels/gym_draft_channel.rb`)**

New method `skip(_data)`:
```ruby
def skip(_data)
  @draft.reload
  @draft.skip_turn!(current_user_id)
  broadcast_state
rescue => e
  transmit({ error: e.message })
end
```

**4. Stimulus: Fix innerHTML XSS (`app/javascript/controllers/gym_draft_controller.js`)**

In `fillTeamSlots()` (lines 217-238): Replace innerHTML construction with DOM API. Use `textContent` for `group.nickname` and `picker.display_name`.

In `renderPokemonGrid()` (lines 240-275): Replace innerHTML construction with DOM API. Use `textContent` for `group.nickname`, `species`, `group.location`.

Pattern to follow:
```javascript
const div = document.createElement("div")
div.className = "text-xs font-medium text-white"
div.textContent = group.nickname  // safe — no HTML parsing
container.appendChild(div)
```

**5. Stimulus: Add double-click prevention (`app/javascript/controllers/gym_draft_controller.js`)**

In `pickPokemon()` (line 67): After performing the action, disable ALL pokemon cards in the grid (set `pointer-events: none` and add `opacity-50`). State broadcast will re-render with correct state.

In `nominatePokemon()` (line 72): Same pattern.

In `approveNomination()` and `rejectNomination()` (lines 77-85): Find both buttons in `nomVoteAreaTarget` and set `disabled = true` on both (not just opacity).

**6. Stimulus: Add skip-turn button + 30s timer (`app/javascript/controllers/gym_draft_controller.js`)**

Add a `skipTurnTimer` property. In `renderDrafting()` and `renderNominating()`:
- Clear any existing timer
- Start a 30-second countdown
- After 30s, show a "SKIP TURN" button (create it dynamically near the turn indicator / nom status)
- Button calls `this.subscription.perform("skip")`
- Timer resets on every `render()` call (state broadcast resets the clock)

**7. View: Add skip turn button container (`app/views/gym_drafts/show.html.erb`)**

Add a `skipButton` target container after the turn indicator (line 87) and after the nom status (line 111):
```erb
<div data-gym-draft-target="skipButton" class="hidden" style="margin-top: 8px;"></div>
```

### Flags
- Flag: Do NOT add server-side timers or background jobs. Client-side 30s timer + server skip action is sufficient.
- Flag: Do NOT change `resolve_nomination!` approval logic or nominator vote handling — it's correct as-is.
- Flag: The `pick_order` array is already populated when entering nominating phase (set during `resolve_votes!`). Do not re-derive it.
- Flag: `current_player_index` is set to 0 when entering nominating (line 104). This is correct — first player in pick_order nominates first.
- Flag: When skipping in drafting phase, `current_player_index + 1` may need to handle the transition to nominating if we've reached `INDIVIDUAL_ROUNDS` picks worth of turns (not picks — some turns may be skipped). Track this with a `current_turn` counter or by checking `current_player_index >= pick_order.size` per round. Simplest approach: skip just increments `current_player_index` by 1; if it equals `pick_order.size`, transition to nominating regardless of pick count. Players who skipped simply don't get a pokemon for that slot.
- Flag: For `renderPokemonGrid`, the entire container innerHTML is replaced each render. When switching to DOM construction, clear container first with `container.replaceChildren()` then append new elements.

### Definition of Done
- [ ] `submit_nomination!` raises "Not your turn" if wrong player nominates
- [ ] Approved nomination advances `current_player_index`; rejected nomination keeps same player
- [ ] `skip_turn!` method works in both drafting and nominating phases
- [ ] `skip` channel action wired up and broadcasts state
- [ ] All user-supplied text rendered via `textContent`, not `innerHTML`
- [ ] Pick/nominate buttons disabled on click (re-enabled by next state render)
- [ ] Vote buttons set `disabled = true` on click
- [ ] Skip button appears after 30s of inactivity, resets on state update
- [ ] Skip button target containers added to view

---

## Builder Plan
*Builder adds their plan here before building. Architect reviews and approves.*

[Builder writes plan here]

Architect approval: [ ] Approved / [ ] Redirect — see notes below
