# Archived Session — 2026-04-29 — Emulator Deploy + Polish

Archived from `handoff/SESSION-CHECKPOINT.md` and `handoff/BUILD-LOG.md` on 2026-04-29.
Read this only if you need historical context for the emulator deploy / hardening work.

---

## Session Summary

Took the in-browser emulator from "code shipped but never deployed" to "live and verified on the production VPS at `4luckyclovers.com`." The feature scope had been built across the previous archive (commits `574fa7f` through `c33c8b8`); this session closed every loose end and shipped real-world hardening fixes.

Ended at commit `24aff23` with all features live, 221/221 tests passing, parallel-clean.

**Work split:**
- **One real bug** that blocked production: PokeRandoZX silent failure mode (fixed in `d886908`)
- **Three TMT steps:** Polish (Step 2), Hardening (Step 3), Sidebar (Step 4)
- **Six inline fixes** for UX and infra issues found during deploy/verification

---

## What Was Built

### Pre-flight: Test infra fix (`c36ce69`)
Parallel-test flake in `emulator_cleanup_test.rb` — `Rails.application.stub(:root)` was a no-op because `Rails.root` is `Rails.application.config.root`, not `Rails.application.root`. Switched to module-level `Rails.stub(:root, ...)`. Suite went from intermittent-fail to clean across 5+ consecutive parallel runs.

### Step 2 — Emulator Polish (`caca621`)
- **Deployment doc** appended to `.claude/documents/deployment.md` with full prereq checklist (JRE install, base ROM placement, JAR placement, randomizer settings file, EmulatorJS install task, periodic cleanup)
- **N+1 fix:** `RunChannel.broadcast_run_state` and `build_state_payload` now eager-load `:soul_link_emulator_sessions` — measured 12 → 2 session queries on broadcasts that include past runs
- **"ROMs generating…" inline label** on the runs page; visibility toggled by Stimulus on `emulator_status === "generating"` broadcast

### Inline: Modal scroll + escape close (`4a10fc7`, `fa5ca36`)
- Added `max-height: calc(100vh - 32px)` and `overflow-y: auto` to `.gb-modal` — prevents the pokemon detail modal from overflowing the viewport on long content (PC box card with evolution chain + cheats was clipping the MARK DEAD/SAVE buttons)
- New global Stimulus controller `escape-close` attached to `<body>` — pressing Escape clicks the topmost visible `.gb-modal-close` button, routes through each modal's existing close action

### Step 3 — Emulator Hardening (`5ed97af`)
Bundled five Must Fix items + cleanup from a fresh-eyes review:

1. **`SoulLinkEmulatorSession#delete_rom_file`** rescue widened from `Errno::ENOENT` → `StandardError` (with logger.warn) — so a partial cascade can't roll back the AR transaction with files already deleted
2. **`EmulatorController#save_data` PATCH** capped at 2MB raw via `request.content_length` check + post-read `bytesize` check; returns `:content_too_large` (413) before reading large bodies — DoS protection
3. **`SoulLink::RomRandomizer` subprocess timeout** rewritten from `Open3.capture3 + Timeout.timeout` (anti-pattern: leaves Java zombies) to `Process.spawn` + `waitpid(WNOHANG)` poll loop + `TERM` then `KILL` escalation
4. **`RunChannel#generate_emulator_roms` and `regenerate_emulator_roms`** wrap status check + enqueue in `run.with_lock` — prevents the channel-layer race where two concurrent clicks both pass `:none` check and both enqueue
5. **`RunChannel#subscribed`** rejects when `params[:guild_id]` doesn't match `connection.session[:guild_id]` — closes the cross-guild authz gap for every channel action
6. **`SoulLinkEmulatorSession#save_data`** now serialized through a custom `GzipCoder` module — transparent gzip compression on write, decompression on read. Compression measured: 0.1% / 22% / 100% on worst/realistic/incompressible payloads
7. **`RomRandomizer#fail!`** uses `save` not `save!` — survives a persist failure with logger.error, doesn't leave session stuck in `:generating`

### Inline: Cheats YAML populated (`f739f12`)
38 Action Replay codes extracted from `pokemoncoders.com/pokemon-platinum-cheats/` and committed to `config/soul_link/cheats.yml`. 25 enabled by default (item bundles, infinite cash, max IV, fast egg hatch, walk through walls, etc.); 13 disabled (destructive ones — max EXP, ghost mode, complete pokedex, etc.). Hotkeys baked into cheat names so they're visible in EmulatorJS's in-game cheat menu.

Source page was behind Cloudflare; user saved page locally and Architect parsed the HTML.

