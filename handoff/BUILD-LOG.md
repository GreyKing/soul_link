# Build Log
*Owned by Architect. Updated by Builder after each step.*

`Current Status` and `Step History` are session-scoped — archived to
`handoff/archive/` at session end and reset.
`Known Gaps` and `Architecture Decisions` are durable — they survive session
reset until the gap is addressed or the decision is replaced.

---

## Current Status
*Session-scoped.*

**Active step:** Step 3 — Emulator Hardening, awaiting Reviewer.
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

### Step 3 — Emulator Hardening — 2026-04-26
**Status:** Built; awaiting Reviewer (REVIEW-REQUEST.md ready).

**Files modified:**
- `app/channels/application_cable/connection.rb` — expose `session` via `attr_reader` for channel guild authz
- `app/channels/run_channel.rb` — guild authz on subscribe; `with_lock` on generate + regenerate enqueue paths
- `app/models/soul_link_emulator_session.rb` — `GzipCoder` module + `serialize :save_data, coder: GzipCoder`; widen `delete_rom_file` rescue from `Errno::ENOENT` → `StandardError`
- `app/controllers/emulator_controller.rb` — `MAX_SAVE_DATA_BYTES = 2.megabytes` size cap (pre-read content_length + post-read bytesize, both → 413); safety comment on `rom`'s `send_file`
- `app/services/soul_link/rom_randomizer.rb` — replace `Open3.capture3 + Timeout.timeout` with `Process.spawn` + `waitpid(WNOHANG)` poll loop + TERM→KILL escalation; `fail!` survives save failure (uses `save` not `save!`, logs on failure); centralize 255-char truncation in `truncate_error`
- 5 test files updated/added (16 new tests, 0 removed)
- `test/lib/tasks/emulator_cleanup_test.rb` — sweep 6 `warn "EMPTY-DIR DEBUG: ..."` lines

**Key decisions:**
- `with_lock` race test uses the brief's authorized fallback (assert `with_lock` was called + behavioral sequential test) rather than thread-based test — ConnectionStub doesn't simulate concurrent subscribes and MySQL row locks on the test DB can deadlock under spurious load
- `stub_connection_with_session` helper added because ActionCable's `ConnectionStub` only stubs `identified_by` attrs, no session — single-line setup change for all existing tests
- Run subprocess seam moved from `Open3.capture3` to `RomRandomizer#run_subprocess`; tests migrated to stub the new seam, dedicated TERM-on-timeout test exercises the real `Process.spawn` path through stubbed primitives
- `GzipCoder.load` falls through plaintext bytes lacking the magic header — defensive only, can be removed once production rows are confirmed gzipped
- Empty save_data short-circuits in `dump` (stores empty bytes, not gzip-of-empty) so GET 204 contract holds
- Used `:content_too_large` instead of deprecated `:payload_too_large` (Rails 8.1)

**Compression measured:**
- 512KB pure zero-padded SRAM → 543 bytes (0.1%)
- 512KB realistic 80%-zero SRAM → 116KB (22%)
- 512KB pure random (worst case) → 525KB (gzip framing overhead)

**Tests:** 216/216 full suite (200 baseline + 16 new), 0 failures across 3 consecutive runs.

**Review:** *Pending Reviewer.*

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
