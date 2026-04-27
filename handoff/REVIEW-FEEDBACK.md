# Review Feedback — Step 1
Date: 2026-04-26
Ready for Builder: YES

## Must Fix

None.

## Should Fix

None inline. The single substantive concern (column type inconsistency) is a
brief-vs-existing-schema question, not a Bob defect — see Escalate below.

## Escalate to Architect

- **`discord_user_id` column type inconsistency.** Bob followed the Step 1
  brief literally: `t.string :discord_user_id` on
  `soul_link_emulator_sessions`. But every other table in the project that
  carries `discord_user_id` declares it `bigint`:
  - `db/schema.rb:142` — `soul_link_pokemon.discord_user_id` is `t.bigint`,
    `null: false`
  - `db/schema.rb:208` — `soul_link_teams.discord_user_id` is `t.bigint`,
    `null: false`
  - `test/fixtures/soul_link_pokemon.yml:10–13` — fixtures use unquoted
    integer literals (`153665622641737728`)
  - The new fixture `test/fixtures/soul_link_emulator_sessions.yml:15` uses
    a quoted string (`"153665622641737728"`)

  The session payload from Discord OAuth (`sessions_controller.rb:38`) is a
  string, and existing controllers (e.g. `teams_controller.rb:11`) pass that
  string into AR queries against bigint columns — Rails coerces transparently
  for single-table queries today. The risk surfaces the moment Step 2+ joins
  `soul_link_emulator_sessions` to `soul_link_pokemon` or `soul_link_teams`
  on `discord_user_id`: MySQL will be comparing `VARCHAR` to `BIGINT` across
  tables, which is silently lossy on out-of-range values and defeats index
  use on at least one side.

  Two valid resolutions, both architectural:
  1. The brief is correct (String is the new standard), and the older
     `bigint` columns are legacy that should be migrated. Step 1 is fine;
     a follow-up step retypes the existing columns.
  2. The brief is wrong (existing `bigint` is the standard), and Step 1
     should use `t.bigint :discord_user_id` to match. The migration would
     need amending.

  Either is defensible. Bob explicitly flagged this in REVIEW-REQUEST so
  it's surfaced for Architect, not slipped through. Per Project Owner
  instruction, this does not block Step 1 — but it needs an Architect
  ruling before any cross-table join on `discord_user_id` lands.

## Cleared

Reviewed migration, model, fixture, schema, and the 16 model tests against
the brief.

- **Migration** (`db/migrate/20260426233223_create_soul_link_emulator_sessions.rb`)
  matches the brief verbatim. Schema (`db/schema.rb:122–135`) shows the
  table with all three expected indexes: `idx_emu_session_run_user`
  (unique composite on `run_id, discord_user_id`),
  `idx_emu_session_run_status` (composite), and the FK-implied
  `index_soul_link_emulator_sessions_on_soul_link_run_id`. `save_data` is
  `size: :long` (MEDIUMBLOB), `seed` is `null: false`, status defaults to
  `"pending"`. FK to `soul_link_runs` confirmed at `db/schema.rb:223`.
- **Model** (`app/models/soul_link_emulator_session.rb`) has all required
  validations, scopes, predicates, `rom_full_path`, `AlreadyClaimedError`,
  and the SQL-atomic `claim!`. `update_all` runs through AR parameter
  binding — no SQL injection surface. `rom_full_path` is nil-safe via
  `.present?` (handles both nil and `""`, asserted in
  `test/models/soul_link_emulator_session_test.rb:164–169`).
- **Race-safety test**
  (`test/models/soul_link_emulator_session_test.rb:116–134`) is genuine,
  not theatrical. It loads two AR copies, claims with the first, then
  attempts to claim with the stale-in-memory second. If `claim!` were
  rewritten to use a Ruby-level `if claimed? then raise` pre-check, the
  stale copy's in-memory `@discord_user_id` would still be `nil`, the
  predicate would return `false`, and the second claim would silently
  overwrite. The test would then fail because no error was raised. The
  SQL `WHERE discord_user_id IS NULL` guard is what makes the test pass.
  Real assertion of a real contract.
- **Multiple NULLs in unique index** is exercised: `unclaimed_one` and
  `unclaimed_two` both reference `active_run` with no `discord_user_id`,
  and the full suite (116 runs) loads them without conflict — proving
  MySQL's multiple-NULL behavior holds in practice and the
  `allow_nil: true` validation matches.
- **All Brief Flags honored** (subject to Architect ruling on String vs.
  bigint above):
  - No `cheat_overrides` column.
  - No `cheats` method.
  - No controllers / routes / services / jobs / views added.
  - `claim!` is SQL-atomic via `update_all` with `discord_user_id: nil`
    guard, not a Ruby pre-check.
  - Fixture/Minitest pattern (no factories).
  - Schema regenerated and committed alongside the migration.
- **No scope creep.** Bob added exactly the four files specified plus the
  auto-regenerated `db/schema.rb`. Nothing else touched.
- **DoD** verified independently: migration ran, schema shows table with
  both named indexes, model has all required surface area, fixture has
  four states, 16 new tests pass, 116/116 full suite passes, race-safety
  asserted in test (not just inspection).

Step 1 is clear.

---

## Patch Review (Patches 1 + 2)
Date: 2026-04-26
Ready for Builder: YES

## Must Fix

None.

## Should Fix

None.

## Escalate to Architect

None. Patch 1's escalation (String vs. bigint) was resolved by Architect's
ruling and Patch 2 was the follow-up cleanup. Both patches landed inside the
brief.

## Cleared

Reviewed both patches end-to-end against their briefs. Independently re-ran:

```
mise exec -- ruby -S bundle exec rails test test/models/soul_link_emulator_session_test.rb
16 runs, 62 assertions, 0 failures, 0 errors, 0 skips

mise exec -- ruby -S bundle exec rails test
116 runs, 311 assertions, 0 failures, 0 errors, 0 skips
```

- **Column type flipped correctly.** `db/schema.rb:124` shows
  `t.bigint "discord_user_id"`. Migration line 5 (`t.bigint :discord_user_id`)
  matches. No stray `t.string :discord_user_id` anywhere. Index on
  `(soul_link_run_id, discord_user_id)` re-built unchanged at schema:132.
- **Factories are minimum-viable.** `test/factories/soul_link_runs.rb` has
  exactly the fields needed to pass `SoulLinkRun`'s `presence` and uniqueness
  validations (`guild_id`, `run_number` sequence, `active: true`). The 1000+n
  run_number offset is a defensive choice against the legacy `active_run`
  fixture (run_number 1) and is justified in the in-file comment — not
  gold-plating. `test/factories/soul_link_emulator_sessions.rb` has only the
  default fields needed (`status`, `seed`, `discord_user_id: nil`,
  `rom_path: nil`, `association :soul_link_run`) plus the three traits
  the brief named (`:ready`, `:claimed`, `:generating`). No speculative
  attributes.
- **Trait combinations work.** Line 14 of the rewritten test:
  `create(:soul_link_emulator_session, :ready, :claimed, soul_link_run: @run)`
  — matches the pattern Architect specified. The combined record gets
  `status: "ready"`, a numeric `discord_user_id` from the sequence, and
  `rom_path` set. Tests pass with that combination.
- **`discord_user_id` is Integer in factories.** Factory line 15:
  `sequence(:discord_user_id) { |n| 153665622641737728 + n }` — unquoted
  numeric literal, sequence math produces Integer values, matches bigint
  column. The base 153665622641737728 is the original GREY snowflake — it
  is *only* used as the sequence offset, and the snowflake range it
  generates (153665622641737729+) does not collide with `ARATYPUSS`,
  `SCYTHE`, or `ZEALOUS` constants used as `claim!` targets. Verified by
  the unique-index test at `soul_link_emulator_session_test.rb:54` not
  tripping.
- **Race-safety test still real.**
  `test/models/soul_link_emulator_session_test.rb:113–131` is intact and
  still genuinely asserts the SQL-level contract. Two AR copies are loaded
  (`fresh_copy` and `stale_copy`), `fresh_copy` claims with `ARATYPUSS`,
  the stale copy's in-memory `@discord_user_id` is asserted nil at line
  124 — that assertion is the load-bearing one. If `claim!` were rewritten
  to a Ruby-level `if claimed? then raise` check, the stale copy would
  return `false` from `claimed?` (its in-memory value is still nil) and
  the second `claim!` would silently succeed. Only the SQL
  `WHERE discord_user_id IS NULL` guard makes the test raise.
- **Trait composition contract.** `:ready` + `:claimed` together correctly
  produce `status: "ready"` (later trait wins on overlapping fields, but
  neither trait sets `status` to anything other than `ready` here, so the
  combination is unambiguous). `:generating` overwrites `status` and
  `rom_path` and is used standalone. No trait conflict surfaces in the
  tests.
- **`include FactoryBot::Syntax::Methods` placement is safe.** Added to
  `ActiveSupport::TestCase` in `test_helper.rb:19`. The included methods
  (`create`, `build`, `attributes_for`, `build_stubbed`, `create_list`,
  `build_list`) do not collide with Rails test base method names. Fixtures
  (`fixtures :all` line above it) and factories coexist — confirmed by the
  full 116-suite run.
- **Fixture file deleted.** `test/fixtures/soul_link_emulator_sessions.yml`
  is gone. No code path references it (the only consumer was the test
  Bob rewrote).
- **Assertion count delta (313 → 311).** The two-line drop is in the
  rewritten `test "two unclaimed sessions in the same run are valid"` test
  (lines 39–52). New assertions: `assert_nil @unclaimed.discord_user_id`,
  `assert_nil other.discord_user_id`,
  `assert_equal @unclaimed.soul_link_run_id, other.soul_link_run_id`,
  `assert extra.valid?`, `assert extra.save` — five assertions that
  cover the actual contract (two NULL `discord_user_id`s in the same
  run do not violate the unique index). The dropped assertions were
  fixture-shape echoes (asserting on values that came from the YAML
  literal). The contract under test is genuinely preserved. No real
  coverage lost.
- **No unintended scope.** Only the files Bob listed changed. No other
  test was migrated to factories. No other fixture was deleted.
  `CLAUDE.md` got exactly the testing-conventions block the brief asked
  for, placed under "Architecture → Quick Reference" as specified.
- **No legacy regressions.** Full suite at 116/116, 311 assertions. The
  net assertion drop is fully accounted for by the rewritten test above —
  no legacy fixture-based test lost coverage. The factory file's
  `run_number` sequence offset of `1000 + n` defensively avoids any
  collision with the `active_run` fixture (run_number 1) when both load
  in the same test class.
- **`active { true }` in the run factory** is technically redundant with
  the column default, but it is documentation-style explicit and does
  not constitute gold-plating in a harmful sense. Leaving it.
- **Patch 2 brief flags honored.** `factory_bot_rails` resolved cleanly
  (`Gemfile.lock:132,134,466`). Factories built. Test rewritten. Fixture
  deleted. CLAUDE.md updated. No commit yet.

Patches 1 and 2 are clear.
