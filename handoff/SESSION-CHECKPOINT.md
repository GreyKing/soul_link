# Session Checkpoint — 2026-04-12
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*

---

## Where We Stopped

Step 2 (gym draft playability fixes) committed on main (abf9a53). Project Owner has requested a new feature: make Pokedex the default view for species selection/search. This will be Step 3.

Known gaps KG-1 through KG-5 logged in BUILD-LOG for future steps (catch flow race condition, team slot ownership, fallen species display, group rollback UX, test coverage).

---

## What Was Decided This Session

- Discord snowflake IDs must be `String` not `Number` in all Stimulus value types
- Gym draft nomination turn order enforced via pick_order + current_player_index
- Skip-turn callable by any player (friends policing AFK)
- User-supplied text rendered via textContent, never innerHTML
- 30s client-side timer before skip button appears
- Known gaps (race conditions, auth, tests) deprioritized — 4 trusted friends, no adversarial threat model

---

## Still Open

- Step 3: Make Pokedex the default view for species selection
- Known gaps KG-1 through KG-5 queued for future steps
- Deploy is Project Owner's responsibility

---

## Resume Prompt

Copy and paste this to resume:

---

You are Ava on Soul Link.
Read SESSION-CHECKPOINT.md, then ARCHITECT.md.
Confirm where we stopped and what the next action is. Then wait.

---
