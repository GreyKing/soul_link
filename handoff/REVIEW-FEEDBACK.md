# Review Feedback — Step 12
Date: 2026-05-01
Status: APPROVED

## Conditions

None.

## Escalate to Architect

None.

## Cleared

Reviewed Step 12 (KG-6: Map ID → Name Lookup) end-to-end: the new YAML, GameState additions, helper method, view edits, and 17 new tests. Diff scope matches the brief precisely.

Verifications performed (independently of Bob's claims):

- **`maps.yml` header comment is present and explicit (Architect focus #1).** Read the first 20 lines: cites pret/pokeplatinum as the source, calls out that integer IDs are "best-effort and have NOT been validated against a real `.sav`", explicitly references KG-7 as the validation step, and explains the fallback. Future readers will not assume the IDs are correct.

- **Hash shape `{ name: "..." }` preserved across all entries (Architect focus #2).** Spot-checked the YAML — every line uses the hash form. No flat `id: "Twinleaf Town"` style snuck in. Future fields (region, dungeon flag) can be added without breaking the API.

- **`map_name` handles string + integer + nil inputs (Architect focus #3).** Read the implementation: `return nil if map_id.nil?` short-circuits nil, `maps.dig(map_id.to_i, "name")` coerces strings via `.to_i` and uses safe-nav `.dig` to return nil for missing keys. Tests pin all three cases. ✓

- **`format_map_name` fallback is exactly "Map #N" (Architect focus #4).** Helper source: `SoulLink::GameState.map_name(map_id) || "Map ##{map_id}"`. The test "format_map_name returns Map #N fallback when GameState returns nil" asserts `"Map #99999"` literally. Not "Unknown #N" or "Map ID N". Matches brief precisely. ✓

- **Both view surfaces render the field (Architect focus #5).** Read both partials:
  - `_run_sidebar_card.html.erb:83-87`: gated on `active_slot&.parsed_map_id`, renders between Money block (line 77-81) and Badges block (line 89-93). ✓
  - `_save_slots_sidebar.html.erb:89-93`: gated on `slot.parsed_map_id`, renders between Money block (line 83-87) and Badges block (line 95-99). ✓
  Same gate semantic, same chronological placement. Consistent.

- **`reload!` clears `@maps` (Architect focus #6).** Read the method: `@maps = nil` is in the list alongside the other ivar resets. Test "reload! clears the maps cache" pins this: writes a YAML, reads it, mutates the YAML on disk, calls `reload!`, asserts the new value is read. ✓

- **Tests cover the empty-file case (Architect focus #7).** "maps returns {} when the file is absent" test points `MAPS_PATH` at `/tmp/__definitely_not_a_real_maps_file__.yml` and asserts `GameState.maps == {}`. The `map_name` test for unknown ID is implicit coverage. No exception path. ✓

- **No regression on `SaveParser` or the parse job (Architect focus #8).** Ran `bin/rails test test/services/soul_link/save_parser_test.rb test/jobs/soul_link/parse_save_data_job_test.rb` independently — all green. The new code is purely additive on the read path.

- **No regression on Step 9 broadcasts (Architect focus #9).** Ran `bin/rails test test/models/soul_link_emulator_save_slot_test.rb` — 23/23 green including the broadcast assertions. The roster card partial gained one ERB block; `data-discord-user-id` is unchanged on the outer card div; the broadcast-replace flow is unaffected.

- **Rubocop stays at 0 offenses (Architect focus #10).** Ran `bundle exec rubocop` independently — clean across 147 files (was 145 in Step 11; the +2 is the two new test files). No new violations introduced.

- **Helper method placement.** `format_map_name` is right after `format_play_time` in `EmulatorHelper`. Same module, same shape (nil-tolerant return, descriptive doc comment). Maintainable.

- **GameState method placement.** `maps` and `map_name` live between `location_name` and `players` — group thematically with location lookup. The brief explicitly noted to NOT group with `map_coordinates` (which is the dashboard map's pixel-coordinates dataset; different concern despite the similar name). Bob followed this.

- **Memoize test uses `File.exist?` counting**, not `YAML.load_file` counting. Bob noted Bootsnap's `CompileCache::YAML::Psych4::Patch` intercepts `YAML.load_file` ahead of any singleton stub. The `File.exist?` count goes through unimpeded. Same workaround as `game_state_cheats_test.rb`. Reasonable + documented.

- **Production sanity-check test.** "the real maps.yml file ships with at least the gym towns" runs against the actual production YAML (after resetting the @maps memo) and asserts 8→Eterna, 7→Oreburgh, 14→Snowpoint. If anyone accidentally deletes or breaks those entries, the test fails immediately. Good canary.

- **`format_map_name` tests use `SoulLink::GameState.stub`** to control the return value, isolating the helper logic from the YAML's specific contents. This decouples the helper test from any future maps.yml edits.

- **Tests.** Ran `bin/rails test` independently: 335 runs, 0 failures, 0 errors. Pre-Step-12 was 318. The +17 breaks down as: 8 GameState maps tests + 9 EmulatorHelper tests (5 backfill of format_play_time + 4 new for format_map_name).

- **`Pokémon` accent character.** Verified in `maps.yml` ("Pokémon League" entry, "Pokémon Center" entry). UTF-8 saved correctly; the YAML loader returns the canonical brand spelling.

Bob shipped exactly what the brief specified, and the pre-flight scope correction (acknowledging that `parsed_map_id` doesn't currently surface in any view, so Step 12 builds BOTH the lookup AND the UI rendering) was the right call. The seven flagged self-review items are well-reasoned. No deviations from the brief in the diff. Ships as-is.

**Step 12 closes Knowledge Gap KG-6 — the SRAM Phase 1 user-visible surface is complete. KG-7 (real-save offset verification) remains open: the parser's `MAP_ID_OFFSET = 0x1234` and the integer→name mapping in `maps.yml` should both be validated against a real `.sav` when the Project Owner has one. The fallback `"Map #N"` keeps the UI honest in the meantime.**

Next big move (per Project Owner): item #3 (discord_bot test coverage) or item #4 (god-object decomposition), both fresh-main-checkout-session candidates per worktree preference.
