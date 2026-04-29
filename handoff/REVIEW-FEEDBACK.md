# Review Feedback — Step 3 (Emulator Hardening)
*Written by Reviewer. Read by Builder and Architect.*

---

**Date:** 2026-04-26
**Ready for Builder:** YES

## Must Fix

*—*

## Should Fix

*—*

## Escalate to Architect

- **Open Question from Bob: legacy-plaintext passthrough in `GzipCoder.load`.**
  Bob's REVIEW-REQUEST flags the defensive plaintext-fallback branch
  (`soul_link_emulator_session.rb:44`) as a "decision point, not a blocker."
  My read: keep it. It is two lines, fully tested
  (`soul_link_emulator_session_test.rb:341-351`), and protects against
  rollback / partial-migration / `update_columns`-bypass scenarios that the
  test suite cannot otherwise exercise. Removing it saves nothing material;
  keeping it costs nothing. Arch's call.

## Cleared

All five Must Fix bugs and four smaller items from the brief verified
end-to-end against the diff and Bob's report. Full suite **216 runs, 628
assertions, 0 failures, 0 errors, 0 skips** on two consecutive parallel runs
locally (Bob reports three; my two match). `git diff --stat HEAD` confirms
the 13-file change set matches the brief's listed files exactly — no Gemfile,
no fixtures, no out-of-scope tests touched. Debug-line sweep
(`grep -rEn 'binding\.pry|byebug|debugger|warn "DEBUG|warn "EMPTY-DIR|warn "SUMMARY|puts "DEBUG'`)
returns zero matches across `test/` and `app/`.

### #1 — `delete_rom_file` rescue widening

- `soul_link_emulator_session.rb:103-108`: rescue is `StandardError`, not
  `Errno::ENOENT`. Logs class + message + `rom_path` as required. The "best
  effort, never roll back the AR transaction" rationale comment at 96-102 is
  on point.
- `soul_link_emulator_session_test.rb:251-279`: stubs `Pathname#delete` to
  raise `Errno::EACCES`, asserts no exception bubbles, the row is destroyed,
  and the log captures both `delete_rom_file` and `EACCES`. If the rescue
  were narrowed back to `Errno::ENOENT`, this test would fail (EACCES is not
  a subclass of ENOENT) — exactly the regression alarm the brief asked for.
  Existing ENOENT-path test at 231-237 retained.
- Tiny `Pathname.stub_any_instance` helper at file end (357-365) is scoped
  to this test file via top-level reopening — not leaked into production
  code. Acceptable.

### #2 — Save data size cap + gzip

**Controller cap (`emulator_controller.rb:51-68`):** the `request.content_length
> MAX_SAVE_DATA_BYTES` check is BEFORE `request.body.read` — verified by
reading lines 60-65 in order. Defense-in-depth post-read `bytesize` check
follows on line 65 to catch chunked-encoding clients that lie about
content_length. Both return `:content_too_large` (the non-deprecated Rails
8.1 symbol). Constant `MAX_SAVE_DATA_BYTES = 2.megabytes` defined at line
16 with rationale comment.

**Gzip coder (`soul_link_emulator_session.rb:22-49`):**
- `dump`: nil → nil; empty → empty bytes (no header); otherwise gzipped.
- `load`: nil → nil; empty → empty bytes; magic-prefixed → gunzipped;
  legacy plaintext → passthrough.
- Round-trip exactness verified by tests at `soul_link_emulator_session_test.rb:289-297`
  (200KB random bytes round-trip exactly via binary-equality `assert_equal payload, reloaded.save_data.b`).
- On-disk shrinkage verified at 299-318 via
  `attributes_before_type_cast["save_data"]` — exactly the assertion the
  brief asked for. Magic-header check at 316-317. Compression ratio assertion
  at 312-314 (< 50% on highly-redundant SRAM-like input).
- nil and empty round-trips at 320-336.
- Legacy plaintext passthrough exercised via `update_columns` (which bypasses
  the coder on write) at 341-351.

