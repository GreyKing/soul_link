# Review Request
*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

Ready for Review: YES

---

## Step 2 — Auto-Persist In-Game Saves to Server

### Files Changed

#### Modified

- `app/javascript/controllers/emulator_controller.js` — single file in scope per the brief. Total diff is ~30 lines added / ~10 lines removed across the same file.

### Diff by line range (in the controller's new file)

| Lines | What | Why |
|------|------|------|
| 1–14 | Updated header comment | Reflects the now-active responsibilities (auto-save default, injection, both save events) — old comment described the diagnostic-disabled flow. |
| 29–33 | Re-enabled `const existingSave = await this._fetchSave()` | Step 1 of the build order: server is the source of truth on load (Project Owner decision). |
| 35–40 | Added `window.EJS_defaultOptions = { "save-save-interval": "30" }` | Step 1 of the brief's build order. Set before any other `EJS_*` global so loader.js sees it whenever it reads `defaultOptions`. localStorage overrides this for returning users via the `getSettingValue` precedence path the brief documents. |
| 63–70 | Tightened the `EJS_onSaveSave` comment | No behavioral change: the existing `event && event.save` check stays; the comment now explains belt-and-suspenders relative to `saveSaveFiles`. |
| 72–90 | Replaced diagnostic `EJS_ready` with the production version | Step 3 of the build order: register the `saveSaveFiles` listener BEFORE injecting (race avoidance per the brief), then call `_injectExistingSave(existingSave)` only when non-null, then log `"Emulator: hooks attached"` once with both flags. The defensive `if (window.EJS_emulator)` wraps only the listener registration — required because loader.js:150 happens before `EJS_ready` fires per the brief, but the guard costs nothing and makes the boot order explicit. |
| 99–115 | Added `window.EJS_defaultOptions = undefined` to `disconnect()` | Step 5 of the build order. Best-effort cleanup matches the existing pattern. |
| 161–168 | Added null / 0-byte short-circuit at the top of `_uploadSave` | Step 4 of the build order. Centralized guard — both `EJS_onSaveSave` (manual button) and `saveSaveFiles` (auto-save / in-game / exit) routes now go through it. Brief explicitly asked for both paths to be guarded; placing the guard in the called function makes it impossible to bypass. |

`_injectExistingSave` body (lines 137–159) is unchanged. Verified diff-wise.

### Key Decisions

- **Guard centralization in `_uploadSave`.** The brief said the null/0-byte short-circuit "should ALSO go through the same `byteLength === 0` guard since defensive layering is cheap." I placed the guard once, inside `_uploadSave`, so both call sites inherit it. Alternative would have been to duplicate the check at each call site — single-point guard is simpler and provably equivalent.
- **`EJS_defaultOptions` ordering.** The brief said "before any `EJS_*` global is set." I set it as the second statement in `connect()` (after `await _fetchSave()`), ahead of every other `EJS_*` assignment. This is conservative: even if loader.js evolves to peek at globals at any point during the script-tag load, the auto-save default is already in place.
- **Defensive `if (window.EJS_emulator)` inside `EJS_ready`.** The brief states `EJS_emulator` is guaranteed to exist when `EJS_ready` fires (per loader.js:150–153). The guard is a belt-and-suspenders cost-zero check that also makes the log line's `hasEmulator: false` case actionable if loader.js ever changes.
- **Did NOT touch `_injectExistingSave` body.** The brief's "DO NOT touch `_injectExistingSave`" was honored. Only the call site moved from "commented out" to "inside the new `EJS_ready`."
- **`EJS_onSaveSave` retained.** Lines 68–70 unchanged (the brief required this).

### Self-Review Answers

**1. What would Reviewer most likely flag?**
- Listener-order in `EJS_ready` (covered: lines 80–85; `saveSaveFiles` listener attached BEFORE `_injectExistingSave` call).
- `EJS_defaultOptions` set position (covered: line 40, set before all other `EJS_*` and well before the script tag at line 92).
- Null-byte guard layering (covered: line 165 in `_uploadSave`; both call paths inherit).
- `EJS_onSaveSave` not removed (covered: lines 68–70 unchanged).
- `disconnect()` cleanup of `EJS_defaultOptions` (covered: line 111).
- Scope discipline — one file changed, no backend touched. Verified.

**2. Did every brief item ship?**
- Build Step 1 — `EJS_defaultOptions` set before loader.js boot — YES (line 40).
- Build Step 2 — `_fetchSave()` re-enabled — YES (line 33).
- Build Step 3 — `EJS_ready` registers listener first, then injects, then logs — YES (lines 75–90).
- Build Step 4 — `_uploadSave` null/0-byte guard — YES (line 165).
- Build Step 5 — `disconnect()` clears `EJS_defaultOptions` — YES (line 111).
- Acceptance: log fires with both flags — YES (lines 86–89). 30s interval propagates — YES (line 40). Inject runs when save exists — YES (line 84). Manual button still works — YES (lines 68–70 retained). 0-byte path skipped — YES (line 165). 255/255 tests pass — YES (verified).

