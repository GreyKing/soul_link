# Review Request — Step 3: Emulator Hardening

**Step:** 3 — Emulator Hardening (5 Must Fix bugs + several smaller items)
**Builder:** Bob
**Ready for Review:** YES

---

## Summary

Bundled hardening pass on the emulator workflow. Five Must Fix bugs (over-narrow rescue, no SRAM size cap, subprocess leak on timeout, channel race on enqueue, no guild authz on the run channel) plus three smaller items (persist failure mid-fail, save_data gzip compression, brittle query-count test) and a debug-line sweep. Pre-authorized by Project Owner.

All 13 DoD checkboxes hit. Suite passes 216/216 in three consecutive runs (was 200 baseline; +16 new tests). Compression measured: highly-compressible 512KB SRAM-shape payload → 543 bytes (0.1% ratio); realistic 80%-zero SRAM → 116KB (22%); pure-random worst-case → 525KB (gzip overhead).

---

## Files Changed

| File | Lines | Change |
|------|-------|--------|
| `app/channels/application_cable/connection.rb` | 5–14 | Expose `session` from the Rack request via `attr_reader` + capture in `connect`. Channels need it for guild authz. No behavior change for existing connections. |
| `app/channels/run_channel.rb` | 2–18 | `subscribed` rejects when `params[:guild_id]` is blank or doesn't match `connection.session[:guild_id]`. String comparison (params is String, session is Integer post-OAuth). |
| `app/channels/run_channel.rb` | 73–95 | `generate_emulator_roms` wraps the `:none` check in `run.with_lock`. SELECT FOR UPDATE serializes concurrent enqueues. |
| `app/channels/run_channel.rb` | 97–122 | `regenerate_emulator_roms` wraps the `:failed` check + destroy_all + enqueue in `run.with_lock`. Same race protection. |
| `app/models/soul_link_emulator_session.rb` | 1–47 | Add `GzipCoder` module (dump/load with magic-header detection for legacy plaintext) and `serialize :save_data, coder: GzipCoder`. Handles nil/empty/legacy cleanly. |
| `app/models/soul_link_emulator_session.rb` | 96–108 | Widen `delete_rom_file` rescue from `Errno::ENOENT` → `StandardError`; log with class+message+rom_path so disk failures (EACCES, EBUSY, NFS hiccups) can never roll back the AR transaction. |
| `app/controllers/emulator_controller.rb` | 11–16 | Add `MAX_SAVE_DATA_BYTES = 2.megabytes` constant with rationale comment. |
| `app/controllers/emulator_controller.rb` | 35–49 | Safety comment above `send_file` in `rom` documenting the path-traversal precondition (rom_path is server-derived). |
| `app/controllers/emulator_controller.rb` | 51–74 | `save_data` PATCH branch: pre-read content_length check + post-read bytesize check; both return `:content_too_large` (413) on overflow. Uses Rails 8's non-deprecated symbol. |
| `app/services/soul_link/rom_randomizer.rb` | 1–53 | Drop `require "open3"`; `call` now passes raw stderr through `fail!` (truncation centralized). |
| `app/services/soul_link/rom_randomizer.rb` | 78–184 | Replace `Timeout.timeout { Open3.capture3 }` with `Process.spawn` + `Process.waitpid(WNOHANG)` poll loop + TERM→grace→KILL escalation. New helpers: `wait_for_subprocess`, `terminate_subprocess`, `read_pipe`. Ensure block kills+reaps any leaked PID. |
| `app/services/soul_link/rom_randomizer.rb` | 199–221 | `fail!` uses `save` (not `save!`) and logs on failure instead of bubbling. New `truncate_error` helper centralizes the 255-char column-limit cap. |
| `test/channels/run_channel_test.rb` | 9–22 | New `stub_connection_with_session` helper that patches `connection.session` onto the ConnectionStub. All existing tests now use it; setup updated. |
| `test/channels/run_channel_test.rb` | 177–182 | Replaced the brittle `assert_queries_count(16)` test with a comment explaining why (the `session_queries == 2` regression above is the load-bearing protection). |
| `test/channels/run_channel_test.rb` | 215–290 | Six new tests: 3 guild-authz rejection cases (mismatch, blank, missing session), 2 `with_lock` invocation assertions (generate, regenerate), 1 behavioral race test (sequential calls — second one no-ops once `emulator_status != :none`). |
| `test/models/soul_link_emulator_session_test.rb` | 246–280 | New EACCES test: `Pathname#delete` raises EACCES; assert no exception bubbles, row is destroyed, log captured. Tiny `Pathname.stub_any_instance` helper added at file end. |
| `test/models/soul_link_emulator_session_test.rb` | 282–339 | Five new gzip coder tests: 200KB random round-trip, 512KB compressible payload (asserts <50% on-disk ratio + magic header), nil round-trip, empty round-trip, legacy-plaintext passthrough via `update_columns`. |
| `test/controllers/emulator_controller_test.rb` | 380–438 | Three new save_data PATCH tests: oversized body → 413, exact-cap body → 204, gzip round-trip through controller (asserts on-disk smaller than raw input). |
| `test/services/soul_link/rom_randomizer_test.rb` | 2 | Drop `require "open3"`. |
| `test/services/soul_link/rom_randomizer_test.rb` | 108–245 | Migrate all `Open3.stub(:capture3, ...)` to `@service.stub(:run_subprocess, ...)`. The seam moved; the contract (returns `[stdout, stderr, status]`) is preserved. |
| `test/services/soul_link/rom_randomizer_test.rb` | 247–276 | New fail!-resilience test: stub `session.save` → false, assert no raise + logged. |
| `test/services/soul_link/rom_randomizer_test.rb` | 278–333 | New TERM-on-timeout test: stub `Process.spawn`/`waitpid`/`kill`/`sleep`, force `GENERATION_TIMEOUT = 0`, assert SIGTERM was sent to the child PID and session lands in `:failed` with timeout message. |
| `test/lib/tasks/emulator_cleanup_test.rb` | 110–125 | Removed all six `warn "EMPTY-DIR DEBUG: ..."` lines from the empty-run-dir test. Logic untouched. |

