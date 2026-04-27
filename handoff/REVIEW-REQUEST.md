# Review Request — Step 2

*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

**Builder:** Bob
**Step:** 2 — `SoulLink::RomRandomizer` service + `SoulLink::GenerateRunRomsJob`
**Ready for Review:** YES

---

## Summary

Step 2 ships the synchronous service that wraps the Universal Pokemon Randomizer
JAR and the background job that fans out generation across the 4 sessions of a
run. No controllers, routes, or views — that's Step 4. The service mutates the
`SoulLinkEmulatorSession` record in place: `pending → generating → ready` on the
happy path, `failed` with a friendly `error_message` on any handled fault.
Failures of one ROM never stop the others.

All test scenarios in the brief are covered. Java is never invoked, the
filesystem is never touched, the database stays clean — every external seam is
stubbed.

---

## Files Created

| File | Purpose |
|------|---------|
| `app/services/soul_link/rom_randomizer.rb` | Synchronous wrapper around the JAR. Pre-condition checks (Java, base ROM, JAR, settings), `Open3.capture3` under `Timeout.timeout`, persists status + relative `rom_path`. |
| `app/jobs/soul_link/generate_run_roms_job.rb` | Fan-out job. Idempotent on count `>= SESSIONS_PER_RUN` (4); creates sessions inside a transaction, runs the service outside it; rescues `StandardError` per session so one crash never aborts the loop. |
| `test/services/soul_link/rom_randomizer_test.rb` | 10 tests, 59 assertions. All scenarios from the brief plus a defensive "Open3 not called when preconditions fail" check. |
| `test/jobs/soul_link/generate_run_roms_job_test.rb` | 5 tests, 38 assertions. Happy path, idempotency at `count == 4` and `count > 4`, handled-failure tolerance, unrescued `StandardError` tolerance. |
| `storage/roms/base/.keep` | Placeholder so the dir is git-tracked while contents are ignored. |
| `storage/roms/randomized/.keep` | Same. |
| `lib/randomizer/.keep` | Same — JAR is provisioned out-of-band. |

## Files Modified

| File | Change |
|------|--------|
| `.gitignore` | Whitelisted `storage/roms/{base,randomized}/.keep` and `lib/randomizer/.keep`; ignored `*.nds` under those dirs and `randomizer.jar`. Carefully written to coexist with the existing `/storage/*` rule. |
| `handoff/ARCHITECT-BRIEF.md` | Appended a 5-line Builder Plan to the bottom (per directive). |

No factory edits — the existing `:ready`, `:claimed`, `:generating` traits and the bare factory cover every scenario.

---

## Test Results

```
mise exec -- ruby -S bundle exec rails test
131 runs, 408 assertions, 0 failures, 0 errors, 0 skips
```

- Step 1 baseline: 116 tests
- New service tests: 10
- New job tests: 5
- **Total: 131 — exactly the expected count.**

```
mise exec -- ruby -S bundle exec rubocop \
  app/services/soul_link/rom_randomizer.rb \
  app/jobs/soul_link/generate_run_roms_job.rb \
  test/services/soul_link/rom_randomizer_test.rb \
  test/jobs/soul_link/generate_run_roms_job_test.rb
4 files inspected, no offenses detected
```

---

## Definition of Done

- [x] `app/services/soul_link/rom_randomizer.rb` exists and matches contract
- [x] `app/jobs/soul_link/generate_run_roms_job.rb` exists and matches contract
- [x] Service tests cover all listed scenarios; all green
- [x] Job tests cover all listed scenarios; all green
- [x] Full suite passes (116 + 15 = 131 tests, 0 failures)
- [x] `.gitignore` updated; `.keep` files committed-ready
- [x] No real Java or filesystem writes in tests
- [x] All test data via FactoryBot — no fixture references in new tests

---

## Behavior Highlights

**Pre-condition guards.** `precondition_error` returns a friendly string for the
first missing dependency in this order: Java, base ROM, JAR, settings. The
service mutates the session to `failed` with that string and returns `false` —
no exception. `Open3` is never invoked when a precondition fails (covered by an
explicit test).

**Mid-call status.** The service flips the session to `generating` and saves it
*before* the subprocess runs. The "session is in 'generating' status while the
subprocess runs" test confirms this by reading the row from the DB inside the
`Open3.capture3` stub.

**Relative path.** `rom_path` is stored as
`storage/roms/randomized/run_<run_id>/session_<session_id>.nds` — never absolute,
never starts with `/`. `SoulLinkEmulatorSession#rom_full_path` resolves it under
`Rails.root`. Verified.

