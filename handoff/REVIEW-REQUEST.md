# Review Request — Step 5

**Ready for Review:** YES

## Summary

Step 5 ships the player-facing emulator: a single `/emulator` page that auto-claims one of the run's four randomized ROMs, streams it to EmulatorJS in the browser, and round-trips SRAM via `GET`/`PATCH /emulator/save_data`. Six render states cover the lifecycle (no run → no ROMs generated → all claimed → generating → failed → ready). The controller's `set_session` carries a SQL-atomic claim with a single retry on `AlreadyClaimedError` for the page-reload-vs-Stimulus-connect race. Stimulus configures EmulatorJS via `window.EJS_*` globals and injects `loader.js`.

## Files Changed

### Production

| File | Lines | Change |
|------|-------|--------|
| `config/routes.rb` | 47–53 | New `resource :emulator, only: [:show], controller: "emulator"` block with member `get :rom`, `get :save_data`, `patch :save_data`. Explicit `controller:` so the singular file `emulator_controller.rb` is used (default would be plural `EmulatorsController`). |
| `app/controllers/emulator_controller.rb` | 1–84 (new) | Full controller. `EMULATOR_CORE = "melonds"`. `before_action :require_login, :set_run, :set_session`. `protect_from_forgery with: :null_session, only: [:save_data], if: -> { request.patch? }`. Auto-claim race-retry: stale `unclaimed.first` → `claim!` → on `AlreadyClaimedError`, re-query and retry once; second `AlreadyClaimedError` falls through to nil. |
| `app/views/emulator/show.html.erb` | 1–63 (new) | Six-state ERB. GB aesthetic via `.gb-card` + raw CSS vars (`var(--l2)`, `var(--d2)`) — matches `runs/index.html.erb`. The `ready` state renders `data-controller="emulator"` with all 5 Stimulus values + `id="emulator-game"` mount target. |
| `app/javascript/controllers/emulator_controller.js` | 1–127 (new) | Stimulus bridge. `connect()`: fetch existing save → set EJS_* globals → register `EJS_onSaveSave` handler → register `EJS_ready` to inject existing save into emulator FS via `gameManager.FS.writeFile(getSaveFilePath(), bytes)` + `loadSaveFiles()` → inject `loader.js`. `disconnect()` clears globals + removes loader script. |
| `app/views/layouts/application.html.erb` | 42 | One new line: `<%= link_to "Play", emulator_path, class: "gb-nav-link" %>` immediately after the existing "Runs" link. Same gating as the rest of the nav (only renders when `logged_in?`). |

### Tests

| File | Lines | Change |
|------|-------|--------|
| `test/controllers/emulator_controller_test.rb` | 1–308 (new) | 23 controller tests. See breakdown below. |

## Test Results

```
mise exec -- ruby -S bundle exec rails test
169 runs, 504 assertions, 0 failures, 0 errors, 0 skips
```

Baseline 146 + **23 new** = 169.

```
mise exec -- ruby -S bundle exec rails test test/controllers/emulator_controller_test.rb
23 runs, 67 assertions, 0 failures, 0 errors, 0 skips
```

Rubocop clean on all changed Ruby files.

### Test breakdown (23)

- **Auth (4):** `show`, `rom`, `save_data` GET, `save_data` PATCH each redirect to login when not signed in.
- **show: no active run (1):** Deactivates fixture run; expects "NO ACTIVE RUN".
- **show: emulator_status :none (1):** Active run, no sessions; expects "ROMS NOT GENERATED YET".
- **show: all claimed (1):** 4 sessions all owned by other players; expects "NO ROM AVAILABLE".
- **show: auto-claim happy path (1):** 4 unclaimed; verifies exactly one is claimed by the visiting player after the request and total count is unchanged.
- **show: idempotent on re-visit (1):** Already-claimed session is not re-claimed; sibling unclaimed stays unclaimed.
- **show: pending (1)** + **show: generating (1)** + **show: failed (1):** Each renders the correct lifecycle banner; failed includes `error_message` text.
- **show: ready (1):** Renders the emulator stage with all five `data-emulator-*-value` attributes including `data-emulator-core-value="melonds"`.
- **show: claim race (1):** Monkey-patches `claim!` to raise `AlreadyClaimedError` on the first call, succeed on the second; verifies the retry path executes and exactly one session ends up claimed by the player. Restores the original method via `ensure`.
- **rom (4):** 404 when not ready, 404 when no session, 404 when `rom_full_path` doesn't exist on disk, 200 + correct body bytes when present (uses `Tempfile`).
- **save_data GET (3):** 204 when nil, 204 when empty bytes, 200 with correct body bytes when present.
- **save_data PATCH (2):** Writes the request body bytes into `session.save_data`. Second test flips `ActionController::Base.allow_forgery_protection = true` and confirms PATCH still succeeds *without* an `X-CSRF-Token` header — exercising the `null_session` bypass for real.