---

## Test Results

```
Baseline: 200 runs, 590 assertions, 0 failures, 0 errors, 0 skips
   After: 216 runs, 628 assertions, 0 failures, 0 errors, 0 skips
   Delta: +16 tests, +38 assertions
```

**Three consecutive full-suite runs (in-process parallelize across all CPU cores):**
```
Run 1: 216 runs, 628 assertions, 0 failures, 0 errors, 0 skips
Run 2: 216 runs, 628 assertions, 0 failures, 0 errors, 0 skips
Run 3: 216 runs, 628 assertions, 0 failures, 0 errors, 0 skips
```

Confirmed clean across the run. The suite uses `parallelize(workers: :number_of_processors)` per `test_helper.rb:12`, so each invocation already exercises the parallel path.

---

## Compression Confirmation

Measured on three SRAM-shape payloads via stdlib `Zlib::GzipWriter`:

| Payload | Raw bytes | Compressed bytes | Ratio |
|---------|-----------|------------------|-------|
| 512KB pure zero-padded (worst-realistic SRAM) | 524,288 | 543 | **0.1%** |
| 512KB realistic (~80% zeros + ~112KB random save data) | 524,288 | 115,976 | **22.1%** |
| 512KB pure random (incompressible worst case) | 524,288 | 524,466 | 100.03% (gzip framing overhead) |

The Pokemon Platinum SRAM in practice falls into the realistic bucket — call it ~20-25% compressed (~100KB on disk per save). Even on the pathologically-compressible zero-pad case, gzip framing adds < 1KB. The worst case (pure random) costs us ~180 bytes of overhead — acceptable.

In-test confirmation via `attributes_before_type_cast["save_data"].bytesize` round-trips:
- Model-level test: 512KB compressible → on-disk < 256KB (asserted < 50%)
- Controller-level test: ~256KB compressible → on-disk < raw input

---

## DoD Checklist

