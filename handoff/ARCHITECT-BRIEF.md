# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 14 — Gym Draft Final-2 Picks: Unified Nominate-or-Endorse Model

### Context

Following the Step 13 ship + the Project Owner's review of `handoff/2026-05-01-gym-draft-audit.md`, we're rewiring the **nominating phase** of gym drafts. Path B (re-spec) was chosen, with an elegant simplification proposed by the Project Owner:

> **Nomination IS the vote.** Each of the 4 players, in pick order, makes one pick during the nominating phase. The pick is either: (a) a NEW pokemon (creates a new candidate) or (b) an endorsement of an already-nominated candidate (adds the player to that candidate's voter list). After all 4 picks, the **top 2 most-endorsed candidates** fill slots 5+6.

This collapses the old "round-robin nominate → up/down vote → resolve" loop into a single 4-pick pass. Pure plurality voting; ties become first-class. The "captain has more weight" Path A narrative is **gone** — every player has equal weight here.

**Audit reference:** see `handoff/2026-05-01-gym-draft-audit.md` for the underlying bug catalog (Bug 1 rejection-loop, Bug 2 skip-auth, Bug 3 vote-feedback, Bug 5 voting-tiebreak silence). All four are closed by Step 14.

### Project Owner decisions (locked)

1. **Unified pick action.** Each player makes exactly one pick during the nominating phase. Channel API: a single `nominate(group_id)` action — if `group_id` is already a candidate, the picker is added to that candidate's voter list (endorsement); otherwise a new candidate is created. The legacy `vote_nomination` channel action is **removed**.
2. **State machine names unchanged.** `lobby → voting → drafting → nominating → complete`. Only the **inner mechanics** of `nominating` change.
3. **Resolution: top-2 by voter count.** After all 4 players have made their nomination-phase pick, sort candidates by voter count desc; top 2 fill slots 5+6. Ties at the threshold (positions 1-2 boundary) trigger the coin-flip modal.
4. **Coin flip uses the Pokémon TCG coin aesthetic.** Reference: the small circular metal coins that ship with the Pokémon Trading Card Game and that the digital TCG apps animate in 3D — gold edge, two distinct faces (pokéball one side, a character face the other), `rotateY` 3D flip with satisfying physics easing, ~1.5-2.5s reveal. Server-side outcome is `Array#sample` (random); the modal is presentation only.

   **Time-box: ~30 minutes of CSS/SVG craft.** If reproducing the TCG-coin look gets fiddly past that, fall back to a **simple 3D coin-flip styled "in-universe"** — gold/red/pokéball palette, two-face round, same `rotateY` animation, just less detail. Either way the modal framing must feel Pokémon-themed: header copy like "WILD COIN APPEARED!" (or similar in-universe phrasing), pokéball-red accent on the modal chrome, GameBoy palette tokens for the rest. Bob's call between TCG-faithful and simple-fallback once he sees how the SVG/CSS plays out.
5. **Skip semantics: 60s grace.** Until 60s have elapsed since the current nominator's turn began, ONLY that nominator can skip themselves. After 60s, ANY player can skip. The skip button shows a visible countdown to the grace deadline. Channel-side auth check enforces both rules.
6. **Equal weight.** No captain-decides anything in nominating. The captain marker (first-pick winner) still applies in drafting but has no special role in the new nominating phase.
7. **Edge case: 1-candidate consensus.** If all 4 players nominate/endorse the same pokemon (single candidate, 4 voters), slot 5 fills with that candidate, slot 6 stays empty. Team is 5 strong. Document in tests; do NOT add a "redo round" or other recovery path. (Rare in practice; explicit decision.)
8. **Avatar pile on candidate cards.** Each candidate card shows a horizontal stack of Discord profile pictures — one per voter (nominator + endorsers), with overlap. See "Avatar caching layer" below for the data approach.
9. **Q5 sweep: button weight on draft-complete page.** While the area is open, de-emphasise "BACK TO GYM READY" so the destructive "MARK GYM N AS BEATEN" CTA is the visual primary. (`gym_drafts/show.html.erb:158-168`.)

### State Model

#### New `state_data` shape (during nominating)
```json
{
  "ready_players": [...],
  "first_pick_votes": {...},
  "picks": [{"round": 1, "group_id": 123, "picked_by": 111}, ...],
  "candidates": [
    {"group_id": 123, "voters": [111, 222]},
    {"group_id": 456, "voters": [333]}
  ],
  "current_turn_started_at": "2026-05-01T18:42:13Z",
  "tiebreak": null
}
```

- **`candidates`** — array of `{ group_id, voters }`. `voters[0]` is the nominator (the player who created the candidate); subsequent voters are endorsers. A "voter" is any player whose pick landed on this candidate. Voters list is stable order (append-only).
- **`current_turn_started_at`** — ISO8601 timestamp; set when the turn changes (initial transition into nominating, or after each pick that didn't terminate the phase). Drives the 60s grace.
- **`tiebreak`** — populated transiently during the resolution flow when a tie needs a coin flip. Shape: `{ "type": "second_place" | "n_way", "tied_group_ids": [int, int, ...], "winners": [int, ...] }`. The server picks the `winners` (random) before broadcasting; the client uses `tied_group_ids` to drive the animation, then reveals `winners`. Cleared on transition to `complete`.

#### Removed fields (cleanup)
- `state_data["current_nomination"]` — gone. The `current_nomination` model accessor goes too (`gym_draft.rb:38-40`).
- `submit_nomination!` model method — gone. Folded into the new `nominate!` action.
- `vote_on_nomination!` model method — gone.
- `resolve_nomination!` model method — gone. Replaced by `resolve_nominations!` (plural).

#### Channel actions (final)
| Action | Behavior |
|---|---|
| `ready` | unchanged |
| `vote` | unchanged (first-pick voting phase) |
| `pick` | unchanged (drafting phase, individual picks) |
| `nominate(group_id)` | **NEW SEMANTICS** — current nominator picks; auto-detects new vs endorsement |
| `vote_nomination` | **REMOVED** |
| `skip` | **AUTH UPDATED** — current nominator OR (60s elapsed since `current_turn_started_at`) |

### Implementation

#### 1. Model — `app/models/gym_draft.rb`

**Add constants:**
```ruby
NOMINATION_GRACE_SECONDS = 60
NOMINATION_FINAL_SLOTS = 2  # how many slots the nominating phase fills (5 and 6)
```

**Replace `current_nomination` with `candidates`:**
```ruby
def candidates
  data["candidates"] || []
end

def current_turn_started_at
  ts = data["current_turn_started_at"]
  ts.present? ? Time.zone.parse(ts) : nil
end

def grace_elapsed?
  return true if current_turn_started_at.nil?
  Time.current - current_turn_started_at >= NOMINATION_GRACE_SECONDS
end

def current_nominator_id
  return nil unless nominating?
  pick_order[current_player_index % pick_order.size]
end

def nomination_picks_made
  candidates.flat_map { |c| c["voters"] }.size
end
```

**Replace `submit_nomination!` + `vote_on_nomination!` with a single action:**
```ruby
def nominate!(picker_uid, group_id)
  raise "Not in nominating phase" unless nominating?
  raise "Not your turn to nominate" unless current_nominator_id == picker_uid.to_i
  raise "That pokemon has already been picked" if picks.any? { |p| p["group_id"] == group_id.to_i }

  cands = candidates.map(&:deep_dup)
  existing = cands.find { |c| c["group_id"] == group_id.to_i }
  if existing
    raise "You already endorsed this nomination" if existing["voters"].include?(picker_uid.to_i)
    existing["voters"] << picker_uid.to_i
  else
    cands << { "group_id" => group_id.to_i, "voters" => [picker_uid.to_i] }
  end

  next_index = current_player_index + 1
  total_picks_after = cands.flat_map { |c| c["voters"] }.size

  if total_picks_after >= pick_order.size
    # All 4 players have made their nomination-phase pick → resolve
    update!(state_data: data.merge(
      "candidates" => cands,
      "current_turn_started_at" => nil
    ).as_json)
    self.reload
    resolve_nominations!
  else
    update!(
      current_player_index: next_index,
      state_data: data.merge(
        "candidates" => cands,
        "current_turn_started_at" => Time.current.iso8601
      ).as_json
    )
  end
end
```

**New resolution algorithm:**
```ruby
def resolve_nominations!
  cands = candidates
  # Sort by voter count desc; preserve nomination order as stable secondary
  ranked = cands.each_with_index.sort_by { |c, i| [-c["voters"].size, i] }.map(&:first)

  winners = []
  tiebreak_payload = nil

  remaining_slots = NOMINATION_FINAL_SLOTS
  i = 0
  while i < ranked.size && remaining_slots > 0
    same_count_group = ranked[i..].take_while { |c| c["voters"].size == ranked[i]["voters"].size }
    if same_count_group.size <= remaining_slots
      winners.concat(same_count_group)
      remaining_slots -= same_count_group.size
      i += same_count_group.size
    else
      # Tie at the threshold — pick `remaining_slots` of `same_count_group` randomly
      chosen = same_count_group.shuffle.first(remaining_slots)
      tiebreak_payload = {
        "type" => same_count_group.size == cands.size ? "n_way" : "second_place",
        "tied_group_ids" => same_count_group.map { |c| c["group_id"] },
        "winners" => chosen.map { |c| c["group_id"] }
      }
      winners.concat(chosen)
      remaining_slots = 0
    end
  end

  new_picks = picks.dup
  winners.each_with_index do |c, idx|
    new_picks << {
      "round" => picks.size + idx + 1,
      "group_id" => c["group_id"],
      "picked_by" => c["voters"].first  # nominator
    }
  end

  update!(
    status: "complete",
    current_round: new_picks.size,
    state_data: data.merge(
      "picks" => new_picks,
      "tiebreak" => tiebreak_payload
    ).as_json
  )
end
```

**Update `skip_turn!`:**
```ruby
def skip_turn!(requester_uid)
  raise "Can only skip during drafting or nominating" unless drafting? || nominating?

  if drafting?
    raise "Not your turn" unless current_drafter_id == requester_uid.to_i
    next_index = current_player_index + 1
    if next_index >= pick_order.size
      update!(current_player_index: 0, status: "nominating",
              state_data: data.merge("current_turn_started_at" => Time.current.iso8601).as_json)
    else
      update!(current_player_index: next_index)
    end
  else
    # Nominating phase — auth: current nominator OR grace elapsed
    is_current = current_nominator_id == requester_uid.to_i
    raise "Not your turn (skip available to others after 60s)" unless is_current || grace_elapsed?

    next_index = (current_player_index + 1) % pick_order.size
    update!(
      current_player_index: next_index,
      state_data: data.merge("current_turn_started_at" => Time.current.iso8601).as_json
    )
  end
end
```

**Update `make_pick!` (transition into nominating):** when transitioning to nominating, set `current_turn_started_at` in state_data. Currently lines 101-108. Add `"current_turn_started_at" => Time.current.iso8601` to the merged state.

**Update `broadcast_state`:** drop `current_nomination`, add `candidates`, add `current_nominator_id`, add `current_turn_started_at` (as ISO string), add `tiebreak`. Also include a derived `nomination_picks_remaining` for view convenience. Players' `discord_user_id` already stringified — keep that pattern. Voters lists need stringification too.

**Pseudocode for the new broadcast_state additions:**
```ruby
candidates: candidates.map { |c| { "group_id" => c["group_id"],
                                   "voters" => c["voters"].map(&:to_s) } },
current_nominator_id: current_nominator_id&.to_s,
current_turn_started_at: data["current_turn_started_at"],
nomination_picks_remaining: pick_order.size - nomination_picks_made,
tiebreak: data["tiebreak"]&.merge(
  "tied_group_ids" => data["tiebreak"]["tied_group_ids"],
  "winners" => data["tiebreak"]["winners"]
)
```

#### 2. Channel — `app/channels/gym_draft_channel.rb`

**Remove** the `vote_nomination` action.

**Update** the `nominate` action to call `@draft.nominate!(current_user_id, data["group_id"])`. (The model now handles both new-and-endorse semantics inside.)

**Update** the `skip` action to pass `current_user_id`:
```ruby
def skip(_data)
  @draft.reload
  @draft.skip_turn!(current_user_id)
  broadcast_state
rescue => e
  transmit({ error: e.message })
end
```

The model's auth check raises with a clear message that the channel surfaces.

#### 3. Avatar caching layer

**Why:** the candidate card needs Discord profile pics for ALL 4 players. Today only the *logged-in* user's avatar URL lives on session. We need a small persistence layer so the view can look up any registered player's avatar.

**Approach:** add a `player_avatars` JSON column to `SoulLinkRun`. On every login (after Discord OAuth succeeds), upsert `current_user_id → current_avatar_url` to the run's `player_avatars` for the user's guild.

**Migration:**
```ruby
class AddPlayerAvatarsToSoulLinkRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :soul_link_runs, :player_avatars, :json
  end
end
```

**Helper on `SoulLinkRun`:**
```ruby
def avatar_for(discord_user_id)
  (player_avatars || {})[discord_user_id.to_s]
end

def upsert_avatar!(discord_user_id, url)
  return if discord_user_id.blank?
  current = (player_avatars || {}).dup
  if url.present?
    return if current[discord_user_id.to_s] == url
    current[discord_user_id.to_s] = url
  else
    return unless current.key?(discord_user_id.to_s)
    current.delete(discord_user_id.to_s)
  end
  update!(player_avatars: current)
end
```

**Wire into login:** in `app/controllers/sessions_controller.rb` (find `create` action), after the session is set, look up the active run for the guild and call `run.upsert_avatar!(discord_user_id, avatar_url)`. Skip if no active run for the guild — no error.

**Fallback in view:** when the avatar is missing for a player, render a colored circle with the player's display_name initial. Helper in `application_helper.rb` or `gym_draft_helper.rb`:
```ruby
def player_avatar_image(run, discord_user_id, size: 32)
  url = run.avatar_for(discord_user_id)
  if url.present?
    image_tag url, class: "gb-avatar gb-avatar--#{size}", alt: SoulLink::GameState.player_name(discord_user_id)
  else
    initial = SoulLink::GameState.player_name(discord_user_id).to_s[0]&.upcase || "?"
    color_index = discord_user_id.to_i % 4
    content_tag :span, initial, class: "gb-avatar gb-avatar--#{size} gb-avatar--initial gb-avatar--c#{color_index}"
  end
end
```

The CSS classes (`.gb-avatar`, `.gb-avatar--32`, `.gb-avatar--initial`, `.gb-avatar--c0..c3`) are NEW. Add them to `pixeldex.css` near the other `.gb-*` tokens. 32px round-ish (matches GB pixel aesthetic — square with `border-radius: 50%` is fine; OR a hexagon for character. Bob's call). Four distinct pastel colors for `c0..c3`.

#### 4. View — `app/views/gym_drafts/show.html.erb`

The nominating panel needs a complete rewrite. Other phases are mostly untouched (with the one Q5 fix on the complete panel).

**Replace the nominating panel structure** (currently lines 102-141). New layout:

```erb
<%# ── NOMINATING PHASE — UNIFIED PICK MODEL ── %>
<div data-gym-draft-target="nominatingPanel" class="hidden">
  <div class="gb-card" style="padding: 16px; margin-bottom: 12px;">
    <div style="font-size: 13px; text-align: center; margin-bottom: 12px;">TEAM SLOTS</div>
    <div style="display: grid; grid-template-columns: repeat(6, 1fr); gap: 6px;" data-gym-draft-target="nomTeamSlots">
      <% 6.times do |i| %>
        <div class="gb-drag-zone" style="text-align: center; min-height: 70px; display: flex; align-items: center; justify-content: center;"
             data-slot-index="<%= i %>">
          <span style="font-size: 10px; color: var(--d2);">#<%= i + 1 %></span>
        </div>
      <% end %>
    </div>
  </div>

  <%# Pick-order strip — who's nominated, who's up next %>
  <div data-gym-draft-target="nomOrderStrip" style="margin-bottom: 12px;"></div>

  <%# Status line + grace countdown %>
  <div style="text-align: center; margin-bottom: 12px;">
    <span data-gym-draft-target="nomStatus" style="font-size: 11px; color: var(--d1);"></span>
    <span data-gym-draft-target="nomGraceCountdown" style="font-size: 10px; color: var(--d2); margin-left: 8px;"></span>
    <div data-gym-draft-target="nomSkipButton" class="hidden" style="margin-top: 8px;"></div>
  </div>

  <%# Live candidates row %>
  <div class="gb-card" style="padding: 10px; margin-bottom: 12px;">
    <div style="font-size: 11px; color: var(--d2); margin-bottom: 8px;">CANDIDATES</div>
    <div data-gym-draft-target="nomCandidatesList" style="display: flex; flex-wrap: wrap; gap: 8px;"></div>
  </div>

  <%# Pokemon grid for the current nominator's pick %>
  <div class="gb-card" style="padding: 10px;">
    <div style="font-size: 11px; color: var(--d2); margin-bottom: 8px;">YOUR PICK (click to nominate or endorse)</div>
    <div class="gb-grid-4" data-gym-draft-target="nomPokemonGrid"></div>
  </div>
</div>
```

**Add the TCG coin-flip modal** AFTER the nominating panel (still inside the `data-controller="gym-draft"` wrapper):

```erb
<%# ── TCG COIN-FLIP MODAL — tiebreak reveal ── %>
<div data-gym-draft-target="coinFlipModal"
     class="hidden"
     style="position: fixed; inset: 0; z-index: 70;">
  <div style="position: absolute; inset: 0; background: rgba(15, 56, 15, 0.92);"></div>
  <div style="position: relative; display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: 16px;">
    <div class="gb-modal" style="max-width: 480px; text-align: center; border-color: #c0392b;"> <%# pokéball-red accent %>
      <div class="gb-modal-title" style="color: #c0392b;">★ WILD COIN APPEARED! ★</div>
      <div style="padding: 16px;">
        <div data-gym-draft-target="coinFlipMessage" style="font-size: 11px; color: var(--d1); margin-bottom: 16px;">
          A tied vote — the coin decides...
        </div>
        <div class="tcg-coin-stage" style="perspective: 800px; height: 120px; display: flex; align-items: center; justify-content: center;">
          <div data-gym-draft-target="coinFlipCoin" class="tcg-coin">
            <div class="tcg-coin__face tcg-coin__face--pokeball"></div>
            <div class="tcg-coin__face tcg-coin__face--character"></div>
          </div>
        </div>
        <div data-gym-draft-target="coinFlipResult" class="hidden" style="margin-top: 16px; font-size: 12px; color: var(--amber);"></div>
      </div>
    </div>
  </div>
</div>
```

**TCG coin styling — primary attempt (~30 minute budget).** The `.tcg-coin` is a new CSS component, ~80px circular with `transform-style: preserve-3d`, two `.tcg-coin__face` children absolutely positioned with `backface-visibility: hidden`, one face rotated 180° on Y. Each face is gold-edged (`box-shadow: inset 0 0 0 4px #d4a444, 0 4px 12px rgba(0,0,0,0.4)`). The `--pokeball` face draws a pokéball — easiest with a radial-gradient or a tiny inline SVG (top half red `#ee1515`, bottom half white-ish `#f0f0f0`, black equator stripe, central black-rimmed white circle). The `--character` face shows a Pikachu silhouette, lightning bolt, or just the Pokémon League logo — whatever's cleanest in inline SVG; this face is decorative-only since the result text appears below.

Animation: a CSS keyframe `@keyframes tcgCoinFlip` that rotates `rotateY(0)` → `rotateY(1980deg)` over 1.8s with `cubic-bezier(0.2, 0.8, 0.4, 1.0)` easing. The final stop angle is 1980deg = 5.5 rotations + 180° (lands on the OPPOSITE face every time, regardless of the result — the result is text-only below the coin). Add a slight `translateY` bounce in the last 200ms for "settle" feel.

**Fallback if the TCG-coin look is fiddly past 30 minutes.** Drop the `.tcg-coin__face--character` and replace with a generic gold-edged second face (just a textured gold circle with a small "?"). Keep all the same animation, palette, and modal framing. The brief authorizes this as Bob's escape hatch — write a `# TCG-coin fallback used; see brief Q4 escape hatch` comment near the CSS so the call is documented, and note it in REVIEW-REQUEST.

Add the CSS to `pixeldex.css`. Bob's discretion on the exact SVG; the test only asserts the modal opens, animates, and closes — not the visual fidelity.

**Q5 fix — complete panel** (currently lines 158-169):
- Make "BACK TO GYM READY" use `gb-btn` (not `gb-btn-primary`) and put it AFTER MARK BEATEN (current order has BACK below but they're equally weighted).
- Keep "MARK GYM N AS BEATEN" as `gb-btn-primary`.

#### 5. Stimulus — `app/javascript/controllers/gym_draft_controller.js`

**Remove:**
- `approveNomination` action
- `rejectNomination` action

**Replace `nominatePokemon`** with a unified `nominateOrEndorse(event)` that just performs `subscription.perform("nominate", { group_id })` — the server figures out new-vs-endorse. Update the action handler in the JS that's bound to the pokemon grid card click.

**Add new render branches:**
- `renderNomOrderStrip()` — same horizontal pick-order chip pattern that drafting uses (not yet implemented in current code; Bob can write a shared helper for both).
- `renderCandidates()` — for each candidate in `state.candidates`, render a card showing:
  - Pokemon nickname (large)
  - Species name (small)
  - Avatar pile: stacked `<img>` (or initial-circle div) for each voter, with `margin-left: -8px` overlap on all but the first
  - Voter count badge (e.g., `★ 3`)
  - Highlight ring on the leading candidate(s)
- `renderNomGraceCountdown()` — compute `60 - elapsed` from `state.current_turn_started_at`, update text every 1s. When elapsed ≥ 60, swap the text to "SKIP AVAILABLE" and reveal the skip button to non-current-nominator viewers.
- `renderCoinFlipModal()` — when `state.tiebreak` is non-null AND `state.status === "complete"`, show the modal:
  1. Set message: `"Slot 6 was tied between {N} candidates"` (or 4-way variant — "All four picks were unique. The coin chooses 2.").
  2. Trigger the TCG-coin CSS animation by adding/re-adding the `.tcg-coin--flipping` class to the coin element (force keyframe restart with `void coin.offsetWidth` trick).
  3. After ~1.8s (matching the keyframe duration), populate `coinFlipResult` with the winner names from `tiebreak.winners` (looked up via `findGroupById`).
  4. Auto-close after another 2s, then the complete panel renders normally.
  
  IMPORTANT: only show the modal once per state — track a flag `this.coinFlipShownFor = JSON.stringify(state.tiebreak)` to dedupe across `render()` calls. The tiebreak field stays populated in `state_data` (historical record) but the modal must not re-fire on every subsequent state update.

**Update `renderNominating()`:** call the new render helpers (`renderNomOrderStrip`, `renderCandidates`, `renderNomGraceCountdown`); render the pokemon grid such that already-nominated candidates show "ENDORSE" label instead of "NOMINATE".

**Update `startSkipTimer`** logic: still 30s default to show the skip button, BUT the button's visibility for non-current-nominators is gated on `state.current_turn_started_at` + 60s grace. Easier: drop the local `skipTurnTimer` setTimeout pattern entirely; instead, drive skip-button visibility from the per-second grace countdown render.

#### 6. CSS additions — `app/assets/stylesheets/pixeldex.css`

- `.gb-avatar`, `.gb-avatar--32`, `.gb-avatar--initial`, `.gb-avatar--c0..c3` — avatar circle styles (initial fallback colors).
- `.gb-avatar-pile` — wrapper that lays out a row of avatars with `-8px` margin-left overlap.
- `.tcg-coin` + `.tcg-coin__face` + `.tcg-coin__face--pokeball` + `.tcg-coin__face--character` — TCG-coin component with `transform-style: preserve-3d`, two-face composition, gold-edged shadow. `@keyframes tcgCoinFlip` (1.8s rotateY 0→1980deg + small translateY bounce). Fallback escape hatch documented above if SVG craft overruns the 30-min budget.
- `.gb-candidate-card` — candidate card layout (40-60 LOC of CSS).
- Reuse existing `.gb-modal` for the coin-flip modal wrapper.

#### 7. Tests — full coverage of the new logic

**Model tests (`test/models/gym_draft_test.rb`)** — REMOVE the now-stale tests:
- "submit_nomination creates nomination with nominator auto-vote"
- "submit_nomination raises for already picked group"
- "submit_nomination raises when nomination is pending"
- "vote_on_nomination records vote"
- "nomination approved with majority adds pick"
- "nomination rejected clears nomination without adding pick"

**Add new tests** (these are mandatory, not optional):
1. **Nominate creates a new candidate** — `@draft.nominate!(GREY, group)` → `candidates.size == 1`, `voters == [GREY]`, advances `current_player_index`.
2. **Endorsement adds voter to existing candidate** — same group_id used twice → `candidates.size == 1`, `voters == [GREY, ARATY]`.
3. **Cannot nominate already-picked individual group** — raises.
4. **Cannot endorse twice** — `nominate!(GREY, X)` then `nominate!(GREY, X)` → raises "You already endorsed this nomination" (same player can't double-vote even though `current_player_index` would advance; but this case shouldn't happen since you only get one turn — keep the guard for safety).
5. **Not your turn** — `nominate!(ARATY, X)` when GREY is up → raises.
6. **Tally edge case 3/1** — 3 voters on candidate A, 1 voter on candidate B → status `complete`, picks 5+6 are A and B.
7. **Tally edge case 2/2** — 2 voters each on A and B → status complete, picks 5+6 are A and B (no tiebreak needed).
8. **Tally edge case 2/1/1** — A has 2, B and C each 1 → status complete, A definitely in picks; one of B/C in picks; `tiebreak.type == "second_place"`, `tied_group_ids == [B.id, C.id]`.
9. **Tally edge case 1/1/1/1** — 4 unique candidates, 1 voter each → 2 picked (random), `tiebreak.type == "n_way"`, `tied_group_ids` has all 4, `winners` has 2.
10. **Tally edge case 1-candidate consensus (4/0)** — all 4 endorse the same → 1 pick (slot 5), slot 6 stays empty (`picks.size == 5`, status `complete`).
11. **`current_turn_started_at` is set on transition into nominating** — after the 4th individual draft pick, `state_data["current_turn_started_at"]` is present.
12. **`current_turn_started_at` advances on each nominate** — record timestamp before/after; assert it changes.
13. **`grace_elapsed?` returns true when 60s+ have passed** — stub `Time.current` via `Time.zone.now` or `freeze_time`.
14. **`skip_turn!(requester)` raises if requester is not current nominator and grace not elapsed.**
15. **`skip_turn!(requester)` succeeds if requester IS current nominator** (any time).
16. **`skip_turn!(requester)` succeeds for non-nominator after grace** — set `current_turn_started_at` to 65 seconds ago, non-current-nominator can skip.
17. **`tiebreak` is nil in state_data when no tie occurred** — 3/1 case asserts this.

**Channel tests (`test/channels/gym_draft_channel_test.rb`)** — REMOVE legacy `vote_nomination` tests. Add:
1. **`nominate` creates new candidate** — perform with new group_id, assert state broadcasts include the candidate.
2. **`nominate` endorses existing candidate** — second player nominates same group_id, voter list grows.
3. **`skip` rejected for non-nominator before grace** — stub `current_user_id`, assert `transmit` receives `{error: ...}`.
4. **`skip` allowed for non-nominator after grace** — set `current_turn_started_at` 65s ago, non-current-nominator's skip succeeds.
5. **`vote_nomination` action removed** — assert calling it via `perform` raises `NoMethodError` or returns gracefully (Bob's call on assertion shape; the action just shouldn't exist on the channel).

**Helper tests** for `player_avatar_image` — initial fallback when no URL, image tag when URL present.

**Test count delta:** ~17 new model tests + ~5 new channel tests + helper tests = +25 to +30 tests. Step 13 ended at 343. Step 14 should land somewhere in the 365-375 range. If lower, Bob is under-testing edge cases.

#### 8. Migrations + backfill

**One migration:** add `player_avatars` JSON column to `soul_link_runs`.

**Backfill for in-flight nominating drafts:**
```ruby
class CleanupCurrentNominationFromInflightDrafts < ActiveRecord::Migration[8.1]
  def up
    GymDraft.where(status: "nominating").find_each do |draft|
      data = draft.state_data || {}
      next unless data.key?("current_nomination")
      data.delete("current_nomination")
      data["candidates"] ||= []
      data["current_turn_started_at"] = Time.current.iso8601
      draft.update_columns(state_data: data)
    end
  end

  def down
    # No-op; data is gone.
  end
end
```

This is the second migration. Two total: avatars + cleanup. Both very small.

The Project Owner can `RESET DRAFT` (Step 13 affordance) on any draft that gets weird state.

### Out of Scope (do NOT expand)

- **Captain-decides anything in nominating.** The Path A captain-tiebreak narrative is gone. Don't sneak it back.
- **Path A surface-level UX (LED row, yes/no per-voter cells).** Replaced by the candidate-card avatar pile.
- **Real-time avatar refresh.** When a player updates their Discord avatar, our cache won't update until they next log in. Acceptable.
- **Avatar caching for non-active runs.** Only the active run for the user's guild gets the avatar cached. Past archived runs get nothing. Acceptable.
- **Cross-guild avatar sharing.** Each run carries its own avatar map. Acceptable.
- **Discord bot integration of the new draft state.** The bot doesn't surface drafts today; out of scope.
- **Refactoring `gym_draft_controller.js` Tailwind drift.** The audit's G6/G7 — fix only the lines you're touching. Don't sweep.
- **A new mockup before building.** The Project Owner explicitly said "no mockup needed first" — work from the audit + this brief.
- **Migration for `picks` round numbers** — the existing `round` field can keep counting up; don't try to renumber.
- **Soft-delete of dropped-from-tiebreak candidates** — they stay in `candidates` array but are simply not in `picks`. The data is intact for any future audit UI.
- **Helper extraction for the avatar pile** beyond `player_avatar_image`. Pile rendering is in the Stimulus controller (JS). The helper is for ERB-rendered surfaces only.
- **Tests for the coin-flip CSS animation timing.** JS timing assertions are flaky; assert the modal opens + closes only.
- **Stalemate handling beyond the 1-candidate edge case.** Ties are resolved by `Array#sample`; that's the policy.

### Constraints / Flags

- **State data backwards compatibility is broken.** A draft mid-nominating-phase under the OLD code will NOT work under the new code. The cleanup migration handles this. Bob: do NOT add a runtime fallback for `current_nomination` data — it's a migrated-once-and-gone field.
- **Time handling:** use `Time.current` and ISO8601 strings consistently. Test with `freeze_time` from ActiveSupport::Testing::TimeHelpers (already used in some Soul Link tests; check `test_helper.rb`). Don't introduce `Timecop`.
- **Server is the source of truth for tiebreak.** The client renders the animation using `state.tiebreak.tied_group_ids` and `state.tiebreak.winners`, both populated server-side at resolution. The client never picks the winner.
- **`Array#sample` is the resolution policy.** Don't get fancy with weighted shuffles or seeded RNG. Keep it simple; `sample` is uniform-random and self-documenting.
- **Avatar URLs from Discord OAuth are the only source.** Don't introduce avatar uploads, gravatar, or any other source.
- **Coin-flip modal blocks user interaction** — overlay covers the page during the animation. Don't let the underlying complete panel render until the modal closes.
- **Voters list is INTEGER user IDs in state_data** (matches existing `picks[].picked_by` shape). Stringification happens in `broadcast_state` only. Tests assert integer storage, string broadcast.
- **No new gems.** All requirements satisfied by existing dependencies.
- **Rubocop must stay clean** (Step 13 ended at 0 offenses, 148 files).
- **`bundle exec rubocop` AND `bin/rails test`** must both be clean before signaling Ready for Review.
- **Bob: read the audit before coding.** `handoff/2026-05-01-gym-draft-audit.md` has the bug catalog and the rationale; this brief is the spec.

### Acceptance Criteria

- New migrations: `add_player_avatars_to_soul_link_runs`, `cleanup_current_nomination_from_inflight_drafts`.
- `SoulLinkRun#avatar_for(uid)` + `SoulLinkRun#upsert_avatar!(uid, url)` defined and tested.
- `app/controllers/sessions_controller.rb` `create` action upserts the avatar after auth.
- `GymDraft` model: `current_nomination` / `submit_nomination!` / `vote_on_nomination!` / `resolve_nomination!` removed. `candidates` / `current_turn_started_at` / `current_nominator_id` / `grace_elapsed?` / `nomination_picks_made` / `nominate!` / `resolve_nominations!` (plural) added. `skip_turn!` takes `requester_uid` and enforces the new auth.
- `GymDraftChannel`: `vote_nomination` action removed; `nominate` calls `nominate!`; `skip` passes `current_user_id`.
- `gym_drafts/show.html.erb`: nominating panel rewritten with candidate cards + grace countdown + skip slot. Coin-flip modal added. Q5 button-weight fix applied.
- `gym_draft_controller.js`: legacy approve/reject removed; new render branches for candidates, order strip, grace countdown, coin-flip modal.
- New helper `player_avatar_image(run, uid)` in an appropriate helper file.
- New CSS classes for `.gb-avatar` family + `.coin-flip-pokeball` keyframe.
- Tests cover all 5 tally splits (3/1, 2/2, 2/1/1, 1/1/1/1, 1-candidate consensus), grace skip auth, avatar upsert, helper rendering. ~25-30 new tests.
- 343 + ~25 = ~368-375 tests passing, 0 failures.
- `bundle exec rubocop` clean.
- Manual smoke (Bob, in `bin/dev` if it works in your sandbox; otherwise harness against test infra and document the gap):
  1. Run `bin/rails db:migrate`.
  2. Walk lobby → voting → drafting → nominating → complete with all 4 players.
  3. Test all 5 tally splits with manually-crafted state in `rails console` or test fixtures.
  4. Confirm coin-flip modal renders for tiebreak cases; auto-closes; complete panel shows.
  5. Confirm avatar pile shows real avatars where cached, initial circles otherwise.
  6. Confirm 60s grace skip: only nominator can skip in first 60s, anyone after.
- Diff scope: 1 model + 1 channel + 1 controller (sessions) + 2 views (1 minor: complete-panel button weight; 1 major: nominating panel) + 1 stylesheet + 1 helper + 1 Stimulus + 2 migrations + 4 test files + 4 handoff files. ~13 source files + 2 migrations + 4 handoff. Anything else is a Reviewer Condition.

### Files Bob Should Read

- `handoff/2026-05-01-gym-draft-audit.md` — full read; this is the rationale.
- `app/models/gym_draft.rb` — full (will be substantially rewritten).
- `app/channels/gym_draft_channel.rb` — full (small).
- `app/javascript/controllers/gym_draft_controller.js` — full (will be substantially rewritten).
- `app/views/gym_drafts/show.html.erb` — full.
- `app/controllers/sessions_controller.rb` — to wire avatar upsert.
- `app/controllers/concerns/discord_authentication.rb` — confirm session keys.
- `test/models/gym_draft_test.rb` — full (existing patterns + private helpers).
- `test/channels/gym_draft_channel_test.rb` — full.
- `test/factories/gym_drafts.rb` — full (small).
- `app/services/soul_link/game_state.rb` — first 110 lines (player_ids, players, player_name).
- `app/assets/stylesheets/pixeldex.css` — grep for `.gb-modal`, `.gb-card`, `.gb-btn-*` to match style; don't read the whole file.

DO NOT load:
- The Path A mockup HTML (`handoff/2026-05-01-gym-draft-redesign.html`) — design has shifted; mockup is historical.
- The Discord bot code (`lib/tasks/soul_link.rake`, `app/services/soul_link_bot/`) — out of scope.
- The dashboard views (Step 13 territory).
- The emulator/save-slot flow.
- The strategy-panel / type-chart code on draft show.

### Files Bob Should Update at the End

- `handoff/REVIEW-REQUEST.md` — files-changed table, self-review answers covering EVERY constraint flag above plus the 17 reviewer focus areas in the Notes section, open questions if any, `Ready for Review: YES`.
- `handoff/BUILD-LOG.md` — Step 14 history entry following Step 11/12/13 structure. Note: the avatar caching layer + 60s skip grace + coin-flip modal are NEW SURFACES introduced this step; call them out.

---

## Notes for Reviewer (Richard)

When this lands on your desk, focus on:

1. **Tally algorithm correctness on all 5 splits.** Walk `resolve_nominations!` mentally for 3/1, 2/2, 2/1/1, 1/1/1/1, and 1-candidate. The greedy-fill loop is subtle; confirm tests cover each split exactly once with the expected `tiebreak` payload.

2. **`tiebreak.winners` is set server-side, not by the client.** Critical security/correctness. The client must NOT pick winners via JS — animation only.

3. **No `current_nomination` references survive.** Grep for `current_nomination` across the codebase post-merge. Should be ZERO hits in `app/`. Tests may reference it in setup/teardown to assert removal.

4. **Skip auth enforces both branches.** Inside-grace: only nominator. After-grace: anyone. Test that BOTH branches raise/succeed correctly for the right caller.

5. **`current_turn_started_at` is updated on every turn change.** Confirm the model writes it on: transition into nominating (from drafting), each `nominate!` that doesn't terminate, each `skip_turn!`. Missing one breaks the grace logic.

6. **Endorsement on already-endorsed-by-self raises.** A safety belt — even though `current_player_index` should prevent this naturally, the guard is there for races.

7. **Avatar upsert handles missing run gracefully.** Login when no active run for the guild → no error, no upsert. Test this.

8. **Avatar fallback color is deterministic per discord_user_id.** Same user always renders same initial color. Helper must be pure.

9. **The cleanup migration is idempotent.** If run twice, no error. The `next unless data.key?("current_nomination")` guard handles this.

10. **`gym_draft_test.rb` legacy tests for `submit_nomination!` and `vote_on_nomination!` are GONE.** If they're still there, Bob forgot to clean up. Should NOT just rename to skip.

11. **Coin-flip modal dedupes across `render()` calls.** Stimulus `render()` fires on every state update; the modal must not re-trigger every time. Look for `coinFlipShownFor` or equivalent flag.

12. **`Q5` is applied surgically.** Only the complete-panel buttons. Not a sweep of every primary button on the page.

13. **Stimulus targets array is updated.** New targets: `nomOrderStrip`, `nomGraceCountdown`, `nomSkipButton`, `nomCandidatesList`, `coinFlipModal`, `coinFlipMessage`, `coinFlipCoin`, `coinFlipResult`. Removed targets: `nomVoteArea`, `nomVotePrompt`. If the array doesn't match, Stimulus throws at runtime.

14. **`broadcast_state` includes `candidates`, `current_turn_started_at`, `current_nominator_id`, `tiebreak`.** And does NOT include `current_nomination`. Walk the broadcast_state output by inspecting one of the new model tests.

15. **CSS additions don't conflict with existing tokens.** New classes are namespaced (`.gb-avatar`, `.gb-candidate-card`, `.coin-flip-*`). No bare `.avatar` or `.candidate` that could collide.

16. **The 1-candidate edge case (4/0)** results in `picks.size == 5` and status `complete`. The team having 5 instead of 6 is intentional — flag if the implementation tries to "fix" this.

17. **Manual smoke must be documented in REVIEW-REQUEST.** If `bin/dev` doesn't work in Bob's sandbox (foreman/tailwind-v4 quirk that surfaced in Step 13), Bob falls back to a render-condition harness AND documents which user flows were NOT exercised in a real browser. Decide if that's acceptable for this step's surface area (modal animations, real-time grace countdown — these may genuinely need browser eyeballing).

Out-of-scope items found during review → BUILD-LOG Known Gaps. Do not bundle.