## EmulatorJS API verification

Both findings deviated from the brief slightly. Both are documented and intentional.

**Core name: `melonds`.** I confirmed the DS core name by reading the source, since `public/emulatorjs/data/cores/` only ships README placeholders (cores are downloaded dynamically by the loader at runtime). Source of truth: `public/emulatorjs/data/src/GameManager.js` line 26:

```js
"nds": ["melonds", "desmume", "desmume2015"],
```

The first entry is the preferred default. `EMULATOR_CORE = "melonds"`.

**Save callback: `EJS_onSaveSave`, not `EJS_onSaveState`.** The brief assumed `EJS_onSaveState` and noted I should verify. I did, in two places:

- `public/emulatorjs/data/loader.js` lines 156–167 — the loader wires both `EJS_onSaveState` (event "saveState") and `EJS_onSaveSave` (event "saveSave"); they're different events.
- `public/emulatorjs/data/src/emulator.js` line 1903 fires `saveState` with payload `{ screenshot, format, state }` — this is the *RetroArch-style snapshot* (in-memory state). Line 1954 fires `saveSave` with payload `{ screenshot, format, save }` — this is the *SRAM file* (the actual cartridge save).

For Pokemon Platinum, the player saves via the in-game Save menu, which writes SRAM. That's `onSaveSave`. `onSaveState` would persist a snapshot of working RAM at the moment the user clicked the EmulatorJS save-state button, which is unrelated to Pokemon's save system. Using `onSaveSave` is the correct choice. Documented in the Builder Plan and the controller's source comment.

There is no public "preload SRAM URL" config. To restore an existing save on boot I use `EJS_ready` to write the bytes directly into the emulator's virtual FS at `gameManager.getSaveFilePath()`, then call `gameManager.loadSaveFiles()` — same pattern that `loadSavFiles` button uses internally (`emulator.js` lines 1967–1983).

## DoD Checklist

- [x] Routes added; `rake routes | grep emulator` shows all 4 endpoints (`/emulator`, `/emulator/rom`, `GET /emulator/save_data`, `PATCH /emulator/save_data`)
- [x] `EmulatorController` exists with all required actions, before-actions, the `null_session` PATCH bypass, and the auto-claim race-retry logic
- [x] `app/views/emulator/show.html.erb` renders all six states correctly (4 message states + generating + ready)
- [x] "Play" link added to layout nav, gated on `logged_in?` via the existing wrapping `<% if logged_in? %>`
- [x] `app/javascript/controllers/emulator_controller.js` configures EmulatorJS, handles save round-trip with CSRF header, writes existing save into FS on `EJS_ready`
- [x] Controller tests cover: auth (4), all six show-states, auto-claim happy path + race retry, rom 404s + 200, save_data GET 204 + 200, save_data PATCH writes correctly, CSRF bypass works under enforced forgery protection
- [x] Full suite: 146 baseline + 23 new = 169, 0 failures
- [x] EmulatorJS core name + save callback verified against `public/emulatorjs/data/src/`
- [x] "What to verify locally" checklist for the user (below)

## What To Verify Locally

I cannot drive a browser. After `git pull && rake emulatorjs:install && bin/rails server` (and `rake soul_link:bot` if you want the Discord bot), please run through this checklist as the run-creator account first, then as a second player account:

**Without an active run:**
1. Sign in with Discord. Confirm the new "Play" link appears in the top nav between "Runs" and the avatar.
2. Click "Play". Expect the **NO ACTIVE RUN** card with a "GO TO RUNS" button.

**With an active run, before generating ROMs:**
3. Start a new run from `/runs`. Click "Play". Expect the **ROMS NOT GENERATED YET** card.

**Generating:**
4. Back to `/runs`. Click "Generate Emulator ROMs". Quickly switch to `/emulator`. Expect **ROM GENERATING…** for the duration the job runs (a few seconds for the randomizer per ROM × 4).
5. Refresh `/emulator` after ~30–60 seconds. Expect either **ROM GENERATING…** still, or transition into the ready state.

**Ready, single player:**
6. Once one of the four sessions is `ready`, the page should render an EmulatorJS canvas inside a `gb-card` panel. The melonDS core will download from the EmulatorJS CDN on first load (~10 MB) — this is normal v4.2.3 behavior.
7. Wait for the boot screen and the Pokemon Platinum title screen. **Things to confirm:**
   - The DS dual-screen layout renders.
   - Audio plays.
   - Keyboard / gamepad input registers (default mappings — not customized this step).
   - Reload the page. The same player should land on the same ROM (no re-claim), and the page should re-render the emulator with the same state of the world (auto-claim should be idempotent).

**Save round-trip:**
8. In the running game, walk into the menu and trigger an in-game save (write to the journal). This writes SRAM inside the emulator's virtual FS but does *not* yet round-trip to the server.
9. Click the "Save SRAM" / "Export Save File" button in the EmulatorJS UI footer (the floppy-disk icon for SRAM, not the camera-roll icon for save states). The Stimulus controller should intercept the default download and `PATCH /emulator/save_data` instead. Open DevTools Network tab to confirm a `204` response.
10. Refresh the page. The page should refetch the SRAM via `GET /emulator/save_data`, EmulatorJS boots, the FS is repopulated in `EJS_ready`, and loading the save in-game should return you to where you were.

**Multi-player auto-claim:**
11. Sign in as a second player. Visit `/emulator`. Expect a different ROM to be auto-claimed — verify by inspecting the response (the `data-emulator-rom-url-value` and `data-emulator-save-data-url-value` are session-scoped via the Discord session, but the underlying ROM bytes will differ; you can confirm by hashing the downloaded ROM, or by simply checking that two players don't see the *same* save state when they both have saves).
12. Continue with players 3 and 4. Player 5 (if you create one) should see **NO ROM AVAILABLE**.

**Failure path:**
13. (Optional) Inject a session failure manually via console: `SoulLinkEmulatorSession.last.update!(status: "failed", error_message: "test")`. Visit `/emulator` as that player. Expect **ROM GENERATION FAILED** with the error text.

If any of those steps misbehave, please paste the relevant DevTools Console + Network output into REVIEW-FEEDBACK.md and I'll iterate.

## Open Questions

1. **EmulatorJS download caching.** The first visit downloads the melonDS core (~10 MB) from the EmulatorJS CDN. EmulatorJS caches this in IndexedDB by default. If the project owner is hosting offline / behind a firewall, we may need to set `EJS_CacheLimit` or self-host cores from `/public/emulatorjs/data/cores/`. Out of scope for Step 5 — flagging only.
2. **No `disconnect()`-side teardown of the Module/canvas.** EmulatorJS v4 doesn't expose a clean shutdown API; turbo-frame nav between Stimulus mounts could theoretically leave the previous Module running in the background. The current implementation clears globals + removes the loader script, which is the documented "best effort" pattern. Real navigation away (full page reload) cleans up everything. Acceptable for Step 5.
3. **Multi-tab.** If a player opens `/emulator` in two tabs simultaneously, both will boot and both will compete for save uploads on the next save. The server-side `claim!` prevents double-claim, but inside one player's session there's no inter-tab lock. Out of scope; mention if you want a "this session is open in another tab" warning later.

## Known Gaps

None. Build is in scope.
