# Build Log
*Owned by Architect. Updated by Builder after each step.*

`Current Status` and `Step History` are session-scoped — archived to
`handoff/archive/` at session end and reset.
`Known Gaps` and `Architecture Decisions` are durable — they survive session
reset until the gap is addressed or the decision is replaced.

---

## Current Status
*Session-scoped.*

**Active step:** Step 3 — Save Slots (5 per session). Awaiting Reviewer.
**Last committed:** `2e9e934` — 2026-04-30 (Step 2: Auto-persist in-game saves)
**Pending deploy:** NO — Step 3 not yet committed.

**Parked plan:** FactoryBot conversion. Inventory + ordering at `handoff/parked-plans/factorybot-conversion.md`.

---

## Step History
*Session-scoped.*

### Step 3 — Save Slots (5 per session) — 2026-04-30
**Status:** Awaiting review

**Files created:**
- `db/migrate/20260430143102_create_soul_link_emulator_save_slots.rb` — slots table + `active_save_slot` pointer on session; data-preservation INSERT migrates existing per-session save into slot 1; columns dropped with type args so rollback is reversible (data lost on rollback per Project Owner acceptance)
- `app/models/soul_link_emulator_save_slot.rb` — model with GzipCoder reuse, slot_number 1..5 validation + uniqueness, after_create_commit + after_update_commit parse-enqueue
- `app/controllers/save_slots_controller.rb` — index/create/update/destroy/restore/download. Authorization via `set_session` resolving to current_user_id-owned session; cross-player URLs return 404
- `app/views/emulator/_save_slots_sidebar.html.erb` — left column partial, 5 cards, banner for overwrite-pending mode, per-slot Download/MakeActive/Delete actions, Clear-All at bottom
- `app/javascript/controllers/save_slots_controller.js` — Stimulus controller; listens for `save-slots:overwrite-needed` and `save-slots:saved` window events; click overlays for overwrite mode; calls `window.EJS_emulator.gameManager.getSaveFile()` at click time to grab fresh bytes for the PATCH (Approach 2 per brief — stateless)
- `test/models/soul_link_emulator_save_slot_test.rb` — 18 tests (validations, gzip coder round-trip, parse callbacks)
- `test/controllers/save_slots_controller_test.rb` — 33 tests covering all 6 actions + cross-player authz
- `test/factories/soul_link_emulator_save_slots.rb` — factory with `:filled` and `:parsed` traits

**Files modified:**
- `app/models/soul_link_emulator_session.rb` — `has_many :save_slots dependent: :destroy`, new `active_slot` association method, removed `serialize :save_data` and the parse callback (moved to slot model). GzipCoder module retained on this class for shared use.
- `app/jobs/soul_link/parse_save_data_job.rb` — operates on a `SoulLinkEmulatorSaveSlot` parameter, not a session
- `app/controllers/emulator_controller.rb` — DELETE save_data wipes all slots + clears active_save_slot; GET reads from `@session.active_slot.save_data`; PATCH branch removed entirely; `set_session` no longer applies to PATCH route. `show` action eager-loads `:save_slots` and pre-fetches `@save_slots` for the sidebar partial.
- `app/javascript/controllers/emulator_controller.js` — added `saveSlotsUrl` Stimulus value; `_uploadSave` now POSTs to that URL; on 409 dispatches `save-slots:overwrite-needed` window event with the JSON body as detail; on 201 dispatches `save-slots:saved`
- `app/views/emulator/show.html.erb` — three-column grid (`280px minmax(0, 1fr) 280px`); save-slots sidebar on left; canvas in middle; run roster on right; canvas wrapper now also has `data-emulator-save-slots-url-value`
- `app/views/emulator/_run_sidebar.html.erb` — drops the inline Clear-Save button (moved to slot column); drops parsed-info display from the YOU card (visible in slot column); keeps parsed info on OTHER players' cards (sourced from their `active_slot`); removed `clear-save` Stimulus mount from this partial
- `config/routes.rb` — removed `patch :save_data`; nested `resources :save_slots, only: [...], param: :slot_number` under `:emulator` with `member { post :restore; get :download }`
- `lib/tasks/soul_link/debug_save.rake` — `reparse_all_saves` and `debug_save_offsets` now iterate `SoulLinkEmulatorSaveSlot.where.not(save_data: nil)`, not sessions
- `lib/tasks/emulator_cleanup.rake` — counts non-nil save bytes via `session.save_slots.where.not(save_data: nil).count`; destroys all slots; clears `active_save_slot` on inactive runs (transitively required by the schema migration)
- `test/controllers/emulator_controller_test.rb` — removed all PATCH save_data tests; updated GET save_data tests to source from active slot; updated DELETE tests to assert all slots wiped + active pointer cleared; parsed-roster tests now create slots on OTHER players (not on YOU, per the YOU-card-no-parsed change)
- `test/models/soul_link_emulator_session_test.rb` — removed save_data gzip + parse callback tests (moved to save slot model test); added save_slots association + active_slot resolution tests
- `test/jobs/soul_link/parse_save_data_job_test.rb` — exercises against a slot, not a session
- `test/lib/tasks/emulator_cleanup_test.rb` — seeds slots instead of `save_data:` on session; updated assertions to check `session.save_slots.count` and `active_save_slot`

