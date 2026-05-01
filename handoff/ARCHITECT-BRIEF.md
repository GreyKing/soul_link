# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 12 — KG-6: Map ID → Name Lookup (SRAM Phase 1 finish)

### Context

The SRAM parser populates `SoulLinkEmulatorSaveSlot#parsed_map_id` (a `uint16`) for active save slots, but no UI surface ever renders it. PROJECT-REVIEW-2026-04-30.md flagged this as KG-6 — "sidebar shows 'Eterna City' instead of `426`". The architect estimated ~1 hour and called it the finish line for SRAM Phase 1's user-visible work.

**Pre-flight scope correction:** during target-file reads I verified that `parsed_map_id` is currently NOT rendered in any view (grep across `app/views/` returns zero hits). It's stored in the DB and exposed via `slot_payload` JSON (`save_slots_controller.rb:127`), but no template displays it. So Step 12 actually does TWO things:
1. Builds the lookup infrastructure (so when an ID flows in, we can name it).
2. Wires the field into the existing run-roster + slot-card surfaces (where the other parsed_* fields already render).

The infrastructure side is straightforward; the UI wire-up should mirror how `parsed_trainer_name` / `parsed_money` / `parsed_play_seconds` / `parsed_badges` are already rendered in `_run_sidebar_card.html.erb` and `_save_slots_sidebar.html.erb`.

**Important caveat (KG-7 dependency):** the `MAP_ID_OFFSET = 0x1234` constant in `SoulLink::SaveParser` is documented as the "least-confident placeholder" — it's never been validated against a real `.sav` file. Until the offset is verified (separate Known Gap KG-7), the integer IDs we'll see in production may not match what's in our `maps.yml`. That's OK — the fallback handles unknown IDs gracefully ("Map #N"). When real-save validation happens, we'll confirm both the offset and the ID-to-name mapping in one pass, and adjust `maps.yml` if needed.

### Project Owner decisions (locked)

- **Auto-accept mode for this work.** Bob can act decisively; Reviewer + tests are the backstop.
- **YAML in `config/soul_link/maps.yml`.** Matches the existing project pattern (`locations.yml`, `gym_info.yml`, etc.). Keep it human-editable; no generated/binary format.
- **`SoulLink::GameState.map_name(map_id)` is the lookup API.** Mirrors the existing `location_name(key)` shape. Returns the name when known, `nil` when not.
- **`EmulatorHelper#format_map_name(map_id)` is the view formatter.** Returns the name for known IDs, `"Map ##{id}"` fallback for unknown IDs (so the player sees a numeric placeholder, not silence — also flags us to extend the YAML), and `nil` for nil input (so views can short-circuit).
- **Render the field on both surfaces** (`_run_sidebar_card.html.erb` and `_save_slots_sidebar.html.erb`). Slot the new line between `Money` and `Badges` to match the chronological "what's the player doing in-game right now" flow.
- **Don't rebuild the YAML from a generated dataset.** Hand-curate ~50 entries covering the Sinnoh region cities + early routes + key story dungeons. When real saves flow in, extend incrementally.
- **The integer IDs in `maps.yml` are best-effort, NOT validated.** Document this explicitly in the YAML's header comment, citing KG-7 as the validation step. The fallback is the safety net.

### Implementation

#### 1. `config/soul_link/maps.yml` (new file)

