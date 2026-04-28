# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 1 — Evolve Button on Pokemon Modal

Add an `EVOLVE` button next to each immediate evolution target in the Pokemon detail modal's evolution display. Clicking it PATCHes the current user's pokemon species to that target and reloads.

**Per-player only.** Soul-link partners do NOT co-evolve. Spec language was "update the species for the discord user" (singular) and matches existing per-player precedent (catch/death/team-slot all per-player).

### No Backend Changes

- `PATCH /pokemon/:id` already accepts `species` via `pokemon_params` (`app/controllers/pokemon_controller.rb:73`).
- Auth check at line 14 already enforces ownership.
- No callbacks fire on species mutation. Verified: model has no `before_save` / `after_update` touching species.
- No new route, no new controller action, no migration.

### Files to Modify

**1. `app/javascript/controllers/pixeldex_controller.js`** — extend `#renderEvoNode` and add a new action.

- In `#renderEvoNode(container, node, selectedSpecies, isFirst)`:
  - Add a 5th argument `parentIsSelected` (default false).
  - When recursing into children at lines 503 and 515, pass `node.isSelected` as `parentIsSelected`.
  - When `parentIsSelected === true` AND `this.modalPokemonIdTarget.value` is non-empty AND the modal is not in a dead-pokemon state, append an `EVOLVE` button after the trigger info (level/method) for this node.
  - Button markup: `<button type="button" class="gb-btn-primary gb-btn-sm" data-action="click->pixeldex#evolvePokemon" data-target-species="<node.name>" style="font-size: 9px; padding: 2px 6px; margin-left: 4px;">EVOLVE</button>`
  - Use `dataset` to set the species — do NOT interpolate user data into innerHTML (architecture rule: textContent only).

- New method `async evolvePokemon(event)`:
  - Read target species from `event.currentTarget.dataset.targetSpecies`.
  - Read pokemon id from `this.modalPokemonIdTarget.value`. If empty, return early.
  - Match `savePokemon` for URL/headers exactly:
    ```js
    const res = await fetch(`${this.pokemonUpdateUrlValue}/${pokemonId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfValue },
      body: JSON.stringify({ species: targetSpecies })
    })
    if (res.ok) window.location.reload()
    ```
  - On non-OK response, surface error to `modalStatusTarget` (mirror `savePokemon` line ~310 error handling).

### Dead-Pokemon Gate

The existing modal already toggles `modalDeadBtn` visibility based on group status. Bob: locate that logic (likely in `selectPokemon` / `#openModal`) and reuse the same gate to decide whether evolve buttons should render. **If the gate doesn't exist as a reusable check**, gate on group status === `'caught'` only.

### Out of Scope (Logged as Known Gaps)

- Co-evolution of linked partners
- Real-time broadcast to other players' dashboards (they see the change on next refresh)
- Level/method gating on the button (always-on UI; player owns timing)
- Loading state on the button during the request

### Tests

No new tests required. Existing `PokemonControllerTest` already covers the species-PATCH path. Bob: run the full suite to confirm no regressions, no new tests added.

### Build Order

1. Read modal view + the `selectPokemon` / `#openModal` flow to understand how `modalPokemonIdTarget` is populated and how the dead gate works.
2. Read `savePokemon` (line 291) end-to-end to mirror its fetch shape and error-status handling.
3. Modify `#renderEvoNode` signature + recursive calls to thread `parentIsSelected`.
4. Add button rendering inside `#renderEvoNode`.
5. Add `evolvePokemon` action.
6. Run full test suite — must be green.
7. Manual verification deferred to Project Owner (Bob can't drive a browser).

### Flag

- Bob: confirm `pokemonUpdateUrlValue` and `csrfValue` are already declared as static values on the pixeldex controller (they should be, since `savePokemon` uses them). If somehow not, add them — but they should exist.
- Bob: if the dead-pokemon gate doesn't exist as a clean reusable check, do NOT invent a complex one — just gate on the group status string and note it for Richard.
