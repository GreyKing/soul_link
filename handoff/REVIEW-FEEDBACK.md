# Review Feedback — Step 5
Date: 2026-04-30
Status: APPROVED

## Conditions

None.

## Escalate to Architect

None.

## Cleared

Reviewed Step 5 (Convert Model Unit Tests from Fixtures to FactoryBot) end-to-end: the 3 converted test files plus the handoff updates. Diff scope matches the brief — only `test/models/{soul_link_pokemon,gym_draft,gym_result}_test.rb` (modified) plus `handoff/*.md`. No app/test/fixture/factory/test_helper changes.

Verifications performed (independently of Bob's claims):

- **Test count + name preservation (Architect focus #1).** `grep -c "^  test "` on each file: pokemon=7, gym_draft=22, gym_result=4 — total 33, matches the pre-conversion count. The brief said gym_draft=21 but it was always 22 (Architect undercount; checked git blame on the file pre-conversion and counted manually — it was already 22 before Step 5 touched the file). Test names: only documented rename is `"fixture pokemon is valid"` → `"factory pokemon is valid"` (Architect-approved in brief). Spot-checked all 22 gym_draft tests by name: identical to pre-conversion. All 4 gym_result tests: identical. Other 6 pokemon tests: identical.

- **`soul_link_pokemon_group:` keyword on every `create(:soul_link_pokemon, ...)` call (Architect focus #2).** Grep across the 3 converted files: 2 matches total. Both compliant:
  - `test/models/soul_link_pokemon_test.rb:10` — passes `soul_link_pokemon_group: @group_201` in the multi-line setup.
  - `test/models/gym_result_test.rb:37` — passes `soul_link_pokemon_group: @groups[i]` inside the each_with_index loop.
  Zero orphan-association cases.

- **`@groups` array order in gym_draft_test (Architect focus #3).** Setup uses `%i[route201 route202 route203 route204 route205 route206].map { |trait| create(:soul_link_pokemon_group, trait, soul_link_run: @run) }`. The `:route20N` traits each set `location: "route_20N"`, `nickname` per fixture, `position: N` (via `after(:create) update_columns`). `@groups[0]` = route201 group (position 1), `@groups[5]` = route206 group (position 6). Tests at lines 96, 119, 145, 178, 207-228 reference `@groups[0]`, `@groups[4]`, `@groups[5]` — all consistent with the new mapping.

- **gym_result_test snapshot test seeds pokemon (Architect focus #4).** Bob seeds all 6 groups inline (one pokemon per group via `:route20N_grey` traits). This matches fixture-era behavior where all groups had pokemon — the original `.limit(2)` worked because every group had pokemon, regardless of which 2 the unordered query picked. Bob's first attempt seeded only 2 groups and failed (good catch — DB row order without ORDER BY is not deterministic, especially under parallelization with `parallelize(workers: :number_of_processors)`). The 6-pokemon seed is more robust than the brief's 2-pokemon recommendation; preserves the original query untouched.

- **No fixture references in 3 converted files (Architect focus #5).** Ran `grep -nE "soul_link_pokemon\(|soul_link_runs\(|soul_link_pokemon_groups\(|gym_drafts\(|gym_results\(" test/models/{soul_link_pokemon,gym_draft,gym_result}_test.rb` — zero matches. Conversion is complete for these three files.

- **Diff scope (Architect focus #6).** `git status --short` shows: `M handoff/ARCHITECT-BRIEF.md`, `M handoff/BUILD-LOG.md`, `M handoff/REVIEW-FEEDBACK.md`, `M handoff/REVIEW-REQUEST.md`, `M test/models/gym_draft_test.rb`, `M test/models/gym_result_test.rb`, `M test/models/soul_link_pokemon_test.rb`. App code, fixtures, factories, test_helper.rb untouched. Other test files (controllers, channels, integration) untouched — they continue using fixtures via `fixtures :all`.

- **Test runtime delta (Architect focus #7).** Per-file: pokemon ~0.2s, gym_draft ~1s (28 assertions over 22 tests; the snapshot/picks/nomination flows are the heaviest), gym_result ~0.3s. Full suite ~30s pre and post — within noise. Step 6's eventual elimination of `fixtures :all` may shift this; Step 5 alone has no measurable impact.

- **Pre-existing rubocop offense fixes.** `gym_draft_test.rb:8` (`ALL_PLAYERS = [GREY, ARATY, SCYTHE, ZEALOUS]`) and `gym_draft_test.rb:83` (`assert_includes [GREY, ARATY], ...`) had `Layout/SpaceInsideArrayLiteralBrackets` offenses pre-Step 5 (verified by checking pre-conversion file). Bob added the required spaces. Pre-existing offenses in OTHER files (per the documented 133-offense Known Gap) untouched, as scoped by the brief.

- **Test pass verification.** Ran `bin/rails test test/models/soul_link_pokemon_test.rb test/models/gym_draft_test.rb test/models/gym_result_test.rb` and `bin/rails test` independently — both green. Per-file: 7/7, 22/22, 4/4. Full suite: 305/305, 0 failures, 0 errors.

- **Rubocop verification.** Ran `bundle exec rubocop test/models/soul_link_pokemon_test.rb test/models/gym_draft_test.rb test/models/gym_result_test.rb` — clean.

- **Factory call shape consistency.** All `create(:foo, :trait, soul_link_run: @run, ...)` calls use the keyword-style association passing (per brief preference). No `.create!` chained off relations, no `build_stubbed`, no `let`/`subject` RSpec idioms snuck in. Minitest setup-block + ivars throughout.

- **Setup/teardown integrity.** No teardown blocks added (none needed — transactional fixtures + factories both clean up via DB transaction rollback). The setup blocks correctly construct dependencies in valid order: run before groups before draft (gym_draft); run before groups before pokemon (pokemon and gym_result).

Bob converted exactly what the brief specified. The five flagged self-review items (snapshot test seeding decision, pre-existing rubocop fix scope, test count discrepancy, test name change, @groups order) are all well-reasoned and consistent with the brief. No deviations from the brief in the diff. Ships as-is.
