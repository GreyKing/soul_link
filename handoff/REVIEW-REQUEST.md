# Review Request — Step 6: Cheat Config + EmulatorJS Cheat Integration

**Author:** Bob (Builder)
**Date:** 2026-04-26
**Ready for Review:** YES

---

## Summary

Adds Action Replay cheat support to the player-facing emulator. New YAML config is loaded once per app boot via `SoulLink::GameState`, surfaced through `SoulLinkEmulatorSession#cheats`, threaded through `EmulatorController#show` only on the `:ready` branch, rendered as a `data-emulator-cheats-value` attribute on the emulator stage div, and injected into EmulatorJS via `window.EJS_cheats` by the Stimulus controller. Cheats are global (no per-player override) — the dropped `cheat_overrides` column stays dropped.

The shipped `config/soul_link/cheats.yml` is `action_replay: []` (empty placeholder). User populates real codes manually after this step ships. **No example codes invented.**

Full suite: **184 runs, 544 assertions, 0 failures, 0 errors, 0 skips** (15 new — 6 GameState loader + 4 model + 5 controller). Rubocop clean on all touched files.

---

## EmulatorJS Cheat-API Verification

The brief flagged `window.EJS_cheats` and the tuple format as guesses. Verified against the bundled EmulatorJS v4.2.3 source:

- **Global name:** `window.EJS_cheats` is read by loader.js and assigned to `config.cheats` — see `public/emulatorjs/data/loader.js:102`:
  ```js
  config.cheats = window.EJS_cheats;
  ```
- **Format:** Array of `[desc, code]` tuples. Each tuple is consumed in `public/emulatorjs/data/src/emulator.js:311-323`:
  ```js
  if (Array.isArray(this.config.cheats)) {
      for (let i = 0; i < this.config.cheats.length; i++) {
          const cheat = this.config.cheats[i];
          if (Array.isArray(cheat) && cheat[0] && cheat[1]) {
              this.cheats.push({
                  desc: cheat[0],
                  checked: false,
                  code: cheat[1],
                  is_permanent: true
              })
          }
      }
  }
  ```
- **Default-enabled behavior:** EmulatorJS always loads cheats with `checked: false` (disabled). The player toggles them via the in-game cheat menu. The YAML's `enabled` flag is therefore informational at the EmulatorJS layer — it cannot pre-check a cheat. We honor it at the Stimulus layer by **filtering out** entries with `enabled: false` before passing the tuple list, so disabled cheats don't appear in the menu at all. Entries with no explicit `enabled` (or `enabled: true`) are passed through.

The brief's tuple-format guess was correct. Conclusion: ship `[name, code]` tuples to `window.EJS_cheats`.

---

## Files Changed

### Created

| File | Purpose |
|------|---------|
| `config/soul_link/cheats.yml` | Empty `action_replay: []` placeholder + comment describing entry shape |
| `test/services/soul_link/game_state_cheats_test.rb` | 6 tests for the loader (file absent, parse, multi-line code, memoization, empty file → `{}`, `reload!`) |

### Modified

| File | Lines | Change |
|------|-------|--------|
| `app/services/soul_link/game_state.rb` | 13 (new const), 131-135 (new `cheats` method), 137-148 (`reload!` includes `@cheats = nil`) | Added `CHEATS_PATH` constant, `cheats` class method matching the existing inline `@x ||= ...` style, and `@cheats = nil` reset in `reload!` |
| `app/models/soul_link_emulator_session.rb` | 28-37 | Added `#cheats` instance method that returns `SoulLink::GameState.cheats.fetch("action_replay", [])`, with `[]` fallback when the key is absent or non-Array |
| `app/controllers/emulator_controller.rb` | 21-26 | `@cheats = @session.cheats if @session&.ready?` — populated only on the `:ready` branch |
| `app/views/emulator/show.html.erb` | 61 | `data-emulator-cheats-value="<%= @cheats.to_json %>"` on the existing `:ready` emulator-stage div |
| `app/javascript/controllers/emulator_controller.js` | 21 (values), 38-50 (EJS injection), 85 (disconnect cleanup) | Added `cheats: { type: Array, default: [] }` static value, EJS_cheats global injection (filtered by `enabled !== false`, mapped to `[name, code]` tuples, only set when the resulting list is non-empty), and `window.EJS_cheats = undefined` in disconnect |
| `test/models/soul_link_emulator_session_test.rb` | 168-204 | 4 new tests covering empty GameState, missing `action_replay` key, non-Array `action_replay`, and array passthrough |
| `test/controllers/emulator_controller_test.rb` | 144 (assertion added to existing test), 148-200 (5 new tests) | Existing ready-state test now asserts the data attribute is present; new tests cover empty cheats, populated cheats payload, and three non-ready states (no active run, generating, failed) — each asserting the data attribute is absent |

