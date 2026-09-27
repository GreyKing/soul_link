# Solid Cable + Solid Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the in-process `async` Action Cable and Active Job adapters
with Solid Cable and Solid Queue, both stored in the existing MySQL database.
Afterwards, bot-originated changes live-update open dashboards and jobs
survive restarts.

**Architecture:**

- One migration adds the `solid_queue_*` and `solid_cable_messages` tables to
  the primary database. There is no `connects_to` anywhere.
- Development and production use `solid_cable` for Action Cable and
  `solid_queue` for Active Job. Test keeps the `test` adapters.
- In production, a new `soul-link-jobs` systemd service runs
  `bin/jobs --mode async`: one process, with the worker, dispatcher and
  scheduler as threads. The existing deploy workflow installs, enables and
  restarts it.

**Tech Stack:** Rails 8.1.1, MySQL 8, solid_cable 4.1.0, solid_queue 1.7.0,
systemd, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-27-solid-cable-queue-design.md`

---

## Ground rules

- Work in the worktree `/Users/gferm/personal/projects/soul_link/.claude/worktrees/practical-lehmann-8234cf`
  on branch `claude/serene-cartwright-be5327`. Run every command from there.
- Commit after each task. Commits stay on the branch until Task 7, which is
  the only deploy.
- Output-filtering hook: `bin/rails test > file` gets rewritten into a
  one-line summary. Always run tests like this:
  ```bash
  rtk proxy bin/rails test <paths> > tmp/t.txt 2>&1
  grep -E "runs, .*assertions" tmp/t.txt
  grep -A8 -E "^Failure|^Error" tmp/t.txt
  ```
  Use the same `rtk proxy ... > file` pattern for rubocop and brakeman.
- Prefer `bin/rails`. If it fails to boot, fall back to
  `mise exec -- bundle exec rails`.
- Baseline on `80c2299`: 1017 runs, 0 failures, 39 rubocop offenses, 2 weak
  brakeman warnings. None of those counts as a regression.
- Do **not** touch production outside the deploy (Task 7) without asking the
  user first. That includes SSH, server env, systemd and manual migrations.

## File map

| File | Change | Task |
|---|---|---|
| `test/infrastructure/solid_queue_adapter_test.rb` | Create | 1 |
| `test/infrastructure/solid_cable_adapter_test.rb` | Create | 1 |
| `Gemfile`, `Gemfile.lock` | Add `solid_cable` and `solid_queue`, replace the old comment | 1 |
| `db/migrate/20260927120000_create_solid_queue_and_solid_cable_tables.rb` | Create | 1 |
| `db/schema.rb` | Regenerated with the Solid tables | 1 |
| `test/infrastructure/cable_config_test.rb` | Create | 2 |
| `config/cable.yml` | solid_cable for development and production | 2 |
| `config/environments/development.rb` | `queue_adapter = :solid_queue` | 2 |
| `config/environments/production.rb` | `queue_adapter = :solid_queue`, comments | 2 |
| `config/cache.yml`, `db/cache_schema.rb`, `db/cable_schema.rb`, `db/queue_schema.rb` | Delete | 2 |
| `config/puma.rb` | Remove the `plugin :solid_queue` line | 2 |
| `config/deploy/soul-link-jobs.service` | Create | 3 |
| `Procfile.dev` | Add a `jobs` process | 3 |
| `.github/workflows/deploy.yml` | Install, enable and restart `soul-link-jobs` | 3 |
| `test/infrastructure/error_logging_test.rb` | Create | 3A |
| `config/initializers/error_logging.rb` | Create: log `Rails.error` reports | 3A |
| `config/recurring.yml` | Clear finished jobs in development too | 3A |
| `lib/tasks/soul_link/debug_save.rake` | Reword the stale comment | 4 |
| `config/cable.yml` | Header comment precision | 4 |
| `.claude/documents/deployment.md`, `CLAUDE.md` | Docs | 4 |

---

### Task 1: Gems and tables in the primary database

**Files:**
- Create: `test/infrastructure/solid_queue_adapter_test.rb`
- Create: `test/infrastructure/solid_cable_adapter_test.rb`
- Modify: `Gemfile` (the comment block after `gem "tzinfo-data"`), `Gemfile.lock`
- Create: `db/migrate/20260927120000_create_solid_queue_and_solid_cable_tables.rb`
- Modify: `db/schema.rb` (regenerated)

- [ ] **Step 1: Write the failing Solid Queue test**

Create `test/infrastructure/solid_queue_adapter_test.rb`:

```ruby
require "test_helper"

# Jobs must live in the primary database so they survive a restart and any
# process (Puma, the Discord bot, the jobs worker) can enqueue them. The
# adapter is called directly because ActiveJob::TestHelper swaps every job
# class onto the test adapter.
class SolidQueueAdapterTest < ActiveSupport::TestCase
  class ProbeJob < ApplicationJob
    cattr_accessor :performed_with

    def perform(run, note)
      self.class.performed_with = [ run, note ]
    end
  end

  test "Solid Queue uses the primary database" do
    assert_equal ActiveRecord::Base.connection_db_config, SolidQueue::Record.connection_db_config
  end

  test "an enqueued job is stored in the database and runs from what was stored" do
    run = create(:soul_link_run)
    job = ProbeJob.new(run, "hello")

    assert_difference -> { SolidQueue::Job.count } => 1, -> { SolidQueue::ReadyExecution.count } => 1 do
      ActiveJob::QueueAdapters::SolidQueueAdapter.new.enqueue(job)
    end

    stored = SolidQueue::Job.find_by!(active_job_id: job.job_id)
    assert_equal ProbeJob.name, stored.class_name

    ProbeJob.performed_with = nil
    ActiveJob::Base.execute(stored.arguments)
    assert_equal [ run, "hello" ], ProbeJob.performed_with
  end
