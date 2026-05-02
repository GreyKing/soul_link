# Session Checkpoint
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*
*Session-scoped — archived to `handoff/archive/` at session end.*

---

## Where We Stopped

Step 15 (SaveDiff infrastructure + Category 1 gyms-beaten auto-detection + KG-13 fix) shipped + pushed to `main`. Awaiting next brief from Project Owner.

---

## What Was Built

**Step 15 — SaveDiff Infrastructure + Category 1 (Gyms-Beaten Auto-Detection) + KG-13 fix.**

Per the SRAM auto-tracking audit (`handoff/2026-05-02-sram-auto-tracking-audit.md`, on main as `b8a769e`), and the Project Owner's option-(b) decision (gym auto-marks beaten only when all 4 players' active save slots show that badge, with manual MARK BEATEN bypass and manual UNMARK creating per-gym suppression).

**Surfaces introduced:**
- `SoulLink::SaveDiff` — pure function diff layer (`app/services/soul_link/save_diff.rb`). Takes two `parsed_badges` snapshots, returns a `Result` of `BadgeGained` / `BadgeLost` events. No AR, no logger, no `Time.current`. Extension point for categories 2/3 (add `catch_events:` / `evolution_events:` keyword fields without rewriting consumers).
- `SoulLink::GymBeatenCoordinator` — static-method service (`app/services/soul_link/gym_beaten_coordinator.rb`) wrapping the all-4 AND-gate. Three guards in priority order: gym already marked → suppression exists → all-4 satisfy. Auto-mark wraps `gym_results.create!` + `gyms_defeated` update in a `run.transaction { }`.
- `GymAutoMarkSuppression` model + table — per-`(run, gym_number)` unique row. Created on UNMARK in `GymProgressController#update`; cleared by both `GymProgressController#update` mark branch AND `GymDraftsController#mark_beaten`.
- `ParseSaveDataJob` rewired: captures `prev_parsed_at` + `prev_badges` BEFORE update_columns, dispatches `SaveDiff` + `GymBeatenCoordinator` only if `prev_parsed_at.present?` (baseline rule).
- `GymResult.broadcasts_refreshes_to ->(record) { [record.soul_link_run, :dashboard] }` — auto-mark surfaces in real-time on open dashboards via the same Step-9 KG-2 pattern.
- KG-13 fix: parse-failure path went from 7 lines (zeroing every parsed_*) to 1 line (`update_columns(parsed_at: Time.current)` + `return`). Eliminates spurious BadgeLost events from CRC-failed saves.

**Counts:** 370 → 397 tests (+27). Rubocop clean (152 → 159 files, 0 offenses). 1 migration.

**Review:** 0 Must Fix, 3 Should Fix. Two resolved inline post-review (transaction-rollback test stubbed wrong exception; missing retry-idempotency regression). Third (BadgeLost log-level not asserted in tests) accepted as-is per Richard's recommendation — code inspection covers focus area #10.

---

## What Was Decided This Session

- **Option (b) AND-gate.** Gym auto-marks only when all 4 players' active slots show `parsed_badges >= gym_number`. While 1-3 players have it, gym stays in current state — no UI flicker.
- **Manual MARK BEATEN bypasses the AND-gate** (different controller action, never hits the coordinator).
- **Manual UNMARK creates a suppression record** persisting until next manual MARK BEATEN clears it.
- **Down events (`BadgeLost`) are no-ops** — coordinator logs at `info` level, no auto-unmark. PO will design un-detection later if needed.
- **Multi-bit jumps process sequentially.** `0→2 badges` produces two `BadgeGained` events; each runs the all-4 check independently.
- **`SaveDiff` is genuinely pure** (no AR / logger / clock). Coordinator does the side effects. Pattern mirrors `SoulLink::SaveParser`.
- **`parsed_badges` count semantics, not raw bits.** No `parsed_badge_bits` column. `parsed_badges >= N` is equivalent to "has badge N" in legitimate Platinum play (in-game bitfield is monotonically progressive).
- **Baseline rule:** diff dispatch is gated on `slot.parsed_at` being non-nil BEFORE the current parse runs. First-ever successful parse is silent (importing a save with N badges doesn't spam N events).
- **KG-13 fix shape:** failure branch only updates `parsed_at`. Doesn't touch any other `parsed_*`. Branches on `result.nil?` (parser's contract), not on hash-value inspection.
- **Suppression as a separate table** (not a JSON column, not a flag on `gym_results`). Clean relational model, unique index, `find_or_create_by!` against the index for double-click idempotency.
- **Categories 2 (gym battle teams) and 3 (catches+routes) explicitly deferred** to a future step. They both need Gen-IV PKM decryption (PID-shuffle + LCG XOR), which is its own design phase. Audit logged KG-11 (party block offset verification) and KG-12 (met-location → route name table) as the prerequisites for that future step.

---

## Known Gaps / Future Work

*See `handoff/BUILD-LOG.md` Known Gaps — running list maintained there.*

Step 15 closed KG-13 (parse-failure zeros parsed_badges). Logged two new gaps from the audit: KG-11 (Gen-IV party block offset within the SRAM slot not yet pinned to a credible source — projectpokemon's Platinum doc has 0xA0 but is "under construction"; need pret/pokeplatinum `SaveData` cross-reference) and KG-12 (Platinum met-location ID → route-name table not yet sourced; different enum from `maps.yml`'s map-header IDs). Both are design-phase prerequisites for the future categories-2/3 step.

KG-7 (real-save offset verification for `MAP_ID_OFFSET`) still open from Step 12.

In-browser smoke deferred this step (parse-job + service code, no new UI). The `broadcasts_refreshes_to` wiring on `GymResult` mirrors the Step 9 KG-2 pattern; no dedicated test (matches KG-2's missing test, accepted by Richard as pattern-parity).

---

## Resume Prompt

Copy and paste this to resume:

---

You are Ava (Architect) on Soul Link — Three Man Team.
Read handoff/SESSION-CHECKPOINT.md, then handoff/BUILD-LOG.md.
Confirm status and next action. Then wait for direction.

---