**3. What does the user see if any of this data is empty or a request fails?**
- Pre-first-save (player has never saved): `getSaveFile(false)` returns null on every 30s tick → `_uploadSave` short-circuits at line 165, no PATCH, no console error spam.
- `_fetchSave` 204 No Content (no server save yet): returns null cleanly (line 124), `existingSave` is null, no injection runs, log shows `hasExistingSave: false`. Emulator boots from IDBFS or fresh.
- `_fetchSave` network/server failure: `console.error` logs the failure (lines 109/115), returns null, same fallback as 204. Game still loads; user can play and the next save will be the first one to land on the server.
- `_uploadSave` PATCH failure (offline, server 5xx, CSRF expired): `console.error` logs it (lines 180/183). Next 30s tick retries automatically. No user-facing error surfaced (game continues).
- `EJS_emulator` unavailable inside `EJS_ready` (shouldn't happen, but the guard exists): listener registration skipped; the log line shows `hasEmulator: false` so the bug is visible at a glance in the dev console.

### Open Questions for Architect / Project Owner

None. The brief was complete and unambiguous. All Project-Owner decisions were locked in section "Project Owner decisions (locked)" of the brief and were followed verbatim:
- Server source-of-truth on load → `_fetchSave()` re-enabled, `_injectExistingSave` runs in `EJS_ready`.
- 30s default interval → set via `EJS_defaultOptions`.
- `EJS_onSaveSave` kept for manual button → retained, unchanged.
- 0-byte/null saves never PATCH → centralized guard in `_uploadSave`.

### Test Counts

- Baseline before this step: **255 runs, 0 failures** (Step 1's count).
- After this step: **255 runs, 0 failures**. No backend change; no test count delta. Run via `bin/rails test` with Ruby 3.4.5.

### Lint

- No new Ruby. `bin/rubocop` was run (with `PATH` forced to mise's Ruby 3.4.5 install — system Ruby is 3.0.6 and bundler can't satisfy the lockfile under it). Output: 133 pre-existing offenses across 127 files; none in any file I touched (controller is JS, not Ruby).
- No JS linter configured in the project (Importmap, no Node).

### Manual Verification Notes (for Reviewer)

The brief explicitly calls out manual dev-console verification because the project has no JS test scaffolding. When the controller boots in the browser:

1. Console should log exactly one `"Emulator: hooks attached" { hasExistingSave: <bool>, hasEmulator: true }`.
2. Open DevTools → Network. Wait 30 seconds (or trigger an in-game save). A `PATCH /emulator/save_data` should appear with `Content-Length: 524288` (Pokemon Platinum SRAM).
3. Manual EmulatorJS "Save File" button → also produces a PATCH (via the existing `EJS_onSaveSave` path).
4. Hard refresh → game resumes at the last save point (server inject → MEMFS → melonDS reload).
5. Pre-first-save (fresh ROM, no in-game save yet): no PATCH should appear despite the 30s tick — the null/0-byte guard handles it.

### Definition of Done

- [x] `EJS_defaultOptions = { "save-save-interval": "30" }` set before loader.js boot
- [x] `_fetchSave()` re-enabled at top of `connect()`
- [x] `EJS_ready` registers `saveSaveFiles` listener BEFORE calling `_injectExistingSave`
- [x] `EJS_ready` logs `"Emulator: hooks attached"` once with both flags
- [x] `_uploadSave` short-circuits on null and 0-byte payloads
- [x] `_injectExistingSave` body untouched
- [x] `EJS_onSaveSave` retained
- [x] `disconnect()` clears `EJS_defaultOptions`
- [x] One file changed: `app/javascript/controllers/emulator_controller.js`
- [x] No backend change (parser, job, controller, routes untouched)
- [x] 255/255 Rails tests pass
- [x] No new rubocop offenses introduced (133 pre-existing offenses unchanged in the files Reviewer cares about; none in files I touched)

### Known Gaps (deferred, NOT in scope of this step)

- **Multi-device conflict resolution** — single browser per player assumed (brief Out of Scope).
- **Pokemon "communication error" in-game popup** — DS Wireless thing, unrelated (brief Out of Scope).
- **Stimulus controller unit tests** — no JS test scaffolding in project (brief Out of Scope).
- **Server-side parse-on-save** — already handled by `ParseSaveDataJob` from Step 1 (brief Out of Scope).
- **Live-update sidebar on save_data PATCH** — already in BUILD-LOG Known Gaps from prior work.
