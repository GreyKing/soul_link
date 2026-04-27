# Review Feedback — Step 6: Cheat Config + EmulatorJS Cheat Integration
Date: 2026-04-26
Ready for Builder: YES

## Must Fix

None.

## Should Fix

None.

## Escalate to Architect

None.

## Cleared

Reviewed all eight changed files (1 created YAML, 1 created loader test, 6 modified) plus the
two cited EmulatorJS source locations. Re-ran the full suite (`mise exec -- ruby -S bundle exec
rails test`) — 184 runs, 544 assertions, 0 failures, 0 errors, 0 skips — and rubocop on all
six Ruby files (no offenses). All twelve scrutiny points clear:

1. **Memoization shape** matches the existing class-level `@x ||= File.exist?(PATH) ? ...`
   pattern used by `pokedex`, `map_coordinates`, `progression`, `pokemon_types`,
   `pokemon_abilities`, and `evolutions` (`app/services/soul_link/game_state.rb:133-135`).
   Bob added `(YAML.load_file(PATH) || {})` to defend against an empty file parsing to `nil` —
   a minor and correct hardening over the older loaders, justified because `#cheats` consumers
   immediately call `.fetch` on the result. `reload!` resets `@cheats = nil` on line 147, in
   the same block as the other ivars.

2. **Memoization test pollution** is defended on three layers: `setup` nils `@cheats`,
   `teardown` nils `@cheats` AND restores the original `CHEATS_PATH` constant, and
   `with_cheats_path` nils `@cheats` and restores `CHEATS_PATH` in its `ensure` block. Hermetic
   regardless of test order.

3. **`#cheats` model nil-safety** has all four cases covered:
   `test/models/soul_link_emulator_session_test.rb:174` (empty hash → `[]`),
   `:180` (no `action_replay` key → `[]`),
   `:186` (`action_replay: nil` → `[]` via `is_a?(Array)` guard),
   `:192` (array passthrough). The file-absent → `{}` chain is covered separately by the
   GameState loader test at `test/services/soul_link/game_state_cheats_test.rb:43`.

4. **Controller ivar scoping** is correct: `@cheats = @session.cheats if @session&.ready?`
   (`app/controllers/emulator_controller.rb:25`). Non-ready branches leave `@cheats` nil and
   the view never references it on those branches.

5. **View renders the data attribute on ready ONLY**: the attribute lives inside the
   `<% else %>` branch of the six-state ERB (`app/views/emulator/show.html.erb:62`), guarded
   by every preceding `elsif` for the non-ready states. Three tests confirm absence on
   non-ready paths (`test/controllers/emulator_controller_test.rb:177`, `:185`, `:193`).

6. **JSON serialization escapes correctly**: `<%= @cheats.to_json %>` runs through ERB's
   default HTML-safe escaping. Confirmed via Rails runner that `&`, `<`, `>` get JSON-escaped
   to `&`/`<`/`>` and `"` gets HTML-escaped to `&quot;`. Stimulus's `Array`
   value type decodes the attribute back through the HTML and JSON layers cleanly. No
   injection risk on future multi-line AR codes containing shell or HTML metacharacters.

7. **Stimulus filter logic** (`app/javascript/controllers/emulator_controller.js:45-50`):
   `cheatsValue` is declared `Array` with `default: []` (line 21); `connect` filters
   `c && c.enabled !== false && c.name && c.code` (so missing `enabled` passes through, only
   explicit `false` is filtered, plus null-safety on `name`/`code`); maps to `[c.name, c.code]`
   tuples; assigns `window.EJS_cheats = tuples` only when the filtered list is non-empty.
   Empty cheats array is a no-op — matches `Array.isArray` precondition at
   `public/emulatorjs/data/src/emulator.js:311`. `disconnect` clears `EJS_cheats = undefined`
   on line 85.

8. **Tuple format** verified against EmulatorJS source: `loader.js:102` assigns
   `config.cheats = window.EJS_cheats`; `emulator.js:311-323` reads `cheat[0]` as `desc` and
   `cheat[1]` as `code`, pushing `{desc, checked:false, code, is_permanent:true}`. Bob's
   `[c.name, c.code]` mapping matches.

9. **Multi-line YAML block strings** are exercised by the loader test at
   `test/services/soul_link/game_state_cheats_test.rb:72-90`, which writes a `code: |` block,
   reads it back, and asserts both lines survive. Real Tempfile + real Psych parser, so this
   is a true integration check rather than a stub round-trip.

10. **No memoization leakage across test ordering.** The loader test brackets the ivar on
    setup/teardown; the model and controller tests use `SoulLink::GameState.stub(:cheats, ...)`
    which replaces the class method directly rather than touching `@cheats`, so the original
    method (memoized or not) is fully restored on block exit. The Bootsnap-prepend issue that
    defeats `YAML.load_file` stubs does not affect class-method stubs at the GameState level.

11. **No scope creep.** The `cheat_overrides` column is not re-added; no per-player override
    UI; no work in Step 7 cleanup territory. Empty `action_replay: []` placeholder ships as
    instructed — no invented codes.

12. **Definition of Done** — every box independently verified:
    - `config/soul_link/cheats.yml` exists with `action_replay: []` placeholder ✓
    - `SoulLink::GameState.cheats` exists, memoized, returns `{}` if file absent ✓
    - `SoulLinkEmulatorSession#cheats` returns the array (or `[]`) ✓
    - `EmulatorController#show` sets `@cheats` only on `:ready` ✓
    - View renders `data-emulator-cheats-value` only on ready ✓
    - Stimulus has `cheats: Array` value and injects into `EJS_cheats` with verified format ✓
    - GameState loader: 6 tests; model: 4 new tests; controller: 5 new + 1 extended ✓
    - Full suite: 184 runs (169 baseline + 15 new), 0 failures ✓
    - EJS_cheats global + tuple format verified against `loader.js:102` and
      `emulator.js:311-323`, cited in REVIEW-REQUEST ✓

One observation worth recording but not blocking: Bob's "memoization" test counts
`File.exist?` calls (1 across three `cheats` invocations) rather than `YAML.load_file` calls,
because Bootsnap's `Psych4::Patch` defeats the `Module.prepend`-vs-singleton-stub priority
used by `Minitest::Mock`. That's a tight equivalent — `||=` short-circuits the entire ternary
on subsequent calls, so "existence checked once" implies "file loaded at most once" — and
is documented in the test file header. The architect explicitly cleared this approach.

Step 6 is clear.

VERDICT: PASS
