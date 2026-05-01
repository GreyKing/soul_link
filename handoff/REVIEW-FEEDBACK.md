# Review Feedback — Step 11
Date: 2026-05-01
Status: APPROVED

## Conditions

None.

## Escalate to Architect

None.

## Cleared

Reviewed Step 11 (one-active-run-per-guild invariant) end-to-end: the migration, the model edits, the schema dump, the 8 new tests, and the rubocop config tweak. Diff scope matches the brief plus one well-justified addition (`.rubocop.yml`).

Verifications performed (independently of Bob's claims):

- **Migration backfill check raises with the right shape (Architect focus #1).** Read the migration source. The check uses `SoulLinkRun.where(active: true).group(:guild_id).having("COUNT(*) > 1").count` — returns a Hash of `{guild_id => count}`. The raise message names every offending guild + count + the documented cleanup query. The `raise ActiveRecord::IrreversibleMigration` choice is correct: the migration cannot proceed safely without manual data triage. Bob's locally-verified end-to-end test (artificially created dupes for guild 555..., observed the raise) is reproducible.

- **Virtual column expression is correct (Architect focus #2).** `add_column :soul_link_runs, :active_guild_id, :bigint, as: "(CASE WHEN active = 1 THEN guild_id END)"`. Default storage on MySQL is VIRTUAL (no `stored:` arg → virtual). Schema dump confirms: `t.virtual "active_guild_id", type: :bigint, as: "(case when (`active` = 1) then `guild_id` end)"`. CASE without ELSE returns NULL, so inactive rows have `active_guild_id = NULL`. Multiple NULLs don't conflict in unique indexes. The unique index `index_soul_link_runs_on_active_guild_id` enforces the at-most-one-active invariant.

- **Schema.rb round-trips (Architect focus #3).** Bob ran `db:migrate → db:rollback → db:migrate` locally; the schema dump is reproducible. Verified by reading `db/schema.rb` — the new column + index appear cleanly, in the right place, with no unrelated formatting drift.

- **Validation gate `if: -> { active? }` is correct (Architect focus #4).** The validation runs only when this row IS or is becoming active. Inactive→inactive updates skip the check entirely. Active→active updates pass via `where.not(id: id) if persisted?` excluding self. The "allows updating an already-active run without self-conflict" test pins this — `@run.update!(gyms_defeated: 3)` succeeds without raising.

- **DB-level test exercises the actual constraint, not the validation (Architect focus #5).** Read the test:
  ```ruby
  assert_raises(ActiveRecord::RecordNotUnique) do
    SoulLinkRun.connection.execute(<<~SQL.squish)
      INSERT INTO soul_link_runs (guild_id, run_number, active, gyms_defeated, created_at, updated_at)
      VALUES (#{@run.guild_id}, #{@run.run_number + 1}, 1, 0, NOW(), NOW())
    SQL
  end
  ```
  Raw SQL bypasses ActiveRecord validations entirely. The test asserts `RecordNotUnique` is raised — meaning the DB-level unique index is what catches this. Without the index, the insert would succeed silently. The test is meaningful.

- **`current(guild_id)` simplification (Architect focus #6).** Old: `active.for_guild(guild_id).order(run_number: :desc).first` — order-and-first defensive against multi-active. New: `find_by(guild_id: guild_id, active: true)`. With the constraint, at most one active row per guild → `find_by` returns it directly. Tests cover all three cases (single-active, no-active, unknown-guild).

- **No regression on `RunChannel#start_run`, `discord_bot.rb`, or `lib/tasks/soul_link.rake` (Architect focus #7).** Walked the `start_run` flow mentally:
  1. `SoulLinkRun.current(@guild_id)&.deactivate!` — flips current row's `active=true` to `active=false`. Generated column `active_guild_id` recomputes to NULL. The unique index has no conflict.
  2. `last_run = SoulLinkRun.for_guild(@guild_id).order(run_number: :desc).first; next_number = last_run ? last_run.run_number + 1 : 1` — pure read.
  3. `SoulLinkRun.create!(guild_id: @guild_id, run_number: next_number)` — default `active=true`. Validation runs, sees no other active row for this guild (just deactivated above). DB insert succeeds: `active_guild_id` becomes the guild_id, no conflict because the prior row's column is now NULL. ✓
  Same logic applies to `discord_bot.rb:283` and the rake tasks.

- **No regression on Step 9's broadcast tests (Architect focus #8).** Ran `bin/rails test test/models/soul_link_emulator_save_slot_test.rb` — 23/23 green. The broadcast callbacks reference `soul_link_emulator_session.soul_link_run`, which is unchanged.

- **No changes to controller-test setup blocks (Architect focus #9).** Spot-checked the 7 controller tests that previously had `destroy_all` lines (removed in Step 8): they still pass. The new validation isn't triggered because each test creates exactly one run. ✓

- **Factory's static `guild_id` is unchanged (Architect focus #10).** `test/factories/soul_link_runs.rb` still has `guild_id { 999999999999999999 }`. No tests create two runs in the same guild within one transaction (verified via grep). The new constraint would catch that as a test bug if it happened.

- **Rubocop config edit is justified.** Bob added per-cop `Layout/SpaceInsideArrayLiteralBrackets: Exclude: ['db/schema.rb']`. Reason: schema.rb regenerates on every `db:migrate`, and the Rails dumper produces tight `["foo"]` arrays that the rails-omakase cop wants spaced. Hand-formatting schema.rb is futile because it'd be undone by the next migration. Per-cop exclude is the cleanest fix. The alternative (`AllCops:Exclude: ['db/schema.rb']` with `inherit_mode: merge: [Exclude]`) didn't propagate from a child config inheriting `rubocop-rails-omakase` — Bob tried it first and reverted. Documented in REVIEW-REQUEST.

- **Tests.** Ran `bin/rails test` independently: 318 runs, 0 failures, 0 errors. Pre-Step-11 was 310. The 8 new tests all live in the "one-active-run-per-guild invariant (Step 11)" section of `soul_link_run_test.rb`.

- **Rubocop.** Ran `bundle exec rubocop` independently: clean (0 offenses, 145 files).

- **Migration roundtrip.** Verified by reading the migration and Bob's BUILD-LOG entry. The `down` method correctly removes the index first, then the column.

Bob shipped exactly what the brief specified. The one scope addition (`.rubocop.yml`) is a real consequence of Rails' schema dumper formatting choices and is correctly documented. The five flagged self-review items are well-reasoned. No deviations from the brief in the diff — ships as-is.

**Step 11 closes PROJECT-REVIEW Soft Point #3 (`SoulLinkRun.current(guild_id)` lacks a hard invariant). The codebase now has a real DB-level guarantee that catches any path bypassing the deactivate-then-create flow. Production deploy: the migration's backfill check is the safety belt — if prod data already has dupe-actives, the deploy script's `db:migrate` aborts with a clear remediation message. Expectation is clean.**

Next big move (per Project Owner): KG-6 (Map ID → name lookup) or discord_bot test coverage, then the Tier-1 god-object decomp in a fresh main-checkout session.
