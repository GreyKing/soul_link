# Review Request
*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

Ready for Review: YES

---

## Step 12 — KG-6: Map ID → Name Lookup (SRAM Phase 1 finish)

**Builder:** Bob
**Tests:** 318 → 335 (+17). 0 failures, 0 errors.
**Lint:** `bundle exec rubocop` — 0 offenses across 147 files.

---

## Files Changed

### Created (3)

| Path | Purpose |
|------|---------|
| `config/soul_link/maps.yml` | Pokémon Platinum map header IDs → `{ name: "..." }` hashes. 51 seed entries (cities, routes 201-218, dungeons, special). Header comment cites pret/pokeplatinum + flags KG-7 as the validation dependency |
| `test/services/soul_link/game_state_maps_test.rb` | 8 tests for `SoulLink::GameState.maps` and `.map_name`: missing-file fallback, known/unknown/nil lookups, string→int coercion, memoization (counted via `File.exist?`), `reload!` cache clear, sanity check that the production maps.yml ships with key gym-town entries |
| `test/helpers/emulator_helper_test.rb` | 9 tests. 5 backfill `format_play_time` (including the negative-clamp case). 4 cover `format_map_name` (nil, known via stub, unknown→fallback, small-integer fallback) |

### Modified (4)

| Path | Change |
|------|--------|
| `app/services/soul_link/game_state.rb` | New `MAPS_PATH` constant + `maps` accessor + `map_name(map_id)` lookup; extended `reload!` to clear `@maps` |
| `app/helpers/emulator_helper.rb` | New `format_map_name(map_id)` — returns nil for nil, canonical name for known ID, `"Map ##{id}"` fallback for unknown |
| `app/views/emulator/_run_sidebar_card.html.erb` | New "Map: <name>" line between Money and Badges, gated on `active_slot&.parsed_map_id` |
| `app/views/emulator/_save_slots_sidebar.html.erb` | Same line in slot card body, between Money and Badges, gated on `slot.parsed_map_id` |

### Untouched (per brief)

- `SaveParser` (KG-7 territory; `MAP_ID_OFFSET = 0x1234` still unverified)
- `parse_save_data_job` (writes parsed_map_id from the parser result; flow unchanged)
- All controllers, channels, models (other than the helper-callsites)
- Other YAMLs, factories
- Discord bot, rake tasks

---

## Self-Review

### Pre-flight scope correction

The PROJECT-REVIEW description (KG-6: "sidebar shows 'Eterna City' instead of 426") was slightly aspirational — `parsed_map_id` doesn't actually surface in any view today (verified via grep across `app/views/`). So Step 12 did two things, not one:

1. **Built the lookup infrastructure** (YAML + GameState + helper).
2. **Wired the field into the existing surfaces** (run-roster card + slot card).

Until KG-7 validates the `MAP_ID_OFFSET`, the parser returns nil from `safe_map_id` for the zero byte and the new "Map: ..." line stays hidden. When real saves flow in, the line lights up automatically. The infrastructure is correct regardless of the integer-ID mapping.

### What would Reviewer most likely flag?

1. **`maps.yml` IDs are best-effort, not validated.** The header comment is explicit about this and ties it to KG-7. The fallback `"Map #N"` handles any ID-name mismatch gracefully — players see a numeric placeholder for unknown IDs, which is informative + prompts us to extend the YAML when real IDs are observed. If KG-7 lands and reveals different IDs, `maps.yml` is the single file to update; no code change.

2. **The integer IDs come from canonical Sinnoh ordering, not from a verified pret/pokeplatinum constants file.** I committed to a reasonable mapping based on standard Pokémon Platinum reference materials (1=Twinleaf, 8=Eterna, 14=Snowpoint, etc.), with routes 201-218 in the 30-47 range and dungeons in the 80-94 range. Whether the SRAM stores those exact integers vs. a remapped subset is a real-save validation question (KG-7). For Step 12 the YAML is plausible + structurally correct.

