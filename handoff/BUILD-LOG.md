# Build Log
*Owned by Architect. Updated by Builder after each step.*

---

## Current Status

**Active step:** None — awaiting next brief
**Last cleared:** Step 2 — 2026-04-12
**Pending deploy:** NO

---

## Step History

### Step 2 — Gym Draft Playability Fixes — COMPLETE
*Date: 2026-04-12*

Files changed:
- `app/models/gym_draft.rb` — nomination turn enforcement, skip_turn! method, turn advancement in resolve_nomination!
- `app/channels/gym_draft_channel.rb` — new skip action
- `app/javascript/controllers/gym_draft_controller.js` — innerHTML→DOM API, double-click prevention, 30s skip timer, nominating turn indicator
- `app/views/gym_drafts/show.html.erb` — two skipButton target containers

Decisions made:
- Nomination turn order reuses pick_order + current_player_index
- Skip-turn callable by any player (friends policing AFK), no server-side timers
- innerHTML replaced with textContent for all user data in gym draft
- 30s client-side timer before skip button appears

Reviewer findings: 3 must-fix items (skip_turn! param cleanup, nominating grid interactivity, turn indicator) — all resolved. 2 should-fix overridden as intentional design.
Deploy: committed abf9a53

### Step 1 — Fix Pokemon Creation Species-Saving Bugs — COMPLETE
*Date: 2026-04-12*

Files changed:
- `app/javascript/controllers/dashboard_controller.js` — userId: Number → String
- `app/javascript/controllers/species_assignment_controller.js` — userId: Number → String
- `app/javascript/controllers/team_builder_controller.js` — userId: Number → String
- `app/javascript/controllers/pixeldex_controller.js` — fixed sprite path double-wrap and size in searchSpecies()

Decisions made:
- Discord snowflake IDs must always be String in JS (exceed MAX_SAFE_INTEGER)
- spriteMapValue contains digested asset paths — never re-wrap

Reviewer findings: All clear, no regressions.
Deploy: committed 1a179d8

---

## Known Gaps
*Logged here instead of fixed. Addressed in a future step.*

- **KG-1** — Race condition in species assignment (no transaction wrapping) — logged 2026-04-12
- **KG-2** — Team slots accept any group_id (no ownership check) — logged 2026-04-12
- **KG-3** — Fallen section uses group.nickname as species fallback — logged 2026-04-12
- **KG-4** — PokemonGroupsController#create rolls back entire group on one bad species — logged 2026-04-12
- **KG-5** — No test coverage for dashboard, catch flow, or gym draft — logged 2026-04-12

---

## Architecture Decisions
*Locked decisions that cannot be changed without breaking the system.*

- Discord user IDs stored as String in all Stimulus value types — 2026-04-12
- Gym draft skip-turn callable by any player, no server timers — 2026-04-12
- User-supplied text always rendered via textContent, never innerHTML — 2026-04-12