```yaml
# config/soul_link/maps.yml
#
# Pokemon Platinum map header IDs → human-readable names.
# Loaded by SoulLink::GameState.map_name(id); rendered via
# EmulatorHelper#format_map_name in run-roster + slot-card surfaces.
#
# Source: pret/pokeplatinum disassembly (`include/constants/map.h`)
# header IDs in canonical Sinnoh region order. IDs in this file are
# best-effort and have NOT been validated against a real `.sav` —
# the parser's MAP_ID_OFFSET = 0x1234 is also unvalidated (KG-7).
# Both validations should happen together when a real save is
# available. Until then, unknown IDs surface as "Map #N" via the
# helper's fallback, which is informative enough for v1.
#
# Format: integer ID → { name: "Display Name" }. The hash shape
# leaves room for future fields (e.g. region:, dungeon: bool) without
# breaking the API.

# ── Towns & Cities ──
1:  { name: "Twinleaf Town" }
2:  { name: "Sandgem Town" }
3:  { name: "Floaroma Town" }
4:  { name: "Solaceon Town" }
5:  { name: "Celestic Town" }
6:  { name: "Jubilife City" }
7:  { name: "Oreburgh City" }
8:  { name: "Eterna City" }
9:  { name: "Hearthome City" }
10: { name: "Pastoria City" }
11: { name: "Canalave City" }
12: { name: "Sunyshore City" }
13: { name: "Veilstone City" }
14: { name: "Snowpoint City" }
15: { name: "Pokémon League" }
16: { name: "Fight Area" }
17: { name: "Survival Area" }
18: { name: "Resort Area" }

# ── Routes 201-218 (early-mid game; common in the 4-player
#    soul-link runs the project tracks) ──
30: { name: "Route 201" }
31: { name: "Route 202" }
32: { name: "Route 203" }
33: { name: "Route 204" }
34: { name: "Route 205" }
35: { name: "Route 206" }
36: { name: "Route 207" }
37: { name: "Route 208" }
38: { name: "Route 209" }
39: { name: "Route 210" }
40: { name: "Route 211" }
41: { name: "Route 212" }
42: { name: "Route 213" }
43: { name: "Route 214" }
44: { name: "Route 215" }
45: { name: "Route 216" }
46: { name: "Route 217" }
47: { name: "Route 218" }

# ── Dungeons / story locations (common encounter points) ──
80: { name: "Oreburgh Mine" }
81: { name: "Eterna Forest" }
82: { name: "Old Chateau" }
83: { name: "Mt. Coronet" }
84: { name: "Lost Tower" }
85: { name: "Solaceon Ruins" }
86: { name: "Wayward Cave" }
87: { name: "Iron Island" }
88: { name: "Lake Verity" }
89: { name: "Lake Valor" }
90: { name: "Lake Acuity" }
91: { name: "Spear Pillar" }
92: { name: "Distortion World" }
93: { name: "Stark Mountain" }
94: { name: "Victory Road" }

# ── Indoor / overworld special ──
100: { name: "Pokémon Center" }
101: { name: "Trainers' School" }
```

Notes:
- The integer IDs above are CANONICAL ORDER references from pret/pokeplatinum. Whether the SRAM stores those exact integers vs. a remapped subset depends on offset validation. Either way, the YAML is the source of truth — adjust integers if KG-7 reveals different mappings.
- `Pokémon` (not `Pokemon`) is intentional — the `é` is the canonical brand spelling and matches existing strings elsewhere in the codebase. Make sure the YAML is saved as UTF-8 (it should be by default).

#### 2. `app/services/soul_link/game_state.rb` additions

Add the constant + accessor + reload hook:

```ruby
MAPS_PATH = Rails.root.join('config', 'soul_link', 'maps.yml')

def maps
  @maps ||= File.exist?(MAPS_PATH) ? (YAML.load_file(MAPS_PATH) || {}) : {}
end

# Returns the human-readable name for a map ID, or nil if unknown.
# The caller (typically EmulatorHelper#format_map_name) decides what
# to render for nil — usually a "Map #N" fallback.
def map_name(map_id)
  return nil if map_id.nil?
  maps.dig(map_id.to_i, "name")
end
```

Update `reload!` to clear the maps cache:
```ruby
def reload!
  @gym_info = nil
  @locations = nil
  @settings = nil
  @pokedex = nil
  @maps = nil          # ← new
  @map_coordinates = nil
  @progression = nil
  @pokemon_types = nil
  @pokemon_abilities = nil
  @evolutions = nil
  @cheats = nil
end
```

