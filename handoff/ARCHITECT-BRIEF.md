# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 1 — `SoulLinkEmulatorSession` Migration + Model

Context: first step in the in-browser DS emulator feature. Creates the per-run, per-player ROM session record. Lifecycle: 4 sessions are created per run (Step 2/4 work) with seeds + ROMs but no `discord_user_id`; players claim one on first emulator visit. This step is **data layer only** — no service, no controller, no view.

### Migration

File: `db/migrate/<timestamp>_create_soul_link_emulator_sessions.rb`

```ruby
create_table :soul_link_emulator_sessions do |t|
  t.references :soul_link_run, null: false, foreign_key: true
  t.string  :discord_user_id                         # nullable until claimed
  t.string  :status, default: "pending", null: false # pending | generating | ready | failed
  t.string  :seed, null: false
  t.string  :rom_path                                # nullable until generation succeeds
  t.binary  :save_data, limit: 16.megabytes          # MEDIUMBLOB on MySQL 8
  t.string  :error_message
  t.timestamps
end

add_index :soul_link_emulator_sessions,
          [:soul_link_run_id, :discord_user_id],
          unique: true,
          name: "idx_emu_session_run_user"

add_index :soul_link_emulator_sessions,
          [:soul_link_run_id, :status],
          name: "idx_emu_session_run_status"
```

### Model — `app/models/soul_link_emulator_session.rb`

- `belongs_to :soul_link_run`
- `STATUSES = %w[pending generating ready failed].freeze`
- `class AlreadyClaimedError < StandardError; end` (nested inside model)

Validations:
- `validates :status, inclusion: { in: STATUSES }`
- `validates :seed, presence: true`
- `validates :discord_user_id, uniqueness: { scope: :soul_link_run_id, allow_nil: true }`

Scopes:
- `scope :ready, -> { where(status: "ready") }`
- `scope :unclaimed, -> { where(discord_user_id: nil) }`
- `scope :claimed, -> { where.not(discord_user_id: nil) }`

Instance methods:
- `ready?` → `status == "ready"`
- `claimed?` → `discord_user_id.present?`
- `rom_full_path` → `Rails.root.join(rom_path) if rom_path.present?` (returns `Pathname` or `nil`)
- `claim!(uid)` — atomic SQL-level claim:
  ```ruby
  rows = self.class.where(id: id, discord_user_id: nil).update_all(discord_user_id: uid)
  raise AlreadyClaimedError, "session #{id} already claimed" if rows.zero?
  reload
  ```

### Tests — `test/models/soul_link_emulator_session_test.rb`

Fixture: `test/fixtures/soul_link_emulator_sessions.yml` — at least 3 entries:
- `unclaimed_one` — status: ready, discord_user_id: nil, rom_path set
- `unclaimed_two` — status: ready, discord_user_id: nil, rom_path set
- `claimed` — status: ready, discord_user_id: a real fixture user id, save_data may be nil
- (Optional) `generating` — status: generating, rom_path nil

Reference an existing `soul_link_runs` fixture; check `test/fixtures/soul_link_runs.yml` for keys.

