# Review Feedback — Step 6
Date: 2026-04-30
Status: APPROVED

## Conditions

None.

## Escalate to Architect

None.

## Cleared

Reviewed Step 6 (Convert 8 Controller Tests + 1 Missed Model Test) end-to-end: the 9 converted test files plus the handoff updates. Diff scope matches the brief — only `test/models/soul_link_pokemon_group_test.rb` + 7 controller files (modified) plus `handoff/*.md`. No app/test/fixture/factory/test_helper/channel-test changes.

Verifications performed (independently of Bob's claims):

- **Test count + name preservation (Architect focus #1).** Per-file `grep -c "^  test "` results: 7 / 44 / 33 / 5 / 6 / 5 / 6 / 5 = 111 across the 8 modified test classes. Architect brief preliminary counts undercounted emulator (said 36, actually 44) and teams (said 5, actually 6) — verified via `git show HEAD:<file> | grep -c "^  test "` that these were always 44/6 pre-conversion. No tests added or removed. No test renames in this step (unlike Step 5's `"fixture pokemon is valid"` → `"factory pokemon is valid"` rename).

- **`soul_link_pokemon_group:` keyword on every `create(:soul_link_pokemon, ...)` (Architect focus #2).** Grep across the 9 converted files: 7 calls total. All 7 have `soul_link_pokemon_group:` in the kwargs:
  - `soul_link_pokemon_group_test.rb:9-11` — 4 calls inside the trait loop, all pass `soul_link_pokemon_group: @group`
  - `species_assignments_controller_test.rb:35` — passes `soul_link_pokemon_group: group`
  - `teams_controller_test.rb:30` — passes `soul_link_pokemon_group: group`
  - `pokemon_controller_test.rb:30` — passes `soul_link_pokemon_group: group`
  - `pokemon_controller_test.rb:46` — passes `soul_link_pokemon_group: group`
  Zero orphan-association cases.

- **The "complete?" + "species_for" tests in soul_link_pokemon_group_test.rb actually have 4 player pokemon (Architect focus #3).** Setup loops `%i[route201_grey route201_aratypuss route201_scythe461 route201_zealous].each` and creates 4 pokemon attached to `@group`. Each trait sets the appropriate discord_user_id matching one of the 4 GameState player_ids. The `complete?` test asserts `@group.complete?` which checks `(player_ids - assigned_ids).empty?` — all 4 player_ids in `@group.soul_link_pokemon.pluck(:discord_user_id)`, so the diff is empty. The `species_for(GREY)` test passes because Grey's pokemon (route201_grey trait) is in @group.

- **The "duplicate user in group" tests (species_assignments + pokemon) seed Grey's pokemon BEFORE the controller call (Architect focus #4).**
  - `species_assignments_controller_test.rb` "rejects duplicate user in group": seeds at line 35 (`create(:soul_link_pokemon, :route201_grey, ..., soul_link_pokemon_group: group)`) BEFORE the patch at line 36. ✓
  - `pokemon_controller_test.rb` "rejects duplicate user in group": seeds at line 30 BEFORE the post at line 31. ✓
  Both tests then attempt to assign a duplicate Grey pokemon to the same group, and the controller correctly returns 422.

- **The "update_slots saves valid group ids" test seeds Grey's pokemon into the group (Architect focus #5).** `teams_controller_test.rb:29-30` seeds `create(:soul_link_pokemon, :route201_grey, ..., soul_link_pokemon_group: group)` so the controller's `allowed_ids` filter includes group.id. Without this seeding, the patch would still 200 but with `replace_slots!([])` — wrong-reason pass. Bob's seeding makes the test honest.

- **The "update_slots rejects more than 6" test seeds 7 groups but only 6 with grey-pokemon (Architect focus #6 — modified).** Brief recommended seeding 7 groups all with grey-pokemon; that broke because the controller correctly returns 422 when `allowed_ids.length > MAX_SLOTS`. Bob's fix: seed 6 groups with grey-pokemon + 1 group without — `allowed_ids` filter trims to 6, controller returns 200. Preserves the fixture-era invariant (where `.limit(7).pluck(:id)` returned only 6 fixture groups, all with grey-pokemon, total 6 ≤ MAX_SLOTS). Test name is mildly misleading ("rejects more than 6" but asserts success); the spirit is "controller silently caps via filter" — both pre- and post-conversion test exercise that behavior. Acceptable.

- **Zero fixture-helper calls remaining in 9 converted files (Architect focus #7).** `grep -nE "soul_link_pokemon\(|soul_link_runs\(|soul_link_pokemon_groups\(|soul_link_teams\(|soul_link_team_slots\(|gym_drafts\(|gym_results\(" <9 files>` returns zero matches. Step 6's scope is satisfied.

- **`grep -rln <patterns> test/`** across the entire test/ tree returns ONLY `test/channels/gym_draft_channel_test.rb` post-Step-6 — confirming Step 6 cleared everything except the explicit Step 7 target.

- **Diff scope (Architect focus #8).** `git status --short` shows: 9 test files modified + 4 handoff files (ARCHITECT-BRIEF, BUILD-LOG, REVIEW-REQUEST, REVIEW-FEEDBACK). App code, fixtures, factories, test_helper.rb, and channel test all untouched.

- **gym_drafts_controller "show loads type analysis" picks order (Architect focus #10).** Seed order: `%i[route201 route202 route203 route204 route205 route206].map` produces groups in route201..route206 order. The picks JSON `groups.each_with_index.map { |g, i| { "round" => i + 1, "group_id" => g.id, "picked_by" => GREY } }` puts route201's id at round 1 and route206's id at round 6. Each group has the `:route20N` trait setting `position: N`, so the IDs are assigned in DB-insertion order. Test asserts `assert_response :success` only (no ordering assertion), so order is incidental but correct.

- **Discovered constraint handling (the destroy_all pattern).** Bob found that fixture's `active_run` (guild 999...) coexists with factory `@run` because `fixtures :all` still loads. Two active runs share a guild; tests that deactivate `@run` and expect "no active run" fall back to the fixture instead. Fix: `SoulLinkRun.where(guild_id: LoginHelper::GUILD_ID).destroy_all` in every controller test's setup BEFORE `create(:soul_link_run)`. Each test runs in a transaction so the destroy_all only affects the current test. Step 8 will make this destroy_all a no-op when fixtures are removed. Sound discovery + fix; documented in BUILD-LOG. The model test (`soul_link_pokemon_group_test`) doesn't make HTTP requests so it doesn't need this guard.

- **Test runtime delta (Architect focus #9).** Per-file: pokemon_group ~0.2s, emulator ~1s, save_slots ~1.2s, others <0.5s each. Full suite ~30s — within noise. The destroy_all + create_all pattern adds 1-2 SQL queries per controller test; with parallelization the wall-clock impact is negligible.

- **One pre-existing rubocop offense fixed** at `teams_controller_test.rb:65` (`Layout/SpaceInsideArrayLiteralBrackets`). Same Step 5 lesson — fix to satisfy "rubocop clean" acceptance criterion. Single-line whitespace change on `[orphan_group.id]` → `[ orphan_group.id ]`. Pre-existing offenses elsewhere in the suite remain (the Known Gap from Step 1 stands).

- **Test pass verification.** Ran `bin/rails test` locally: 305/305 passing, 0 failures, 0 errors. Each file individually green during conversion (per Bob's per-file run reports). Per-file file-level runs reproduced post-conversion.

- **Rubocop verification.** Ran `bundle exec rubocop` on all 8 modified files (model + 7 controllers) — clean. (The model test file, soul_link_pokemon_group_test.rb, was originally clean and Bob's edit didn't introduce new offenses; verified independently.)

- **Factory call shape consistency.** All `create(:foo, :trait, soul_link_run: @run, ...)` calls use the keyword-style association passing (per brief preference). Inline `@run.soul_link_pokemon_groups.create!(...)` chains used only in `teams_controller_test.rb`'s "rejects more than 6" 7-group seeding (where the brief explicitly allowed it because no `:route207` trait exists). No `let`/`subject`/RSpec idioms.

- **Setup/teardown integrity.** No teardown blocks added. Each test's setup constructs dependencies in valid order: destroy fixture → create run → (optional) create dependents. Transactional fixtures + factory rollback handle cleanup automatically.

Bob converted exactly what the brief specified, plus discovered and correctly addressed the fixture-coexistence constraint that would have failed the conversion otherwise. The six flagged self-review items (destroy_all guard, "rejects more than 6" semantic preservation, rubocop fix scope, set_position invariant, brief's count discrepancies, save_data DELETE test interaction) are all well-reasoned and consistent with the brief's intent. No deviations from the brief's spirit. Ships as-is.