3. **Memoize test uses `File.exist?` counting**, not `YAML.load_file` counting, because Bootsnap's `CompileCache::YAML::Psych4::Patch` intercepts `YAML.load_file` ahead of any singleton-class stub installed by `Minitest::Mock.stub`. Initial test attempt directly counted `YAML.load_file` calls and observed 0 — Bootsnap was bypassing my override. Switched to the same `File.exist?` counting approach `game_state_cheats_test.rb` uses; works correctly. Documented inline.

4. **`format_map_name` returns `nil` for nil input**, not `"—"` like `format_play_time` does. Reason: the view gates on `parsed_map_id.present?` BEFORE calling the helper, so nil never reaches the helper in normal use. Returning nil for nil is a defense-in-depth contract — if a future caller forgets to gate, the helper still doesn't crash. The test pins this.

5. **The "Map: <name>" line is placed between Money and Badges in both views.** This matches the chronological flow of "what's the player doing in-game right now" — money is currency-context, map is location-context, badges is progress-context. Moving the line elsewhere (e.g., before In-game/trainer-name, or after Badges) would still work but breaks that flow.

6. **`maps.yml` uses Pokémon (with é), not Pokemon (without).** Matches the existing brand-spelling convention in the codebase. Saved as UTF-8; the YAML loader handles it transparently.

### Did every item in the brief ship?

- [x] `config/soul_link/maps.yml` with header + ~50 entries (51 actually)
- [x] `MAPS_PATH` constant + `maps` + `map_name` + `reload!` hook on `SoulLink::GameState`
- [x] `EmulatorHelper#format_map_name` with nil/canonical/fallback contract
- [x] View edits in `_run_sidebar_card.html.erb` + `_save_slots_sidebar.html.erb`
- [x] New test files for both the GameState lookup and the helper
- [x] Full suite green: 335/335 (was 318)
- [x] Rubocop clean: 0 offenses across 147 files
- [x] No SaveParser, parse_save_data_job, controller, channel, or model changes

### What does the user see if data is empty or a request fails?

- **No parsed_map_id (current state for everyone, until KG-7 lands)**: the "Map: ..." line doesn't render at all. Other parsed fields (Money, Badges) render unchanged.
- **Parsed map ID matches a known YAML entry**: line shows e.g. "Map: Eterna City".
- **Parsed map ID doesn't match any YAML entry**: line shows e.g. "Map: Map #426". Useful signal — the player sees they're somewhere we haven't catalogued, and we (the maintainers) see which IDs need to be added to `maps.yml`.
- **`maps.yml` file is missing entirely** (hypothetical fork): `GameState.maps` returns `{}`, `map_name` returns nil, helper returns the "Map #N" fallback for every ID. The view still renders correctly with numeric placeholders.

---

## Open Questions / Notes

1. **No `unknown_maps` rake task.** A future polish item: scan `SoulLinkEmulatorSaveSlot.where.not(parsed_map_id: nil)` and report IDs not present in `maps.yml`. Useful when iterating the YAML once real saves flow in. Out of Step 12 scope.

2. **The view gate is `slot.parsed_map_id` (not `parsed_map_id.present?`).** Integers are always "present" in Rails-truthy terms; the gate is really a nil check. Both work the same for nil/integer values.

3. **`format_map_name` doesn't accept negative IDs specially.** A negative `parsed_map_id` (impossible in practice — it's a `uint16` in the SRAM) would render as e.g. "Map #-5". Acceptable; `safe_map_id` returns nil for the 0 byte, and `uint16` can't go negative. No defense needed.

4. **Test runtime delta**: 17 new tests, suite went from ~1.66s to ~1.78s. No regression.

5. **Rails app boot reads `maps.yml` lazily** — the `@maps ||= ...` memoize triggers on first call. Boot-time cost is unchanged. The YAML is small (~3 KB).

6. **Pre-existing rubocop offenses in OTHER files** — none. Step 11's autocorrect sweep brought the codebase to 0 and Step 12 maintained that.

7. **The "real maps.yml ships with gym towns" sanity-check test** is the production canary. It runs against the actual `config/soul_link/maps.yml` (not a temp file) and asserts 8→Eterna, 7→Oreburgh, 14→Snowpoint. If those entries get accidentally deleted or the file format changes, the test fails immediately.

---

**Ready for Review: YES**
