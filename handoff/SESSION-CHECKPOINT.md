# Session Checkpoint — 2026-04-26
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*
*Session-scoped — archived to `handoff/archive/` at session end.*

---

## Where We Stopped

Steps 1 and 2 of the in-browser DS emulator feature are complete and committed. Data layer + service/job for ROM randomization both done. 131 full-suite tests passing. Active step is Step 3 — EmulatorJS asset rake task.

JRE 21 installed on the Vultr VPS. Pending: 40 Ubuntu updates + system restart (separate maintenance window).

---

## What Was Built

### Step 1 — SoulLinkEmulatorSession Migration + Model (`574fa7f`)
- Migration with bigint `discord_user_id` (nullable until claimed), MEDIUMBLOB `save_data`
- Model with `claim!`, `ready?`, `claimed?`, `rom_full_path`, scopes, `AlreadyClaimedError`
- 16 model tests using FactoryBot factories
- Patches: column type bigint (not string), FactoryBot adoption

### Step 2 — RomRandomizer Service + GenerateRunRomsJob (`71f1dcf`)
- `SoulLink::RomRandomizer` — sync service wrapping JAR via `Open3.capture3`, defensive Java/ROM/JAR/settings checks, 30s timeout
- `SoulLink::GenerateRunRomsJob` — creates 4 sessions transactionally, runs randomizer 4× sequentially, idempotent on count
- 15 new tests (10 service + 5 job), all hermetic
- `.gitignore` excludes ROM/JAR binaries; `.keep` files placed for `storage/roms/base`, `storage/roms/randomized`, `lib/randomizer`

---

## What Was Decided This Session

- Plan locked: 7-step in-browser emulator feature (single-player only; multiplayer dropped to Known Gaps)
- ROM lifecycle: 4 ROMs generated per run (eager batch on run-start), claim-on-load by player, auto-assign first unclaimed
- ROM generation moves to ActiveJob (`:async` adapter, no SolidQueue worker)
- "Generate Emulator ROMs" button on runs page next to existing "Create Discord Channels" — Step 4
- Discord IDs: `bigint` in DB, `String` in Stimulus, coerced at controller boundary
- New tests use FactoryBot; legacy tests stay on fixtures; do not bulk-convert
- `error_message` truncated at 255 (column width, not 500)
- Service returns `false` on handled failure; never raises in normal paths
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
