# Build Log
*Owned by Architect. Updated by Builder after each step.*

`Current Status` and `Step History` are session-scoped — archived to
`handoff/archive/` at session end and reset.
`Known Gaps` and `Architecture Decisions` are durable — they survive session
reset until the gap is addressed or the decision is replaced.

---

## Current Status
*Session-scoped.*

**Active step:** Step 3 — EmulatorJS asset rake task
**Last committed:** `71f1dcf` — 2026-04-26 (Step 2)
**Pending deploy:** NO

---

## Step History
*Session-scoped.*

### Step 2 — `SoulLink::RomRandomizer` Service + `GenerateRunRomsJob` — 2026-04-26
**Status:** Complete, committed `71f1dcf`

**Files created:**
- `app/services/soul_link/rom_randomizer.rb`
- `app/jobs/soul_link/generate_run_roms_job.rb`
- `test/services/soul_link/rom_randomizer_test.rb`
- `test/jobs/soul_link/generate_run_roms_job_test.rb`
- `storage/roms/base/.keep`, `storage/roms/randomized/.keep`, `lib/randomizer/.keep`

**Files modified:**
- `.gitignore` — exclude ROM/JAR binaries, keep `.keep` files trackable

**Key decisions:**
- `error_message` truncated at 255 chars (matches column width — Architect ruling overriding original 500-char brief)
- Service is sync, returns `false` on handled failure (no raise), mutates session
- `rom_path` stored relative to Rails.root
- Job is idempotent on session count (4 sessions exist → no-op)
- Defensive Java check on every `call` (not memoized — server state can change)
- ROM CLI flags: `-i / -o / -s / -seed` per the original plan; verified by the brief

**Tests:** 15 new (10 service + 5 job), 131/131 full suite, all hermetic — no real Java or filesystem writes.

**Review:** Richard — PASS_WITH_OBSERVATIONS (3 non-blocking; concurrent-enqueue race captured as Known Gap below).

---

### Step 1 — `SoulLinkEmulatorSession` Migration + Model — 2026-04-26
**Status:** Complete, committed `574fa7f`

**Files created:**
- `db/migrate/20260426233223_create_soul_link_emulator_sessions.rb`
- `app/models/soul_link_emulator_session.rb`
- `test/factories/soul_link_runs.rb`
- `test/factories/soul_link_emulator_sessions.rb`
- `test/models/soul_link_emulator_session_test.rb`

**Files modified:**
- `db/schema.rb` (auto-regen)
- `Gemfile` + `Gemfile.lock` — added `factory_bot_rails`
- `test/test_helper.rb` — `include FactoryBot::Syntax::Methods`
- `CLAUDE.md` — Testing Conventions subsection

**Files deleted:**
- `test/fixtures/soul_link_emulator_sessions.yml` (superseded by factories)

**Key decisions:**
- `discord_user_id` is `bigint` to match existing tables (Patch 1 corrected the original brief which had `string`)
- FactoryBot adopted for new test code only; legacy 116 tests stay on fixtures (Patch 2)
- `claim!` is SQL-atomic via `update_all` with `WHERE discord_user_id IS NULL` guard — Ruby-level pre-checks would race

**Tests:** 16 new tests, 62 assertions; full suite 116 runs, 311 assertions, 0 failures.

**Review:** Richard — PASS (no must-fix, no escalations after patches).

---

## Known Gaps
*Durable. Items logged here instead of expanding the current step. Persists across sessions until addressed.*

- No functional/integration tests for API endpoints (`/api/pokemon`, `/api/calculator`)
- No crit stage 2/3 test coverage
- No crit totals for multi-hit moves (per-hit crit only)
- Stat summary in full calc shows raw integers without stat-name/nature label (e.g., shows `148`, brief specified `200 Atk (Adamant)`)
- No abilities/items/weather modifiers in calculator
- No HP calculation or percentage damage display
- 5-entry cap on evolution chain depth (fine for Gen IV)
- Convert legacy fixture-based tests to FactoryBot (deferred — do not bundle into feature work)
- Concurrent enqueue of `GenerateRunRomsJob` could create duplicate sessions if button isn't disabled — Step 4 will add button-disable + DB-level guard if needed
- `error_message` column is varchar(255) — widen if real-world stack traces prove limiting
- Service-test stubbing duplicates `Open3.capture3` mocks across cases — refactor into a helper if a third randomizer test ever exists
- Step 2's randomizer service was synchronous-by-design; replace with background-job orchestration if generation moves off the request path
- ROM versioning when randomizer settings change mid-run
- Co-op multiplayer watch page for emulator (Option A from plan review — status grid via ActionCable)
- EmulatorJS save endpoint may need server-side debounce if save cadence is high

---

## Architecture Decisions
*Durable. Locked decisions that cannot be changed without breaking the system. Persists across sessions.*

- Discord user IDs stored as String in all Stimulus value types — 2026-04-12
- User-supplied text always rendered via textContent, never innerHTML — 2026-04-12
- evolves_to is array format `[{species, level/method}]` — 2026-04-12
- Gen IV crit multiplier is 2x — 2026-04-12
- `Api::BaseController` is the base class for all JSON API controllers — 2026-04-12
- Server-side sprite URLs via `asset_path` in API responses — 2026-04-12
- Discord user IDs are `bigint` in DB columns, `String` in Stimulus values, coerced at the controller boundary — 2026-04-26
- New tests use FactoryBot factories from `test/factories/`; legacy tests stay on fixtures from `test/fixtures/`; do not convert legacy without an explicit step — 2026-04-26