**Subprocess failure modes.**
- Non-zero exit → `error_message` is `stderr.strip` truncated to the column limit. (See open question 1 below.)
- `Timeout::Error` → `error_message` is `"Generation timed out after 30s"`.
- Unexpected exceptions during `save!` raise `GenerationError` — that's a real DB bug, not a generation failure.

**Job idempotency.** If 4 (or more) sessions already exist for the run,
`perform` returns immediately. The service is never invoked. Verified for both
`count == 4` and `count == 5`.

**Belt-and-braces job rescue.** The service is designed to swallow handled
failures and return `false`. The job *also* wraps each `service.call` in a
`rescue StandardError` so a real bug in one ROM does not abort the others. The
"unrescued StandardError" test verifies this: when call #2 raises, calls 3 and 4
still happen.

---

## Stubbing Strategy (the load-bearing part)

CI does not have Java and we never want real ROMs hitting the working tree.
Every external seam is intercepted:

| Seam | Stub strategy |
|------|---------------|
| `system("command -v java …")` | The service exposes a private `java_available?` predicate. Tests stub the **instance method** on the service, not `Kernel.system`. (Stubbing `Kernel.system` doesn't intercept `system(...)` invocations from inside other classes — Ruby resolves `system` via the Kernel mixin on the receiver, not through `Kernel.system`. This was the cause of the first iteration's failure.) |
| `File.exist?(BASE_ROM/JAR/SETTINGS)` | A pass-through stub: the lambda matches the three configured paths and returns the desired truthy/falsy value; everything else falls through to the real `File.exist?`. Required because Rails internals call `File.exist?` constantly during the test run. |
| `FileUtils.mkdir_p` | Stubbed to a no-op. The "successful generation" test uses a spy lambda that records the call and asserts the expected directory was created. |
| `Open3.capture3` | Stubbed per scenario: returns `["stdout", "", success_status]` for the happy path, `["", "boom", failure_status]` for non-zero exit, raises `Timeout::Error` for timeout. `Process::Status` can't be allocated, so we use `Struct.new(:success?).new(true/false)` — the service only calls `#success?` on it. |
| `SoulLink::RomRandomizer#call` (in job tests) | Replaced via `define_method` with a per-test behavior lambda; the original is captured ahead of time and restored in `ensure`. The behavior lambda is `instance_exec`'d, giving it access to `@session`. |

---

## Open Questions / Flags for Architect

### 1. `error_message` column is varchar(255), not 500-char-capable

The brief specifies "store a truncated `stderr` (max 500 chars)" but
`schema.rb:125` declares `t.string "error_message"` — that's `varchar(255)` on
MySQL. A 500-char value triggers `Mysql2::Error: Data too long for column
'error_message'` and the service can't save the failure. (Surfaced live during
the first test run.)

I shipped with `STDERR_LIMIT = 255` to match the column, with an inline comment
flagging the deviation. The behavior is otherwise identical: stderr is `.strip`ped
and truncated; on overflow we keep the leading bytes.

**Question for Architect:** keep at 255 (the column limit), or schedule a
follow-up migration to widen the column to text/varchar(500) so stderr fits the
brief's 500-char target? If the latter, that's a Step 2.5 — say the word and
I'll write the migration. Not blocking the rest of Step 2.

### 2. Randomizer JAR CLI flags

Per the brief's flag, I assumed `-i / -o / -s / -seed` from the original plan.
I have no JAR locally to verify against (`lib/randomizer/.keep` only). The
service test asserts the CLI shape includes those flags so any drift in Step 4
will surface immediately when the JAR actually runs on the VPS.

**No action needed unless Architect has reason to believe the flags differ.**
The brief explicitly told me not to invent flags and to escalate if they look
wrong — and I have no contradicting signal.

### 3. `discord_user_id: nil` in `create!`

`SoulLinkEmulatorSession.create!(... discord_user_id: nil)` is redundant since
the column is nullable, but it documents intent at the call site (these
sessions are deliberately unclaimed at creation time). Happy to drop it if it
reads as noise.

---

## What I Did NOT Touch

- No controllers, routes, views — Step 4.
- No factory changes — existing traits sufficed.
- No SolidQueue config — Rails 8 `:async` adapter is the chosen path.
- No real Java / no real subprocess invocation in tests.
- No real filesystem writes (mkdir is stubbed).
- No fixtures referenced in new tests.
- No commits — Architect commits.

---

Ready for Review: YES
