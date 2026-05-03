# Session Checkpoint
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*
*Session-scoped — archived to `handoff/archive/` at session end.*

---

## Where We Stopped

Step 16 (Non-decryption SRAM expansion: TID/SID + Pokédex caught/seen + Hall of Fame detection) shipped + FF-merged to `main` (`eff673b`). Awaiting next brief from Project Owner.

---

## What Was Built

**Step 16 — Non-decryption SRAM expansion on top of Step 15 SaveDiff infra. KG-14 closed.**

Bundles three highest-ROI SRAM additions that don't pay PKM-decryption cost, all riding the Step-15 `SoulLink::SaveDiff` pure-diff layer:
1. **TID/SID surfacing** — save-mix-up detection via cross-player `(parsed_trainer_id, parsed_secret_id)` comparison.
2. **Pokédex caught/seen counter** — closes KG-14 via primary-source citations from PKHeX `SAV4Pt.cs`/`Zukan4.cs` and pret/pokeplatinum `include/pokedex.h`.
3. **Hall of Fame detection** — auto run-completion when all 4 sessions report `parsed_hof_count >= 1`. Block layout cited from PKHeX `SAV4Pt.cs` ExtraBlocks + `Dendou4.cs` and pret/pokeplatinum `save_table.h`.

**Surfaces introduced:**
- `SoulLink::SaveDiffDispatcher` — new fan-out service. `dispatch(slot, prev:, curr:)` owns the baseline rule (skip on first-ever parse) + empty-diff short-circuit + 4-way coordinator fan-out. `ParseSaveDataJob` becomes a "pure parser + persist" job calling the dispatcher with two state-snapshot Hashes.
- `SoulLink::TidObservationCoordinator` and `SoulLink::PokedexProgressCoordinator` — log-only (mirrors `GymBeatenCoordinator`'s `BadgeLost` no-op shape; user-visible value comes from parser-persisted columns + view reads).
- `SoulLink::HallOfFameCoordinator` — side-effect coordinator. All-4 AND-gate (mirrors `GymBeatenCoordinator.all_players_have_badge?`); on pass, sets `run.completed_at = Time.current`. Triple guard: events.empty? / run nil-or-inactive-or-completed / all-4 fail.
- `SaveDiff::Result` extended with `tid_events:`, `pokedex_events:`, `hof_events:` keyword fields (default `[]`); 3 new event structs (`TidObserved`, `PokedexProgress`, `HallOfFameEntered`); 10 new keyword args on `SaveDiff.between(...)` (all default `nil`). Step-15-style call signatures continue working unchanged.
- `SaveParser::Result` extended with 5 new fields (`trainer_id`, `secret_id`, `pokedex_caught`, `pokedex_seen`, `hof_count`) + new private helpers (`read_uint16_le`, `count_pokedex_bits`, `safe_hof_count`). Defensive cap: Pokédex count > 493 (`POKEDEX_BIT_LIMIT`) → nil; HoF CRC fail → nil (NEVER 0).
- `SoulLinkRun#completed?` + `#tid_conflict_groups` (returns groups of session-ids sharing `[trainer_id, secret_id]` pair, excludes nil/zero TID).
- `broadcasts_refreshes_to ->(record) { [ record, :dashboard ] }` on `SoulLinkRun` — mirrors Step 15 `GymResult` pattern. The "🏆 COMPLETE" pill on the dashboard runs panel surfaces in real time when `HallOfFameCoordinator` updates `completed_at`.
- View additions: TID/SID + Pokédex + HoF pill on `_run_sidebar_card`; same minus conflict pill on `_save_slots_sidebar`; "🏆 COMPLETE" pill + "COMPLETED" timestamp tile on `_runs_content`.

**Counts:** 400 → 461 tests (+61). Rubocop clean (159 → 169 files, 0 offenses). 2 migrations.

**Review:** 0 Must Fix, 1 Should Fix (cosmetic block-param rename `_sid` → `_session_id` in `tid_conflict_groups` — applied inline post-review).

---

## What Was Decided This Session

- **Dispatcher extraction.** `ParseSaveDataJob` becomes "pure parser + persist". Diff + dispatch lives in `SoulLink::SaveDiffDispatcher`. Per-category branching consolidates into one place — opens the door for Step 17/18 categories (PKM-decryption-gated catches + battle teams) without rewriting the job again.
- **Three-coordinator symmetry.** TID and Pokédex coordinators are log-only (the value lives in parser-persisted columns + view reads). Coordinators exist for symmetric pattern adherence + traceability. HoF is the side-effect coordinator.
- **TID-mix-up is read-side.** `SoulLinkRun#tid_conflict_groups` runs at view time on the broadcast partial. Pair key is `[tid, sid]` — same TID with different SIDs is NOT flagged.
- **No auto-deactivation of completed runs.** PO follow-on. `active` flag stays as-is on completion. Logged as KG-16.
- **HoF block CRC.** Same CRC16-CCITT-FALSE variant as the general block (verified against PKHeX `Dendou4.cs`); reused the existing `crc16_ccitt` helper. Both partition mirrors read; higher CRC-valid `ClearCount` wins. Both corrupt → nil.
- **HoF count semantics: `>= 1` boolean gate.** PKHeX's `ClearCount` field is the # of HoF entries recorded. Our run-completion logic only cares whether the player has entered at least once — the `>= 1` check makes this clear.
- **Pokédex defensive cap at 493 (Sinnoh national dex max).** Belt-and-suspenders for offset misalignment — popcount > 493 returns nil, mirroring `safe_map_id`'s graceful degradation pattern.
- **`SoulLinkRun.broadcasts_refreshes_to` pattern.** Verified absent before Step 16; mirrors Step 15 GymResult pattern. Dashboard `show.html.erb` already had `<%= turbo_stream_from @run, :dashboard %>` to receive it.
- **Migration column types: plain `:integer`** (4-byte signed) — NOT `limit: 2` (smallint risks overflow on uint16 upper half). uint16 max 65535 fits cleanly in default `:integer`.

---

## Known Gaps / Future Work

*See `handoff/BUILD-LOG.md` Known Gaps — running list maintained there.*

Step 16 closed KG-14 (Pokédex caught/seen offsets validated against PKHeX + pret primary sources). Logged four new gaps:
- **KG-16:** Auto-deactivation of completed runs deferred — PO call. `active` flag stays as-is when `completed_at` is set; user owns deactivation via existing END RUN button.
- **KG-17:** Discord notification on HoF deferred — could be a 1-liner inside `HallOfFameCoordinator`. PO call.
- **KG-18:** TID conflict resolution flow — pill is informational only. No UI to resolve.
- **KG-19:** HoF "uncomplete" path — direct AR edit (`run.update!(completed_at: nil)`) only. No UI.

KG-7 (real-save offset verification for `MAP_ID_OFFSET`) still open from Step 12. KG-15 (item bag / HM offsets) still open from Step 15 audit.

In-browser smoke deferred this step (parse-job + service + view code, all server-side broadcast-driven). The `broadcasts_refreshes_to` wiring on `SoulLinkRun` mirrors the Step 15 GymResult pattern; no dedicated test (matches the same pattern-parity acceptance from Step 15).

---

## Resume Prompt

Copy and paste this to resume:

---

You are Ava (Architect) on Soul Link — Three Man Team.
Read handoff/SESSION-CHECKPOINT.md, then handoff/BUILD-LOG.md.
Confirm status and next action. Then wait for direction.

---
