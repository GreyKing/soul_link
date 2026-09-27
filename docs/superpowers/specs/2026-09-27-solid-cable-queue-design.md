# Solid Cable + Solid Queue (Cleanup Phase 2 of 5)

**Date:** 2026-09-27
**Baseline:** `main` at `80c2299` (phase 1 shipped), 1017 runs, 0 failures

## Context

Phase 1 (`2026-09-27-audit-bug-fixes-design.md`) fixed bugs. This phase
changes infrastructure only. Behaviour stays the same, except that live
updates now reach browsers from every process and jobs survive restarts.

Today:

- `config/cable.yml` uses `adapter: async` in development and production.
  Async only delivers broadcasts inside the process that sent them. The
  Discord bot is a separate process (`rake soul_link:bot`), so its
  `RunChannel.broadcast_run_state` calls never reach a browser. Neither do the
  Turbo `broadcasts_refreshes_to` refreshes triggered by bot DB writes: those
  enqueue a `Turbo::Streams::BroadcastStreamJob`, which runs on the bot's own
  async pool and broadcasts into the bot's own process. It also means Puma can
  never run more than one worker.
- `config.active_job.queue_adapter = :async` keeps jobs in process memory.
  They are lost on restart or deploy. There are five job classes:
  `SoulLink::ParseSaveDataJob`, `SoulLink::GenerateRunRomsJob` (shells out to
  Java, ~30s), `SoulLink::GenerateRomDownloadJob`, `GymPollLockJob` and
  `GymPollDiscordSyncJob`. There are also Turbo's broadcast jobs.
- Dead leftovers from when the Solid gems were removed: the Gemfile comment,
  `plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]` in `config/puma.rb`,
  `config/cache.yml`, `db/cache_schema.rb`, `db/cable_schema.rb`,
  `db/queue_schema.rb`, and the production comment "inline ... no background
  jobs needed".

## Decisions (2026-09-27)

| Question | Decision |
|---|---|
| Database | The existing single MySQL database. No `cable` or `queue` databases, and no `connects_to`. |
| Where the worker runs | Its own systemd service, `soul-link-jobs`, running `bin/jobs --mode async` (one process, threads only) to save memory. |
| Development | Full parity: dev uses solid_cable and solid_queue. `bin/dev` starts a worker. |
| Solid Cache | Not adopted. The cache stays on `memory_store`. |
| Deploys | One. Work is held on the branch, then `main` is fast-forwarded and pushed. |

## Design

### Gems

Add `solid_cable` and `solid_queue` to the Gemfile, at the latest versions
compatible with Rails 8.1.1. At time of writing Bundler resolves solid_cable
4.1.0 and solid_queue 1.7.0 (plus fugit, et-orbi and raabro). Replace the "we don't need these" comment with a
one-line note: both use the primary database, and Solid Cache is not used.

### Action Cable: `config/cable.yml`

```yaml
development:
  adapter: solid_cable
  polling_interval: 0.1.seconds
  message_retention: 1.day

test:
  adapter: test

production:
  adapter: solid_cable
  polling_interval: 0.1.seconds
  message_retention: 1.day
```

- There is no `connects_to`, so `SolidCable::Record` uses the primary
  connection.
- `reconnect_attempts: [ 1, 2, 3, 5, 10, 15, 30, 60, 60, 60 ]` (about 4 minutes
  of backoff). By default, Puma's listener retries once after a DB connection
  error and then its thread ends silently, so live updates would stop until
  the next Puma restart, for example after a MySQL restart. A successful poll
  resets the counter.
- `polling_interval: 0.1.seconds` keeps gym-draft and dashboard updates
  feeling instant. Only processes with subscribers poll, which in practice
  means Puma: one indexed query every 100ms.
- Cleanup relies on `autotrim`, which is on by default. On a random fraction
  of writes it deletes up to 100 messages older than `message_retention`
  (1 day). It runs `TrimJob.perform_now` on the adapter's background thread
  and never goes through Solid Queue.