### Inline: PokeRandoZX `cli` subcommand fix (`d886908`)
**The real production blocker.** Without the `cli` subcommand as the first arg after `-jar`, PokeRandoZX launches a Swing JFrame which fails on the headless VPS with `HeadlessException` — but Java's AWT thread swallows the exception and the process exits with code 0 having never written the output ROM. Result: silent generation failures; sessions marked `ready` but `total 0` in the run output dir. Architect's brief had the wrong CLI shape; Bob followed the brief literally; only manifested on the headless server. CLI mode also doesn't accept `-seed` (it auto-generates), so the DB `seed` column is now informational only.

### Inline: Canvas sized to DS aspect ratio (`9b0bf29`)
The `#emulator-game` div was `width: 100%; min-height: 480px` — wide and short, so EmulatorJS scaled the canvas by height (480px) leaving black side bars. Replaced with `aspect-ratio: 2 / 3; max-width: min(100%, 60vh); max-height: 90vh; margin: 0 auto;`. Canvas now fills the viewport vertically with no black bars; players can switch to side-by-side DS layout via the gear menu if preferred.

### Step 4 — Run Roster Sidebar (`24aff23`)
A 280px sidebar on the right of `/emulator` showing all 4 sessions of the current run. Tier 1 only: existing model data — player name (via `SoulLink::GameState.player_name`), status, last-played time, save size on disk (via `read_attribute_before_type_cast` for raw compressed bytes), seed. Current player's card has a YOU badge + thicker border. Responsive via `flex-wrap: wrap`. Tier 2 (parsing SRAM for in-game info: time-played, money, party, badges) deferred to a future feature.

---

## Decisions This Session

- **PokeRandoZX `cli` subcommand is required** — without it, JAR launches GUI, fails on headless server, exits 0 with no output. Architect brief was wrong; corrected.
- **CLI mode auto-seeds; `-seed` flag is rejected.** DB `seed` column kept as informational only — 4 invocations naturally produce 4 different ROMs.
- **`save_data` is gzip-compressed in DB** via custom `GzipCoder` serializer. Defensive plaintext-fallback in `load` for migrations / `update_columns` bypass scenarios.
- **2MB raw size cap** on inbound PATCH save_data via content_length + bytesize. Pokemon Platinum SRAM is ~512KB; 2MB is a generous bound that prevents OOM from a 500MB malicious upload.
- **`with_lock` is the channel-layer race fix** — chosen over advisory locks or DB unique constraints for simplicity in a 4-player single-process app.
- **Guild authz at `subscribed` time** — single check, applies to every channel action (`setup_discord`, `start_run`, `end_run`, `generate_emulator_roms`, `regenerate_emulator_roms`).
- **Subprocess timeout via `Process.spawn` + waitpid loop** — `Open3.capture3 + Timeout.timeout` is a known anti-pattern (raises in calling thread but leaves child running).
- **`rom` action's `send_file` is server-derived** — `rom_path` only ever set by `RomRandomizer` via `Pathname#relative_path_from(Rails.root)`. Documented inline; future writers should add a `path.start_with?(OUTPUT_DIR)` guard before introducing user-influenced paths.
- **Sidebar is Tier 1 only** — Tier 2 SRAM parsing deferred. Tier 1 surfaces existing model fields without parsing the opaque save blob.
- **`EMULATOR_CORE = "melonds"`** kept as the default; players can override via the gear menu (DeSmuME for performance, DeSmuME 2015 for slow hardware). melonDS is most accurate for Soul Link's timing-critical events.

---

## Architecture Decisions Locked This Session

These are durable. Will be carried into the new BUILD-LOG.

- PokeRandoZX must be invoked with `cli` as the first arg after `-jar`. CLI mode auto-seeds; do not pass `-seed`.
- `save_data` column is gzip-compressed via `SoulLinkEmulatorSession::GzipCoder`. `read_attribute_before_type_cast("save_data")` returns the raw compressed bytes (use this for size display, not `save_data.bytesize`).
- Inbound PATCH `save_data` is capped at 2MB raw (`MAX_SAVE_DATA_BYTES`).
- `RunChannel#subscribed` rejects mismatched `params[:guild_id]` vs `connection.session[:guild_id]` — applies to every channel action.
- `RunChannel#generate_emulator_roms` and `#regenerate_emulator_roms` wrap their idempotency check + enqueue in `run.with_lock`.
- `Process.spawn` + `waitpid(WNOHANG)` is the subprocess pattern; `Open3.capture3 + Timeout.timeout` is banned (zombie leak).

---

## Known Gaps Carried Forward

These are NOT addressed; future steps may pick them up.

