# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 6 — Convert Controller Tests + Missed Model Test from Fixtures to FactoryBot

### Context

Step 5 (commit `efcc659`, merged to main) converted the 3 heaviest model unit tests. Step 6 finishes the test-side conversion: 8 controller files + 1 missed model test (`soul_link_pokemon_group_test.rb`, which Step 5's brief inadvertently scoped out). After Step 6, **zero** test files reference fixtures by name. Step 7 (channel test) and Step 8 (delete fixtures + drop `fixtures :all` + sweep) will follow in a future session.

This step is the largest in the conversion — 9 files, ~23 fixture-helper calls — but each individual conversion is mechanical. The session-builder pattern from Step 5 carries over: Minitest `setup do ... end`, `create(:foo, :trait, soul_link_run: @run, ...)` keyword form, ivars, no RSpec idioms. The lessons from Step 5 (`soul_link_pokemon_group:` keyword on every pokemon `create`, seed all groups when a query has non-deterministic ordering) apply here.

### Project Owner decisions (locked)

- **Auto-accept mode for this work.** Bob can act decisively; Reviewer + tests are the backstop. Don't escalate minor judgment calls.
- **Convert exactly nine files.** The 8 controller files listed below + `soul_link_pokemon_group_test.rb`. Channel test (`gym_draft_channel_test.rb`) is Step 7 — do NOT touch it.
- **Preserve every test.** Same test name, same assertions, same coverage. Renames are allowed only when the original name explicitly references "fixture" (e.g. comments mentioning fixtures stay informational; the test name semantic stays).
- **Don't touch fixtures, factories, test_helper, or app code.** Step 6 only edits the 9 target test files.
- **`create(...)`, not `build(...)`.** Persisted records match fixture semantics — fixtures are pre-saved rows.
- **Brief is exhaustive.** Each file has its own conversion pattern below; Bob applies them one by one. Run tests after each file (or after a small batch of similar-shape files).

### Files to Convert (9 total)

#### 1. `test/models/soul_link_pokemon_group_test.rb` (2 fixture-helper calls)

**Current setup:**
```ruby
setup do
  @run = soul_link_runs(:active_run)
  @group = soul_link_pokemon_groups(:group_route201)
end
```

**Replacement.** This file is the trickiest of the 9 because:
- The `species_for returns pokemon for given user` test calls `@group.species_for(GREY)` and expects a non-nil pokemon → Grey must have a pokemon in `@group`.
- The `complete? is true when all players have pokemon` test asserts `@group.complete?` which iterates over `SoulLink::GameState.player_ids` (4 players) → ALL 4 players must have pokemon in `@group`.

```ruby
setup do
  @run = create(:soul_link_run)
  @group = create(:soul_link_pokemon_group, :route201, soul_link_run: @run)
  %i[route201_grey route201_aratypuss route201_scythe461 route201_zealous].each do |trait|
    create(:soul_link_pokemon, trait, soul_link_run: @run, soul_link_pokemon_group: @group)
  end
end
```

The `set_position auto-increments` test creates 2 new groups in `@run` and asserts `g2.position > g1.position`. With fixtures the run had 6 groups so the new ones got positions 7 and 8. With factories the run only has @group (position 1) plus the 2 new ones; before_create :set_position writes max+1 → positions 2 and 3. Assertion `g2.position > g1.position` (3 > 2) still holds.

**Test count:** 7 (unchanged).

#### 2. `test/controllers/emulator_controller_test.rb` (1 fixture-helper call)

Single call: `@run = soul_link_runs(:active_run)` in setup. Swap to:

```ruby
setup do
  @run = create(:soul_link_run)
end
```

Every other test body already uses factories (left over from earlier Save Slots work). Nothing else changes. **Test count:** 36 (unchanged — this is the heaviest controller file by test count, but the conversion is one line in setup).

#### 3. `test/controllers/save_slots_controller_test.rb` (1 fixture-helper call)

Single call: `@run = soul_link_runs(:active_run)`. Same one-line swap as emulator_controller_test:

```ruby
setup do
  @run = create(:soul_link_run)
  @sess = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
end
```

(The `@sess` line already exists; just convert `@run`.) **Test count:** 33 (unchanged).

#### 4. `test/controllers/species_assignments_controller_test.rb` (2 fixture-helper calls)

Setup just needs `@run` swap. The "assign_from_pokedex rejects duplicate user in group" test references `soul_link_pokemon_groups(:group_route201)` inline AND assumes Grey already has a pokemon in that group (the test comment says "Grey already has pokemon in this group"). Both must be created explicitly:

**Setup:**
```ruby
setup do
  @run = create(:soul_link_run)
end
```

**Inline rewrite of "rejects duplicate user in group" test:**
```ruby
test "assign_from_pokedex rejects duplicate user in group" do
  login_as(GREY)
  group = create(:soul_link_pokemon_group, :route201, soul_link_run: @run)
  create(:soul_link_pokemon, :route201_grey, soul_link_run: @run, soul_link_pokemon_group: group)
  patch assign_from_pokedex_species_path, params: { species_name: "Bidoof", group_id: group.id }, as: :json
  assert_response :unprocessable_entity
end
```

**Test count:** 5 (unchanged).

#### 5. `test/controllers/teams_controller_test.rb` (2 fixture-helper calls)

Setup just needs `@run` swap. Two test bodies need attention:

**A. "show creates team if none exists"** currently does `SoulLinkTeam.where(discord_user_id: GREY).destroy_all` to remove the fixture's grey_team. After conversion, no fixture team exists so the destroy_all is a no-op. **Keep the line** — it's harmlessly defensive and documents intent.

**B. "update_slots saves valid group ids"** uses `soul_link_pokemon_groups(:group_route201)` and asserts success. The controller's `update_slots` filters incoming `group_ids` against `allowed_ids` (groups where Grey has pokemon). For the test's group ID to survive that filter, Grey must have a pokemon in that group:

```ruby
test "update_slots saves valid group ids" do
  login_as(GREY)
  group = create(:soul_link_pokemon_group, :route201, soul_link_run: @run)
  create(:soul_link_pokemon, :route201_grey, soul_link_run: @run, soul_link_pokemon_group: group)
  patch update_slots_team_path, params: { group_ids: [ group.id ] }, as: :json
  assert_response :success
end
```

**C. "update_slots rejects more than 6"** does `@run.soul_link_pokemon_groups.limit(7).pluck(:id)`. Fixture run had exactly 6 groups; `.limit(7)` returned all 6. The test relies on having ≥6 groups in the run. After conversion, the run starts empty, so the test must seed enough groups. The simplest conversion: seed 7 groups and let `.limit(7)` actually return 7. The assertion is `assert_response :success` (the controller filters down via allowed_ids), so the count of incoming IDs doesn't directly matter — but the test name says "rejects more than 6", so the spirit is "send 7 IDs". To preserve that intent, seed 7 groups inline in the test:

```ruby
test "update_slots rejects more than 6" do
  login_as(GREY)
  7.times do |i|
    g = @run.soul_link_pokemon_groups.create!(nickname: "G#{i}", location: "route_20#{(i % 6) + 1}", status: "caught")
    @run.soul_link_pokemon.create!(soul_link_pokemon_group: g, discord_user_id: GREY,
                                   species: "Bulbasaur", name: "G#{i}", location: g.location, status: "caught")
  end
  groups = @run.soul_link_pokemon_groups.limit(7).pluck(:id)
  patch update_slots_team_path, params: { group_ids: groups }, as: :json
  assert_response :success
end
```

Note: "route_207" doesn't exist as a string anywhere in the system, but the model only validates `location` presence — any string works. The modulo-6 wrap is just to keep the location strings recognizable.

**Test count:** 5 (unchanged).

#### 6. `test/controllers/pokemon_controller_test.rb` (3 fixture-helper calls)

Setup needs `@run` swap. Two test bodies need attention:

**A. "create rejects duplicate user in group"** references `soul_link_pokemon_groups(:group_route201)` and assumes Grey has a pokemon there (comment: "Grey already has a pokemon in this group via fixtures"). Convert:

```ruby
test "create rejects duplicate user in group" do
  login_as(GREY)
  group = create(:soul_link_pokemon_group, :route201, soul_link_run: @run)
  create(:soul_link_pokemon, :route201_grey, soul_link_run: @run, soul_link_pokemon_group: group)
  post pokemon_index_path, params: { group_id: group.id, species: "Bidoof" }, as: :json
  assert_response :unprocessable_entity
end
```

**B. "update rejects other players pokemon"** references `soul_link_pokemon(:pkmn_route201_aratypuss)` to get a pokemon owned by ARatypuss (not Grey). Convert:

```ruby
test "update rejects other players pokemon" do
  login_as(GREY)
  group = create(:soul_link_pokemon_group, :route201, soul_link_run: @run)
  araty_pokemon = create(:soul_link_pokemon, :route201_aratypuss, soul_link_run: @run, soul_link_pokemon_group: group)
  patch pokemon_path(araty_pokemon), params: { species: "Hacked" }, as: :json
  assert_response :forbidden
end
```

**Test count:** 5 (unchanged).

#### 7. `test/controllers/pokemon_groups_controller_test.rb` (3 fixture-helper calls)

Setup needs `@run` swap. Two test bodies reference `:group_route206`. The model's `update to dead cascades status` test patches `status: "dead"`, and `destroy removes group` deletes the group. Both just need a group existing in `@run`:

**A. "update to dead cascades status":**
```ruby
test "update to dead cascades status" do
  login_as(GREY)
  group = create(:soul_link_pokemon_group, :route206, soul_link_run: @run)
  patch pokemon_group_path(group), params: { status: "dead" }, as: :json
  assert_response :success
  group.reload
  assert_equal "dead", group.status
end
```

**B. "destroy removes group":**
```ruby
test "destroy removes group" do
  login_as(GREY)
  group = create(:soul_link_pokemon_group, :route206, soul_link_run: @run)
  assert_difference "SoulLinkPokemonGroup.count", -1 do
    delete pokemon_group_path(group), as: :json
  end
  assert_response :success
end
```

**Test count:** 6 (unchanged).

#### 8. `test/controllers/gym_drafts_controller_test.rb` (8 fixture-helper calls)

This is the heaviest of the 9 (8 calls). Setup builds `@run` and `@draft`; the "show loads type analysis for complete draft" test builds 6 groups and seeds the draft state.

**New setup (mirrors Step 5's gym_draft_test pattern):**
```ruby
setup do
  @run = create(:soul_link_run)
  @draft = create(:gym_draft, :lobby, soul_link_run: @run)
end
```

**"show loads type analysis for complete draft" test:**
```ruby
test "show loads type analysis for complete draft" do
  login_as(GREY)
  groups = %i[route201 route202 route203 route204 route205 route206].map do |trait|
    create(:soul_link_pokemon_group, trait, soul_link_run: @run)
  end

  @draft.update!(
    status: "complete",
    pick_order: [ GREY ],
    state_data: {
      "ready_players" => [],
      "first_pick_votes" => {},
      "picks" => groups.each_with_index.map { |g, i|
        { "round" => i + 1, "group_id" => g.id, "picked_by" => GREY }
      }
    }
  )

  get gym_draft_path(@draft)
  assert_response :success
end
```

The "create reuses existing active draft" test asserts `assert_redirected_to gym_draft_path(@draft)` — depends on `@draft` being the run's existing active lobby draft. Setup builds it with `:lobby` trait, so this works unchanged.

The "create makes new draft and redirects to show" test does `@draft.destroy!` first — that still works because `@draft` is now a factory record (also persisted, also destroyable).

**Test count:** 5 (unchanged).

### Out of Scope (do NOT expand)

- Channel test (`test/channels/gym_draft_channel_test.rb`) — Step 7
- Fixture deletion (`test/fixtures/*.yml`) — Step 8
- `test/test_helper.rb` `fixtures :all` line — Step 8
- Any factory file — Step 4 shipped them; if Bob finds a missing trait, that's a Reviewer-flagged scope expansion, NOT an inline factory edit
- App code, models, controllers, views, JS, ERB
- Adding new test cases or removing existing ones — preserve test count exactly:
  - soul_link_pokemon_group=7, emulator=36, save_slots=33, species_assignments=5, teams=5, pokemon=5, pokemon_groups=6, gym_drafts=5
- Refactoring helper methods or constants on touched files
- Pre-existing rubocop offenses outside the lines Bob is touching
- Any model test besides `soul_link_pokemon_group_test.rb` (the explicitly missed one)
- Any test file that doesn't match a fixture-helper grep pattern
- The "6 other files (mixed)" note from the parked plan is now resolved by the file-by-file scope above — Bob does not need to discover additional files

### Constraints / Flags

- **Run tests after each file is converted.** Don't batch all 9 and run once at the end. Sequence (smallest-impact-first): emulator_controller → save_slots_controller → soul_link_pokemon_group_test → species_assignments → teams → pokemon → pokemon_groups → gym_drafts. After each: `bin/rails test <file>`. After the last: full `bin/rails test`.
- **305/305 must pass at the end.**
- **`soul_link_pokemon_group:` keyword on every `create(:soul_link_pokemon, ...)` call.** Same rule from Step 5. Grep the diff: every `create(:soul_link_pokemon, ` line must have `soul_link_pokemon_group:` somewhere on the same line or in the kwargs block.
- **`@groups` arrays stay arrays** when used positionally by index. The gym_drafts controller test uses `groups.each_with_index.map { ... { "group_id" => g.id, ... } }` — order matters for the picks JSON.
- **No `let` / `subject` / `before(:each)`.** Match Minitest `setup` + ivars convention.
- **Don't reorder tests.**
- **Don't introduce new factory traits.** All needed traits exist (`:route201..:route206`, `:route20N_<player>` for 24 combinations, `:grey_team`, `:slot_1..:slot_2`, `:lobby`). If Bob feels a trait is missing, escalate.
- **Keyword-style `create(:foo, :trait, soul_link_run: @run, ...)` over chained `.create!`.** Prefer factories over `@run.soul_link_pokemon_groups.create!(...)` chains for new creates EXCEPT in `teams_controller_test.rb` "update_slots rejects more than 6" where the inline `create!` chain is more readable than spinning up 7 sequenced factories with non-existing route locations.
- **Pre-existing rubocop offenses on the lines Bob touches:** fix them. Pre-existing offenses elsewhere in the file: leave alone (Step 5 lesson — fix only the lines in Bob's diff).
- **Zero fixture-helper calls remaining in the 9 files.** Verify with `grep -nE "soul_link_pokemon\(|soul_link_runs\(|soul_link_pokemon_groups\(|soul_link_teams\(|soul_link_team_slots\(|gym_drafts\(|gym_results\("` against the 9 files.

### Acceptance Criteria

- All 9 files compile and run individually green: `bin/rails test <file>` for each.
- Full suite green: `bin/rails test` → 305/305 passing, 0 failures, 0 errors.
- `bundle exec rubocop` clean on all 9 files.
- `grep -E "soul_link_pokemon\(|soul_link_runs\(|soul_link_pokemon_groups\(|soul_link_teams\(|soul_link_team_slots\(|gym_drafts\(|gym_results\(" <9 files>` returns zero matches.
- After Step 6, `grep -rln <fixture-helper patterns> test/` returns ONLY `test/channels/gym_draft_channel_test.rb` (the Step 7 target). Verify this — it's the proof that Step 6 finished its scope.
- Diff scope: only the 9 test files + `handoff/BUILD-LOG.md` + `handoff/REVIEW-REQUEST.md` + `handoff/ARCHITECT-BRIEF.md` (this file, already overwritten) + `handoff/REVIEW-FEEDBACK.md`. App code, fixtures, factories, test_helper.rb, channel test all untouched.

### Files Bob Should Read

- The 9 target test files (he's converting them)
- `test/factories/soul_link_pokemon.rb`, `soul_link_pokemon_groups.rb`, `gym_drafts.rb`, `soul_link_runs.rb` — what's available
- Step 5's converted tests (`test/models/gym_draft_test.rb`, `gym_result_test.rb`) for the proven pattern
- `test/fixtures/soul_link_pokemon.yml`, `soul_link_pokemon_groups.yml`, `gym_drafts.yml` — only if a row's exact shape is unclear
- `handoff/parked-plans/factorybot-conversion.md` — for context

DO NOT load `app/controllers/`, `app/models/`, or any app code. The controller / model semantics are not changing.

### Files Bob Should Update at the End

- `handoff/REVIEW-REQUEST.md` — files-changed table, self-review answers, open questions, `Ready for Review: YES`
- `handoff/BUILD-LOG.md` — Step History entry for Step 6 (status: Awaiting review)

---

## Notes for Reviewer

When this lands on your desk, focus on:

1. **Test count + name preservation across all 9 files.** Use `grep -c "^  test "` per file. Expected: 7 + 36 + 33 + 5 + 5 + 5 + 6 + 5 = 102 (plus emulator was already 36, so the adjusted full count is whatever the pre-conversion total was). Architect intentionally did NOT pre-count emulator/save_slots tests because they're large and Bob will report. Compare against pre-Step-6 baseline (run `git show HEAD:test/<file> | grep -c "^  test "` for each).

2. **`soul_link_pokemon_group:` keyword on every `create(:soul_link_pokemon, ...)` call.** Run `grep -n "create(:soul_link_pokemon[, ]" <9 files>` and verify every line has `soul_link_pokemon_group:` in scope.

3. **The "complete?" + "species_for" tests in soul_link_pokemon_group_test.rb actually have 4 player pokemon attached to @group.** Without all 4 trait-seeded pokemon, the assertions silently regress. Confirm Bob's setup loops over the 4 traits.

4. **The "duplicate user in group" tests (species_assignments + pokemon)** seed Grey's pokemon into the route201 group BEFORE the controller call. Without this seeding, the duplicate-rejection assertion would be testing the wrong state.

5. **The "update_slots saves valid group ids" test seeds Grey's pokemon into the group.** Without it, the controller's `allowed_ids` filter would reject the group ID, the empty-slots-result would still 200, but `replace_slots!` would be called with `[]` — the test would pass but for the wrong reason.

6. **The "update_slots rejects more than 6" test seeds 7 groups + Grey-pokemon-per-group.** Verify the test seeds enough groups that `.limit(7)` returns 7 (or accept fewer; the assertion is just success).

7. **Zero fixture-helper calls remaining in the 9 files.** Run the grep listed in the Acceptance Criteria.

8. **Diff scope.** `git status --short` and `git diff --stat HEAD~1` should show only the 9 test files + 4 handoff files. Anything else is a Reviewer Condition.

9. **Test runtime delta.** Step 5 documented this as informational. Step 6 adds more factory creates per test but distributes across many files; runtime impact should still be marginal at the suite level.

10. **gym_drafts_controller_test "show loads type analysis":** verify the seeded `@groups` array order matches the picks order — `groups.each_with_index.map { |g, i| { "round" => i + 1, "group_id" => g.id, "picked_by" => GREY } }` puts route201's id at round 1, route206's id at round 6.

Out-of-scope items found during review → BUILD-LOG Known Gaps. Do not bundle.
