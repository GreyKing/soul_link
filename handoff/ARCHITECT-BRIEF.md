# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 5 — Convert Model Unit Tests from Fixtures to FactoryBot

### Context

Step 4 shipped the missing factories (commit `6e2c8c8`, merged to main). Step 5 is the first of two test-conversion steps. We now eliminate fixture-helper calls in three model unit-test files and replace them with `create(:factory, :trait)` calls against the factories we just built. Other fixture-based tests (controllers, channels, integration) stay on fixtures until Step 6 — Step 5 is scoped tightly to model specs to keep the diff small and reversible.

After Step 5: tests still pass, fixtures still load via `fixtures :all`, but these three files no longer reference any fixture by name. After Step 6: fixtures get deleted, `fixtures :all` removed, every test is factory-based.

### Project Owner decisions (locked)

- **Auto-accept mode for this work.** Bob can act decisively; Reviewer + tests are the backstop.
- **Convert exactly three files.** No fourth file, no controller tests, no channel tests. Step 6 picks up the rest.
- **Preserve every test.** Same test name, same assertions, same semantics. The conversion is mechanical; if a test must change shape, that's a Reviewer flag.
- **Don't touch fixtures, don't touch test_helper, don't touch factories, don't touch app code.** Step 5 only edits the three target test files.
- **`create(...)`, not `build(...)`.** Persisted records match fixture semantics — fixtures are pre-saved rows.

### Files to Convert (3 total)

#### 1. `test/models/soul_link_pokemon_test.rb` (9 fixture-helper calls)

Current calls:
- `soul_link_pokemon(:pkmn_route201_grey)` — 5×
- `soul_link_runs(:active_run)` — 1×
- `soul_link_pokemon_groups(:group_route201)` — 1×
- `soul_link_pokemon_groups(:group_route202)` — 2×

Pattern. Add a `setup` block that creates the world:

```ruby
setup do
  @run = create(:soul_link_run)
  @group_201 = create(:soul_link_pokemon_group, :route201, soul_link_run: @run)
  @group_202 = create(:soul_link_pokemon_group, :route202, soul_link_run: @run)
  @pokemon = create(:soul_link_pokemon, :route201_grey,
                   soul_link_run: @run,
                   soul_link_pokemon_group: @group_201)
end
```

Per-test rewrites:
- `pokemon = soul_link_pokemon(:pkmn_route201_grey)` → `pokemon = @pokemon` (or `pokemon = @pokemon.reload` if the test mutates and re-reads)
- `run = soul_link_runs(:active_run)` → `run = @run`
- `group = soul_link_pokemon_groups(:group_route201)` → `group = @group_201`
- `group = soul_link_pokemon_groups(:group_route202)` → `group = @group_202`

The "fixture pokemon is valid" test becomes "factory pokemon is valid" — same assertion, the @pokemon record satisfies validations because the factory builds valid records.

The "enforces unique discord_user_id per group" test currently builds a duplicate `SoulLinkPokemon.new(...)` — keep that exact code, just swap `existing = soul_link_pokemon(:pkmn_route201_grey)` with `existing = @pokemon`. Don't refactor the duplicate construction into another factory call.