- **Tier 2 SRAM parsing** for in-game info (character name, time-played, money, party count, current map, badges earned) — separate feature
- **No automated browser test harness** — smoke tests are manual; Project Owner verifies UI changes
- **`#d4b14a` amber color** for pending-state status badge is inline in the partial. If used in a third place, promote to a `--amber` palette token in `pixeldex.css`.
- **Randomizer settings file** (`random_basic_1.rnqs`) is small/basic — heavier randomization (abilities, types-per-move, evolutions) requires re-export from the GUI and re-scp
- **Destructive regenerate** still wipes save_data for ready/claimed sessions when status is `:failed` (acceptable v1 tradeoff)
- **`error_message` column at varchar(255)** — widen to text only if real-world stack traces prove limiting
- **Convert legacy fixture-based tests to FactoryBot** — deferred since the test infra fix in `c36ce69`; do not bundle into feature work
- **No real-time updates on the run roster sidebar** — page-load refresh only. Could broadcast on save_data PATCH if anyone wants live "X just saved" updates.
- **Channel-layer guild authz cached at login** — if the user joins a new guild mid-session without re-logging-in, they won't see it. Acceptable for current use.

---

## Step History — File Manifest

### Step 4 — Run Roster Sidebar (`24aff23`)
**Created:** `app/views/emulator/_run_sidebar.html.erb`
**Modified:** `app/controllers/emulator_controller.rb`, `app/views/emulator/show.html.erb`, `test/controllers/emulator_controller_test.rb`

### Inline: canvas DS aspect ratio (`9b0bf29`)
**Modified:** `app/views/emulator/show.html.erb`

### Inline: PokeRandoZX cli fix (`d886908`)
**Modified:** `app/services/soul_link/rom_randomizer.rb`, `test/services/soul_link/rom_randomizer_test.rb`

### Inline: cheats YAML populated (`f739f12`)
**Modified:** `config/soul_link/cheats.yml`

### Step 3 — Emulator Hardening (`5ed97af`)
**Modified:** `app/channels/application_cable/connection.rb`, `app/channels/run_channel.rb`, `app/controllers/emulator_controller.rb`, `app/models/soul_link_emulator_session.rb`, `app/services/soul_link/rom_randomizer.rb`, `test/channels/run_channel_test.rb`, `test/controllers/emulator_controller_test.rb`, `test/lib/tasks/emulator_cleanup_test.rb`, `test/models/soul_link_emulator_session_test.rb`, `test/services/soul_link/rom_randomizer_test.rb`

### Inline: escape-close global controller (`fa5ca36`)
**Created:** `app/javascript/controllers/escape_close_controller.js`
**Modified:** `app/views/layouts/application.html.erb`

### Inline: modal scroll (`4a10fc7`)
**Modified:** `app/assets/stylesheets/pixeldex.css`

### Step 2 — Emulator Polish (`caca621`)
**Modified:** `app/channels/run_channel.rb`, `app/javascript/controllers/run_management_controller.js`, `app/views/runs/index.html.erb`, `test/channels/run_channel_test.rb`, plus `.claude/documents/deployment.md` (gitignored, local only)

### Pre-flight: parallel test flake fix (`c36ce69`)
**Modified:** `test/lib/tasks/emulator_cleanup_test.rb`

---

## Last Review (Step 4)

**Verdict:** PASS_WITH_OBSERVATIONS — 2 non-blocking style nits.

**Observations:**
1. `#d4b14a` amber color for pending/generating status is inline in the partial; not a palette token. Acceptable per "no new CSS" flag, but worth promoting if reused.
2. Bob's report described the ready palette as matching the runs page ACTIVE label, but the actual ACTIVE badge uses `var(--d2)` while the partial uses `var(--d1)`. Cosmetic note mismatch, not a code problem.

**Things specifically verified:**
- Canvas `aspect-ratio: 2 / 3; max-width: min(100%, 60vh); max-height: 90vh; margin: 0 auto;` preserved byte-for-byte from `9b0bf29`
- `@run_sessions` set ONLY on `@session&.ready?` branch
- `read_attribute_before_type_cast("save_data")&.bytesize` used for size display (no gzip decompression)
- Direct Integer-to-Integer comparison `s.discord_user_id == current_user_id` (no coercion)
- Failed-status palette uses existing `gb-flash-alert` colors at `pixeldex.css:140-143`
- All five brief-listed body assertions covered in tests; two new tests assert non-ready negative cases
- 221/221 across 3 sequential local runs; rubocop clean

---

## Pre-Session State (just before this session started)

For continuity — the session before this one shipped:
- Steps 1-7 of the original emulator feature build (574fa7f → c33c8b8)
- Evolve Button on Pokemon Modal (a708443) — separate small feature
- Build log + session checkpoint updates

That work is documented in BUILD-LOG entries that get cleared with this archive.
