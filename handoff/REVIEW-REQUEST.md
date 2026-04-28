# Review Request
*Written by Builder. Read by Reviewer.*
*Overwrite this file at the start of each review — it is not a log.*

---

**Author:** Bob
**Date:** 2026-04-27
**Ready for Review:** YES

## Summary

Step 1 — Evolve Button on Pokemon Modal. Adds an `EVOLVE` button next to each direct evolution target of the currently-selected species in the Pokemon detail modal's evolution display. Clicking PATCHes the current user's pokemon `species` to the target and reloads. Per-player only — partner co-evolution intentionally out of scope. Frontend-only change in `app/javascript/controllers/pixeldex_controller.js`. No backend, no migration, no view changes, no new tests.

## Files Changed

- `app/javascript/controllers/pixeldex_controller.js`
  - **Lines 246–249** — In `#openModal`, set `this.modalCanEvolve = status !== "dead" && Boolean(myPokemon.id)` BEFORE `#populateEvolution(species)` runs (line 252), so the renderer can read it. Mirrors the existing dead-btn gate used at line 260.
  - **Line 498** — `#populateEvolution` now passes `false` as the 5th arg (`parentIsSelected`) to the root `#renderEvoNode` call.
  - **Lines 501, 534–547, 552, 564** — `#renderEvoNode` signature gets new 5th arg `parentIsSelected = false`. After the existing trigger info (level/method) block, render an `EVOLVE` button when `parentIsSelected && this.modalCanEvolve && this.modalPokemonIdTarget.value`. Button: `gb-btn-primary gb-btn-sm`, inline styles for size/spacing per brief, `data-action="click->pixeldex#evolvePokemon"`, species in `dataset.targetSpecies`, "EVOLVE" via `textContent`. Recursive calls pass `node.isSelected` as `parentIsSelected` for both linear and branching child traversal.
  - **Lines 357–383** — New `async evolvePokemon(event)` method. Mirrors `savePokemon`'s fetch shape: same URL pattern (`${this.pokemonUpdateUrlValue}/${pokemonId}`), same headers (Content-Type + X-CSRF-Token), PATCH with `{ species: targetSpecies }`. Same error handling pattern (modalStatusTarget shows server error or fallback string; NETWORK ERROR on throw; reload on success).

## Tests

Full suite: **184 runs, 0 failures, 0 errors, 0 skips.**

Run via `PATH=/Users/gferm/.local/share/mise/installs/ruby/3.4.5/bin:$PATH bundle exec rails test` (mise/zsh PATH had Ruby 3.0.6 ahead of the mise shim — explicit override needed; gemfile.lock pins Ruby 3.4.5 per `mise.toml`).

No new tests added — brief explicitly stated none required, existing `PokemonControllerTest` already covers `species` PATCH.

## Notes for Reviewer

Things to scrutinize:

1. **Dead-pokemon gate placement.** The brief said "if the gate doesn't exist as a clean reusable check, gate on group status === 'caught' only." There was no reusable function — the existing dead check is an inline `if (status === "dead")` in `#openModal`. I introduced `this.modalCanEvolve` as a shared instance flag set in `#openModal`, then read inside `#renderEvoNode`. This is a small new pattern, not a refactor of the existing dead-btn gate. Clean enough I think, but flagging in case you'd prefer threading it through `#populateEvolution` as an explicit arg instead. Also note: `#populateEvolution` is also called from `searchSpecies` (line 282) when the user types into the species input — that path doesn't reset `modalCanEvolve`, so it correctly inherits the value set by the most recent `#openModal`. That's the desired behavior (same modal session, same eligibility), but worth confirming you agree.

2. **Argument-order precedent on `parentIsSelected`.** I added it as the 5th positional arg with default `false` per the brief. Default keeps backward-compat at the call site in `#populateEvolution`, though I did update that call too to be explicit. The internal recursive calls pass `node.isSelected` (the parent of the next recursion level). This means the button shows on direct children of the *currently-selected species node* in the tree, not direct children of the modal pokemon's species per se — those are the same thing because the tree marks the modal's current species with `isSelected`.

3. **Status string vocabulary.** I used `"EVOLVING..."` and `"EVOLVE FAILED"` as the modal status text. Brief said "mirror `savePokemon` line ~310 error handling" but didn't dictate the exact string. Easy to change if Richard prefers `"SAVING..."`/`"SAVE FAILED"` for consistency, or wants something else.

4. **Button text uses `textContent`.** "EVOLVE" is a hardcoded literal so this is moot, but I followed the architecture rule on the species name (which IS user-supplied / dynamic) by using `dataset.targetSpecies` and never touching innerHTML.

5. **Out-of-scope items per brief** (logged in BUILD-LOG Known Gaps territory but brief already acknowledges them):
   - Partner co-evolution
   - Real-time broadcast to other players
   - Level/method gating on the button
   - Loading state on the button itself (status target only)

   Not adding these to Known Gaps unless Ava/Richard wants me to formally log them — brief already documents them as deliberate scope decisions for this step.

6. **No view changes.** The EVOLVE button is appended into `modalEvoTextTarget` by the renderer; the existing modal markup needs no edits. Verified `gb-btn-primary` + `gb-btn-sm` classes exist by their use elsewhere in the codebase / brief reference.

Manual browser verification deferred to Project Owner per brief — I can't drive a browser.
