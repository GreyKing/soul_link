# Build Log
*Owned by Architect. Updated by Builder after each step.*

`Current Status` and `Step History` are session-scoped — archived to
`handoff/archive/` at session end and reset.
`Known Gaps` and `Architecture Decisions` are durable — they survive session
reset until the gap is addressed or the decision is replaced.

---

## Current Status
*Session-scoped.*

**Active step:** Step 2 — Auto-Persist In-Game Saves to Server. Awaiting review.
**Last committed:** `62be21e` — 2026-04-29 (Step 1: SRAM Phase 1)
**Pending deploy:** NO

**Parked plan:** FactoryBot conversion. Inventory + ordering at `handoff/parked-plans/factorybot-conversion.md`.

---

## Step History
*Session-scoped.*

### Step 2 — Auto-Persist In-Game Saves to Server — 2026-04-29
**Status:** Awaiting review

**Files modified:**
- `app/javascript/controllers/emulator_controller.js` — re-enabled `_fetchSave()` on `connect()`; added `window.EJS_defaultOptions = { "save-save-interval": "30" }` before loader.js boot; replaced diagnostic `EJS_ready` with: register `saveSaveFiles` listener first, then inject existing save if present, then log `"Emulator: hooks attached"` once with `hasExistingSave`/`hasEmulator` flags; added null/0-byte guard at top of `_uploadSave`; cleared `EJS_defaultOptions` in `disconnect()`. `EJS_onSaveSave` retained (manual export). `_injectExistingSave` body untouched.

**Key decisions:**
- Centralized null/0-byte guard inside `_uploadSave` so both call paths (`EJS_onSaveSave` event payload, `saveSaveFiles` direct bytes) share it. Brief asked for "defensive layering"; placing the guard in the function-under-call makes it impossible to bypass.
- Listener registration ordered BEFORE inject inside `EJS_ready` per the brief's race-condition warning (`gm.loadSaveFiles()` could trigger an auto-save tick between attach points).
- `EJS_defaultOptions` set FIRST in `connect()`, before `EJS_player`/`EJS_gameUrl`/etc. The brief said "before any EJS_* global is set"; obeyed literally to keep the ordering guarantee tight in case loader.js evolves to read globals at any point during script-tag append.

**Tests:** 255/255 pass. No backend change; suite count unchanged from Step 1.

**Lint:** No new Ruby. JS controller has no lint configured (Importmap project, no Node toolchain). Pre-existing rubocop offenses (133 across 127 files) are unrelated; documented previously in Known Gaps.

**Review:** *Pending.*

---

### Step 1 — SRAM Phase 1: Trainer Block Parsing — 2026-04-29
**Status:** Complete, committed `62be21e`

**Files created:**
- `app/services/soul_link/save_parser.rb` — pure parser: slot selection (CRC16-CCITT poly 0x1021, init 0xFFFF, MSB-first), English Gen IV char decode (64 entries, 0xFFFF terminator, 0x0000 skip, U+FFFD fallback), returns nil on any error
- `app/jobs/soul_link/parse_save_data_job.rb` — async parse + `update_columns` write (skips after_update_commit recurse); sets `parsed_at` on both success and failure paths
- `app/helpers/emulator_helper.rb` — `format_play_time` helper
- `db/migrate/20260429215107_*` — 6 new columns on `soul_link_emulator_sessions`

**Files modified:**
- `app/models/soul_link_emulator_session.rb` — `after_update_commit :enqueue_parse_if_save_changed` callback (gated on `saved_change_to_attribute?("save_data")` and non-blank)
- `app/views/emulator/_run_sidebar.html.erb` — 4 new rendered fields gated on column presence; badges line gated on `parsed_trainer_name.present?` (not `parsed_at`) so failed parses don't render "Badges: 0/8"

**Key decisions:**
- Schema columns (Option A) for cached parsing; not on-demand
- English-only char table; Phase 2-5 (party, PC boxes, multi-language, map names) deferred
- Real-save offset verification NOT performed this session — offsets cited from Project Pokemon docs + pret/pokeplatinum + PKHeX (read-only). MAP_ID_OFFSET specifically is a placeholder; `safe_map_id` returns nil on zero so sidebar omits cleanly
- Architect tightened the badges gate from `parsed_at` → `parsed_trainer_name.present?` post-Bob to honor the brief's :failed → "—" contract (parsed_badges defaults to 0, would otherwise render "0/8" on failed parse)

**Tests:** 34 new (18 parser + 7 job + 6 callback + 3 controller); 221 → 255, 0 failures, 4 clean parallel runs.

**Review:** Richard — PASS_WITH_OBSERVATIONS (3 minor: badges gate UX [resolved by Architect inline], off-by-one in Bob's count breakdown [cosmetic], pre-existing rubocop offenses in `delete_rom_file` tests [not introduced by this step]).

**Open Architect rulings (escalated by Richard):**
1. Real-save offset verification still outstanding — Architect ruled "ship as-is" since infra is correct + failure modes honest. Logged as Known Gap below.
2. MAP_ID_OFFSET placeholder — same call.

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

### From SRAM Phase 1 (2026-04-29)
- **Real-save offset verification outstanding.** Trainer-block offsets in `SoulLink::SaveParser` cited from Project Pokemon docs + pret/pokeplatinum + read-only PKHeX. Adjust constants if first real save reveals divergence. `MAP_ID_OFFSET = 0x1234` is the least-confident placeholder; `safe_map_id` returns nil on zero so sidebar omits cleanly. When Project Owner has a real `.sav`, verify all 5 fields decode to known values.
- **Pre-existing rubocop offenses** in `test/models/soul_link_emulator_session_test.rb:220, 258` (4 "Use space inside array brackets" inside `delete_rom_file` tests). Not introduced by SRAM work. Clean with `rubocop -a` in a dedicated cleanup step.
- **Phase 2 deferred:** map_id → map name lookup (config/soul_link/maps.yml or similar) so sidebar shows "Eterna City" instead of `426`
- **Phase 3 deferred:** multi-language char tables (Japanese, Korean, etc.); current parser is English-only
- **Phase 4 deferred:** Pokemon party data (encrypted/PRNG-scrambled blocks A-D, requires Pokemon-internal descrambling — significant effort)
- **Phase 5 deferred:** PC boxes (same scrambling as party + box-level layout)

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