The "assign_to_group sets group..." test currently creates a fresh pokemon via `run.soul_link_pokemon.create!(...)` — keep that exact code (it's testing `assign_to_group!` semantics on an unassigned pokemon, and the explicit `create!` makes the unassigned-state contract obvious). Just swap `run = soul_link_runs(:active_run)` and `group = soul_link_pokemon_groups(:group_route201)` with `@run` / `@group_201`.

The "assign_to_group raises if already assigned" test references both `:pkmn_route201_grey` and `:group_route202` — port both via setup vars.

#### 2. `test/models/gym_draft_test.rb` (8 fixture-helper calls)

Current setup block:
```ruby
setup do
  @run = soul_link_runs(:active_run)
  @draft = gym_drafts(:lobby_draft)
  @groups = [
    soul_link_pokemon_groups(:group_route201),
    soul_link_pokemon_groups(:group_route202),
    soul_link_pokemon_groups(:group_route203),
    soul_link_pokemon_groups(:group_route204),
    soul_link_pokemon_groups(:group_route205),
    soul_link_pokemon_groups(:group_route206)
  ]
end
```

Replacement:
```ruby
setup do
  @run = create(:soul_link_run)
  @groups = %i[route201 route202 route203 route204 route205 route206].map do |trait|
    create(:soul_link_pokemon_group, trait, soul_link_run: @run)
  end
  @draft = create(:gym_draft, :lobby, soul_link_run: @run)
end
```

The order is critical — `@draft` must be created AFTER `@groups` because the draft tests pick groups by index from `@groups`. The factory's `:lobby` trait pins the JSON state, matching the fixture exactly.

`@groups` stays an Array (not a Hash) — the test references `@groups[0]`, `@groups[4]`, `@groups[5]` etc. Index 0 = route201, index 5 = route206, mirroring the current ordering.

ID-on-fixture-state assertions (`assert_equal @groups[0].id, @draft.picks.first["group_id"]`) work correctly because `@groups[0]` is the same record both at pick time and at assertion time.

The 18 remaining test bodies are unchanged — they reference `@run`, `@draft`, `@groups[i]`, and the four `GREY/ARATY/SCYTHE/ZEALOUS` constants. The `move_to_voting!` / `move_to_drafting!` / `move_to_nominating!` private helpers also stay unchanged.

#### 3. `test/models/gym_result_test.rb` (1 fixture-helper call + indirect group fixture use)

Current setup:
```ruby
setup do
  @run = soul_link_runs(:active_run)
end
```

Becomes:
```ruby
setup do
  @run = create(:soul_link_run)
  @groups = %i[route201 route202 route203 route204 route205 route206].map do |trait|
    create(:soul_link_pokemon_group, trait, soul_link_run: @run)
  end
end
```

The `setup` block grows because `snapshot_from_groups` (line 28-37) currently relies on the fixture run having pokemon groups attached to it via `fixtures :all`. After conversion, those groups must be created explicitly. The "snapshot_from_groups builds correct structure" test calls `@run.soul_link_pokemon_groups.includes(:soul_link_pokemon).limit(2)` — without the explicit factory creates, this would return an empty relation and the assertion `assert_equal 2, snapshot["groups"].size` would fail.

The snapshot test also asserts `first_group["pokemon"].first.key?("species")` — for that to pass, the groups must HAVE pokemon. Recommended pattern (inline seeding inside the test, since only one test needs the pokemon):

```ruby
test "snapshot_from_groups builds correct structure" do
  create(:soul_link_pokemon, :route201_grey, soul_link_run: @run, soul_link_pokemon_group: @groups[0])
  create(:soul_link_pokemon, :route202_grey, soul_link_run: @run, soul_link_pokemon_group: @groups[1])
  groups = @run.soul_link_pokemon_groups.includes(:soul_link_pokemon).limit(2)
  snapshot = GymResult.snapshot_from_groups(groups)
  ...
end
```

Inline seeding keeps the setup block lighter and makes the test self-documenting.

### Out of Scope (do NOT expand)

- Any other test file (controllers, channels, integration)
- Fixtures (`test/fixtures/*.yml`) — Step 6 deletes them
- `test/test_helper.rb` `fixtures :all` line — Step 6 removes it
- Any factory file — Step 4 shipped them; if Bob finds a missing trait, that's a Reviewer-flagged scope expansion, NOT an inline factory edit
- App code, models, controllers, views, JS, ERB templates
- Refactoring helper methods on the three test files (e.g., `move_to_voting!` style cleanup)
- Adding new test cases or removing existing ones — preserve test count exactly: pokemon=7, gym_draft=21, gym_result=4

### Constraints / Flags

- **Run tests after each file is converted.** Don't batch all three and run once at the end — if a conversion subtly breaks something, you want to localize it. Sequence: convert pokemon test → run pokemon test → convert gym_draft test → run gym_draft test → convert gym_result test → run full suite.
- **Same test count: 305/305 must pass at the end.** Each test must keep its name and assertion shape. Adding `setup` lines is fine; removing or splitting tests is NOT.
- **Don't introduce `let` / `subject` / RSpec idioms.** Project uses Minitest with `setup` blocks and ivars. Match that.
- **Don't introduce `before(:each)` or `before(:all)`.** Use `setup do ... end` (Minitest's idiom).
- **`@groups` in gym_draft_test stays an Array.** Don't refactor to Hash because the test uses positional indexing.
- **Prefer `create(:foo, :trait, soul_link_run: @run)` keyword form** over chained `.create!`. Matches the existing factory test style.
- **The pokemon factory's traits do NOT default `soul_link_pokemon_group`** — every `create(:soul_link_pokemon, :trait)` call MUST pass `soul_link_pokemon_group:` explicitly. Forgetting this builds a record with a fresh, orphan group from the base association default — the test "passes" but has wrong topology. (Why this matters: Step 4's brief locked traits to NOT set the group association so callers control which group they bind to. Verify by grep: every `create(:soul_link_pokemon, ...)` in the diff must have `soul_link_pokemon_group:` in its kwargs.)
- **Do NOT add factory traits.** If a test needs a non-existent shape, escalate; don't extend the factory.
- **Don't reorder tests.** Tests are in semantic groups (Lobby Phase, Voting Phase, etc. — see comments). Preserve the order.
- **Watch `test "fixture pokemon is valid"`.** Rename the test to `test "factory pokemon is valid"` to keep semantics honest.

