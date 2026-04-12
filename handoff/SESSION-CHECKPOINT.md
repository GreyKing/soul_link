# Session Checkpoint — 2026-04-12
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*

---

## Where We Stopped

All steps complete. No pending work. ARCHITECT-BRIEF cleared. Six commits on main ready to deploy.

---

## What Was Decided This Session

- Discord snowflake IDs must be `String` not `Number` in all Stimulus controller value types
- `spriteMapValue` contains full digested asset paths — never wrap in additional path segments
- Gym draft nomination turn order enforced via pick_order + current_player_index
- Skip-turn callable by any player (friends policing AFK), no server-side timers
- User-supplied text always rendered via textContent, never innerHTML
- Race conditions in species assignment + pokemon create fixed with unique DB index + transaction + RecordNotUnique rescue
- Team slots filtered by current user's pokemon ownership
- PokemonGroupsController#create: group always survives, per-player errors collected individually
- GymResult model tracks per-gym victories with frozen team snapshots (full per-player breakdown)
- Backfill mechanism for retroactively adding team snapshots to already-beaten gyms
- Unmark restricted to highest-numbered gym to prevent counter desync
- Known low-priority gaps deprioritized: Pokedex/location model validation, ActionCable channel tests

---

## Still Open

- Deploy (Project Owner's responsibility)
- Low-priority: Pokedex species name validation at model level
- Low-priority: Location validation at model level
- Low-priority: GymDraftChannel ActionCable tests

---

## Resume Prompt

Copy and paste this to resume:

---

You are Ava on Soul Link.
Read SESSION-CHECKPOINT.md, then ARCHITECT.md.
Confirm where we stopped and what the next action is. Then wait.

---
