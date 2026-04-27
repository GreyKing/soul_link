# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 6 — Cheat Config + EmulatorJS Cheat Integration

Context: Steps 1–5 ship a working single-player emulator. This step adds Action Replay cheat support: a YAML config of cheats (loaded once per app boot via `SoulLink::GameState`), exposed through the model and controller, injected into EmulatorJS via the appropriate global. Cheats are **global** (same set for every player) — the Step 1 `cheat_overrides` column was dropped, so per-player customization is a future Known Gap.

### Files to Create

- `config/soul_link/cheats.yml`
- `test/services/soul_link/game_state_cheats_test.rb` (or extend an existing `game_state_test.rb` if there is one — check)

### Files to Modify

- `app/services/soul_link/game_state.rb` — add a `cheats` class method that loads `config/soul_link/cheats.yml` (memoized, like the other YAML loaders). Return `{}` if the file is absent.
- `app/models/soul_link_emulator_session.rb` — add `#cheats` method that returns the array of cheats from `SoulLink::GameState.cheats`. Returns `[]` if no config or no cheats loaded.
- `app/controllers/emulator_controller.rb` — set `@cheats = @session.cheats` in `show`, only when state is `:ready` (or pass it always — your call, but not in test-state branches that don't render the emulator).
- `app/views/emulator/show.html.erb` — add a `data-emulator-cheats-value="<%= @cheats.to_json %>"` attribute on the emulator-stage div in the `:ready` branch only.
- `app/javascript/controllers/emulator_controller.js` — add `cheats: Array` to `static values`, and inject them into EmulatorJS via the appropriate global (the brief assumes `EJS_cheats` but **Bob verifies** against `public/emulatorjs/docs/`).
- `test/models/soul_link_emulator_session_test.rb` — extend with cheats test
- `test/controllers/emulator_controller_test.rb` — extend with cheats test (ready-state ivar populated)

### YAML — `config/soul_link/cheats.yml`

```yaml
# Action Replay codes for Pokemon Platinum (Gen IV NDS).
# Each entry has a name, the AR code (multi-line string), and an enabled flag.
# When enabled: true, the cheat is preloaded in EmulatorJS and toggleable in
# the in-game cheat menu. When false, it doesn't appear at all.
#
# Real cheat codes go here — currently empty placeholder so the loader works.

action_replay: []
```

**Project Owner will populate this manually with real codes after Step 6 ships.** Do NOT invent example codes — invented codes that look plausible but don't work would be worse than an empty list.

### `SoulLink::GameState.cheats` Spec

Mirror the existing class-method pattern (`gym_info`, `players`, etc.):

```ruby
CHEATS_PATH = Rails.root.join("config", "soul_link", "cheats.yml")

class << self
  # ... existing methods ...

  def cheats
    @cheats ||= load_cheats
  end

  private

  def load_cheats
    return {} unless File.exist?(CHEATS_PATH)
    YAML.load_file(CHEATS_PATH) || {}
  end
end
```

If the existing `SoulLink::GameState` doesn't use the class-method/memoized-by-instance-var pattern, match what IS there. Don't introduce a new style.

### `SoulLinkEmulatorSession#cheats` Spec

```ruby
def cheats
  list = SoulLink::GameState.cheats.fetch("action_replay", [])
  return [] unless list.is_a?(Array)
  # Pass through everything — let EmulatorJS toggle based on `enabled`.
  list
end
```

Returns the raw array of cheat hashes. JS layer renders/enables.

### Controller Update

In `EmulatorController#show`, set `@cheats = @session.cheats` ONLY when the state is `:ready` (i.e., `@session.present? && @session.ready?`). Other branches don't need it.

### View Update

In the `:ready` branch only, add to the emulator-stage div:
```erb
data-emulator-cheats-value="<%= @cheats.to_json %>"
```

(Stimulus auto-decodes JSON for `Array` value types; passing the string is fine.)

### Stimulus Update

```js
static values = {
  // existing values ...
  cheats: { type: Array, default: [] }
}

async connect() {
  // ... existing setup ...
  if (this.cheatsValue.length > 0) {
    // Bob: verify EJS_cheats is the correct global. Look at the EmulatorJS docs
    // bundled in public/emulatorjs/docs/ (or its API JSON under data/) for the
    // exact format. Common shape: array of [name, code] tuples or {name, code}
    // objects. Adjust the mapping accordingly.
    window.EJS_cheats = this.cheatsValue.map(c => [c.name, c.code])
  }
  // ... rest of connect ...
}
```

**The brief's mapping (`[name, code]` tuples) is a guess.** If EmulatorJS expects `[{name, code}]` or some other shape, use what's documented. Don't ship code that fails silently.

### Tests

Use FactoryBot.

#### `SoulLink::GameState.cheats`
- Returns `{}` when file is absent (stub `File.exist?` to false)
- Returns the parsed hash when the file exists (stub `YAML.load_file` to return a fixture hash)
- Memoizes — second call doesn't re-read the file (assert `YAML.load_file` called once across two calls)

#### `SoulLinkEmulatorSession#cheats`
- Returns `[]` when GameState has no cheats
- Returns `[]` when GameState has no `action_replay` key
- Returns the array when GameState has `action_replay` with entries
- Stub `SoulLink::GameState.cheats` to return controlled values per test

#### `EmulatorController` (extension to existing test file)
- `@cheats` ivar is populated when state is `:ready`
- View renders the data attribute when ready (assert response body contains `data-emulator-cheats-value=`)
- View does NOT render the data attribute in non-ready states

### Build Order

1. Read existing `app/services/soul_link/game_state.rb` to confirm the loader pattern.
2. Create `config/soul_link/cheats.yml` with the empty placeholder.
3. Add `cheats` to `SoulLink::GameState`.
4. Add `#cheats` to `SoulLinkEmulatorSession`.
5. Update `EmulatorController#show` to set `@cheats` on ready.
6. Update the view's `:ready` branch with the data attribute.
7. Read `public/emulatorjs/docs/` and `public/emulatorjs/data/src/` for the actual `EJS_cheats` API. Confirm format. If it differs from the brief's guess, use what's correct.
8. Update Stimulus controller with the `cheats` value type and the EJS injection.
9. Write/extend tests. Run targeted test files. Iterate to green.
10. Run full suite: `mise exec -- ruby -S bundle exec rails test`. Confirm 169 + new tests, 0 failures.

### Flags

- Flag: **Don't invent example AR codes.** Empty `action_replay: []` is the right default; user populates with real codes.
- Flag: **Cheats are global, not per-player.** No per-player override mechanism in this step. The dropped `cheat_overrides` column stays dropped.
- Flag: **EJS_cheats format is unverified in the brief.** Read EmulatorJS source/docs and confirm before committing the JS. If format differs, use what's correct.
- Flag: **YAML may contain multi-line code strings** (AR codes are often `02000000 12345678\n02000004 ABCDEF01`). Use YAML's `|` pipe block for them. The current placeholder is empty, but the loader must handle multi-line strings cleanly when the user populates them.
- Flag: **`SoulLink::GameState.cheats` is memoized by class instance variable** — same pattern as `gym_info` etc. In test, you may need to reset the ivar between tests (`SoulLink::GameState.instance_variable_set(:@cheats, nil)` in setup) if memoization causes pollution. Look at how existing tests for `SoulLink::GameState` handle this.
- Flag: **Use FactoryBot.**
- Flag: **No new gems, no new YAML libraries** — `YAML.load_file` from stdlib only.
- Flag: All Rails commands prefixed `mise exec -- ruby -S bundle exec`.
- Flag: Do NOT commit. Architect commits.

### Definition of Done

- [ ] `config/soul_link/cheats.yml` exists with `action_replay: []` placeholder
- [ ] `SoulLink::GameState.cheats` exists, memoized, returns `{}` if file absent
- [ ] `SoulLinkEmulatorSession#cheats` returns the array (or `[]`)
- [ ] `EmulatorController#show` sets `@cheats` on `:ready` state
- [ ] View renders `data-emulator-cheats-value` data attribute on ready state only
- [ ] Stimulus controller has `cheats: Array` value type and injects into `EJS_cheats` (or correct global) with the verified format
- [ ] Tests cover GameState loader (3+ cases), model `#cheats` (3+ cases), controller ivar + view rendering
- [ ] Full suite: 169 baseline + new tests, 0 failures
- [ ] EmulatorJS cheat global name + format verified against `public/emulatorjs/docs/` or source — REVIEW-REQUEST cites the verification source

---

## Builder Plan
*Builder adds their plan here before building. Architect reviews and approves.*

1. Verified `EJS_cheats` API in `public/emulatorjs/data/loader.js:102` (`config.cheats = window.EJS_cheats`) and `public/emulatorjs/data/src/emulator.js:311-323` — accepts an array of `[desc, code]` tuples; each becomes `{desc, checked:false, code, is_permanent:true}`. Default is OFF; user toggles in cheat menu. The brief's `[name, code]` tuple guess is correct. The `enabled` YAML key is informational only — EmulatorJS always loads cheats as `checked:false`. We keep `enabled` in YAML so the user can suppress entries (we filter `enabled:false` out before mapping).
2. Match `SoulLink::GameState` style: class-method + `@cheats ||=` ivar + entry in `reload!`. Loader returns `{}` if file missing.
3. `SoulLinkEmulatorSession#cheats`: read `action_replay`, return `[]` if not an Array; pass through hashes.
4. Controller: `@cheats = @session.cheats` only on `:ready` branch (after the existing nil/state checks). View: add `data-emulator-cheats-value="<%= @cheats.to_json %>"` to the existing `:ready` div.
5. Stimulus: add `cheats: { type: Array, default: [] }`; in `connect`, before injecting loader.js, if `cheatsValue.length > 0` set `window.EJS_cheats = this.cheatsValue.filter(c => c.enabled !== false).map(c => [c.name, c.code])`. Add `window.EJS_cheats = undefined` to `disconnect`. Tests: GameState (file-absent / file-present / memoized), model (`{}` / no `action_replay` / array passthrough), controller (`@cheats` populated on ready / data attr present on ready / data attr absent in non-ready). Reset `@cheats` ivar in setup to avoid memoization pollution across tests.
