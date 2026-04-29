# Build Log
*Owned by Architect. Updated by Builder after each step.*

`Current Status` and `Step History` are session-scoped — archived to
`handoff/archive/` at session end and reset.
`Known Gaps` and `Architecture Decisions` are durable — they survive session
reset until the gap is addressed or the decision is replaced.

---

## Current Status
*Session-scoped.*

**Active step:** Step 1 — SRAM Phase 1: Trainer Block Parsing — **AWAITING REVIEW**
**Last committed:** `09b3a7e` — 2026-04-29 (sidebar grid layout fix, inline)
**Pending deploy:** NO

**Parked plan:** FactoryBot conversion. Inventory + ordering at `handoff/parked-plans/factorybot-conversion.md`. Resume after SRAM Phase 1 ships.

---

## Step History
*Session-scoped.*

### Step 1 — SRAM Phase 1: Trainer Block Parsing (Builder, 2026-04-29)
- Migration `20260429215107_add_parsed_save_fields_to_soul_link_emulator_sessions.rb` (6 cols).
- Service `SoulLink::SaveParser` — slot selection via CRC16-CCITT, Gen IV English char decode, returns nil on any error.
- Job `SoulLink::ParseSaveDataJob` — `update_columns` writes (no callback recurse), parsed_at on both branches.
- Model: `after_update_commit :enqueue_parse_if_save_changed`.
- Helper: `EmulatorHelper#format_play_time`.
- View: 4 new gated lines in `_run_sidebar.html.erb`.
- Tests: 34 new (18 parser + 8 job + 6 callback + 3 controller). 221 → 255, 0 failures, 4 clean parallel runs.
- **Open question for Architect**: real-save offset verification did not happen this session. Map-id specifically unverified.

---

## Known Gaps
*Durable. Items logged here instead of expanding the current step. Persists across sessions until addressed.*

### From earlier work (Evolve Button feature)
- Co-evolution of soul-link partners on evolution (deliberate; revisit if Project Owner wants paired evolution)
- No real-time broadcast of species change to other players' dashboards (they see updates on next refresh)
- No level/method gating on EVOLVE button (always available; player owns in-game timing)
- No loading state on EVOLVE button itself (status text only)

### From the emulator deploy + polish session (2026-04-29)
- **Tier 2 SRAM parsing** for in-game info (character name, time-played, money, party count, current map, badges earned) — separate feature, real engineering effort (Gen IV character set decoder + checksum/slot logic)
- **No automated browser test harness** — smoke tests are manual; Project Owner verifies UI changes
- **`#d4b14a` amber color** for pending-state status badge is inline in `_run_sidebar.html.erb`. If used in a third place, promote to a `--amber` palette token in `pixeldex.css`.
- **Randomizer settings file** (`random_basic_1.rnqs`) is small/basic — heavier randomization (abilities, types-per-move, evolutions) requires re-export from the GUI and re-scp
- **Destructive regenerate** wipes save_data for ready/claimed sessions when status is `:failed`. Acceptable v1 tradeoff; future iteration could selectively preserve `:ready` sessions.
- **`error_message` column at varchar(255)** — widen to text only if real-world stack traces prove limiting
- **Convert legacy fixture-based tests to FactoryBot** — deferred; do not bundle into feature work
- **No real-time updates on the run roster sidebar** — page-load refresh only. Could broadcast on save_data PATCH if live "X just saved" UX is wanted.
- **Channel-layer guild authz cached at login** — if user joins a new guild mid-session without re-logging-in, they won't see it. Acceptable for current use.

---

## Architecture Decisions
*Durable. Locked decisions that cannot be changed without breaking the system. Persists across sessions.*

### Emulator infrastructure (locked 2026-04-29)
- **PokeRandoZX must be invoked with `cli` as the first arg after `-jar`.** CLI mode auto-seeds; do NOT pass `-seed`. Without the `cli` subcommand, the JAR launches a Swing GUI which fails on headless servers with `HeadlessException` but exits 0 — silent generation failure.
- **`save_data` column is gzip-compressed** via `SoulLinkEmulatorSession::GzipCoder` (custom serializer). Reads/writes are transparent. Use `read_attribute_before_type_cast("save_data")` for raw compressed bytes (e.g. for size display); regular `save_data` accessor triggers decompression.
- **Inbound PATCH `save_data` is capped at 2MB raw** (`EmulatorController::MAX_SAVE_DATA_BYTES`). Pokemon Platinum SRAM is ~512KB; cap is a generous DoS bound enforced via `request.content_length` check + post-read `bytesize` check.
- **`RunChannel#subscribed`** rejects when `params[:guild_id]` doesn't match `connection.session[:guild_id]`. Single check, applies to every channel action.
- **`RunChannel#generate_emulator_roms` and `#regenerate_emulator_roms`** wrap their idempotency check + enqueue in `run.with_lock` — prevents the channel-layer race where two concurrent clicks both pass `:none` and both enqueue.
- **Subprocess pattern: `Process.spawn` + `waitpid(WNOHANG)` poll loop + TERM→KILL on deadline.** `Open3.capture3 + Timeout.timeout` is banned (raises in calling thread but leaves child Java running — zombie leak).
- **`emulator_session.rom_path` is server-derived** — only ever set by `RomRandomizer` via `Pathname#relative_path_from(Rails.root)` of a path constructed under `OUTPUT_DIR`. Never user input. If a future writer changes this, `EmulatorController#rom`'s `send_file` becomes a file-read-anywhere primitive and needs an explicit `path.start_with?(OUTPUT_DIR)` guard.

### Carried over (still load-bearing)
- Discord user IDs are `bigint` in DB columns, `String` in Stimulus values, coerced at the controller boundary
- New tests use FactoryBot factories from `test/factories/`; legacy tests stay on fixtures from `test/fixtures/`; do not convert legacy without an explicit step