- Since solid_cable 4.1, `broadcast` doesn't write straight to the database.
  It pushes onto an in-memory queue, and a `solid_cable_writer` thread inserts
  the messages in batches (up to 4 per batch, 1ms delay by default). That
  suits long-lived processes (Puma, the bot and the jobs worker). The limits
  are listed under Known limitations.
- The old comment about the async adapter and the web console goes, because
  a console broadcast now reaches the browser.

### Active Job: environments

- In `development.rb` and `production.rb`, set
  `config.active_job.queue_adapter = :solid_queue`. There is no
  `config.solid_queue.connects_to`, so the primary database is used.
- Fix the misleading production comment.
- `test.rb` is unchanged: `ActiveJob::TestHelper` still installs the test
  adapter.
- `config/queue.yml` is unchanged. The dispatcher polls every 1s with a batch
  of 500. The worker handles all queues with 3 threads and polls every 0.1s.
  `processes` is ignored in async mode.
- `config/recurring.yml` keeps its `clear_solid_queue_finished_jobs` task. It
  runs every hour and deletes finished jobs, which Solid Queue keeps for 1 day
  by default. A `development:` entry now reuses it (see Error visibility).
  Failed jobs are never cleared; volume is tiny, so that is noted for phase 3.

### Worker process

**Production:** a new `config/deploy/soul-link-jobs.service`, modelled on
`soul-link-bot.service`:

```ini
[Unit]
Description=Soul Link Jobs (Solid Queue)
After=network.target mysql.service
OnFailure=systemd-failure-notify@%n.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/soul_link
# Async mode runs the worker (3 job threads plus a poller), the dispatcher,
# the scheduler and their heartbeats in one process on one connection pool.
# Set in ExecStart, so a RAILS_MAX_THREADS entry in the env file can never
# override it (EnvironmentFile= wins over Environment=).
ExecStart=/usr/bin/env RAILS_MAX_THREADS=10 /root/.rbenv/shims/bundle exec bin/jobs --mode async
Restart=always
RestartSec=5

EnvironmentFile=/etc/soul_link/env

[Install]
WantedBy=multi-user.target
```

- **Why async mode.** Fork mode would run a supervisor, a worker, a
  dispatcher and a scheduler as four Rails processes. Async mode runs them as
  threads in one process. That costs one extra Rails boot on the VPS instead
  of about four.
- **What we give up.** A worker thread that hard-crashes the Ruby VM takes the
  dispatcher and scheduler down with it. That is acceptable here: the job
  volume is small, and `Restart=always` plus the failure email cover it.
- **Pool size.** Solid Queue's own advisory check assumes one process per
  component (threads + 2 = 5). In async mode every component shares one pool,
  so the jobs process gets `RAILS_MAX_THREADS=10`, which only feeds the
  `pool:` in `database.yml`. Web and bot keep their current pool of 5.
  Connections open lazily, so the most the app can use is about 20, well under
  MySQL's default limit of 151.
- **Shutdown (decided 2026-09-27: keep the 5s default).** On a restart,
  systemd sends SIGTERM. The async supervisor stops its threads and waits
  `shutdown_timeout` (5s) for them. Jobs that finish in that window complete
  normally, and jobs not yet claimed stay in the queue.
  - If a job is still running after 5s, the supervisor calls `exit!` and
    skips deregistration. About 5 minutes later (`process_alive_threshold`)
    the new supervisor prunes the dead process. Its claimed job is then
    recorded as **failed** (`ProcessPrunedError`) and is not rerun.
  - In practice only ROM generation takes that long. The fix is to regenerate
    it from the UI.
  - The unclean exit can also mark the unit failed during that restart and
    fire the failure email.
  - We chose fast deploys over waiting out a ROM batch, which can take up to
    about 2 minutes.

**Development:** `Procfile.dev` gains
`jobs: env RAILS_MAX_THREADS=10 bin/jobs --mode async`, so `bin/dev` starts
web, css and jobs. The bot is still started separately.

**Puma:** remove the `plugin :solid_queue` line and its comment.

### Schema

