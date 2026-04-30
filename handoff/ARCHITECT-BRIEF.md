# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 2 — Auto-Persist In-Game Saves to Server

### Problem

`save_data` on `SoulLinkEmulatorSession` only updates when the player clicks the EmulatorJS UI's manual "Save File" button. In-game saves (player presses save in Pokemon) commit to melonDS's SRAM but stay in MEMFS — volatile, gone on refresh. The diagnostic disable in `connect()` (commit `d772e9f`) was the right call at the time but left server backup as a manual export only.

### Root cause (verified from EmulatorJS source)

We're listening on the wrong event. `EJS_onSaveSave` (loader.js:168) wires the `saveSave` event, which fires on the manual "Save File" button click (emulator.js:1954) — payload `{ screenshot, format, save }`. The internal SRAM commit lifecycle uses a *different* event: **`saveSaveFiles`** (GameManager.js:411).

Source flow (verified by reading `data/src/GameManager.js`, `data/src/emulator.js`):

```js
// GameManager.js:409-413
saveSaveFiles() {
  this.functions.saveSaveFiles();          // cmd_savefiles WASM export → flushes SRAM into MEMFS
  this.EJS.callEvent("saveSaveFiles", this.getSaveFile(false));
}

// getSaveFile(false) returns Uint8Array of /data/saves/<rom>.sav, OR null if missing
```

`saveSaveFiles()` is invoked from:
- The `save-save-interval` setInterval (emulator.js:4321) — settings menu UI default "300" (5min); options 0/30/60/300/600/900/1800
- `EJS.on("exit")` (GameManager.js:46-48)
- Netplay-pause path (emulator.js:1849)

The `saveSaveFiles` event is NOT auto-wired by loader.js — we must register via `window.EJS_emulator.on("saveSaveFiles", cb)` inside the `EJS_ready` callback (only point at which `window.EJS_emulator` is guaranteed to exist).

### Project Owner decisions (locked)

- Server is the source of truth on load. IDBFS is a local convenience cache. If both have data on `EJS_ready`, server wins — inject server save into MEMFS, call `loadSaveFiles()`.
- Auto-save interval: 30 seconds. Tradeoff: extra writes (≤ 1MB/min, gzipped ≪ that) for a tighter "X just saved" surface. Configurable per-player via the in-game menu — first-time users see 30s; returning users keep whatever they set.
- Keep `EJS_onSaveSave` as a belt-and-suspenders for the manual export button.
- 0-byte / null saves never PATCH the server. Empty SRAM would clobber a real save.

### Files to Modify

- `app/javascript/controllers/emulator_controller.js` — only file in scope.

### Build Order

**1. Set the auto-save default before loader.js boots.** Add in `connect()`, before any `EJS_*` global is set:

```js
window.EJS_defaultOptions = { "save-save-interval": "30" }
```

This propagates via loader.js:103 → `config.defaultOptions` → `getSettingValue("save-save-interval")` → menu UI's `defaultOption` path → `menuOptionChanged("save-save-interval", "30")` → sets up the 30s setInterval. localStorage overrides this for returning users (handled by `getSettingValue` precedence; verified at emulator.js:4159-4172).

**2. Re-enable the server-save fetch.** Uncomment the diagnostic-disabled `_fetchSave()` call at the top of `connect()`. The result feeds `_injectExistingSave` in step 4.