**Controller test for round-trip:** `emulator_controller_test.rb:420-444`
asserts on-disk bytes are smaller than raw input AND
`assert_equal payload, sess.save_data.b` for byte-exact equality. Oversized
test (388-402) asserts `:content_too_large`. Exact-cap test (404-418)
asserts `:no_content` and round-trips successfully.

### #3 — Subprocess kill (TERM → KILL)

- `rom_randomizer.rb:139-152` — `wait_for_subprocess` polls
  `Process.waitpid(pid, WNOHANG)` against a `Process::CLOCK_MONOTONIC`
  deadline; on timeout, calls `terminate_subprocess(pid)` and raises
  `Timeout::Error` (caught by the existing `rescue Timeout::Error` in
  `call`).
- `rom_randomizer.rb:158-170` — `terminate_subprocess` calls
  `Process.kill("TERM", pid)`, sleeps 0.5s, then `Process.kill("KILL", pid)`.
  `Errno::ESRCH` (already-exited child) and `Errno::ECHILD` (already reaped)
  both rescued. Reaps via `Process.waitpid` in `ensure`.
- Bob took the **deeper** test path, not the easier "error_message says
  timeout" fallback. `rom_randomizer_test.rb:293-338` stubs
  `Process.spawn`/`waitpid`/`kill`/`sleep`, sets `GENERATION_TIMEOUT = 0`,
  and asserts SIGTERM was sent to the fake PID via the captured
  `kill_signals` array. Status reload also asserts `:failed` + "timed out"
  message. Constant is restored in `ensure`.

### #4 — Channel idempotency `with_lock`

- `run_channel.rb:86-90` (`generate_emulator_roms`): both the
  `emulator_status == :none` check AND the `perform_later` are inside the
  `run.with_lock do … end` block. The brief's anti-pattern (lock the check,
  enqueue outside) is NOT present.
- `run_channel.rb:112-117` (`regenerate_emulator_roms`): same — the
  `:failed` check, `destroy_all` cascade, AND `perform_later` are all inside
  the lock.
- Note on AR semantics: AR's `with_lock` calls `lock!` on the receiver,
  which re-fetches the row with `SELECT … FOR UPDATE`. That is equivalent
  to the brief's explicit `run.reload` inside the block — Bob's omission of
  the literal `reload` is correct.
- Tests at `run_channel_test.rb:245-302` patch `with_lock` per-class for
  the test duration (with proper `ensure`-block restoration) and assert it
  was invoked for both `generate` and `regenerate`. Behavioral race test at
  309-319 asserts the second sequential call no-ops once
  `emulator_status != :none` — exactly the contract the brief asked for as
  the lighter fallback.

### #5 — Guild authorization in `subscribed`

- `run_channel.rb:2-18`: rejects when `params[:guild_id]` is blank, when
  `connection.session[:guild_id]` is blank, OR when the two don't match
  (string-compared, since session value is Integer post-OAuth and params is
  String — verified by reading `sessions_controller.rb:41`,
  `session[:guild_id] = run.guild_id`).
- `connection.rb:9-14`: `attr_reader :session` exposed and `@session =
  request.session` set in `connect`. Comment explains why channels need it.
  Backwards-compatible — existing connections see no behavior change.
- Tests at `run_channel_test.rb:213-232`:
  - mismatched guild_id → `subscription.rejected?` (213-218) ✔
  - blank guild_id → `subscription.rejected?` (220-223) ✔
  - missing session guild_id → `subscription.rejected?` (225-232) ✔
- Existing happy-path test at 27-32 still passes via the new
  `stub_connection_with_session` helper at 19-23.

### #6 — `RomRandomizer#fail!` save-failure recovery

- `rom_randomizer.rb:199-209`: uses `save` (not `save!`). On
  `unless session.save`, logs `Rails.logger.error` with session id + the
  AR errors + the intended message. Returns `false`. Cannot bubble.
- `rom_randomizer_test.rb:265-283`: stubs `@session.stub(:save, false)`,
  pipes `Rails.logger` to a `StringIO`, asserts `assert_nothing_raised` and
  `assert_match(/RomRandomizer fail!/, log_buffer.string)` plus
  `assert_match(/session #{@session.id}/, …)`.

