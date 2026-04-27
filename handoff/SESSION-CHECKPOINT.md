# Session Checkpoint — 2026-04-26
*Read this before reading anything else. If it covers current state, skip BUILD-LOG.*
*Session-scoped — archived to `handoff/archive/` at session end.*

---

## Where We Stopped

Steps 1, 2, 3 of the in-browser DS emulator feature are complete and committed. Data layer + service/job for ROM randomization + EmulatorJS asset rake task all done. 131 full-suite tests passing. Active step is Step 4 — Run-creator ROM-generation trigger.

**Plan refinement** (discovered while scoping Step 4): the existing "Setup Discord" button on the runs page uses `RunChannel` ActionCable, not HTTP. New "Generate Emulator ROMs" button will follow the same pattern. Original locked Step 4 (routes + controller + button) is split: Step 4 = trigger only (channel + button), Step 5 = player consumer (routes + controller + view + Stimulus). Total step count unchanged (still 7).

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

### Step 3 — EmulatorJS Asset Rake Task (`9ce4114`)
- `lib/tasks/emulatorjs.rake` — `emulatorjs:install` + `emulatorjs:clean`, stdlib only, manual redirect handling, idempotent
- Verified install: v4.2.3 from upstream, `data/loader.js` lands at expected path
- `.gitignore` excludes `/public/emulatorjs/`

### Step 4 — Run-Creator ROM-Generation Trigger (`f8d1662`)
- ActionCable trigger only — no HTTP route, mirrors existing `setup_discord` pattern
- `SoulLinkRun#emulator_status` (`:none` / `:generating` / `:ready` / `:failed`) included in broadcasts
- `RunChannel#generate_emulator_roms` enqueues `GenerateRunRomsJob`; idempotent at channel + worker layers
- Job broadcasts run state in `ensure` block so UI reconciles after completion
- Stimulus toggle uses string literals (`"none"`, `"failed"`) — symbols become strings over the wire
- "Generate Emulator ROMs" button on runs page next to "Setup Discord"
- 15 new tests, 146/146 full suite

### Step 5 — Player-Facing Emulator (`a2699a7`)
- `EmulatorController` with auto-claim race-retry, CSRF bypass scoped to PATCH save_data
- 6-state view: no-run / no-roms / all-claimed / generating / failed / ready
- Stimulus controller bridges to EmulatorJS via `EJS_*` globals, save round-trip via PATCH
- `EMULATOR_CORE = "melonds"`; save callback is `EJS_onSaveSave` (SRAM)
- "Play" link added to layout nav
- 23 new tests, 169/169 full suite

### Step 6 — Cheat Config + EmulatorJS Injection (`d38ae04`)
- `config/soul_link/cheats.yml` placeholder; user populates real AR codes manually
- `SoulLink::GameState.cheats` (memoized YAML loader); `SoulLinkEmulatorSession#cheats`
- `EJS_cheats` format verified in EmulatorJS source: `[desc, code]` tuples
- Stimulus filters `enabled: false` entries client-side
- 15 new tests, 184/184 full suite

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
