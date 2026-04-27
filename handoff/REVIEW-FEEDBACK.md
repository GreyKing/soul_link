# Review Feedback — Step 2

Date: 2026-04-26
Ready for Builder: YES

---

## Must Fix

None.

---

## Should Fix

None blocking. See Observations.

---

## Escalate to Architect

None. The one open question Bob flagged (`error_message` 255 vs 500) was
already ruled by Architect — keep at 255 to match column width. No further
escalations.

---

## Observations (non-blocking)

### O1. Job idempotency check is not lock-protected (theoretical race)

`app/jobs/soul_link/generate_run_roms_job.rb:15` reads
`SoulLinkEmulatorSession.where(...).count >= SESSIONS_PER_RUN` without a lock.
Two simultaneous enqueues for the same run could both see `count == 0` and
each create 4 sessions → 8 total. There is no DB-level unique constraint on
`(soul_link_run_id, slot)` or similar to catch this; `discord_user_id`
uniqueness allows multiple NULLs.

In practice, Step 4 will gate this on a single button click and the Rails 8
`:async` adapter is single-process, so the race is unlikely in the deployed
shape. Worth revisiting in Step 4 (controller-level guard, or a `with_lock`
on the run row, or a unique slot column). Not blocking Step 2.

### O2. `discord_user_id: nil` in `create!` is redundant but documenting

`generate_run_roms_job.rb:41` — Bob flagged this himself. The column is
nullable and the factory default is nil. Reads as intentional documentation
of "these are deliberately unclaimed." Keep it; harmless.

### O3. Service-test stubbing routes through one helper

All 10 service tests funnel through the `with_preconditions` helper before
calling `@service.call`, which is what guarantees the Java/File seams are
stubbed. If a future test forgets to wrap, the real
`system("command -v java …")` would run. Low-risk today (current tests are
correct); a future-proofing improvement would be to seed the predicate stub
in `setup do … end`. Not blocking.

---

## Cleared

Reviewed `app/services/soul_link/rom_randomizer.rb`,
`app/jobs/soul_link/generate_run_roms_job.rb`, the two new test files,
`.gitignore`, and the three `.keep` placeholders.

**Spec compliance.** Service contract met:

- Returns `false` on handled failure (no raise) — `fail!` returns false at
  every failure path.
- Sets `status="failed"` + `error_message` on every failure path
  (preconditions, non-zero exit, timeout).
- Stores `rom_path` relative to `Rails.root` via `relative_path_from(Rails.root)`
  — never absolute, never starts with a slash, always under `storage/`.
- Defensive Java check (`java_available?`) is re-evaluated on every `call`
  (not memoized) — correct per brief.
- Stderr truncated at `STDERR_LIMIT = 255` (Architect ruling). Inline comment
  in the service explains the deviation from the brief's 500.
- `Timeout::Error` is rescued and produces the expected
  `"Generation timed out after 30s"` message.
- Only persistence bugs surface as `GenerationError`; normal failure paths
  return `false`.

CLI shape uses `-i / -o / -s / -seed` exactly as the brief specified, with
`JAR_PATH`, `BASE_ROM_PATH`, `SETTINGS_PATH`, and the session seed as
positional arguments — verified against the test's argument assertions
(lines 156–165 of the service test).

**Job contract.** Idempotency on `count >= SESSIONS_PER_RUN` works for both
`count == 4` and `count > 4` (covered by named tests). Session creation is
wrapped in a transaction; the subprocess loop runs outside it. Per-session
failures are tolerated two ways:

- The service returns `false` on handled failure — the loop continues.
- The job's own `rescue StandardError` catches unhandled crashes — the loop
  still continues, the crash is logged.

Both paths covered by named tests (lines 87 and 117 of the job test).

Seed format is `SecureRandom.random_number(2**63).to_s` — positive 63-bit
integer as a String, asserted by the happy-path test (lines 51–54).

**Hermeticity.** Confirmed by reading the test file and re-running the suite:

- `system("command -v java …")` is never invoked because the
  `java_available?` predicate is stubbed at the instance level. Bob's
  rationale for not stubbing `Kernel.system` (Ruby resolves `system` via the
  Kernel mixin on the receiver, not through `Kernel.system`) is correct.
