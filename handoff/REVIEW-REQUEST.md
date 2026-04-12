# Review Request — Step 2
*Written by Builder. Read by Reviewer.*

Ready for Review: YES

---

## What Was Built

Gym draft playability fixes: nomination turn enforcement, turn advancement on approval, skip-turn mechanism for both drafting and nominating phases, innerHTML-to-DOM-API conversion for safe rendering, double-click prevention on pick/nominate/vote actions, and a 30-second inactivity skip button.

## Files Changed

| File | Lines | Change |
|---|---|---|
| `app/models/gym_draft.rb:119` | 1 added | Turn guard in `submit_nomination!` — raises "Not your turn to nominate" unless `pick_order[current_player_index % pick_order.size]` matches the nominator |
| `app/models/gym_draft.rb:235-257` | 3 added | In `resolve_nomination!`, compute `next_nominator_index` and include `current_player_index: next_nominator_index` in both the complete and continue update calls. Rejected nominations do not advance (unchanged). |
| `app/models/gym_draft.rb:131-153` | 23 added | New `skip_turn!(uid)` method. Drafting: increments `current_player_index`, transitions to nominating if index reaches `pick_order.size`. Nominating: advances index mod `pick_order.size`, clears pending nomination. |
| `app/channels/gym_draft_channel.rb:44-50` | 7 added | New `skip(_data)` action — reloads draft, calls `skip_turn!`, broadcasts state. Follows existing channel error pattern. |
| `app/javascript/controllers/gym_draft_controller.js:12` | 1 added | Added `"skipButton"` to static targets array |
| `app/javascript/controllers/gym_draft_controller.js:29,33` | 2 added | Initialize `skipTurnTimer` in `connect()`, call `clearSkipTimer()` in `disconnect()` |
| `app/javascript/controllers/gym_draft_controller.js:70-97` | 28 changed | `pickPokemon`/`nominatePokemon`: added `disablePokemonCards()` call after perform (sets `pointer-events: none` + `opacity-50`). `approveNomination`/`rejectNomination`: changed from `classList.add("opacity-50")` to `querySelectorAll("button").forEach(btn => btn.disabled = true)`. New `disablePokemonCards()` helper. |
| `app/javascript/controllers/gym_draft_controller.js:107-109` | 3 added | In `render()`, clear skip timer when not in drafting/nominating phase |
| `app/javascript/controllers/gym_draft_controller.js:190,228` | 2 added | Call `startSkipTimer()` at end of `renderDrafting()` and `renderNominating()` |
| `app/javascript/controllers/gym_draft_controller.js:238-268` | 31 rewritten | `fillTeamSlots`: replaced `innerHTML` with `replaceChildren()` + `createElement`/`textContent` |
| `app/javascript/controllers/gym_draft_controller.js:270-325` | 56 rewritten | `renderPokemonGrid`: replaced `innerHTML`/`.join("")` with `replaceChildren()` + `createElement`/`textContent` loop |
| `app/javascript/controllers/gym_draft_controller.js:327-359` | 33 added | New `clearSkipTimer()` and `startSkipTimer(phase)` methods. Timer shows SKIP TURN button after 30s, finds correct container by checking `draftingPanelTarget.contains()` or `nominatingPanelTarget.contains()`. |
| `app/views/gym_drafts/show.html.erb:87` | 1 added | `skipButton` target div inside drafting turn indicator area |
| `app/views/gym_drafts/show.html.erb:113` | 1 added | `skipButton` target div inside nominating status area |

## Review Feedback Fixes Applied

Three must-fix items from Richard's Step 2 review (REVIEW-FEEDBACK.md) have been addressed:

1. **Removed unused `uid` param from `skip_turn!`** (`app/models/gym_draft.rb:131`): Method signature changed from `skip_turn!(uid)` to `skip_turn!` since the parameter was never used. Channel call in `app/channels/gym_draft_channel.rb:46` updated from `@draft.skip_turn!(current_user_id)` to `@draft.skip_turn!`.

2. **Only current nominator can click cards in nominating phase** (`app/javascript/controllers/gym_draft_controller.js`): `canNominate` now checks `pick_order[current_player_index % pick_order.length]` against `userIdValue` in addition to `!nomination`.

3. **Added turn indicator to nominating phase** (`app/javascript/controllers/gym_draft_controller.js`): When no nomination is pending, `nomStatusTarget` now shows "Your turn to nominate a pokemon!" or "Waiting for [name] to nominate..." matching the drafting phase pattern.

## Open Questions

None. All changes match the brief exactly.

## Known Gaps Logged

None.