**3. Replace the diagnostic `EJS_ready`.** Current implementation is a console.log only. Replace with a function that:
   1. Registers `window.EJS_emulator.on("saveSaveFiles", bytes => this._uploadSave(bytes))` **first** (before injection — otherwise the inject's `loadSaveFiles()` could trigger an auto-save tick before our listener is attached).
   2. Then, if `existingSave` is non-null, calls `this._injectExistingSave(existingSave)`.
   3. Logs once: `console.log("Emulator: hooks attached", { hasExistingSave: !!existingSave, hasEmulator: !!window.EJS_emulator })`.

**4. Harden `_uploadSave`.** It must guard against the null / 0-byte case from `getSaveFile(false)`:

```js
async _uploadSave(saveBytes) {
  if (!saveBytes || saveBytes.byteLength === 0) return
  // ...existing PATCH logic...
}
```

The `EJS_onSaveSave` callback path (`event.save`) already gates on `event && event.save`, but should ALSO go through the same `byteLength === 0` guard since defensive layering is cheap.

**5. Update `disconnect()`** to also clear `window.EJS_defaultOptions`. Best-effort cleanup matches the existing pattern.

### Out of Scope (do NOT expand into Step 2)

- Multi-device conflict resolution — single browser per player assumed
- Pokemon "communication error" in-game popup — a DS Wireless thing, unrelated to SRAM
- Stimulus controller unit tests — project doesn't have JS test scaffolding; verify via dev console (manual)
- Server-side parse-on-save — already handled by `ParseSaveDataJob` (`after_update_commit` callback on `SoulLinkEmulatorSession`)
- Any change to `app/services/soul_link/save_parser.rb`, `app/jobs/soul_link/parse_save_data_job.rb`, or routes/controllers
- Re-implementing `_injectExistingSave` — keep the existing implementation as-is. It's the right shape; the corruption blamed on it earlier was actually the FAILSAFE bundle (now fixed)

### Constraints / Flags

- DO NOT register `saveSaveFiles` listener at the top of `connect()`. `window.EJS_emulator` does not exist there. Loader.js creates it. `EJS_ready` is the earliest safe point.
- DO NOT touch `_injectExistingSave` body. Don't add new error handling, don't change the FS path computation, don't refactor it. The body is correct; only the *call site* changes (re-enabled inside the new EJS_ready).
- DO NOT remove `EJS_onSaveSave`. Both events stay wired.
- DO NOT add backend tests (Ruby). No backend change.
- DO NOT write JS unit tests (no scaffolding exists; introducing it is out of scope).
- DO NOT bump dependencies, regenerate manifests, or precompile assets — Importmap picks up the controller file directly.

### Acceptance Criteria

- Console logs show `"Emulator: hooks attached" { hasExistingSave: …, hasEmulator: true }` once on `EJS_ready`.
- After 30 seconds of gameplay (or on in-game save), browser network tab shows a `PATCH /emulator/save_data` with `Content-Length` matching the SRAM file size (Pokemon Platinum: 524288 bytes / 512KB).
- After a hard refresh, the game resumes at the last in-game save point. (Implies the inject path runs and melonDS reloads SRAM.)
- The manual "Save File" button still works: triggers a PATCH (via the existing `EJS_onSaveSave` path).
- 0-byte payloads from `getSaveFile(false)` (would happen pre-first-save) do not PATCH.
- 100% of the existing 255-test Rails suite passes (no regression — no backend change is intended).

### Files Bob Should Read

- `app/javascript/controllers/emulator_controller.js` (the full file — small)
- `public/emulatorjs/data/loader.js` — only to confirm event registration pattern (lines 150-169)

That's it. Bob should NOT load `emulator.js` or `GameManager.js` — the relevant API is fully documented in this brief. Anything unclear → ask Architect, do not guess.

### Files Bob Should Update

- `app/javascript/controllers/emulator_controller.js`

### Files Bob Should Update at the End

- `handoff/REVIEW-REQUEST.md` — list of changed files, reasoning summary, any flags/risks
- `handoff/BUILD-LOG.md` — append to Step History with status "Awaiting review"

---

## Notes for Reviewer

When this lands on your desk, focus on:

1. **Listener order in EJS_ready** — `saveSaveFiles` must register BEFORE `_injectExistingSave`. The race is small (one `loadSaveFiles()` tick) but real.
2. **Null-byte guard** — `_uploadSave` must short-circuit on `null` and `byteLength === 0`. The `getSaveFile(false)` return value is genuinely null pre-first-save.
3. **`EJS_defaultOptions` set position** — must be before loader.js script appended. The loader reads window globals synchronously at boot.
4. **`EJS_onSaveSave` retained** — Bob should NOT have removed this. Belt-and-suspenders for manual export.
5. **`disconnect()` cleanup** — `EJS_defaultOptions` should also be cleared.
6. **Scope** — verify Bob did NOT touch backend (parser, job, controller, routes). One file only: `emulator_controller.js`.

Out-of-scope items found during review → BUILD-LOG Known Gaps. Do not bundle.