- One migration creates every `solid_queue_*` table and
  `solid_cable_messages`. The table definitions are copied from the install
  templates of the gem versions that end up in `Gemfile.lock`, so they match
  what the gems expect.
- The migration puts the tables into `db/schema.rb` for the primary database.
  That covers CI (`bin/rails db:schema:load`), the parallel test databases and
  fresh dev setups.
- Delete the stale `db/cable_schema.rb`, `db/queue_schema.rb`,
  `db/cache_schema.rb` and `config/cache.yml`.
- **Production:** the deploy already runs `bin/rails db:migrate` before any
  service restarts. Until the restart, the old processes stay on async and
  never touch the new tables, so the ordering is safe.

### Deploy: `.github/workflows/deploy.yml`

Add these steps next to the existing unit installs and restarts:

```sh
cp config/deploy/soul-link-jobs.service /etc/systemd/system/
# (after daemon-reload)
systemctl enable soul-link-jobs      # idempotent; starts at boot
# (with the other restarts)
systemctl restart soul-link-jobs
```

- The deploy creates and starts the new service, so no manual SSH is needed.
- The env file doesn't change: the jobs unit sets its own `RAILS_MAX_THREADS`.
- `appleboy/ssh-action` doesn't use `set -e`, so a failed `bundle install` or
  `db:migrate` would still restart every service onto code whose gems or
  tables are missing. Both lines now end in `|| exit 1`.
- With `Type=simple`, `systemctl restart` returns 0 and the unit reports
  `active` even while the worker crash-loops.
  - The script records `JOBS_T0` before the restarts. After the web restart it
    waits up to 60s for `Started Worker` to appear in
    `journalctl -u soul-link-jobs --since "$JOBS_T0"`, and requires the unit's
    `NRestarts` to be 0.
  - If either check fails, it prints only warning-level and higher journal
    lines, because Actions logs are public, and fails the workflow.
  - The check runs last, so bot and web are always restarted first.

### Data flow after the change

- **Bot writes a record.** `broadcasts_refreshes_to` enqueues a Turbo job and
  a row lands in `solid_queue_jobs`. The worker runs the job, which inserts a
  row into `solid_cable_messages`. Puma's listener picks it up and pushes it
  to subscribed browsers.
- **Bot calls `RunChannel.broadcast_run_state`.** The call becomes an insert
  into `solid_cable_messages`, which Puma delivers. The bot loads `cable.yml`
  for `RAILS_ENV=production` (from `/etc/soul_link/env`) through
  `rake soul_link:bot` → `:environment`, so it needs no code change.
- **Web enqueues a job** (ROM generation, save parsing, poll sync). The job
  row is committed in the same database. If it is enqueued inside a
  transaction, it commits or rolls back with that transaction.
- **Restart or deploy.** Jobs that are ready or scheduled stay in the
  database and run after the restart. A job still running 5s after SIGTERM is
  recorded as failed (see Shutdown).

### Error visibility (added after the Task 2 review)

The Solid Cable writer thread and Solid Queue's threads report failures
through `Rails.error.report`. The app has no `Rails.error` subscriber, so
those reports would vanish. The bot's `rescue` around
`RunChannel.broadcast_run_state` no longer sees cable write errors either,
because the write happens on another thread. A small initializer,
`config/initializers/error_logging.rb`, subscribes a logger to `Rails.error`,
so these failures show up in each process's log (journald in production).

`config/recurring.yml` also gets a `development:` entry that reuses the hourly
finished-job cleanup. Otherwise the dev database's `solid_queue_jobs` table
grows without limit, since every dashboard edit enqueues a Turbo refresh job.

### Other cleanup

- `lib/tasks/soul_link/debug_save.rake`: the comment explaining `perform_now`
  cites the async adapter's thread pool. Reword it: a one-shot batch runs
  synchronously so the output is ordered and failures show up inline. The code
  keeps `perform_now`.
- Docs: update the ActionCable, Puma, systemd and Procfile sections of
  `.claude/documents/deployment.md`, the "Dev gotcha" line in `CLAUDE.md`, and
  any other `.claude/documents/` text that describes the async adapter.