**Key decisions:**
- Reused `SoulLinkEmulatorSession::GzipCoder` directly via `serialize :save_data, coder: SoulLinkEmulatorSession::GzipCoder` (per brief — no concern extraction yet).
- Added `after_create_commit :enqueue_parse_if_save_present` ALONGSIDE `after_update_commit :enqueue_parse_if_save_changed` on the slot model. The brief only specified after_update_commit, but the controller creates slots via `@session.save_slots.create!(slot_number:, save_data:)` — there is no update event on creation, so without the after_create_commit no parse would fire on the first save into an empty slot. Without it, slot cards would show "no parsed data" until something else triggered a parse. Worth Reviewer's eyes.
- `slot_payload`'s `saved_bytes` calculation: freshly-created records return `ActiveModel::Type::Binary::Data` from `read_attribute_before_type_cast`, not a String. Normalized via `.to_s.bytesize` so the 201-Created JSON response carries the correct on-disk size without forcing a reload.
- Migration: column drops use the type-arg form (`remove_column ..., :type, ...`) so rollback is reversible at the schema level. Brief listed bare `remove_column` — I added types to make a hypothetical `db:rollback` work cleanly (data still lost; matches Project Owner acceptance per brief).
- Run roster sidebar: parsed metadata for other players now sources from their `active_slot` (vs. the old per-session parsed_* columns). The card omits parsed lines when `active_slot` is nil OR has nil parsed fields. The YOU card no longer shows parsed info at all (slot column on the left covers it).
- Stimulus overwrite path: implemented Approach 2 from the brief — slot controller calls `window.EJS_emulator.gameManager.getSaveFile()` at click time to grab fresh SRAM bytes. Stateless; small in-game drift on overwrite-click is documented in the controller comment per brief.
- `_save_slots_sidebar.html.erb` reuses the existing `clear_save_controller` for the Clear-All button. The clear-save controller's DELETE-then-IDB-wipe-then-reload flow is unchanged; only its mount location moved.

**Tests:** 263 → 305 (+42 across model 18, controller 33, session-changes 4, parse job 7 unchanged, plus emulator-controller test rewrites). 0 failures, 0 errors.

**Lint:** `bundle exec rubocop` clean on all 16 touched files.

**Migration verified:** Ran `db:migrate` + `db:rollback` + `db:migrate` cycle in dev. Rollback reverts schema cleanly (data not preserved — accepted). Re-migrate is idempotent.

**Open questions for Reviewer:** see REVIEW-REQUEST.md.

### Step 2 — Auto-Persist In-Game Saves to Server — 2026-04-30
**Status:** Complete, committed `2e9e934`, deployed to `4luckyclovers.com`

**Files modified:**
- `app/javascript/controllers/emulator_controller.js` — re-enabled `_fetchSave()` on `connect()`; added `window.EJS_defaultOptions = { "save-save-interval": "30" }` before loader.js boot; replaced diagnostic `EJS_ready` with: register `saveSaveFiles` listener first, then inject existing save if present, then log `"Emulator: hooks attached"` once with `hasExistingSave`/`hasEmulator` flags; added null/0-byte guard at top of `_uploadSave`; cleared `EJS_defaultOptions` in `disconnect()`. `EJS_onSaveSave` retained (manual export). `_injectExistingSave` body untouched.

**Key decisions:**
- Centralized null/0-byte guard inside `_uploadSave` so both call paths (`EJS_onSaveSave` event payload, `saveSaveFiles` direct bytes) share it. Brief asked for "defensive layering"; placing the guard in the function-under-call makes it impossible to bypass.
- Listener registration ordered BEFORE inject inside `EJS_ready` per the brief's race-condition warning (`gm.loadSaveFiles()` could trigger an auto-save tick between attach points).
- `EJS_defaultOptions` set FIRST in `connect()`, before `EJS_player`/`EJS_gameUrl`/etc. The brief said "before any EJS_* global is set"; obeyed literally to keep the ordering guarantee tight in case loader.js evolves to read globals at any point during script-tag append.

**Tests:** 255/255 pass. No backend change; suite count unchanged from Step 1.

**Lint:** No new Ruby. JS controller has no lint configured (Importmap project, no Node toolchain). Pre-existing rubocop offenses (133 across 127 files) are unrelated; documented previously in Known Gaps.

**Review:** Richard — APPROVED (no conditions, no escalations). All six Architect focus areas verified: listener order in `EJS_ready`, null/0-byte guard centralization, `EJS_defaultOptions` set position, `EJS_onSaveSave` retained, `disconnect()` cleanup, scope discipline (single code file).

**Deploy:** GitHub Actions run 25143303161 — test job 50s (255/255 pass), deploy job 17s (VPS SSH, asset precompile, web + bot service restart). All green.

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
- **In-game SRAM saves are persisted via the `saveSaveFiles` event, NOT `saveSave`.** `saveSave` (loader.js auto-wires `EJS_onSaveSave`) only fires on the manual "Save File" export button. The internal SRAM commit lifecycle uses `saveSaveFiles`, fired by `gameManager.saveSaveFiles()` after every `cmd_savefiles` flush. We register `window.EJS_emulator.on("saveSaveFiles", cb)` inside `EJS_ready` and set `EJS_defaultOptions["save-save-interval"] = "30"` so the auto-save tick covers in-game saves. `EJS_onSaveSave` is retained as belt-and-suspenders for the manual button. Server is the source of truth on load: `_injectExistingSave` runs in `EJS_ready` after the listener is attached. `_uploadSave` short-circuits null / 0-byte payloads — `getSaveFile(false)` returns null pre-first-save, and an empty SRAM PATCH would clobber a real server save.
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