Place the new methods between `location_name` and `players` (groups thematically with location lookup, NOT with `map_coordinates` which is the dashboard map's pixel-coordinates dataset — different concern despite the similar name).

#### 3. `app/helpers/emulator_helper.rb` additions

Add the formatter alongside `format_play_time`:

```ruby
# Formats a Pokemon Platinum map header ID as a human-readable name
# for the run-roster + slot-card surfaces. Returns nil for nil input
# (callers should gate on this with `if format_map_name(...).present?`),
# the canonical name when SoulLink::GameState knows the ID, or a
# "Map ##{id}" fallback when not — informative enough for v1, and
# also a signal to extend config/soul_link/maps.yml as new IDs are
# observed in real saves.
def format_map_name(map_id)
  return nil if map_id.nil?
  SoulLink::GameState.map_name(map_id) || "Map ##{map_id}"
end
```

#### 4. View edits

**`app/views/emulator/_run_sidebar_card.html.erb`** — between the Money block and the Badges block:

```erb
<% if active_slot&.parsed_map_id %>
  <div style="font-size: 10px; color: var(--d2); line-height: 1.6;">
    Map: <%= format_map_name(active_slot.parsed_map_id) %>
  </div>
<% end %>
```

Place this after the existing `parsed_money` block (around line 75-79) and before the `parsed_trainer_name` gate that wraps the badges line.

**`app/views/emulator/_save_slots_sidebar.html.erb`** — between Money (~line 83-87) and Badges (~89-93):

```erb
<% if slot.parsed_map_id %>
  <div style="font-size: 10px; color: var(--d2); line-height: 1.6;">
    Map: <%= format_map_name(slot.parsed_map_id) %>
  </div>
<% end %>
```

Same gate semantic: render only when a non-nil parsed_map_id exists. Today this means the line never renders (parser returns nil from `safe_map_id` whenever the byte is 0, which is everything until KG-7 validates the offset). When a real save flows through, the line lights up.

#### 5. Tests

**Add `test/services/soul_link/game_state_maps_test.rb`** (new file). Mirrors the test setup of `game_state_cheats_test.rb` (write a temp yaml, point GameState's MAPS_PATH at it, hermetic setup/teardown). Cover:

- `map_name(id)` returns the canonical name for a known ID (use a known entry from the seeded yaml — e.g., `8` → `"Eterna City"`).
- `map_name(id)` returns `nil` for an ID that's not in the file.
- `map_name(nil)` returns `nil` (no exceptions).
- `map_name("8")` returns `"Eterna City"` (string→int coercion via `.to_i`).
- `maps` returns `{}` if the file is missing.

The test setup pattern from cheats:
```ruby
setup do
  SoulLink::GameState.instance_variable_set(:@maps, nil)
  @real_maps_path = SoulLink::GameState::MAPS_PATH
end

teardown do
  SoulLink::GameState.instance_variable_set(:@maps, nil)
  if @real_maps_path && SoulLink::GameState::MAPS_PATH != @real_maps_path
    SoulLink::GameState.send(:remove_const, :MAPS_PATH)
    SoulLink::GameState.const_set(:MAPS_PATH, @real_maps_path)
  end
end
```

Each test writes a small YAML fixture with `Tempfile.create(["maps", ".yml"])` and re-`const_set`s `MAPS_PATH` to the temp path. Read `game_state_cheats_test.rb` for the exact pattern; use it.

**Add `test/helpers/emulator_helper_test.rb`** (new file). Cover:

- `format_play_time(...)` — port the existing inline doc-comment examples to real test cases. (5 tests: nil, 0, 3660, 45_780, negative-clamps-to-zero.)
- `format_map_name(nil)` returns `nil`.
- `format_map_name(known_id)` — stub `SoulLink::GameState.map_name` to return `"Eterna City"`, assert.
- `format_map_name(unknown_id)` — stub `SoulLink::GameState.map_name` to return `nil`, assert `"Map #99999"` is returned.

Use Minitest's `Minitest::Mock` or just the `stub` pattern (`SoulLink::GameState.stub(:map_name, "Eterna City") { ... }`). The stub pattern is cleaner and matches what `emulator_controller_test.rb` already uses for `GameState.cheats`.

**Test count delta:** +5 (game_state_maps) + ~7 (emulator_helper, including the play_time backfill) ≈ 318 → ~330. Bob has discretion on the exact count.

### Out of Scope (do NOT expand)

- Changing `MAP_ID_OFFSET` in `SaveParser` or any parser-side validation (KG-7 territory; needs a real `.sav`).
- Backfilling `parsed_map_id` for existing slots — the parse job's normal flow handles future saves; old slots just have nil and the UI omits the line.
- A rake task to list "unknown map IDs we've seen in production" — would be useful for iterating maps.yml, but adds scope. Future polish.
- Discord bot rendering of map names (the bot uses Discord embeds, separate UX surface).
- Refactoring `EmulatorHelper` beyond adding `format_map_name`.
- Touching `_save_slots_sidebar.html.erb`'s slot-card structure beyond the new line.
- Tier-1 refactors (god-object decomp, presenter extraction). Fresh-session candidates.
- Adding region grouping or dungeon flags to maps.yml — keep `{ name: "..." }` minimal.
- Validation that `map_name` always returns a string (the helper handles the `nil` case explicitly).

### Constraints / Flags

- **Sequence the work**: `maps.yml` first → GameState methods → helper method → view edits (only after the helper exists, so the view doesn't error mid-edit) → tests last.
- **318/318 must still pass** after all edits. New tests bring the count up.
- **Rubocop must stay clean** (Step 11's end state: 0 offenses, 145 files). New helper methods follow existing style.
- **Don't introduce new YAML schema patterns** — the `{name: "..."}` hash shape matches existing files. If Bob feels tempted to use a flat `id: name` form, don't — the hash leaves room for `region:` or `dungeon: bool` later without breaking callers.
- **The `Pokémon` accent character matters.** The existing strings in the codebase use the accented form; `maps.yml` should too. Save as UTF-8.
- **Don't ship without the safety belt comment** in `maps.yml`. The header should explicitly note the IDs need real-save validation alongside KG-7.
- **Helper fallback string is `"Map ##{id}"`** — short, clear, matches the codebase's brevity. NOT `"Unknown map (##{id})"` (verbose) or just `"##{id}"` (ambiguous).

### Acceptance Criteria

- New file `config/soul_link/maps.yml` with header comment + ~50 seed entries.
- New `SoulLink::GameState.map_name(id)` method + `MAPS_PATH` constant + `maps` accessor + `reload!` hook for `@maps`.
- New `EmulatorHelper#format_map_name(map_id)` method.
- View additions in `_run_sidebar_card.html.erb` and `_save_slots_sidebar.html.erb`, gated on `parsed_map_id.present?`.
- New tests in `test/services/soul_link/game_state_maps_test.rb` and `test/helpers/emulator_helper_test.rb`.
- Full suite green (318 → 318+N where N ≈ 12).
- `bundle exec rubocop` clean (0 offenses).
- Manual smoke test (Bob): `Rails.console` → `SoulLink::GameState.map_name(8)` returns `"Eterna City"`; `format_map_name(99999)` returns `"Map #99999"`; `format_map_name(nil)` returns `nil`.
- Diff scope: 1 new YAML, 1 model edit (game_state), 1 helper edit, 2 view edits, 2 new test files, 4 handoff files. Anything else is a Reviewer Condition.

### Files Bob Should Read

- `app/services/soul_link/game_state.rb` (entire — small)
- `test/services/soul_link/game_state_cheats_test.rb` (test pattern reference)
- `app/helpers/emulator_helper.rb` (existing; small)
- `app/views/emulator/_run_sidebar_card.html.erb` (where to add the new line)
- `app/views/emulator/_save_slots_sidebar.html.erb` (where to add the same line)
- `config/soul_link/locations.yml` (yaml comment style + structure reference — first 20 lines)
- `app/services/soul_link/save_parser.rb` lines 240-264 (`safe_map_id` is the source of `parsed_map_id`; understand that 0 → nil)

DO NOT load app/controllers, channels, or other models — no business-logic changes.

### Files Bob Should Update at the End

- `handoff/REVIEW-REQUEST.md` — files-changed table, self-review answers, open questions, `Ready for Review: YES`
- `handoff/BUILD-LOG.md` — Step 12 history entry. **Update Known Gaps**: KG-6 closed (move to Closed section). KG-7 (real-save offset verification) STILL OPEN — note that map IDs in `maps.yml` are also pending validation alongside it.

---

## Notes for Reviewer

When this lands on your desk, focus on:

1. **`maps.yml` header comment is present and explicit.** It must say IDs are unvalidated and tie that to KG-7. Without this comment, future readers will assume the IDs are correct.

2. **The hash shape `{ name: "..." }` is preserved consistently** across all entries. No flat `id: "Twinleaf Town"` style; that closes off future extension.

3. **`map_name(map_id)` handles string + integer + nil inputs.** The `.to_i` coercion is there for cases where the param comes from JSON/params (string). nil short-circuits without an exception.

4. **`format_map_name` fallback is `"Map #N"` exactly, not a variant.** Don't accept "Unknown #N" or "Map ID N" — the brief specifies the precise string for consistency.

5. **Both view surfaces render the field.** Manually inspect `_run_sidebar_card.html.erb` and `_save_slots_sidebar.html.erb` — the new line is placed between Money and Badges in both, with the same `parsed_map_id.present?` (or `&.parsed_map_id`) gate.

6. **`reload!` clears `@maps`.** Without this, calling `GameState.reload!` would leave stale map data in memory if the YAML was edited. Verify in the diff.

7. **Tests cover the empty-file case.** If `MAPS_PATH` doesn't exist (e.g., a hypothetical fork without the YAML), `maps` should return `{}` and `map_name` should return `nil` — never crash.

8. **No regression on `SaveParser` or the parse job.** They write `parsed_map_id` from the SRAM byte; that flow doesn't touch any of the new code. Run the parser test file independently to confirm.

9. **No regression on Step 9 broadcasts.** The roster card partial gained one new line; `data-discord-user-id` stays on the outer card div; Step 9's broadcast tests should pass without modification.

10. **Rubocop stays at 0 offenses across 145 files.** New code follows existing style; the new test files don't introduce any new violations.

Out-of-scope items found during review → BUILD-LOG Known Gaps. Do not bundle.