end
```

- [ ] **Step 2: Write the failing Solid Cable test**

Create `test/infrastructure/solid_cable_adapter_test.rb`:

```ruby
require "test_helper"

# Broadcasts must go through the primary database so a broadcast from any
# process (the Discord bot, the jobs worker, a console) reaches browsers
# connected to Puma.
class SolidCableAdapterTest < ActiveSupport::TestCase
  CHANNEL = "phase2:probe".freeze

  test "Solid Cable uses the primary database" do
    assert_equal ActiveRecord::Base.connection_db_config, SolidCable::Record.connection_db_config
  end

  test "a broadcast is written to solid_cable_messages" do
    adapter = ActionCable::SubscriptionAdapter::SolidCable.new(ActionCable.server)
    messages = -> { SolidCable::Message.where(channel_hash: SolidCable::Message.channel_hash_for(CHANNEL)) }

    assert_difference -> { messages.call.count }, 1 do
      adapter.broadcast(CHANNEL, { hello: "world" }.to_json)
      # solid_cable 4.1 writes from a background thread. shutdown closes the
      # queue and joins the writer, so the insert has happened afterwards.
      adapter.shutdown
    end

    assert_equal({ "hello" => "world" }, JSON.parse(messages.call.last.payload))
  end
end
```

- [ ] **Step 3: Run both tests and confirm they fail**

```bash
rtk proxy bin/rails test test/infrastructure > tmp/t.txt 2>&1
grep -E "runs, .*assertions" tmp/t.txt
grep -A8 -E "^Failure|^Error" tmp/t.txt
```

Expected: 4 errors, all `NameError: uninitialized constant SolidQueue` (or
`SolidCable`, `ActiveJob::QueueAdapters::SolidQueueAdapter`,
`ActionCable::SubscriptionAdapter::SolidCable`).

- [ ] **Step 4: Add the gems**

In `Gemfile`, replace this block:

```ruby
# Rails 8.1 defaults to solid_cache/solid_queue/solid_cable which each require
# separate database configs. We don't need background jobs, durable cache, or
# Action Cable, so these are removed.
```

with:

```ruby
# Action Cable pub/sub and Active Job backend. Both keep their tables in the
# primary database (no separate cable/queue databases). Solid Cache is not used.
gem "solid_cable"
gem "solid_queue"
```

Then run:

```bash
bundle install
grep -E "^    solid_(cable|queue) " Gemfile.lock
```

Expected: `solid_cable (4.1.0)` and `solid_queue (1.7.0)`, or newer. If a
newer version resolves, diff its
`lib/generators/solid_queue/install/templates/db/queue_schema.rb` and
`lib/generators/solid_cable/install/templates/db/cable_schema.rb`
(`bundle exec gem contents solid_queue | grep queue_schema`) against the
migration in Step 5, and copy any new columns or tables into it.

- [ ] **Step 5: Write the migration**

Create `db/migrate/20260927120000_create_solid_queue_and_solid_cable_tables.rb`.
The tables are copied from the solid_queue 1.7.0 and solid_cable 4.1.0
install templates:

```ruby
# Solid Queue and Solid Cable tables, kept in the primary database instead of
# the separate queue/cable databases Rails generates by default. Copied from
# the install templates of solid_queue 1.7.0 and solid_cable 4.1.0.
class CreateSolidQueueAndSolidCableTables < ActiveRecord::Migration[8.1]
  def change
    create_table "solid_queue_jobs" do |t|
      t.string "queue_name", null: false
      t.string "class_name", null: false
      t.text "arguments"
      t.integer "priority", default: 0, null: false
      t.string "active_job_id"
      t.datetime "scheduled_at"
      t.datetime "finished_at"
      t.string "concurrency_key"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.bigint "batch_id"
      t.index [ "active_job_id" ], name: "index_solid_queue_jobs_on_active_job_id"
      t.index [ "batch_id" ], name: "index_solid_queue_jobs_on_batch_id"
      t.index [ "class_name" ], name: "index_solid_queue_jobs_on_class_name"
      t.index [ "finished_at" ], name: "index_solid_queue_jobs_on_finished_at"
      t.index [ "queue_name", "finished_at" ], name: "index_solid_queue_jobs_for_filtering"
      t.index [ "scheduled_at", "finished_at" ], name: "index_solid_queue_jobs_for_alerting"
    end

    create_table "solid_queue_blocked_executions" do |t|
      t.bigint "job_id", null: false
      t.string "queue_name", null: false
      t.integer "priority", default: 0, null: false
      t.string "concurrency_key", null: false
      t.datetime "expires_at", null: false
      t.datetime "created_at", null: false
      t.index [ "concurrency_key", "priority", "job_id" ], name: "index_solid_queue_blocked_executions_for_release"
      t.index [ "expires_at", "concurrency_key" ], name: "index_solid_queue_blocked_executions_for_maintenance"
      t.index [ "job_id" ], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
    end

    create_table "solid_queue_claimed_executions" do |t|
      t.bigint "job_id", null: false
      t.bigint "process_id"
      t.datetime "created_at", null: false
      t.index [ "job_id" ], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
      t.index [ "process_id", "job_id" ], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
    end

    create_table "solid_queue_failed_executions" do |t|
      t.bigint "job_id", null: false
      t.text "error"
      t.datetime "created_at", null: false
      t.index [ "job_id" ], name: "index_solid_queue_failed_executions_on_job_id", unique: true
    end

    create_table "solid_queue_pauses" do |t|
      t.string "queue_name", null: false
      t.datetime "created_at", null: false
      t.index [ "queue_name" ], name: "index_solid_queue_pauses_on_queue_name", unique: true
    end

    create_table "solid_queue_processes" do |t|
      t.string "kind", null: false
      t.datetime "last_heartbeat_at", null: false
      t.bigint "supervisor_id"
      t.integer "pid", null: false
      t.string "hostname"
      t.text "metadata"
      t.datetime "created_at", null: false
      t.string "name", null: false
      t.index [ "last_heartbeat_at" ], name: "index_solid_queue_processes_on_last_heartbeat_at"
      t.index [ "name", "supervisor_id" ], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
      t.index [ "supervisor_id" ], name: "index_solid_queue_processes_on_supervisor_id"
    end

    create_table "solid_queue_ready_executions" do |t|
      t.bigint "job_id", null: false
      t.string "queue_name", null: false
      t.integer "priority", default: 0, null: false
      t.datetime "created_at", null: false
      t.index [ "job_id" ], name: "index_solid_queue_ready_executions_on_job_id", unique: true
      t.index [ "priority", "job_id" ], name: "index_solid_queue_poll_all"
      t.index [ "queue_name", "priority", "job_id" ], name: "index_solid_queue_poll_by_queue"
    end

    create_table "solid_queue_recurring_executions" do |t|
      t.bigint "job_id", null: false
      t.string "task_key", null: false
      t.datetime "run_at", null: false
      t.datetime "created_at", null: false
      t.index [ "job_id" ], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
      t.index [ "task_key", "run_at" ], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
    end

    create_table "solid_queue_recurring_tasks" do |t|
      t.string "key", null: false
      t.string "schedule", null: false
      t.string "command", limit: 2048
      t.string "class_name"
      t.text "arguments"
      t.string "queue_name"
      t.integer "priority", default: 0
      t.boolean "static", default: true, null: false
      t.text "description"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index [ "key" ], name: "index_solid_queue_recurring_tasks_on_key", unique: true
      t.index [ "static" ], name: "index_solid_queue_recurring_tasks_on_static"
    end

    create_table "solid_queue_scheduled_executions" do |t|
      t.bigint "job_id", null: false
      t.string "queue_name", null: false
      t.integer "priority", default: 0, null: false
      t.datetime "scheduled_at", null: false
      t.datetime "created_at", null: false
      t.index [ "job_id" ], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
      t.index [ "scheduled_at", "priority", "job_id" ], name: "index_solid_queue_dispatch_all"
    end

    create_table "solid_queue_semaphores" do |t|
      t.string "key", null: false
      t.integer "value", default: 1, null: false
      t.datetime "expires_at", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index [ "expires_at" ], name: "index_solid_queue_semaphores_on_expires_at"
      t.index [ "key", "value" ], name: "index_solid_queue_semaphores_on_key_and_value"
      t.index [ "key" ], name: "index_solid_queue_semaphores_on_key", unique: true
    end

    create_table "solid_queue_batches" do |t|
      t.string "active_job_batch_id"
      t.string "description"
      t.text "on_finish"
      t.text "on_success"
      t.text "on_failure"
      t.text "metadata"
      t.integer "total_jobs", default: 0, null: false
      t.integer "completed_jobs", default: 0, null: false
      t.integer "failed_jobs", default: 0, null: false
      t.datetime "enqueued_at"
      t.datetime "finished_at"
      t.datetime "failed_at"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index [ "active_job_batch_id" ], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
      t.index [ "finished_at" ], name: "index_solid_queue_batches_on_finished_at"
    end

    create_table "solid_queue_batch_executions" do |t|
      t.bigint "job_id", null: false
      t.bigint "batch_id", null: false
      t.datetime "created_at", null: false
      t.index [ "job_id" ], name: "index_solid_queue_batch_executions_on_job_id", unique: true
      t.index [ "batch_id" ], name: "index_solid_queue_batch_executions_on_batch_id"
    end

    add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
    add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
    add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
    add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
    add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
    add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
    add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
    add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade

    create_table "solid_cable_messages" do |t|
      t.binary "channel", limit: 1024, null: false
      t.binary "payload", limit: 536870912, null: false
      t.datetime "created_at", null: false
      t.integer "channel_hash", limit: 8, null: false
      t.index [ "channel_hash" ], name: "index_solid_cable_messages_on_channel_hash"
      t.index [ "created_at" ], name: "index_solid_cable_messages_on_created_at"
    end
  end