- `File.exist?` is wrapped in a pass-through stub that intercepts only the
  four guarded paths (BASE_ROM_PATH, JAR_PATH, SETTINGS_PATH; Java is the
  predicate) and delegates everything else to the real implementation —
  necessary because Rails internals call `File.exist?` constantly.
- `FileUtils.mkdir_p` is stubbed to a no-op (or to a recording spy in the
  happy-path test, which asserts the expected directory was passed).
- `Open3.capture3` is stubbed per scenario — happy path returns
  `["randomized ok", "", fake_status(true)]`, non-zero exit returns
  `["", "boom: bad rom", fake_status(false)]`, timeout raises
  `Timeout::Error`. The `Process::Status` substitute is a
  `Struct.new(:success?)`, which works because the service only calls
  `#success?` on it.

Independently re-ran:

```
mise exec -- ruby -S bundle exec rails test \
  test/services/soul_link/rom_randomizer_test.rb \
  test/jobs/soul_link/generate_run_roms_job_test.rb
15 runs, 97 assertions, 0 failures, 0 errors, 0 skips

mise exec -- ruby -S bundle exec rails test
131 runs, 408 assertions, 0 failures, 0 errors, 0 skips
```

No subprocess warnings. No real Java, no real ROM writes.

**Test coverage vs brief.** Every "Cover" bullet is asserted by a named test:

Service:
- "Java missing fails the session with a friendly message"
- "Base ROM missing fails the session"
- "Randomizer JAR missing fails the session"
- "settings file missing fails the session"
- "successful generation marks the session ready and stores a relative
  rom_path" (also asserts `mkdir_p` was called with the expected directory
  and that the CLI shape contains all required flags + the session seed)
- "session is in 'generating' status while the subprocess runs" (the strong
  hermetic check — observes status from inside the Open3 stub)
- "non-zero exit fails the session with truncated stderr"
- "non-zero exit truncates very long stderr to the column limit"
- "timeout fails the session with a timeout message"
- "precondition failure does not call Open3" (defensive extra; valuable)

Job:
- "creates 4 unclaimed pending sessions when run has none" — asserts seed
  uniqueness, `discord_user_id: nil`, positive 63-bit integer format, and
  randomizer called 4 times (covers the "calls randomizer for each session"
  bullet).
- "is a no-op when 4 sessions already exist for the run"
- "is a no-op when more than 4 sessions exist (defensive)"
- "handled per-session failure does not halt remaining ROM generation"
- "unrescued StandardError in one session does not stop the others"

No tests-by-implication. Every brief bullet maps to a named test.

**Flags honored.**

- No CLI flags invented — `-i / -o / -s / -seed` exactly as the brief
  specified.
- No controllers, routes, views, services, jobs, or buttons added beyond
  the two listed files. `git status` shows only the listed paths.
- All test data via FactoryBot (`create(:soul_link_run)`,
  `create(:soul_link_emulator_session, ...)`) — no fixture references in
  new tests.
- `.gitignore` correctly whitelists `storage/roms/{base,randomized}/.keep`
  and `lib/randomizer/.keep` while ignoring everything else under those
  paths. Verified two ways:
  - `git ls-files --others --exclude-standard` shows the three `.keep`
    files as trackable.
  - `git check-ignore -v` confirms the run-output directories
    (`storage/roms/randomized/run_*`) created during local test runs are
    ignored as intended (matched by `/storage/roms/randomized/*` at line
    33 of `.gitignore`).
- No SolidQueue config introduced; service is sync, job runs on the Rails 8
  `:async` adapter as specified.

**Definition of Done.** All eight DoD boxes pass independent verification:

- Service file exists and matches contract.
- Job file exists and matches contract.
- Service tests cover all listed scenarios; all green.
- Job tests cover all listed scenarios; all green.
- Full suite passes (131 = 116 + 10 service + 5 job).
- `.gitignore` updated; `.keep` files trackable.
- No real Java or filesystem writes in tests.
- All test data via FactoryBot — no fixture references in new tests.

Step 2 is clear.

VERDICT: PASS_WITH_OBSERVATIONS
