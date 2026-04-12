# Review Feedback -- Step 2
Date: 2026-04-12
Ready for Builder: NO

## Must Fix

- `app/models/gym_draft.rb:131` -- `skip_turn!(uid)` accepts `uid` but never validates it against the current turn holder. Any connected player can skip anyone else's turn by calling `subscription.perform("skip")`. Add a guard: in drafting, raise unless `pick_order[current_player_index] == uid.to_i`; in nominating, raise unless `pick_order[current_player_index % pick_order.size] == uid.to_i`. This matches the pattern already used in `make_pick!` (line 94) and `submit_nomination!` (line 119).

- `app/javascript/controllers/gym_draft_controller.js:225` -- `canNominate` is set to `!nomination` with no check on whose turn it is. Every player sees interactive clickable cards during the nominating phase when no nomination is pending. The server guard catches it, but the UI should only enable cards for the current nominator. Compare `pick_order[current_player_index % pick_order.length]` against `userIdValue` and AND that with `!nomination`.

- `app/javascript/controllers/gym_draft_controller.js:220` -- When no nomination is pending, `nomStatusTarget` says "Nominate a pokemon for the team!" with no indication of whose turn it is. This is the nominating equivalent of the `turnIndicator` in drafting. Show the current nominator name: "Your turn to nominate!" or "Waiting for [name] to nominate...".

## Should Fix

- `app/javascript/controllers/gym_draft_controller.js:338-358` -- `startSkipTimer` shows the SKIP TURN button to all connected clients after 30 seconds, not just the player whose turn it is. Any player can click it and (once the Must Fix auth guard is added) the server will reject non-current-player skips. The timer should only start if it is the current user's turn, or at minimum gate the timer: in drafting, only if `currentId === this.userIdValue`; in nominating, only if the current nominator matches the user.

- `app/models/gym_draft.rb:150` -- `skip_turn!` in the nominating branch clears `current_nomination` unconditionally. If a nomination is in progress with votes partially collected, skipping wipes it. This may be intentional for the 30s timeout case, but confirm the intended behavior. If a nomination is pending, the skip should probably be blocked or the brief should clarify.

## Escalate to Architect

None.

## Cleared

Channel action (`gym_draft_channel.rb:44-50`) follows existing pattern correctly. Model turn advancement in `resolve_nomination!` (lines 241-256) correctly computes `next_nominator_index` with modular wrap and advances before the complete check. `fillTeamSlots` and `renderPokemonGrid` DOM construction produces equivalent output to the original innerHTML approach. View template skip button target containers are placed correctly in both drafting and nominating panels. Double-click prevention on pick, nominate, and vote actions works correctly. `skip_turn!` drafting-to-nominating transition at `pick_order.size` is consistent with `make_pick!` logic.