end
```

- [ ] **Step 6: Migrate development, check the reversal, and check the schema diff**

```bash
bin/rails db:migrate
bin/rails db:rollback
bin/rails db:migrate
git diff --stat db/schema.rb
grep -c 'create_table "solid_' db/schema.rb
grep -n "define(version:" db/schema.rb
```

Expected:
- The rollback drops every table cleanly. `change` reverses `create_table`
  and `add_foreign_key`.
- `grep -c` prints `14`: 13 `solid_queue_*` tables plus `solid_cable_messages`.
- The version is `2026_09_27_120000`.

Open `git diff db/schema.rb` in the Read tool, not through the filtered
`git diff`. It should only add the Solid tables and foreign keys and bump the
version. If the dump also changes existing tables, your dev DB has drifted.
Restore those hunks by hand so that only the Solid additions remain.

- [ ] **Step 7: Run the new tests and confirm they pass**

```bash
rtk proxy bin/rails test test/infrastructure > tmp/t.txt 2>&1
grep -E "runs, .*assertions" tmp/t.txt
grep -A8 -E "^Failure|^Error" tmp/t.txt
```

Expected: `4 runs, ... 0 failures, 0 errors`. Rails loads the new schema into
the test databases automatically (`maintain_test_schema`). If it complains
about pending migrations, run `bin/rails db:test:prepare` and retry.

- [ ] **Step 8: Commit**

```bash
git add Gemfile Gemfile.lock db/migrate/20260927120000_create_solid_queue_and_solid_cable_tables.rb db/schema.rb test/infrastructure/solid_queue_adapter_test.rb test/infrastructure/solid_cable_adapter_test.rb
git commit -m "feat: add Solid Queue and Solid Cable tables to the primary database"
```

---

### Task 2: Point development and production at the Solid adapters, remove dead config

**Files:**
- Create: `test/infrastructure/cable_config_test.rb`
- Modify: `config/cable.yml` (whole file)
- Modify: `config/environments/development.rb` (after the `verbose_enqueue_logs` line)
- Modify: `config/environments/production.rb` (the cache and queue lines)
- Modify: `config/puma.rb` (the two `solid_queue` plugin lines)
- Delete: `config/cache.yml`, `db/cache_schema.rb`, `db/cable_schema.rb`, `db/queue_schema.rb`

- [ ] **Step 1: Write the failing cable config test**

Create `test/infrastructure/cable_config_test.rb`:

```ruby
require "test_helper"

