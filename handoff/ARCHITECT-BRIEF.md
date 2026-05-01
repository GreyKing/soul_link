# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 11 — Enforce "One Active SoulLinkRun Per Guild" Invariant

### Context

`SoulLinkRun.current(guild_id)` lacks a hard invariant. Today, the model relies on `start_run` flows always deactivating the previous active run before creating a new one — a soft contract that:

- The Step 6 fixture-coexistence pain (`SoulLinkRun.where(guild_id: ...).destroy_all` in 7 controller test setups) was a direct symptom: two active runs sharing a guild produced silent fallback behavior in `current(guild_id)`.
- A race in `RunChannel#start_run` between two parallel WS messages could leak a second active row.
- Manual DB tampering / direct `update!(active: true)` on an inactive run while another is active would silently break the invariant.

Step 11 closes this with a real database constraint. After this step, no path — application or otherwise — can produce two active runs for the same guild.

The PROJECT-REVIEW (Soft Point #3) flagged this as a Tier-1-adjacent risk. It's not a refactor (no behavior change in the happy path); it's a guardrail against a known failure mode.

### Project Owner decisions (locked)

- **Auto-accept mode for this work.** Bob can act decisively; Reviewer + tests + the migration's backfill check are the backstops.
- **MySQL 8.0 virtual generated column + unique index.** Postgres has partial unique indexes (`UNIQUE INDEX ... WHERE active = true`); MySQL doesn't. The cleanest equivalent on MySQL 8 is a virtual generated column whose value is `guild_id` when `active = true` and `NULL` otherwise, plus a regular unique index on it. NULLs don't conflict in unique indexes, so multiple inactive runs per guild remain fine.
- **Backfill check is a hard fail.** If the migration finds a guild with multiple active runs, it must `raise ActiveRecord::IrreversibleMigration` with a clear remediation message — not silently coerce. The Project Owner's main instance has 4 trusted players; this should never trip in practice, but the safety belt matters.
- **No changes to the `start_run` flow.** The deactivate-then-create pattern in `RunChannel#start_run` (and the equivalent in `discord_bot.rb` and `lib/tasks/soul_link.rake`) already produces the right outcome on the happy path. Adding a transaction wrapper or an advisory lock is out of scope; the new DB constraint is what catches the rare race.

### Implementation

#### 1. Migration: virtual generated column + unique index

New file `db/migrate/<timestamp>_enforce_single_active_run_per_guild.rb`:

```ruby
class EnforceSingleActiveRunPerGuild < ActiveRecord::Migration[8.1]
  def up
    # Backfill check — abort if production data already violates the
    # invariant. The Architect's expectation is that this never trips
    # (the `start_run` flow always deactivates first), but raw DB
    # tampering or a never-tested race could have left dupes. Better to
    # raise loudly than to silently coerce.
    duplicate_guilds = SoulLinkRun.where(active: true)
                                  .group(:guild_id)
                                  .having("COUNT(*) > 1")
                                  .count

    if duplicate_guilds.any?
      detail = duplicate_guilds.map { |g, n| "guild_id=#{g}: #{n} active runs" }.join("; ")
      raise ActiveRecord::IrreversibleMigration, <<~MSG.squish
        Cannot enforce one-active-run-per-guild: #{detail}.
        Deactivate the extras manually before re-running:
        SoulLinkRun.where(guild_id: <id>, active: true).order(:run_number).limit(N-1).update_all(active: false)
      MSG
    end

    # MySQL 8 virtual generated column. Value is guild_id when active is
    # true, NULL otherwise. NULLs don't conflict in unique indexes, so
    # multiple inactive runs per guild remain fine. The unique index on
    # this column enforces the invariant at the storage layer.
    add_column :soul_link_runs, :active_guild_id, :bigint,
               as: "(CASE WHEN active = 1 THEN guild_id END)"

    add_index :soul_link_runs, :active_guild_id, unique: true,
              name: "index_soul_link_runs_on_active_guild_id"
  end

  def down
    remove_index :soul_link_runs, name: "index_soul_link_runs_on_active_guild_id"
    remove_column :soul_link_runs, :active_guild_id
  end
end
```

Notes:
- The column type is `:bigint` because `guild_id` is `:bigint` (it's a Discord snowflake).
- Default storage for MySQL generated columns in Rails 8.1 is VIRTUAL. No `stored:` arg → virtual. We don't need it materialized; the unique index gets recomputed on writes.
- `db/schema.rb` will dump this as `t.virtual "active_guild_id", type: :bigint, as: "..."`. Rails 8.1's schema dumper handles virtual columns natively.
- The CASE expression uses `active = 1` (not `active = true`) because MySQL stores BOOLEAN as TINYINT.

#### 2. Model: validation + `current(guild_id)` refactor

Update `app/models/soul_link_run.rb`:

**Add validation:**
```ruby
validate :no_other_active_run_for_guild, if: -> { active? }

private

def no_other_active_run_for_guild
  scope = self.class.where(guild_id: guild_id, active: true)
  scope = scope.where.not(id: id) if persisted?
  return unless scope.exists?
  errors.add(:active, "another run is already active for this guild")
end
```

The `if: -> { active? }` gate is critical: validations only run when this row IS (or is becoming) active. Updating an inactive run's other fields shouldn't trigger the check. The `where.not(id: id) if persisted?` excludes self so an already-active row can be saved (e.g., updating `gyms_defeated`).

**Simplify `current`:**
```ruby
def self.current(guild_id)
  find_by(guild_id: guild_id, active: true)
end
```

Drops the `order(run_number: :desc).first` defensive ordering. With the invariant, there's at most one active row per guild — `find_by` is exact. The existing `(guild_id, active)` index covers this query.

#### 3. Tests

New tests in `test/models/soul_link_run_test.rb`:

```ruby
# ── one-active-run invariant ─────────────────────────────────────────────

test "validates only one active run per guild" do
  # @run from setup is already active, guild=999...
  duplicate = build(:soul_link_run, guild_id: @run.guild_id, run_number: @run.run_number + 1)
  assert_not duplicate.valid?
  assert_includes duplicate.errors[:active], "another run is already active for this guild"
end

test "allows a second run for the same guild after deactivating the first" do
  @run.deactivate!
  next_run = build(:soul_link_run, guild_id: @run.guild_id, run_number: @run.run_number + 1)
  assert next_run.valid?
end

test "allows runs in different guilds to be simultaneously active" do
  other = build(:soul_link_run, guild_id: @run.guild_id + 1, run_number: 1)
  assert other.valid?
end

test "allows updating an already-active run without self-conflict" do
  @run.update!(gyms_defeated: 3)
  assert @run.persisted?
  assert_equal 3, @run.reload.gyms_defeated
end

test "DB-level unique index catches a race that bypassed validation" do
  # Simulate a TOCTOU race: validate against a snapshot that's about to
  # become stale, then INSERT directly via raw SQL skipping validations.
  # The DB constraint must catch it.
  @run.update_column(:active, false) # bypass validation cleanly
  first_active = create(:soul_link_run, guild_id: @run.guild_id, run_number: @run.run_number + 1)
  # First active row exists. Now insert a second via raw SQL bypassing AR.
  assert_raises(ActiveRecord::RecordNotUnique) do
    SoulLinkRun.connection.execute(<<~SQL)
      INSERT INTO soul_link_runs (guild_id, run_number, active, gyms_defeated, created_at, updated_at)
      VALUES (#{first_active.guild_id}, #{first_active.run_number + 1}, 1, 0, NOW(), NOW())
    SQL
  end
end

# ── current(guild_id) ────────────────────────────────────────────────────

test "current returns the single active run for a guild" do
  assert_equal @run, SoulLinkRun.current(@run.guild_id)
end

test "current returns nil when no active run exists for guild" do
  @run.deactivate!
  assert_nil SoulLinkRun.current(@run.guild_id)
end

test "current returns nil for an unknown guild" do
  assert_nil SoulLinkRun.current(@run.guild_id + 999)
end
```

The "DB-level unique index" test exercises the constraint directly via raw SQL — Bob should verify the test passes (the INSERT raises `RecordNotUnique`).

#### 4. Schema.rb dump

After running the migration, `db/schema.rb` will pick up:
```ruby
t.virtual "active_guild_id", type: :bigint, as: "(case when `active` = 1 then `guild_id` end)"
t.index ["active_guild_id"], name: "index_soul_link_runs_on_active_guild_id", unique: true
```

The exact `as:` SQL string may vary based on MySQL's normalization (backticks, casing). Bob should commit whatever Rails dumps — don't hand-edit.

### Out of Scope (do NOT expand)

- Wrapping `start_run` in an explicit transaction (the DB constraint catches the rare race; an explicit txn is a possible follow-up but adds review surface for no behavior change in the happy path)
- Advisory locking on guild_id during run creation (same reasoning)
- Refactoring `discord_bot.rb` create-run flow (Tier-1 work — fresh-session candidate)
- Refactoring `lib/tasks/soul_link.rake` create-run flows (low-risk, defer)
- Adding a Ruby-level "deactivate-then-create" helper (`SoulLinkRun.start_for_guild!(guild_id)`) — would be cleaner but expands scope
- Touching the `(guild_id, active)` composite index — it's still useful for listing past runs in `history`
- Postgres-specific paths (the project is MySQL-only per `config/database.yml`)
- Adding a CHECK constraint that `run_number > 0` or similar — separate cleanup
- Production data inspection — the migration's backfill check is the verification

### Constraints / Flags

- **Sequence the work**: write the migration first, run `db:migrate` locally + verify in `db/schema.rb`. THEN add the model validation + simplify `current`. THEN add tests. Run tests against the new constraint. The order matters because the model validation tests presume the migration's column exists.
- **310/310 must still pass** after the migration + model change. The 7 controller tests that previously had `destroy_all` lines (removed in Step 8) MUST keep passing — the new validation catches what the destroy_all used to clean up. If any test fails because two `create(:soul_link_run)` calls happen in the same transaction, Bob should investigate (likely a test that needs `active: false` on one of the creates) and fix at the test site.
- **Migration backfill check must NOT auto-fix data.** If duplicate active runs exist, raise. The Project Owner is the only one who decides which to keep. Document the manual cleanup query in the raise message.
- **`active?` predicate.** Rails generates `active?` automatically from a boolean column (it's the same as `active`). Use `active?` in the validation guard for readability.
- **Don't change the existing `(guild_id, active)` index.** It's used by `history` and other queries. The new unique index on `active_guild_id` is a separate index with a different shape.
- **Verify the schema.rb dump committed** is reproducible — running `db:migrate` from scratch should produce the same schema.rb. If Rails picks weird capitalization/quoting in the `as:` string, that's the dumper's choice — don't fight it.
- **Pre-existing rubocop offenses on lines Bob touches** — fix them. Step 10's KG-5 sweep brought the codebase to 0 offenses; Step 11 should keep it that way.

### Acceptance Criteria

- New migration `db/migrate/<timestamp>_enforce_single_active_run_per_guild.rb` exists.
- `bin/rails db:migrate` runs cleanly on the dev DB; schema.rb updates with the virtual column + unique index.
- The migration's backfill check raises a clear error if duplicate-active-runs exist (verified by manually creating dupes via `update_column(:active, true)` on an inactive run, attempting migrate, observing the raise, then cleaning up — Bob does this once locally to verify the safety belt works, then reverts the test data).
- Model `SoulLinkRun` has the new `validate :no_other_active_run_for_guild` and the simplified `find_by`-based `current` method.
- New tests in `test/models/soul_link_run_test.rb` covering: validation rejects duplicate active, validation accepts after deactivate, validation accepts different guilds, validation allows self-update, DB constraint catches raw-SQL bypass, `current` returns the single active, `current` returns nil for no-active, `current` returns nil for unknown guild. **8 new tests total.**
- Full suite green: 310 + 8 = **318/318** passing, 0 failures, 0 errors.
- `bundle exec rubocop` clean (0 offenses, same as Step 10's end state).
- Diff scope: 1 new migration, 1 model edit, 1 test file edit, 1 schema.rb update, 4 handoff files. Anything else is a Reviewer Condition.

### Approval-needed checkpoint

If the migration's backfill check finds violating data on **the dev DB** during local testing, that's expected (Bob is artificially creating dupes to verify the safety belt). Just clean up and re-run.

If the same check finds violating data on **production** (via the deploy script's `db:migrate`), the migration aborts the deploy. That's the desired behavior — it's the Project Owner's call which run to keep. **Do NOT auto-resolve in code.** A manual rake task or console session is the right cleanup path, decided by the Project Owner.

For Step 11's purposes (local dev + test): Bob assumes no prod-data interference. The Project Owner runs the deploy and gets the constraint or the loud abort.

### Files Bob Should Read

- `app/models/soul_link_run.rb` (entire file — small)
- `db/schema.rb` lines around `create_table "soul_link_runs"` (verify column types, existing indexes)
- `app/channels/run_channel.rb` `start_run` method (sanity-check the existing flow plays nice with the new constraint)
- `app/services/soul_link/discord_bot.rb` lines 235-285 (the bot's create-run flow — same sanity check)
- `lib/tasks/soul_link.rake` lines 35-55, 305-320 (rake tasks — same sanity check)
- `test/models/soul_link_run_test.rb` (entire file — to know where new tests slot in)
- `test/factories/soul_link_runs.rb` (to know the factory's defaults — guild_id is constant 999..., not a sequence)
- One existing migration in `db/migrate/` for the file-naming + style reference

DO NOT load the full app/services or app/controllers — no business logic changes.

### Files Bob Should Update at the End

- `handoff/REVIEW-REQUEST.md` — files-changed table, self-review answers, open questions, `Ready for Review: YES`
- `handoff/BUILD-LOG.md` — Step 11 history entry. **Update Architecture Decisions § Carried over** to add: "One active SoulLinkRun per guild is enforced by a virtual-column unique index on `soul_link_runs.active_guild_id` (added in Step 11). DB-level constraint catches any path that bypasses `RunChannel#start_run`'s deactivate-then-create flow."

---

## Notes for Reviewer

When this lands on your desk, focus on:

1. **Migration backfill check actually raises** on duplicate data. Bob should describe in REVIEW-REQUEST his local test of this safety belt (artificially create dupes via `update_column`, run migrate, see the raise, clean up).

2. **The virtual column expression is correct.** `(CASE WHEN active = 1 THEN guild_id END)` — when active is true, returns guild_id; when false, returns NULL (CASE without ELSE returns NULL). NULLs don't conflict in unique indexes. Multiple inactive rows for the same guild work.

3. **Schema.rb dump is committed.** Running `db:rollback && db:migrate` should produce no diff. Bob should describe this verification.

4. **Validation gate `if: -> { active? }`** is correct. Inactive→inactive updates should not trigger the validation. Active→active updates (e.g., bumping gyms_defeated) should pass via `where.not(id: id)`.

5. **The "DB constraint catches raw-SQL bypass" test** actually exercises the constraint, not just the validation. If Bob's test only triggers the validation (e.g., via `create!` with a duplicate active row), it doesn't prove the DB constraint works. The test should use `connection.execute` to bypass AR.

6. **`current(guild_id)` returns at most one row.** With `find_by(guild_id:, active: true)`, two-active-rows is now impossible. Drop the defensive `order(run_number: :desc).first`.

7. **No regression on `RunChannel#start_run`, `discord_bot.rb`, or `lib/tasks/soul_link.rake`.** Their deactivate-then-create flow still works because the deactivate updates `active_guild_id` to NULL before the new INSERT. Walk one path manually to confirm.

8. **No regression on Step 9's broadcast tests.** `SoulLinkEmulatorSaveSlot` broadcasts to `[run, :emulator]`. The run reference is unchanged. Tests should pass without modification.

9. **No changes to the controller tests' setup blocks.** The Step 8 sweep removed `destroy_all` lines; they were redundant. With Step 11's constraint, even if they came back, they'd still work — but they're not needed.

10. **The factory's static `guild_id { 999... }` is unchanged.** Tests that need a different guild explicitly pass it; the constraint catches any test that accidentally creates two active runs in the same guild (which would be a test bug, not a constraint flaw).

Out-of-scope items found during review → BUILD-LOG Known Gaps. Do not bundle.
