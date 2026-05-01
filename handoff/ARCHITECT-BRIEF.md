# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 8 — Final Sweep: Delete Fixtures + Drop Hybrid Convention

### Context

Step 7 (commit `a18a27f`, merged to main) closed out the test-side conversion: zero files in `test/` reference fixtures by name. The `fixtures :all` line in `test/test_helper.rb` and the YAML files at `test/fixtures/*.yml` are now dead weight. Step 8 mechanically removes them, drops the hybrid convention from `CLAUDE.md`, retires the durable architecture decision in `BUILD-LOG.md`, and cleans up the defensive `destroy_all` lines that Step 6 added (which become no-ops once fixtures are gone). Then runs a flake check to confirm the suite is robust under parallelization without fixture preload.

After Step 8, the FactoryBot conversion is fully done. The parked plan moves from `handoff/parked-plans/factorybot-conversion.md` to `handoff/archive/2026-04-30-factorybot-conversion.md` (matching the project's existing archive pattern: `2026-04-12-pixeldex-calculator.md`, `2026-04-29-emulator-deploy-and-polish.md`).

### Project Owner decisions (locked)

- **Auto-accept mode for this work.** Bob can act decisively; Reviewer + tests + flake check are the backstop.
- **Bulk file deletions are the work, not destructive accidents.** Bob deletes `test/fixtures/*.yml` directly without per-step approval.
- **Don't touch factories or app code.** Step 8 only edits test_helper, CLAUDE.md, BUILD-LOG durable section, the 7 controller tests, and the parked-plan archive move.
- **Flake check is mandatory.** 3 full-suite passes with different seeds. Each must be 305/305, 0 failures, 0 errors. Reason: factories rebuild rows per test under `parallelize(workers: :number_of_processors)`; race conditions on uniqueness constraints, sequence collisions, or order-dependent assertions can manifest intermittently. 3 passes gives ~95% confidence the suite is stable.

### Files to Delete (7 YAML files)

```
test/fixtures/gym_drafts.yml
test/fixtures/gym_results.yml
test/fixtures/soul_link_pokemon.yml
test/fixtures/soul_link_pokemon_groups.yml
test/fixtures/soul_link_runs.yml
test/fixtures/soul_link_team_slots.yml
test/fixtures/soul_link_teams.yml
```

**Do NOT delete `test/fixtures/files/`** (with `.keep` inside) — it's the standard Rails ActiveStorage attachment fixture directory. Untouched by this conversion.

Use `rm` directly. Verify post-delete: `ls test/fixtures/` should show only `files/`.

### Files to Modify (4 + handoff)

#### 1. `test/test_helper.rb`

Drop the `fixtures :all` line. Keep `parallelize(workers: :number_of_processors)`, `include FactoryBot::Syntax::Methods`, and the OmniAuth + LoginHelper bits intact.

The block becomes:
```ruby
module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # FactoryBot short syntax (`create`, `build`) for test code.
    include FactoryBot::Syntax::Methods

    # Add more helper methods to be used by all tests here...
  end
end
```

The comment immediately above `fixtures :all` (`# Setup all fixtures in test/fixtures/*.yml...`) goes too. The "FactoryBot short syntax" comment should drop the "Legacy fixture-based tests are unaffected — both styles coexist" line since that's no longer true; replace with the simpler comment shown above.

#### 2. `CLAUDE.md` testing-conventions section (lines 53-57)

Current:
```
### Testing conventions

- **New tests** use FactoryBot factories from `test/factories/`.
- **Legacy tests** use fixtures from `test/fixtures/`. Do not convert without an explicit step.
- Factories should be minimum-viable — just enough to satisfy validations and associations. Don't add fields the test doesn't need.
```

Replacement:
```
### Testing conventions

- All tests use FactoryBot factories from `test/factories/`. Fixtures (`test/fixtures/*.yml`) were removed during the 2026-04-30 conversion sweep.
- Factories should be minimum-viable — just enough to satisfy validations and associations. Don't add fields the test doesn't need.
```

#### 3. `handoff/BUILD-LOG.md` Architecture Decisions § "Carried over (still load-bearing)"

Locate the line: `- New tests use FactoryBot factories from test/factories/; legacy tests stay on fixtures from test/fixtures/; do not convert legacy without an explicit step`. Replace with:

```
- All tests use FactoryBot factories from `test/factories/`. Fixtures and the `fixtures :all` test_helper line were removed in Step 8 (2026-04-30).
```

The other "Carried over" entries stay intact.

#### 4. The 7 controller tests with dead `destroy_all` setup lines

Each setup currently has:
```ruby
setup do
  SoulLinkRun.where(guild_id: LoginHelper::GUILD_ID).destroy_all
  @run = create(:soul_link_run)
  ...
end
```

After fixture deletion, the `destroy_all` is a no-op (the table starts empty for each transaction). Remove the line + its preceding comment block (Step 6 added a 4-line comment explaining why the guard existed). Each setup becomes:

```ruby
setup do
  @run = create(:soul_link_run)
  ...
end
```

The 7 files:
- `test/controllers/emulator_controller_test.rb`
- `test/controllers/save_slots_controller_test.rb`
- `test/controllers/species_assignments_controller_test.rb`
- `test/controllers/teams_controller_test.rb`
- `test/controllers/pokemon_controller_test.rb`
- `test/controllers/pokemon_groups_controller_test.rb`
- `test/controllers/gym_drafts_controller_test.rb`

Plus one in-test cleanup in `teams_controller_test.rb` "show creates team if none exists":
```ruby
test "show creates team if none exists" do
  login_as(GREY)
  # Destroy fixture team first
  SoulLinkTeam.where(discord_user_id: GREY).destroy_all
  assert_difference "SoulLinkTeam.count", 1 do
    get team_path
  end
  assert_response :success
end
```

The comment + the `destroy_all` line both drop. Test becomes:
```ruby
test "show creates team if none exists" do
  login_as(GREY)
  assert_difference "SoulLinkTeam.count", 1 do
    get team_path
  end
  assert_response :success
end
```

#### 5. Move parked plan to archive

```
git mv handoff/parked-plans/factorybot-conversion.md handoff/archive/2026-04-30-factorybot-conversion.md
```

This matches the existing archive convention (date-prefixed, descriptive filename). After the move, `handoff/parked-plans/` should be empty (or contain only files unrelated to the conversion).

Append a top-of-file marker to the archived plan:
```
> **Status:** COMPLETE — landed via Steps 4-8 (commits 6e2c8c8, efcc659, f7203b0, a18a27f, <step8 sha>). Archived 2026-04-30.
```

The body of the original plan stays untouched — it's now historical record.

### Out of Scope (do NOT expand)

- Touching factories
- Touching app code (models, controllers, channels, views)
- Refactoring setup blocks beyond removing the dead `destroy_all` lines
- Cleaning up pre-existing rubocop offenses elsewhere in the suite
- Updating `Gemfile`, `Gemfile.lock`, or any non-test config
- Removing or refactoring `test/fixtures/files/` (ActiveStorage convention)
- Renaming or restructuring the factories directory
- Touching Step History entries for prior steps in BUILD-LOG (only the durable § Architecture Decisions § Carried over line changes)
- Any other handoff cleanup beyond the parked-plan archive move

### Constraints / Flags

- **Run full suite after each substantive change**, not just at the end. Sequence:
  1. Delete fixtures + drop `fixtures :all` → `bin/rails test` (must be green)
  2. Update CLAUDE.md → no test impact
  3. Remove `destroy_all` lines (8 occurrences total: 7 setup + 1 in-test) → `bin/rails test` (must be green)
  4. Move parked plan → no test impact
  5. Flake check: 3 reps with different seeds.
- **Flake-check command:** `bin/rails test --seed 12345`, `bin/rails test --seed 67890`, `bin/rails test --seed 13579`. Use the existing rake test invocation; no special harness. Each rep: 305 runs / 0 failures / 0 errors.
- **305/305 across all flake-check reps.** A single run with 1 failure across 3 reps is a Reviewer Condition, not "we'll retry once".
- **Don't regress test runtime.** No specific budget, but report the pre/post total wall-clock at the end. Step 5/6/7 documented this as informational.
- **Don't touch the `parallelize(workers: :number_of_processors)` line** in test_helper. Factories build rows in parallel transactions; the parallelization is what made the conversion possible without runtime penalty.
- **Bulk fixture deletion is `rm test/fixtures/*.yml` (or 7 individual `rm` invocations).** Don't `rm -rf test/fixtures/` — that nukes `files/.keep`. The user explicitly OK'd the YAML deletions ("the fixture deletions are bulk file removals from a versioned directory — that IS the work, not a destructive accident").
- **Pre-existing rubocop offenses elsewhere:** leave alone. Step 5/6/7 lessons hold.

### Acceptance Criteria

- `ls test/fixtures/` returns ONLY `files/` (and `.` / `..`).
- `grep -n "fixtures :all" test/test_helper.rb` returns nothing.
- `grep -n "Legacy tests" CLAUDE.md` returns nothing; the new "All tests use FactoryBot" line is present.
- `grep -rn "SoulLinkRun.where(guild_id: LoginHelper::GUILD_ID).destroy_all" test/` returns ZERO matches.
- `grep -rn "SoulLinkTeam.where(discord_user_id: GREY).destroy_all" test/` returns ZERO matches.
- `handoff/parked-plans/factorybot-conversion.md` does NOT exist; `handoff/archive/2026-04-30-factorybot-conversion.md` DOES exist with the COMPLETE status marker at top.
- `bin/rails test` green: 305 runs, 0 failures, 0 errors.
- 3 flake-check reps with different seeds: each 305/305, 0 failures.
- `bundle exec rubocop` clean on touched test files (the 7 controller tests, test_helper.rb).
- Diff scope: 7 controller test files modified, `test/test_helper.rb` modified, 7 fixture YAMLs deleted, `CLAUDE.md` modified, `handoff/BUILD-LOG.md` modified (durable section + Step 8 history), `handoff/REVIEW-REQUEST.md` modified, `handoff/REVIEW-FEEDBACK.md` modified, `handoff/ARCHITECT-BRIEF.md` modified (this brief, already overwritten), `handoff/parked-plans/factorybot-conversion.md` deleted, `handoff/archive/2026-04-30-factorybot-conversion.md` created. Anything else is a Reviewer Condition.

### Files Bob Should Read

- `test/test_helper.rb` — what to edit
- `CLAUDE.md` lines 53-57 — what to replace
- The 7 controller test files — to remove the dead destroy_all lines
- `test/controllers/teams_controller_test.rb` lines 17-23 — the in-test destroy_all to remove
- `handoff/BUILD-LOG.md` § "Architecture Decisions" § "Carried over" — the durable line to update
- `handoff/parked-plans/factorybot-conversion.md` — to archive
- `handoff/archive/` — to confirm the naming pattern (`YYYY-MM-DD-name.md`)

DO NOT load app code, factories, or fixtures (they're being deleted, not edited).

### Files Bob Should Update at the End

- `handoff/REVIEW-REQUEST.md` — files-changed table, self-review, open questions, `Ready for Review: YES`
- `handoff/BUILD-LOG.md` — Step History entry for Step 8 (status: Awaiting review) AND durable Architecture Decisions update

---

## Notes for Reviewer

When this lands on your desk, focus on:

1. **Flake-check pass.** 3 reps with explicitly different seeds (12345, 67890, 13579). Each must be 305/305. If even one rep flakes, that's a Condition — investigate the failing test, not "retry once".

2. **Fixture deletion completeness.** `ls test/fixtures/` returns ONLY `files/`. If Bob accidentally left a YAML file (or removed `files/.keep`), Condition.

3. **`fixtures :all` line gone from test_helper.rb.** Plus the comment block above it. Plus the "Legacy fixture-based tests are unaffected" comment.

4. **CLAUDE.md testing-conventions section.** New line is "All tests use FactoryBot factories from `test/factories/`". The "Legacy tests" line is gone. The factories-minimum-viable line stays.

5. **All 8 dead `destroy_all` calls removed** (7 setup + 1 in-test in teams_controller_test). Plus the explanatory comments Step 6 added. Verify with: `grep -rn "destroy_all" test/controllers/ test/models/` — only assertion-message uses in run_channel_test.rb (lines 100, 200) should remain.

6. **BUILD-LOG durable Architecture Decisions § Carried over updated.** The "legacy tests stay on fixtures" line is gone; the new "All tests use FactoryBot" line replaces it.

7. **Parked plan archived correctly.** `handoff/parked-plans/factorybot-conversion.md` removed (or just the file gone if the directory has other files); `handoff/archive/2026-04-30-factorybot-conversion.md` created with status marker at top. Use `git mv` so the move shows as a rename in `git log --follow`.

8. **Diff scope.** `git status --short` should show: 7 controller test mods, test_helper.rb mod, CLAUDE.md mod, BUILD-LOG.md mod, REVIEW-REQUEST.md mod, REVIEW-FEEDBACK.md mod, ARCHITECT-BRIEF.md mod (this file), 7 deleted fixture YAMLs, parked-plan rename. App code, factories, channels, controllers, models, ActiveStorage `files/` dir all untouched.

9. **Test runtime delta.** Quick eyeball: pre-Step-8 ran ~30s, post-Step-8 should be similar or faster (no more fixture preload at test_helper load time). Report.

10. **Did Bob touch the `parallelize` line?** It must stay. Verify with grep.

Out-of-scope items found during review → BUILD-LOG Known Gaps. Do not bundle.
