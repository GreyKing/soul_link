# Build Log
*Owned by Architect. Updated by Builder after each step.*

`Current Status` and `Step History` are session-scoped — archived to
`handoff/archive/` at session end and reset.
`Known Gaps` and `Architecture Decisions` are durable — they survive session
reset until the gap is addressed or the decision is replaced.

---

## Current Status
*Session-scoped.*

**Active step:** *None — Step 1 shipped, awaiting next brief.*
**Last committed:** `a708443` — 2026-04-28 (Step 1)
**Pending deploy:** NO

---

## Step History
*Session-scoped.*

### Step 1 — Evolve Button on Pokemon Modal — 2026-04-27
**Status:** Complete, committed `a708443`

**Files modified:**
- `app/javascript/controllers/pixeldex_controller.js` — added `modalCanEvolve` flag in `#openModal`, threaded `parentIsSelected` through `#renderEvoNode`, new `evolvePokemon` action mirroring `savePokemon`'s fetch shape

**Key decisions:**
- Per-player scope only — partner co-evolution explicitly out (matches existing per-player precedent for catch/death/team operations)
- Reused existing `PATCH /pokemon/:id` endpoint; no backend changes, no migration, no new routes
- Dead-pokemon gate via shared `modalCanEvolve` instance flag (architect-approved alternative to threading status through `#populateEvolution`); set in `#openModal` before evolution renders, inherited by `searchSpecies` mid-edit re-renders
- Button shows on direct children of the currently-selected species node; species name passed via `dataset.targetSpecies` (textContent rule preserved)
- Status vocabulary: `EVOLVING...` / `EVOLVE FAILED` (action-specific, parallel to `savePokemon`)

**Tests:** 184/184 full suite, 0 failures. No new tests added (per brief — existing `PokemonControllerTest` covers species PATCH).

**Review:** Richard — PASS (no Must Fix, no Should Fix, no Escalate).

**Smoke test:** Bob couldn't drive a browser. Project Owner to verify locally — open dashboard, click a pokemon cell with an existing pokemon, confirm EVOLVE buttons appear next to direct evolution targets, click one, confirm species updates after reload.

---

## Known Gaps
*Durable. Items logged here instead of expanding the current step. Persists across sessions until addressed.*

- Co-evolution of soul-link partners on evolution (deliberate per-step-1; revisit if Project Owner wants paired evolution)
- No real-time broadcast of species change to other players' dashboards (they see updates on next refresh)
- No level/method gating on EVOLVE button (always available; player owns in-game timing)
- No loading state on EVOLVE button itself (status text only)

---

## Architecture Decisions
*Durable. Locked decisions that cannot be changed without breaking the system. Persists across sessions.*

*None.*