### Acceptance Criteria

- All three files compile and run individually: `bin/rails test test/models/soul_link_pokemon_test.rb`, `bin/rails test test/models/gym_draft_test.rb`, `bin/rails test test/models/gym_result_test.rb` — each green.
- Full suite green: `bin/rails test` → 305/305 passing, 0 failures, 0 errors.
- `bundle exec rubocop` clean on all three files.
- Self-review item: confirm via grep that no `soul_link_pokemon(`, `soul_link_runs(`, `soul_link_pokemon_groups(`, `gym_drafts(` calls remain in the three converted files.
- Diff scope: only `test/models/soul_link_pokemon_test.rb`, `test/models/gym_draft_test.rb`, `test/models/gym_result_test.rb`, `handoff/BUILD-LOG.md`, `handoff/REVIEW-REQUEST.md`, `handoff/REVIEW-FEEDBACK.md` (Reviewer's). Anything else is a Reviewer Condition.

### Files Bob Should Read

- `test/models/soul_link_pokemon_test.rb` — current state (Bob converts)
- `test/models/gym_draft_test.rb` — current state (Bob converts)
- `test/models/gym_result_test.rb` — current state (Bob converts)
- `test/factories/soul_link_pokemon.rb`, `soul_link_pokemon_groups.rb`, `gym_drafts.rb`, `gym_results.rb`, `soul_link_runs.rb` — what's available
- `test/fixtures/soul_link_pokemon.yml`, `soul_link_pokemon_groups.yml`, `gym_drafts.yml` — only to verify nothing was lost in the trait set
- `handoff/parked-plans/factorybot-conversion.md` — original conversion plan (this brief is the operational version)

DO NOT load app/models or app/controllers. The model semantics are not changing.

### Files Bob Should Update at the End

- `handoff/REVIEW-REQUEST.md` — files-changed table, self-review answers, open questions, `Ready for Review: YES`
- `handoff/BUILD-LOG.md` — Step History entry for Step 5 (status: Awaiting review)

---

## Notes for Reviewer

When this lands on your desk, focus on:

1. **Test count + test name preservation.** Run `bin/rails test test/models/soul_link_pokemon_test.rb test/models/gym_draft_test.rb test/models/gym_result_test.rb -v` and count test names. pokemon=7, gym_draft=21, gym_result=4. Any rename (e.g. "fixture pokemon is valid" → "factory pokemon is valid") is acceptable; any add/remove is a Condition.

2. **`soul_link_pokemon_group:` keyword on every `create(:soul_link_pokemon, ...)` call.** The factory's traits don't default the group association — a missing kwarg orphan-couples the pokemon to a fresh, throwaway group. Grep the diff: every `create(:soul_link_pokemon, ` line must have `soul_link_pokemon_group:` somewhere on the same line or its block.

3. **`@groups` array order in gym_draft_test.rb.** `@groups[0]` must be the route201 group, `@groups[5]` must be route206. Tests at lines 99 (`@groups[0].id`), 188 (`@groups[4].id`), 207-220 (`@groups[4]`, `@groups[5]`) rely on this. Walk the conversion and confirm the order of `%i[route201 route202 route203 route204 route205 route206].map` matches.

4. **`gym_result_test.rb` snapshot test seeds pokemon.** Without explicitly creating two pokemon (via `create(:soul_link_pokemon, :route201_grey, ..., soul_link_pokemon_group: @groups[0])`), the snapshot's `pokemon.first.key?("species")` assertion fails because the groups have no associated pokemon. Verify Bob added these creates either inline in the test or in the setup block.

5. **No fixture references in the three files after conversion.** Run `grep -E "soul_link_pokemon\(|soul_link_runs\(|soul_link_pokemon_groups\(|gym_drafts\(|gym_results\(" test/models/soul_link_pokemon_test.rb test/models/gym_draft_test.rb test/models/gym_result_test.rb` — should return zero matches.

6. **Diff scope.** Confirm via `git status` and `git diff --stat` that ONLY the three test files + two handoff files appear. App code, fixtures, factories, test_helper.rb, other test files — all untouched.

7. **Test runtime delta.** Fixtures load once per process; factories create rows per test. If runtime regressed by >2× on the three converted files, that's not a Condition (Step 5 is correctness-focused) but log it for the Step 6 sweep.

Out-of-scope items found during review → BUILD-LOG Known Gaps. Do not bundle.