# The bot and the jobs worker are separate processes. Only a database-backed
# adapter lets their broadcasts reach browsers connected to Puma.
class CableConfigTest < ActiveSupport::TestCase
  def cable_config(env)
    ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/cable.yml")).fetch(env)
  end

  %w[development production].each do |env|
    test "#{env} broadcasts through Solid Cable in the primary database" do
      config = cable_config(env)

      assert_equal "solid_cable", config["adapter"]
      assert_not config.key?("connects_to"), "Solid Cable must share the primary database"
      assert_equal "0.1.seconds", config["polling_interval"]
      assert_equal "1.day", config["message_retention"]
    end
  end

  test "test keeps the in-memory test adapter" do
    assert_equal({ "adapter" => "test" }, cable_config("test"))
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
rtk proxy bin/rails test test/infrastructure/cable_config_test.rb > tmp/t.txt 2>&1
grep -E "runs, .*assertions" tmp/t.txt
grep -A8 -E "^Failure|^Error" tmp/t.txt
```

Expected: 2 failures, `Expected: "solid_cable" Actual: "async"`, for
development and production. The test-environment case passes.

- [ ] **Step 3: Rewrite `config/cable.yml`**

Replace the whole file with:

```yaml
# Solid Cable stores broadcasts in the primary database (solid_cable_messages),
# so a broadcast from any process (Puma, the Discord bot, the jobs worker, a
# console) reaches every subscribed browser. Old messages are trimmed
# automatically after message_retention.
development: &solid_cable
  adapter: solid_cable
  polling_interval: 0.1.seconds
  message_retention: 1.day

test:
  adapter: test

production:
  <<: *solid_cable
```

- [ ] **Step 4: Run the cable config test and confirm it passes**

```bash
rtk proxy bin/rails test test/infrastructure/cable_config_test.rb > tmp/t.txt 2>&1
grep -E "runs, .*assertions" tmp/t.txt
```

Expected: `3 runs, ... 0 failures, 0 errors`.

- [ ] **Step 5: Switch Active Job to Solid Queue in development**

In `config/environments/development.rb`, after these lines:

```ruby
  # Highlight code that enqueued background job in logs.
  config.active_job.verbose_enqueue_logs = true
```

add:

```ruby

  # Durable jobs in the primary database, same as production. bin/dev starts
  # the worker (see Procfile.dev).
  config.active_job.queue_adapter = :solid_queue
```

- [ ] **Step 6: Switch Active Job to Solid Queue in production**

In `config/environments/production.rb`, replace:

```ruby
  # Use in-memory cache (no separate cache database needed for this app).
  config.cache_store = :memory_store

  # Use inline queue adapter (no background jobs needed for this app).
  config.active_job.queue_adapter = :async