Cover:
- Status inclusion: 4 valid pass, 1 invalid fails
- Seed presence required
- Two unclaimed sessions in the same run are valid (NULL doesn't conflict in unique index)
- Two claimed sessions for same `(run, discord_user_id)` are invalid
- Scopes: `ready`, `unclaimed`, `claimed`
- `claim!` happy path: sets discord_user_id, returns reloaded record
- `claim!` raises `AlreadyClaimedError` if already claimed
- `claim!` is race-safe (concurrent claim → exactly one succeeds; can verify with two threads or just assert the SQL guard exists)
- `ready?` and `claimed?` predicates
- `rom_full_path` returns Pathname when rom_path set, nil otherwise

### Build Order

1. Generate migration: `mise exec -- ruby -S bundle exec rails g migration create_soul_link_emulator_sessions`
2. Fill the migration body, then run: `mise exec -- ruby -S bundle exec rails db:migrate`
3. Verify `db/schema.rb` shows the table + both indexes
4. Create model file
5. Create fixture file
6. Create test file
7. Run new tests: `mise exec -- ruby -S bundle exec rails test test/models/soul_link_emulator_session_test.rb`
8. Run full suite for regressions: `mise exec -- ruby -S bundle exec rails test`

### Flags

- Flag: Discord user IDs are **String** in this project (locked architecture decision). All references must be String — never integer/bigint.
- Flag: MySQL allows multiple NULLs in a composite unique index. Multiple unclaimed sessions per run is intended. The `allow_nil: true` on the AR validation matches.
- Flag: Do NOT add `cheat_overrides` column — dropped from spec.
- Flag: Do NOT add a `cheats` method — that arrives in Step 6 with the YAML.
- Flag: Do NOT add any controller, route, service, or job in this step. Data layer only.
- Flag: `claim!` must be SQL-atomic via `update_all` with `discord_user_id: nil` guard — not a Ruby-level `if claimed? then ...` check. Two players hitting `/emulator` at the same instant must produce exactly one successful claim.
- Flag: Use the existing fixture/Minitest pattern (no factories). Look at `test/fixtures/soul_link_*.yml` for tone.
- Flag: All Rails commands must be prefixed `mise exec -- ruby -S bundle exec`.
- Flag: After migration, `db/schema.rb` will be updated automatically — commit it with the migration.

### Definition of Done

- [ ] Migration runs cleanly; `db/schema.rb` shows new table with both indexes
- [ ] Model file exists with all validations, scopes, methods, and `AlreadyClaimedError`
- [ ] Fixture file exists with at least 3 entries covering the relevant states
- [ ] New model tests pass
- [ ] Race-safety of `claim!` is asserted in tests (or verified by inspection)
- [ ] Full existing test suite still passes (no regressions)

---

## Builder Plan
*Builder adds their plan here before building. Architect reviews and approves.*

1. Generate migration via `rails g migration` then fill body per brief (string discord_user_id, MEDIUMBLOB save_data via `limit: 16.megabytes`, both indexes).
2. Run `db:migrate`, verify `db/schema.rb` shows table with `idx_emu_session_run_user` (unique) and `idx_emu_session_run_status`.
3. Create model with belongs_to, STATUSES, AlreadyClaimedError, validations, scopes, predicates, `rom_full_path`, and SQL-atomic `claim!` using `update_all` guarded by `discord_user_id: nil`.
4. Create fixture (`unclaimed_one`, `unclaimed_two`, `claimed`, `generating`) referencing `active_run`; use string Discord IDs (e.g. `"153665622641737728"`).
5. Write Minitest covering all assertions in brief — including a race-safety test that pre-claims the row (simulating the SQL guard's contract) and asserts the second `claim!` raises.

---

## PATCH 2026-04-26 — `discord_user_id` column type

The original brief specified `t.string :discord_user_id` based on Architect misreading the locked rule. That rule ("Discord user IDs stored as String in all Stimulus value types") applies to JavaScript values only — JS Number loses precision above 2^53. DB columns should use `bigint` to match existing tables (`soul_link_pokemon`, `soul_link_teams`). Bob followed the original brief correctly; this is an Architect correction.

### Changes required

1. **Migration:** change `t.string :discord_user_id` → `t.bigint :discord_user_id` (still nullable, no `null: false`).
2. **Fixture:** unquote the ID — `discord_user_id: "153665622641737728"` → `discord_user_id: 153665622641737728`.
3. **Tests:** re-run new file + full suite. Race-safety test should still pass (SQL guard is type-agnostic).

### Build Order (patch)

1. `mise exec -- ruby -S bundle exec rails db:rollback`
2. Edit `db/migrate/20260426233223_create_soul_link_emulator_sessions.rb`: string → bigint
3. `mise exec -- ruby -S bundle exec rails db:migrate`
4. Verify `db/schema.rb` shows `t.bigint "discord_user_id"`
5. Edit `test/fixtures/soul_link_emulator_sessions.yml`: unquote the ID on `claimed`
6. `mise exec -- ruby -S bundle exec rails test test/models/soul_link_emulator_session_test.rb`
7. `mise exec -- ruby -S bundle exec rails test`
8. Append a "Patch Applied" section to `handoff/REVIEW-REQUEST.md` (don't rewrite — append).

### Definition of Done (patch)

- [ ] `db/schema.rb` shows `t.bigint "discord_user_id"`
- [ ] Fixture uses unquoted integer ID
- [ ] 16 new tests still pass
- [ ] 116 full suite still passes
- [ ] REVIEW-REQUEST.md has a "Patch Applied" section

### Architect Decision (will be locked into BUILD-LOG)

Discord user IDs cross a type boundary at the controller layer:
- **DB columns:** `bigint` (matches Discord snowflake numeric format)
- **Stimulus values:** `String` (JS Number loses precision above 2^53)
- **Controllers:** receive String from HTTP/session, pass to AR which coerces; pass String to Stimulus.

---

## PATCH 2 2026-04-26 — Adopt FactoryBot for new test code

Project Owner intended FactoryBot from project start but the gem was never added. Adopting it now for new test code only. **Legacy 116 tests stay on fixtures** — do not migrate them.

### Changes

1. **Gemfile** — add `gem "factory_bot_rails"` to the `:test` group (next to `capybara` / `selenium-webdriver`). Run `mise exec -- bundle install`.
2. **`test/factories/soul_link_runs.rb`** — minimum-viable factory for `SoulLinkRun`. Read `app/models/soul_link_run.rb` to find required fields and uniqueness constraints (e.g., `run_number` scoped to `guild_id` — use `sequence`). Don't gold-plate — just enough to validate.
3. **`test/factories/soul_link_emulator_sessions.rb`** — factory with traits:
   - **Default:** status `"pending"`, seed via `sequence(:seed) { |n| "seed-#{n}" }`, `discord_user_id: nil`, no `rom_path`, `association :soul_link_run`
   - **trait `:ready`** — status `"ready"`, rom_path `"storage/roms/randomized/test/seed.nds"`
   - **trait `:claimed`** — `discord_user_id` set to a unique Integer (use `sequence`); claimable means there's already a player on it
   - **trait `:generating`** — status `"generating"`, no `rom_path`
   - Combine in tests like `create(:soul_link_emulator_session, :ready, :claimed)`
4. **`test/models/soul_link_emulator_session_test.rb`** — rewrite to use factories. Replace `soul_link_runs(:active_run)` → `create(:soul_link_run)`, replace `soul_link_emulator_sessions(:unclaimed_one)` → `create(:soul_link_emulator_session, :ready)`, etc. Same 16 tests, same assertions, same coverage — only data construction changes.
5. **Delete** `test/fixtures/soul_link_emulator_sessions.yml` (no longer used).
6. **`test/test_helper.rb`** — confirm `FactoryBot::Syntax::Methods` is available so `create`/`build` work without prefix. `factory_bot_rails` includes it via Railtie automatically; if tests fail with `NoMethodError: create`, add the include to the test base class.
7. **`CLAUDE.md`** — append a short "Testing conventions" subsection under "Architecture":
   ```
   ### Testing conventions

   - **New tests** use FactoryBot factories from `test/factories/`.
   - **Legacy tests** use fixtures from `test/fixtures/`. Do not convert without an explicit step.
   - Factories should be minimum-viable — just enough to satisfy validations and associations. Don't add fields the test doesn't need.
   ```

### Build Order

1. Edit Gemfile, run `mise exec -- bundle install`. Confirm Gemfile.lock updated.
2. Create both factory files.
3. Rewrite `test/models/soul_link_emulator_session_test.rb` to use factories. Keep the GREY/ARATYPUSS/SCYTHE/ZEALOUS Discord ID constants (they're still useful as named values), but the records they reference get built via `create(...)`.
4. Delete `test/fixtures/soul_link_emulator_sessions.yml`.
5. Run new tests: `mise exec -- ruby -S bundle exec rails test test/models/soul_link_emulator_session_test.rb` — must be 16/16.
6. Run full suite: `mise exec -- ruby -S bundle exec rails test` — must be 116/116 (no regressions in legacy fixture-based tests).
7. Append the Testing conventions subsection to CLAUDE.md.
8. Append a "Patch 2 Applied" section to `handoff/REVIEW-REQUEST.md` listing every file change + test results.

### Flags

- Flag: do **NOT** convert any other test file to factories. Only `soul_link_emulator_session_test.rb`.
- Flag: do **NOT** delete any other fixture file. Legacy tests rely on them.
- Flag: factories are minimum-viable — just enough to validate. Future steps extend as needed.
- Flag: `discord_user_id` in factories is **Integer** (bigint column). Use unquoted numeric literals.
- Flag: legacy fixtures and FactoryBot coexist cleanly in Rails — fixtures load once per class, factories per test. No special config needed.
- Flag: if `bundle install` fails without `mise exec`, that means mise governs Ruby — use `mise exec -- bundle install`. Try without first.
- Flag: do not commit. Architect commits after Reviewer signoff.

### Definition of Done

- [ ] `Gemfile` + `Gemfile.lock` include `factory_bot_rails`
- [ ] `test/factories/soul_link_runs.rb` exists with minimum-viable factory
- [ ] `test/factories/soul_link_emulator_sessions.rb` exists with `:ready`, `:claimed`, `:generating` traits
- [ ] `test/models/soul_link_emulator_session_test.rb` uses factories exclusively, no fixture references
- [ ] `test/fixtures/soul_link_emulator_sessions.yml` deleted
- [ ] New file: 16/16 tests pass
- [ ] Full suite: 116/116 tests pass (no legacy regressions)
- [ ] `CLAUDE.md` has the Testing conventions subsection
- [ ] `handoff/REVIEW-REQUEST.md` has Patch 2 Applied section