## Testing

Write these tests first; each one should fail on the current code:

1. **Cable config.** Parse `config/cable.yml` with ERB. Development and
   production use `solid_cable` with no `connects_to` and have the
   polling/retention settings. Test uses `test`.
2. **Solid Cable on the primary database.** Broadcasting through
   `ActionCable::SubscriptionAdapter::SolidCable` and then calling
   `adapter.shutdown` inserts a `SolidCable::Message` for that channel.
   `shutdown` closes the writer queue and joins the thread, which makes the
   write deterministic. `SolidCable::Record` uses the primary connection.
3. **Solid Queue on the primary database.** Enqueuing a real app job (for
   example `GymPollDiscordSyncJob`) through
   `ActiveJob::QueueAdapters::SolidQueueAdapter` persists a `SolidQueue::Job`
   with a ready execution. Deserializing and running the stored job invokes
   `perform` with the original arguments. This is what "jobs survive a
   restart" means.

Manual checks, recorded in the plan:

- `RAILS_ENV=production bin/rails runner` reports the queue adapter as
  `solid_queue` and the Action Cable pubsub as `SolidCable`. Use a dummy
  secret or credentials as needed.
- `bin/jobs --mode async` boots in dev, and the configuration check prints no
  pool warning.
- With `bin/dev` and the bot running locally, a bot-side change shows up live
  in an open dashboard.
- The full suite passes, including with `CI=true`. Rubocop shows only the 39
  pre-existing offenses, and Brakeman only its 2 pre-existing weak warnings.

The test environment keeps `adapter: test` for cable and the test job adapter.
Following the project memory, any job assertions stay scoped with `only:`.

## Known limitations (not regressions)

- A one-shot process such as `rake soul_link:reparse_all_saves` or
  `bin/rails runner` can drop a broadcast made in its last millisecond or so,
  because the solid_cable writer thread dies when the process exits. Under
  async, those broadcasts never reached a browser at all. The bot, Puma and
  the jobs worker are long-lived and unaffected.

- If a deploy interrupts `GenerateRunRomsJob` or `GenerateRomDownloadJob`
  mid-run, the job is recorded as failed about 5 minutes later, and the
  sessions or download stay `pending` or `generating`. Retrying
  `GenerateRunRomsJob` would do nothing anyway, because it is idempotent on
  session count. Today the job is lost outright, which ends the same way.
  Recovering stuck ROM sessions belongs to phase 3.
- Discord gym-poll votes still don't push to an open web poll page, because
  `GymPoll` has no refresh broadcast. This is existing behaviour and out of
  scope.

## Rollback runbook

If phase 2 has to be reverted:

1. Revert with `git revert` commits on `main` and push. Never reset or
   force-push. The server runs `git pull origin main`, so a reset `main` would
   pull nothing while the deploy still showed green.
2. The reverted deploy puts web and bot back on async. `db:migrate` is a no-op,
   and the Solid tables stay. That is harmless: leave them. If they are ever
   dropped, also delete `schema_migrations` row `20260927120000`, or a later
   re-ship won't recreate them.
3. The old `deploy.yml` doesn't manage `soul-link-jobs`. On its next restart
   or a reboot, the service would crash-loop, because old code has no
   `solid_queue/cli`. Over SSH, with the user's approval:
   - First, if you want to see what will be abandoned, run
     `SolidQueue::Job.where(finished_at: nil).group(:class_name).count`.
   - Then run
     `systemctl disable --now soul-link-jobs && rm /etc/systemd/system/soul-link-jobs.service && systemctl daemon-reload && systemctl reset-failed`.

## Out of scope

- Kamal and Docker files (`config/deploy.yml`, `Dockerfile`,
  `bin/docker-entrypoint`). They are unused. `config/deploy.yml` still sets
  `SOLID_QUEUE_IN_PUMA`; that can go in phase 3's dead-code pass.
- Running more than one Puma worker. This change makes it possible but does
  not turn it on.
- Mission Control or any jobs dashboard.