```

with:

```ruby
  # Use in-memory cache. Solid Cache is not used.
  config.cache_store = :memory_store

  # Durable jobs in the primary database, run by the soul-link-jobs systemd
  # service (bin/jobs --mode async).
  config.active_job.queue_adapter = :solid_queue
```

- [ ] **Step 7: Remove the Puma plugin line**

In `config/puma.rb`, delete these lines (and one of the blank lines around
them):

```ruby
# Run the Solid Queue supervisor inside of Puma for single-server deployments.
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]
```

- [ ] **Step 8: Delete the stale Solid files**

```bash
git rm config/cache.yml db/cache_schema.rb db/cable_schema.rb db/queue_schema.rb
```

Keep `config/queue.yml`, `config/recurring.yml` and `bin/jobs`; they are now
used.

- [ ] **Step 9: Verify that development and production resolve the new adapters**

```bash
rtk proxy bin/rails runner 'puts ActiveJob::Base.queue_adapter_name; puts ActionCable.server.pubsub.class' > tmp/dev_adapters.txt 2>&1; cat tmp/dev_adapters.txt
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 SOUL_LINK_HOST=localhost rtk proxy bin/rails runner 'puts ActiveJob::Base.queue_adapter_name; puts ActionCable.server.pubsub.class' > tmp/prod_adapters.txt 2>&1; cat tmp/prod_adapters.txt
```

Expected: both files contain exactly these two lines:

```
solid_queue
ActionCable::SubscriptionAdapter::SolidCable
```

The production run doesn't need a production database, because neither line
queries it. If it fails on credentials, rerun with
`RAILS_MASTER_KEY=$(cat /Users/gferm/personal/projects/soul_link/config/master.key)`
prepended. Never print or commit that key.

- [ ] **Step 10: Run the infrastructure tests plus the job and channel suites**

```bash
rtk proxy bin/rails test test/infrastructure test/jobs test/channels test/models > tmp/t.txt 2>&1
grep -E "runs, .*assertions" tmp/t.txt
grep -A8 -E "^Failure|^Error" tmp/t.txt
```

Expected: 0 failures, 0 errors. The test environment still uses the `test`
cable adapter and `ActiveJob::TestHelper`'s test adapter.

- [ ] **Step 11: Commit**

```bash
git add config/cable.yml config/environments/development.rb config/environments/production.rb config/puma.rb test/infrastructure/cable_config_test.rb
git commit -m "feat: use Solid Cable and Solid Queue in development and production"
```

The `git rm` from Step 8 is already staged and goes into this commit.

---

### Task 3: Worker process (systemd unit, Procfile.dev, deploy)

**Files:**
- Create: `config/deploy/soul-link-jobs.service`
- Modify: `Procfile.dev`
- Modify: `.github/workflows/deploy.yml` (the unit-install block and the restart lines)

- [ ] **Step 1: Check the async-mode configuration with the pool the unit will use**

```bash
RAILS_MAX_THREADS=10 rtk proxy bin/jobs check --mode async > tmp/jobs_check.txt 2>&1; cat tmp/jobs_check.txt
```

Expected: `Solid Queue configuration is valid.` and no `Warning:` lines.

- [ ] **Step 2: Create `config/deploy/soul-link-jobs.service`**

```ini
# /etc/systemd/system/soul-link-jobs.service
# Solid Queue worker for Soul Link: runs Active Job jobs stored in the primary
# database. Async mode runs the worker, dispatcher and scheduler as threads in
# one process instead of forking one process each, to save memory.
#
# Installed, enabled and restarted by .github/workflows/deploy.yml.

[Unit]
Description=Soul Link Jobs (Solid Queue)
After=network.target mysql.service
OnFailure=systemd-failure-notify@%n.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/soul_link
ExecStart=/root/.rbenv/shims/bundle exec bin/jobs --mode async
Restart=always
RestartSec=5

EnvironmentFile=/etc/soul_link/env
# The worker's 3 job threads, its poller, the dispatcher, the scheduler and
# their heartbeats all share this process's connection pool (database.yml
# reads RAILS_MAX_THREADS). Web and bot keep the default of 5.
Environment=RAILS_MAX_THREADS=10

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 3: Add the worker to `Procfile.dev`**

Replace the file contents with:

```
web: bin/rails server
css: bin/rails tailwindcss:watch
jobs: env RAILS_MAX_THREADS=10 bin/jobs --mode async
```

- [ ] **Step 4: Wire the unit into the deploy**

In `.github/workflows/deploy.yml`, change:

```sh
            cp config/deploy/soul-link-web.service /etc/systemd/system/
            cp config/deploy/soul-link-bot.service /etc/systemd/system/
```

to:

```sh
            cp config/deploy/soul-link-web.service /etc/systemd/system/
            cp config/deploy/soul-link-bot.service /etc/systemd/system/
            cp config/deploy/soul-link-jobs.service /etc/systemd/system/
```

Then change:

```sh
            systemctl daemon-reload
```

to:

```sh
            systemctl daemon-reload
            # Idempotent: makes the jobs worker start at boot (first deploy creates it)
            systemctl enable soul-link-jobs
```

Then change:

```sh
            systemctl restart soul-link-bot
            systemctl restart soul-link-web
```

to:

```sh
            systemctl restart soul-link-jobs
            systemctl restart soul-link-bot
            systemctl restart soul-link-web
```

Leave everything else alone. `db:migrate` already runs before these steps, so
the tables exist before the new service starts.

- [ ] **Step 5: Check the workflow YAML still parses**

```bash
ruby -ryaml -e 'y = YAML.load_file(".github/workflows/deploy.yml"); s = y["jobs"]["deploy"]["steps"][0]["with"]["script"]; %w[soul-link-jobs.service enable\ soul-link-jobs restart\ soul-link-jobs].each { |k| puts "#{k}: #{s.include?(k)}" }'
```

Expected: three lines, each ending in `true`.

- [ ] **Step 6: End-to-end check in development: a separate process reaches the cable table through the queue**

This path is what a bot-side change goes through: another process enqueues a
Turbo refresh job, the worker runs it, and the broadcast lands in
`solid_cable_messages`, where Puma's listener picks it up.

Start the worker in the background, using the Bash tool with
`run_in_background: true`:

```bash
env RAILS_MAX_THREADS=10 bin/jobs --mode async > tmp/jobs_dev.log 2>&1
```

Then, from a separate process:

```bash
rtk proxy bin/rails runner '
  stream = "phase2:e2e"
  hash   = SolidCable::Message.channel_hash_for(stream)  # Turbo broadcasts a String streamable under its own name
  before = SolidCable::Message.where(channel_hash: hash).count
  Turbo::StreamsChannel.broadcast_refresh_later_to(stream)  # debounced 0.5s, then enqueued
  sleep 3
  puts "jobs finished: #{SolidQueue::Job.where(class_name: "Turbo::Streams::BroadcastStreamJob").where.not(finished_at: nil).where("created_at > ?", 1.minute.ago).count}"
  puts "cable messages: #{SolidCable::Message.where(channel_hash: hash).count - before}"
' > tmp/e2e.txt 2>&1; cat tmp/e2e.txt
```

Expected: `jobs finished: 1` (or more) and `cable messages: 1`.

- `jobs finished: 0` means the worker isn't running. Check
  `tmp/jobs_dev.log`.
- `cable messages: 0` with a finished job means the worker's broadcast didn't
  reach the table. Check `tmp/jobs_dev.log` for a solid_cable error.

Stop the background worker afterwards (TaskStop, or
`pkill -f "bin/jobs --mode async"`).

- [ ] **Step 7: Commit**

```bash
git add config/deploy/soul-link-jobs.service Procfile.dev .github/workflows/deploy.yml
git commit -m "feat: run Solid Queue as the soul-link-jobs service in async mode"
```

---

### Task 3A: Log background-thread errors; clear finished jobs in development

This task came out of the Task 2 review. solid_cable 4.1 writes broadcasts on
a background thread. On failure, `SolidCable::BatchedBroadcaster#flush`
rescues and calls `Rails.error.report`, and Solid Queue's `on_thread_error`
does the same. The app registers no `Rails.error` subscriber, and with no
subscribers `report` does nothing, so those failures would leave no trace.
The bot's own `rescue` in `DiscordBot#broadcast_run_state` no longer sees
cable write errors, because the write now happens on another thread.

Separately, `config/recurring.yml` only clears finished jobs in production.
Every dashboard edit now enqueues a Turbo refresh job, so `solid_queue_jobs`
in the dev database would grow without limit.

**Files:**
- Create: `test/infrastructure/error_logging_test.rb`
- Create: `config/initializers/error_logging.rb`
- Modify: `config/recurring.yml`

- [ ] **Step 1: Write the failing test**

Create `test/infrastructure/error_logging_test.rb`:

```ruby
require "test_helper"

# Background threads (the Solid Cable writer, Solid Queue's supervisor
# threads) report failures through Rails.error instead of raising. Without a
# subscriber those reports would vanish.
class ErrorLoggingTest < ActiveSupport::TestCase
  test "errors reported to Rails.error are written to the log" do
    original = Rails.logger
    log = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(log)

    Rails.error.report(RuntimeError.new("writer boom"), handled: true, source: "solid_cable")

    assert_match(/\[solid_cable\] RuntimeError: writer boom/, log.string)
  ensure
    Rails.logger = original
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
rtk proxy bin/rails test test/infrastructure/error_logging_test.rb > tmp/t.txt 2>&1
grep -E "runs, .*assertions" tmp/t.txt
grep -A8 -E "^Failure|^Error" tmp/t.txt
```

Expected: 1 failure, with `Expected /\[solid_cable\] RuntimeError: writer boom/ to match ""`.

- [ ] **Step 3: Add the subscriber**

Create `config/initializers/error_logging.rb`:

```ruby
# Rails.error has no subscribers by default, so errors reported from
# background threads would vanish. Examples are a failed Solid Cable write on
# its writer thread, or a Solid Queue supervisor or worker thread error.
# Log them.
class ErrorLogSubscriber
  def report(error, handled:, severity:, context:, source: nil)
    level = severity == :warning ? :warn : severity
    backtrace = Array(error.backtrace).first(10).join("\n")
    Rails.logger.public_send(level, "[#{source}] #{error.class}: #{error.message}\n#{backtrace}".strip)
  end
end

Rails.error.subscribe(ErrorLogSubscriber.new)
```