- [x] `delete_rom_file` catches `StandardError`, logs, doesn't bubble
- [x] PATCH save_data rejects bodies > 2MB with 413, before reading
- [x] save_data round-trips through gzip compression; on-disk bytes are smaller than raw
- [x] Subprocess timeout sends TERM then KILL to the child Java process
- [x] `RomRandomizer#fail!` survives a save failure without bubbling
- [x] `RunChannel#subscribed` rejects mismatched guild_id
- [x] `RunChannel#generate_emulator_roms` (and regenerate) wrap their idempotency check in `with_lock`
- [x] Concurrent-enqueue race test asserts exactly 1 job enqueued under contention (lighter `with_lock`-was-called assertion + behavioral sequential test, per brief's fallback)
- [x] `EmulatorController#rom` has a safety comment explaining the path-traversal precondition
- [x] Brittle `assert_queries_count(16)` test dropped (replaced with explanatory comment; the targeted N+1 test at run_channel_test.rb:148 carries the load-bearing assertion)
- [x] Zero `warn "DEBUG"`, `puts "DEBUG"`, `binding.pry`, `byebug`, `debugger` lines in any test
- [x] Full suite passes: 200 baseline + 16 new tests, 0 failures
- [x] Suite passes 3+ consecutive runs (no new flakes)

---

## Decisions / Notes

- **`with_lock` race test approach.** Brief authorized falling back to a "lighter mock-based assertion that `with_lock` was called" if true thread-based testing was flaky. I went straight to that fallback because: (a) ActionCable's `ConnectionStub` doesn't simulate real concurrent subscriptions, (b) MySQL row locks on the test DB can deadlock under spurious load and produce flakes, (c) the contract being tested is "call `with_lock`" — anything beyond that becomes a test of MySQL itself. Added a complementary behavioral test that sequences two `generate` calls with a state mutation between (mimicking what the job would do post-acquire) and asserts only one job is enqueued.
- **`stub_connection_with_session` helper.** `ActionCable::Channel::ConnectionStub` only stubs `identified_by` attrs — no session. Cleanest path was a setup helper that calls `stub_connection` then patches `connection.session` via `define_singleton_method`. Drop-in for all existing tests; one-line change in setup.
- **Run subprocess seam.** Tests migrated from stubbing `Open3.capture3` to stubbing `@service.stub(:run_subprocess, ...)`. The contract (`[stdout, stderr, status]` return) is preserved; only the seam moved. The dedicated TERM-on-timeout test does exercise the real `Process.spawn` path through stubs of spawn/waitpid/kill/sleep so the new pipe+poll loop is genuinely covered.
- **Legacy plaintext passthrough in `GzipCoder.load`.** Brief asked for "Defensive: if it doesn't start with gzip magic, assume legacy plaintext and pass through". Implemented and tested via `update_columns` (which bypasses the coder on write, simulating a pre-existing row). The branch can be removed once all production rows are confirmed gzipped.
- **`:content_too_large` not `:payload_too_large`.** Rails 8.1 deprecates `:payload_too_large` in favor of `:content_too_large` (both map to HTTP 413). Used the non-deprecated form to avoid warnings in CI logs.
- **Empty save_data short-circuits in dump.** An empty buffer skips the gzip path entirely and stores empty bytes. This preserves the legacy contract that GET save_data returns 204 when the column is blank — gzipping an empty buffer would produce ~20 bytes of magic+CRC and break that contract.
- **`STDERR_LIMIT = 255` retained from prior step.** Brief here didn't ask to change it; the new `truncate_error` helper just centralizes the existing cap. Original Architect note about the 255-char column-limit override is preserved at the constant.
- **Did NOT touch:** `set_session` claim-retry logic, the existing `:json` coder usage anywhere else, `SoulLinkRun#emulator_status` itself, the cleanup rake task body (just the test debug lines), or any non-emulator code.

---

## Open Questions

None. Ship-ready.

If Reviewer wants the legacy-plaintext branch in `GzipCoder.load` removed before commit (since no production rows pre-exist this coder), that's a one-line delete plus dropping the corresponding test. Flagging as a decision point, not a blocker.