### Deleted

None.

---

## Key Decisions

1. **`enabled: false` filtered in Stimulus, not in the model.** EmulatorJS hard-codes `checked: false` regardless of input, so the YAML's `enabled` flag has no power at the EmulatorJS layer. Filtering at the JS boundary keeps the model dumb (passes everything through) and lets the user disable a cheat by editing one YAML line — the entry simply doesn't make it to the in-game menu. Documented inline above the filter logic.
2. **`@cheats` populated only on `:ready` branch in the controller.** Other branches don't render the emulator stage, so the ivar isn't needed. This matches the brief and avoids a needless `nil.to_json` on the unused branches (which would render as `"null"` in the data attribute).
3. **Test isolation: real Tempfiles, not stubs, for the loader test.** Bootsnap monkeypatches Psych via `Module.prepend` (`Bootsnap::CompileCache::YAML::Psych4::Patch`), which sits ahead of `Minitest::Mock.stub`'s singleton-class override — `YAML.stub(:load_file, ...)` does not actually replace the call path. Worked around by writing real YAML to a Tempfile, redefining `SoulLink::GameState::CHEATS_PATH` to point at it via `remove_const` + `const_set`, and restoring on teardown. This is **hermetic** (no shared state, no real-cheats.yml dependency) and exercises the actual YAML parser, which catches multi-line block-string handling for free. The discovery is captured as a comment at the top of the test file.
4. **`File.exist?`-call counting for the memoization test.** Since we can't stub `YAML.load_file` cleanly through Bootsnap, the memoization test stubs `File.exist?` (which is unpatched) and asserts the existence check fires exactly once across three `cheats` calls. The `||=` operator short-circuits the entire ternary on subsequent calls, so this is a tight equivalent of "the file was loaded once."
5. **`reload!` test added** — the brief didn't explicitly require it, but the `cheats` line was added to `reload!` and a regression there would silently break dev workflows that rely on `reload!` to pick up YAML edits. Cheap to cover.

---

## Test Results

```
$ mise exec -- ruby -S bundle exec rails test
Running 184 tests in parallel using 10 processes
184 runs, 544 assertions, 0 failures, 0 errors, 0 skips
```

Targeted breakdown:
- `test/services/soul_link/game_state_cheats_test.rb` — 6 runs / 15 assertions / 0 failures
- `test/models/soul_link_emulator_session_test.rb` — 19 runs (4 new) / 35 assertions / 0 failures
- `test/controllers/emulator_controller_test.rb` — 29 runs (5 new + 1 extended) / 112 assertions / 0 failures

Rubocop:
```
$ bundle exec rubocop app/services/soul_link/game_state.rb \
                     app/models/soul_link_emulator_session.rb \
                     app/controllers/emulator_controller.rb \
                     test/services/soul_link/game_state_cheats_test.rb \
                     test/models/soul_link_emulator_session_test.rb \
                     test/controllers/emulator_controller_test.rb
6 files inspected, no offenses detected
```

---

## Open Questions

None blocking. One observation worth noting:

- **No automated browser test for the EJS_cheats handoff.** Same constraint as Steps 4 and 5 — Bob can't drive a real browser. The Stimulus side is exercised by the controller/view assertions (data attribute present + value contents), and the EmulatorJS side has been traced through loader.js → emulator.js. Recommend the user spot-check by populating one real AR code in `config/soul_link/cheats.yml`, hitting `/emulator`, and confirming the cheat appears (toggleable, defaulting to off) in the EmulatorJS in-game cheat menu.

---

## Smoke Test Checklist (for User after merge)

1. Add a real AR code to `config/soul_link/cheats.yml`, e.g.:
   ```yaml
   action_replay:
     - name: "Walk Through Walls"
       enabled: true
       code: |
         02000000 12345678
         02000004 ABCDEF01
   ```
2. Restart the Rails server (loader memoizes — `bin/dev` reload won't pick up YAML changes).
3. Visit `/emulator`. Open browser devtools console. Run `window.EJS_cheats` — should print the tuple array.
4. In the EmulatorJS UI, open the cheat menu (gear icon → Cheats). The cheat should appear, default unchecked. Toggle it on; the cheat should activate in-game.
5. Set `enabled: false` on the cheat in YAML, restart the server, refresh `/emulator`. The cheat should no longer appear in the cheat menu.

---

**Ready for Review: YES**