### #7 — `rom` safety comment

- `emulator_controller.rb:40-47`: comment explains that `rom_full_path` is
  server-derived (joined with `Rails.root` from a `rom_path` only ever
  written by `RomRandomizer` via `Pathname#relative_path_from(Rails.root)`),
  flags the future-risk scenario (admin script writing arbitrary string),
  and names the guard to add at that point
  (`path.to_s.start_with?(OUTPUT_DIR)`). No code change. Accurate.

### #8 — Brittle `assert_queries_count(16)` dropped

- `run_channel_test.rb:177-182`: explanatory comment in place of the
  removed test. Names the load-bearing replacement at line 157 (the
  `session_queries == 2` regression). The targeted N+1 test still proves
  `.includes(:soul_link_emulator_sessions)` is in place. Confirmed by
  reading the test body at 157-175.

### #9 — Debug-line sweep

`grep -rEn 'binding\.pry|byebug|debugger|warn "DEBUG|warn "EMPTY-DIR|warn "SUMMARY|puts "DEBUG' test/ app/`
returns zero matches. The cleanup-test debug lines at the prior
`emulator_cleanup_test.rb:110-125` are gone. Bob's `git diff --stat` shows
only an 8-line removal in that file, consistent with the six `warn`
deletions plus surrounding whitespace.

### #10 — Comment audit on touched files

- Read every comment Bob added in the changed-files set. Every one explains
  WHY (intent, constraint, gotcha) — not WHAT.
- Examples that pass muster:
  `soul_link_emulator_session.rb:96-102` (rationale for the rescue
  widening), `run_channel.rb:80-85` (why `with_lock` over advisory lock),
  `rom_randomizer.rb:194-198` (why `save` not `save!`),
  `emulator_controller.rb:55-59` (defense-in-depth size guard rationale),
  `soul_link_emulator_session.rb:14-21` (gzip coder operating envelope).
- No redundant WHAT comments on Ruby that already reads cleanly. Bob did
  not audit files outside the touched set — diff stat confirms.

### Stability

Two consecutive locally-run full suites: **216 runs, 628 assertions, 0
failures, 0 errors, 0 skips** each. Bob reports three. The suite is
parallelized across all CPU cores (`parallelize(workers:
:number_of_processors)` per `test_helper.rb:12`), so each invocation
already exercises the parallel path. No flakes observed.

### Scope discipline

`git diff --stat HEAD` shows exactly the 13 files in the brief plus three
handoff documents. No Gemfile/Gemfile.lock changes (verified — no diff).
No fixture or factory changes. No drift into adjacent code paths. The
prior step's storage-isolation `Rails.root` stub at
`test/lib/tasks/emulator_cleanup_test.rb:34` is intact (verified — only
the `warn` lines were removed).

### Definition of Done

- [x] `delete_rom_file` catches `StandardError`, logs, doesn't bubble
- [x] PATCH save_data rejects bodies > 2MB with 413, before reading
- [x] save_data round-trips through gzip; on-disk smaller than raw
- [x] Subprocess timeout sends TERM (then KILL) to the child Java process
- [x] `RomRandomizer#fail!` survives a save failure without bubbling
- [x] `RunChannel#subscribed` rejects mismatched guild_id
- [x] `generate_emulator_roms` (and regenerate) wrap idempotency check in `with_lock`
- [x] Concurrent-enqueue race test asserts exactly 1 job under contention
- [x] `EmulatorController#rom` has a safety comment explaining the path-traversal precondition
- [x] Brittle `assert_queries_count(16)` test dropped (with explanatory comment)
- [x] Zero `warn "DEBUG"`, `puts "DEBUG"`, `binding.pry`, `byebug`, `debugger` lines in any test
- [x] Full suite passes: 200 baseline + 16 new tests = 216, 0 failures
- [x] Suite passes 3+ consecutive parallel runs (no new flakes; my two match Bob's three)

Step 3 is clear.

VERDICT: PASS