- [ ] **Step 4: Run it and confirm it passes**

```bash
rtk proxy bin/rails test test/infrastructure/error_logging_test.rb > tmp/t.txt 2>&1
grep -E "runs, .*assertions" tmp/t.txt
```

Expected: `1 runs, 1 assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Clear finished jobs in development too**

Replace the `production:` block at the bottom of `config/recurring.yml` with:

```yaml
production: &clear_finished_jobs
  clear_solid_queue_finished_jobs:
    command: "SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)"
    schedule: every hour at minute 12

development:
  <<: *clear_finished_jobs
```

Keep the commented examples above it unchanged. Verify:

```bash
rtk proxy bin/jobs check --mode async > tmp/jobs_check.txt 2>&1; cat tmp/jobs_check.txt
```

Expected: `Solid Queue configuration is valid.`

- [ ] **Step 6: Run the whole suite**

```bash
rtk proxy bin/rails test > tmp/t.txt 2>&1
grep -E "runs, .*assertions" tmp/t.txt
grep -A8 -E "^Failure|^Error" tmp/t.txt
```

Expected: 1025 runs, 0 failures, 0 errors. Anything reported to `Rails.error`
now also appears in `log/test.log`. That's harmless, but if a test asserts on
exact log output, report it.

- [ ] **Step 7: Commit**

```bash
git add test/infrastructure/error_logging_test.rb config/initializers/error_logging.rb config/recurring.yml
git commit -m "feat: log errors reported by background threads and clear finished jobs in dev"
```

---

### Task 4: Comments and docs

**Files:**
- Modify: `lib/tasks/soul_link/debug_save.rake:10-14`
- Modify: `.claude/documents/deployment.md` (Deploy Job, Systemd Services, Puma, ActionCable, Development, Key Environment Variables)
- Modify: `CLAUDE.md` (the Commands block and the Dev gotcha bullet)

- [ ] **Step 1: Reword the stale rake comment**

In `lib/tasks/soul_link/debug_save.rake`, replace:

```ruby
    # perform_now (not perform_later): the Async queue adapter runs jobs on a
    # thread pool that gets torn down when this rake process exits. With
    # perform_later, fast-finishing jobs win the race and slow ones get
    # killed mid-flight. Synchronous execution in the main thread is the
    # reliable path for a one-shot batch reparse.
```

with:

```ruby
    # perform_now (not perform_later): parse each slot synchronously so the
    # output below is in order and a failure shows up inline, without waiting
    # on the jobs worker.
```

- [ ] **Step 2: Update `.claude/documents/deployment.md`**

Make these edits:

1. **Deploy Job** list: replace step 6 with
   `6. Reload nginx, enable soul-link-jobs, restart soul-link-jobs, soul-link-bot and soul-link-web`.
2. **Systemd Services**: after the `soul-link-bot.service` subsection, add:

   ```markdown
   ### soul-link-jobs.service
   - Runs Solid Queue: `bundle exec bin/jobs --mode async` (worker, dispatcher and scheduler as threads in one process, to save memory)
   - `Environment=RAILS_MAX_THREADS=10`: every component shares this process's DB pool
   - Restart: always (5s delay); same env file and failure notification
   - Enabled and restarted by the deploy workflow
   ```

3. **Puma Configuration**: change the Plugins line to `- Plugins: \`tmp_restart\``.
4. **ActionCable**: replace the paragraph starting "All environments use the
   `async` adapter" with:

   ```markdown
   Development and production use **Solid Cable**: broadcasts are rows in `solid_cable_messages` in the primary database. Puma polls it every 0.1s and messages are trimmed after 1 day. A broadcast from any process (the bot, the jobs worker, `rails console`) reaches browsers. Tests use the `test` adapter.

   Since solid_cable 4.1, broadcasts are written by a background thread. A one-shot process (rake, runner) can drop a broadcast made just before it exits.
   ```

5. After the ActionCable section, add:

   ```markdown
   ## Background Jobs

   Development and production use **Solid Queue**, with tables in the primary database (`solid_queue_*`). Jobs survive restarts. Config: `config/queue.yml` (1 worker, 3 threads, all queues) and `config/recurring.yml` (hourly cleanup of finished jobs, in development and production). Production runs the worker as `soul-link-jobs.service`; development runs it through `bin/dev`. Tests use the Active Job test adapter. Failures that background threads report through `Rails.error` (the Solid Cable writer, Solid Queue's threads) are logged by `config/initializers/error_logging.rb`.
   ```

6. **Development**: change "Runs two processes" to "Runs three processes" and
   add `- \`jobs\`: Solid Queue worker (\`bin/jobs --mode async\`)`.
7. **Key Environment Variables**: change the `RAILS_MAX_THREADS` row to
   `| \`RAILS_MAX_THREADS\` | Puma thread count and DB pool size (the jobs service sets 10) |`.

- [ ] **Step 3: Update `CLAUDE.md`**

In the Commands block, change:

```bash
bin/dev                              # Start web server + Tailwind watcher (Procfile.dev)
```

to:

```bash
bin/dev                              # Start web server + Tailwind watcher + Solid Queue worker (Procfile.dev)
```

Replace the bullet:

```markdown
- **Dev gotcha:** Async cable adapter only works within same process — `rails console` broadcasts won't reach browser.
```

with:

```markdown
- **Cable and jobs:** Solid Cable and Solid Queue, both in the primary MySQL database. Broadcasts from any process (bot, jobs worker, console) reach browsers. Jobs need the worker (`bin/dev` starts it; prod runs `soul-link-jobs.service`).
```

- [ ] **Step 4: Make the `config/cable.yml` comment precise**

A one-shot process can drop its last broadcasts (see the spec's Known
limitations), so "any process" overstates it. Replace the header comment with:

```yaml
# Solid Cable stores broadcasts in the primary database (solid_cable_messages),
# so a broadcast from any long-lived process (Puma, the Discord bot, the jobs
# worker, a console session) reaches every subscribed browser. Writes happen on
# a background thread: a one-shot rake/runner process may drop broadcasts made
# just before it exits. Old messages are trimmed after message_retention.
```

Run `rtk proxy bin/rails test test/infrastructure/cable_config_test.rb > tmp/t.txt 2>&1` and grep the "runs, assertions" line. Expect 3 runs and 0 failures.

- [ ] **Step 5: Commit**

```bash
git add config/cable.yml lib/tasks/soul_link/debug_save.rake .claude/documents/deployment.md CLAUDE.md
git commit -m "docs: describe Solid Cable, Solid Queue and the jobs service"
```

---

### Task 5: Full verification

- [ ] **Step 1: Full suite**

```bash
rtk proxy bin/rails test > tmp/t.txt 2>&1
grep -E "runs, .*assertions" tmp/t.txt
grep -A8 -E "^Failure|^Error" tmp/t.txt
```

Expected: `1025 runs` (1017 plus 8 new), 0 failures, 0 errors.

- [ ] **Step 2: Full suite as CI runs it (eager loading)**

```bash
CI=true rtk proxy bin/rails test > tmp/t_ci.txt 2>&1
grep -E "runs, .*assertions" tmp/t_ci.txt
grep -A8 -E "^Failure|^Error" tmp/t_ci.txt
```

Expected: the same count, 0 failures, 0 errors. If a job-count assertion
flakes, scope it with `only:`. Turbo's `broadcasts_refreshes_to` enqueues
broadcast jobs that leak into `enqueued_jobs` in parallel tests.

- [ ] **Step 3: Schema load from scratch, as CI does it**

```bash
RAILS_ENV=test rtk proxy bin/rails db:schema:load > tmp/schema_load.txt 2>&1; tail -3 tmp/schema_load.txt
RAILS_ENV=test bin/rails runner 'puts SolidQueue::Job.count, SolidCable::Message.count'
```

Expected: no errors, then `0` and `0`.

- [ ] **Step 4: Lint and security**

```bash
rtk proxy bundle exec rubocop > tmp/rubocop.txt 2>&1; tail -3 tmp/rubocop.txt
rtk proxy bundle exec brakeman -q --no-pager > tmp/brakeman.txt 2>&1; grep -E "Security Warnings|No warnings" tmp/brakeman.txt
```

Expected: 39 offenses (the pre-existing ones), none in files this plan
touched, and 2 brakeman warnings. For any new offense, run
`bundle exec rubocop -a <file>`, re-run the affected tests, and commit.

- [ ] **Step 5: Review the whole diff**

```bash
git diff --stat 80c2299..HEAD
```

Every changed file should be in this plan's file map, plus the spec and the
plan.

---

### Task 6: Code review

- [ ] **Step 1:** Use superpowers:requesting-code-review against
  `80c2299..HEAD`. Fix anything confirmed, re-run Task 5 Steps 1 and 4, and
  commit.

---

### Task 7: Ship (one deploy)

A push to `main` deploys to production. The deploy runs `db:migrate`, installs
and enables `soul-link-jobs`, and restarts jobs, bot and web.

- [ ] **Step 1: Confirm a fast-forward is possible**

```bash
git fetch origin
git merge-base --is-ancestor origin/main HEAD && echo "fast-forward OK"
```

Expected: `fast-forward OK`. If not, call the `sync_with_base_branch` tool,
resolve conflicts, re-run Task 5, and retry.

- [ ] **Step 2: Push the branch to `main`**

```bash
git push origin HEAD:main
git rev-parse HEAD
git ls-remote origin refs/heads/main
```

Expected: both commands print the same SHA.

- [ ] **Step 3: Watch the workflow run**

```bash
gh run list --branch main --limit 1
gh run watch <run-id> --exit-status
```

Expected: the `test` and `deploy` jobs both succeed. If `deploy` fails, read
`gh run view <run-id> --log-failed` and report it to the user before changing
anything.

- [ ] **Step 4: Ask before checking the server**

Ask the user whether to run read-only checks over SSH. Only with a yes:

```bash
ssh root@4luckyclovers.com 'systemctl is-active soul-link-jobs soul-link-bot soul-link-web; systemctl is-enabled soul-link-jobs; journalctl -u soul-link-jobs -n 30 --no-pager'
```

Expected: `active` three times, then `enabled`, and a log showing the Solid
Queue supervisor starting in async mode with no errors. Ask the user to make
a change from Discord (for example, a catch) with the dashboard open, and
confirm it updates live.
