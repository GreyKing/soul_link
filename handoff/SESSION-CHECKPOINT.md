# Session Checkpoint — 2026-04-26
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*
*Session-scoped — archived to `handoff/archive/` at session end.*

---

## Where We Stopped

Step 1 of the in-browser DS emulator feature is complete and committed (`574fa7f`). Data layer for `SoulLinkEmulatorSession` is in place. Race-safe `claim!` via SQL guard. 116 full-suite tests passing, 16 new. FactoryBot adopted for new test code (hybrid with legacy fixtures).

Pre-flight done: JRE 21 installed on the Vultr VPS for Step 2's randomizer service.

---

## What Was Built

### Step 1 — SoulLinkEmulatorSession Migration + Model (COMPLETE)
- Migration with bigint `discord_user_id` (nullable until claimed), MEDIUMBLOB `save_data`
- Model with `claim!`, `ready?`, `claimed?`, `rom_full_path`, scopes, validations, `AlreadyClaimedError`
- 16 model tests using FactoryBot factories
- Two patches landed: column type bigint (not string), FactoryBot adoption

---

## What Was Decided This Session

- Plan locked: 7-step in-browser emulator feature (single-player only; multiplayer dropped to Known Gaps)
- ROM lifecycle: 4 ROMs generated per run (eager batch on run-start), claim-on-load by player, auto-assign first unclaimed
- ROM generation moves to ActiveJob (`:async` adapter, no SolidQueue worker)
- "Generate Emulator ROMs" button on runs page next to existing "Create Discord Channels"
- Discord IDs: `bigint` in DB, `String` in Stimulus, coerced at controller boundary
- New tests use FactoryBot; legacy tests stay on fixtures; do not bulk-convert
- Session-end protocol: archive `SESSION-CHECKPOINT.md` + step-scoped `BUILD-LOG.md` sections + REVIEW files; durable BUILD-LOG sections survive

---

## Known Gaps / Future Work

*See `handoff/BUILD-LOG.md` Known Gaps — running list maintained there.*

---

## Resume Prompt

Copy and paste this to resume:

---

You are Ava (Architect) on Soul Link — Three Man Team.
Read handoff/SESSION-CHECKPOINT.md, then handoff/BUILD-LOG.md.
Confirm status and next action. Then wait for direction.

---
