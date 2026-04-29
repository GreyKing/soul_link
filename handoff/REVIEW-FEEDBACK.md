# Review Feedback — Step 1
*Written by Reviewer. Read by Builder and Architect.*

---

**Date:** 2026-04-27
**Ready for Builder:** YES

## Must Fix

*—*

## Should Fix

*—*

## Escalate to Architect

*—*

## Cleared

Reviewed `app/javascript/controllers/pixeldex_controller.js` end-to-end for Step 1
(Evolve button on Pokemon modal). Spec compliance, security architecture rules, and
the six scrutiny points Bob raised all check out. Full test suite re-run confirms
**184 runs, 0 failures, 0 errors, 0 skips.**

### Verified

- **textContent / no-innerHTML rule (line 541, 545):** Species name flows through
  `evolveBtn.dataset.targetSpecies = node.name` and is read back via
  `event.currentTarget.dataset.targetSpecies` (line 361). The button label "EVOLVE"
  is set via `textContent`. No string interpolation into innerHTML anywhere in the
  evolve path. Architecture rule honored.
- **Per-player only (lines 357–383):** `evolvePokemon` PATCHes
  `${this.pokemonUpdateUrlValue}/${pokemonId}` where `pokemonId` is sourced from
  `modalPokemonIdTarget.value`. That target is populated at line 257 from
  `myPokemon.id`, where `myPokemon = pokemonData.find(p => p.is_mine)` (line 220).
  Confirmed: only the current discord user's pokemon row is mutated. Linked
  partners untouched. Brief's per-player precedent preserved.
- **`savePokemon` pattern parity:** Same URL shape, same headers
  (`Content-Type: application/json` + `X-CSRF-Token: this.csrfValue`), same
  non-OK error handling (parse `data.error`, write to `modalStatusTarget`,
  `NETWORK ERROR` fallback in catch), same `window.location.reload()` on success.
- **No backend / no migration / no view changes / no new tests** — confirmed by
  scope of the diff and by green test suite. Existing `PokemonControllerTest`
  already exercises the species PATCH path, as the brief asserted.

### Scrutiny points evaluated (per Bob's REVIEW-REQUEST.md)

1. **`modalCanEvolve` instance flag (lines 246–249).** The brief offered a fallback
   ("gate on group status === 'caught' only") because no reusable check existed.
   Bob chose a slightly stronger gate that also requires `myPokemon.id` to be
   present, set in `#openModal` before `#populateEvolution` runs. The
   `searchSpecies` path correctly inherits the flag for the lifetime of a modal
   session, which matches the desired UX (eligibility is per-modal-open, not
   per-species-search). Acceptable. Threading it through `#populateEvolution` as
   an explicit arg would be marginally cleaner but is not required.
2. **`parentIsSelected` 5th arg (lines 498, 501, 552, 564).** Default `false` keeps
   the public call site benign; recursive calls pass `node.isSelected`, which
   `#buildNode` (line 465) sets only on the modal's current species. Net effect:
   buttons render exclusively on direct children of the currently-selected node
   in the tree — i.e., direct evolution targets — which is exactly what the brief
   asked for. The selected species itself does not get a self-button (root call
   passes `parentIsSelected=false`). Final-form species and species with no
   evolution data render no buttons. Branching evolution lines (children > 1)
   correctly thread `node.isSelected` into each branch line.
3. **Status string vocabulary (`EVOLVING...` / `EVOLVE FAILED`).** Action-specific
   strings are at least as clear as `SAVING...`/`SAVE FAILED` for this UI, and
   the brief did not dictate exact text. No change required.
4. **textContent rule on the button.** Verified above — see `Verified` block.
5. **Out-of-scope items** — all match brief's deliberate scope decisions for this
   step. No need to add to BUILD-LOG Known Gaps; brief already documents them.
6. **Test coverage** — re-ran `bundle exec rails test`: 184 runs, 0 failures,
   0 errors, 0 skips. Matches Bob's claim exactly.

### Notes / observations (informational only, NOT blockers)

- Inline styles on the EVOLVE button (`fontSize: "9px"`, `padding: "2px 6px"`,
  `marginLeft: "4px"`) follow the brief's literal markup. Consistent with the
  inline-style pattern already used elsewhere in `#renderEvoNode` (lvl/method
  spans at lines 521–523, 528–530) and in `#populateLinked`. No drift.
- `evolveBtn.dataset.action = "click->pixeldex#evolvePokemon"` is set
  programmatically rather than via `setAttribute("data-action", ...)`. Both
  approaches register Stimulus actions correctly — Stimulus reads from
  `data-action` regardless of how it was placed. No issue.
- `#findParentOf` cap of 5 backward-walk iterations (line 424) is pre-existing
  code, not touched by this step. Out of scope.

Step 1 is clear. Bob is good to move on when Ava sends the next brief.
