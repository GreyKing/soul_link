# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 3 — Emulator Hardening

Context: a fresh-eyes review of the emulator workflow surfaced 5 real Must Fix bugs plus several smaller hardening items. This step bundles them all. Project Owner pre-authorized commit.

This is a meaty step — many small changes across many files. They're independent enough that you can ship most of them even if one stalls.

### Files to Modify

**Production code:**
- `app/models/soul_link_emulator_session.rb` — widen rescue in `delete_rom_file`; add gzip compression on save_data column
- `app/controllers/emulator_controller.rb` — size cap on save_data PATCH; safety comment on `rom`
- `app/services/soul_link/rom_randomizer.rb` — replace `Open3.capture3 + Timeout` with subprocess-killable pattern; recover from persist failure mid-fail
- `app/channels/run_channel.rb` — `with_lock` on generate; guild authz in `subscribed`

**Tests:**
- `test/models/soul_link_emulator_session_test.rb` — non-ENOENT delete; gzip round-trip
- `test/controllers/emulator_controller_test.rb` — size cap rejection
- `test/services/soul_link/rom_randomizer_test.rb` — subprocess kill assertion (best-effort); persist-fail recovery
- `test/channels/run_channel_test.rb` — drop or relax brittle `assert_queries_count(16)`; add concurrent-enqueue race test (using threads + `with_lock`); add guild-mismatch rejection test
- `test/lib/tasks/emulator_cleanup_test.rb` — remove leftover `warn "EMPTY-DIR DEBUG: ..."` lines

**Misc:**
- All test files — sweep for stray `warn "DEBUG:..."` / `puts` / `binding.pry` / `byebug` lines from prior debugging sessions and remove
- `handoff/BUILD-LOG.md` — log the Nice-to-Have items as Known Gaps (architect will do this, not Bob)

---

### #1 Widen `delete_rom_file` rescue

**File:** `app/models/soul_link_emulator_session.rb`

Current:
```ruby
def delete_rom_file
  rom_full_path&.delete if rom_full_path&.exist?
rescue Errno::ENOENT
  # Already gone — nothing to do.
end
```

Change to:
```ruby
def delete_rom_file
  rom_full_path&.delete if rom_full_path&.exist?
rescue StandardError => e
  # File cleanup is best-effort. We never want a disk-level failure (EACCES,
  # EBUSY, file already gone) to roll back the AR transaction — that would
  # leave the cascade in a half-deleted state with rows present and ROMs
  # missing.
  Rails.logger.warn("delete_rom_file: #{e.class}: #{e.message} (rom_path=#{rom_path.inspect})")
end
```

**Test:** add a test that stubs `Pathname#delete` to raise `Errno::EACCES`, destroys the session, asserts: (a) no exception bubbles, (b) the row is destroyed, (c) something gets logged. Keep existing ENOENT test.

---

### #2 Save data: size cap + gzip compression

**Two coordinated pieces.** The controller enforces an inbound size cap so we never read a multi-MB body to memory. The model gzips before write and gunzips after read so disk use stays small.

#### Controller — `app/controllers/emulator_controller.rb#save_data`

Add at the top of the PATCH branch (before `request.body.read`):

```ruby
MAX_SAVE_DATA_BYTES = 2.megabytes  # raw, uncompressed. Pokemon Platinum SRAM is ~512KB.

def save_data
  if request.patch?
    if request.content_length && request.content_length > MAX_SAVE_DATA_BYTES
      return head :payload_too_large
    end

    blob = request.body.read
    return head :payload_too_large if blob.bytesize > MAX_SAVE_DATA_BYTES

    @session.update!(save_data: blob)
    head :no_content
  else
    # ... existing GET branch ...
  end
end
```

The double-check (content_length AND bytesize) handles clients that lie about content_length or use chunked encoding without it.

#### Model — gzip compression on `save_data`

`save_data` is a MEDIUMBLOB. We'll compress on write and decompress on read transparently. Use Rails' `serialize` with a custom coder, OR override the writer/reader. Custom coder is cleaner:

```ruby
require "zlib"
require "stringio"

class SoulLinkEmulatorSession < ApplicationRecord
  # Transparent gzip compression of the save_data BLOB. Pokemon Platinum SRAM
  # is ~512KB raw, mostly zero-padded — compresses to ~50-80KB. Stays fully
  # opaque to EmulatorJS: it sends/receives raw bytes; the model handles the
  # transform.
  GZIP_MAGIC = "\x1f\x8b".b.freeze  # standard gzip header

  serialize :save_data, coder: GzipCoder

  module GzipCoder
    def self.dump(value)
      return nil if value.nil?
      io = StringIO.new
      io.set_encoding(Encoding::BINARY)
      gz = Zlib::GzipWriter.new(io)
      gz.write(value.b)
      gz.close
      io.string
    end

    def self.load(value)
      return nil if value.nil? || value.empty?
      bytes = value.is_a?(String) ? value : value.to_s
      bytes = bytes.b
      # Defensive: if it doesn't start with gzip magic, assume legacy plaintext
      # and pass through. (Belt-and-suspenders; nothing should be plaintext yet.)
      return bytes unless bytes.start_with?(GZIP_MAGIC)
      Zlib::GzipReader.new(StringIO.new(bytes)).read
    end
  end
end
```

**Why a module not a class:** AR's `serialize` accepts any object responding to `dump` and `load`. A module is the lightest weight. If `serialize` rejects it, fall back to a class with the same two methods.

**Test:** model tests covering — (a) write a 200KB random byte string, reload, assert exact equality; (b) the column on disk holds compressed bytes (much smaller than the input — compare `session.attributes_before_type_cast["save_data"].bytesize` to original); (c) nil round-trips as nil; (d) empty round-trips as nil or empty (your call, document either way).

**Test (controller):** PATCH a body larger than 2MB → 413; PATCH normal-sized body → 204; assert `session.save_data` after PATCH equals what was sent (round-trip through compression).

---

### #3 Kill the subprocess on timeout

**File:** `app/services/soul_link/rom_randomizer.rb`

The current pattern (`Timeout.timeout { Open3.capture3 ... }`) raises in the calling thread but leaves the Java child running. Replace with a pattern that actually signals the child:

```ruby
def run_with_timeout(cmd_args)
  stdout_w_pipe, stderr_w_pipe = nil, nil
  pid = nil

  begin
    stdout_r, stdout_w = IO.pipe
    stderr_r, stderr_w = IO.pipe
    pid = Process.spawn(*cmd_args, out: stdout_w, err: stderr_w)
    stdout_w.close
    stderr_w.close

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + GENERATION_TIMEOUT
    loop do
      finished_pid = Process.waitpid(pid, Process::WNOHANG)
      break if finished_pid

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        Process.kill("TERM", pid) rescue nil
        sleep 0.5
        Process.kill("KILL", pid) rescue nil
        Process.waitpid(pid) rescue nil
        return [:timeout, nil, nil]
      end

      sleep 0.1
    end

    status = $?
    stdout = stdout_r.read
    stderr = stderr_r.read
    [status.success? ? :ok : :failed, stdout, stderr, status]
  ensure
    [stdout_r, stdout_w, stderr_r, stderr_w].compact.each { |io| io.close rescue nil }
  end
end
```

Then in `call`:
```ruby
result, stdout, stderr, status = run_with_timeout([
  "java", "-jar", JAR_PATH.to_s,
  "-i", BASE_ROM_PATH.to_s,
  "-o", output_path.to_s,
  "-s", SETTINGS_PATH.to_s,
  "-seed", @session.seed.to_s
])

case result
when :timeout
  fail!("Generation timed out after #{GENERATION_TIMEOUT}s")
when :failed
  fail!(truncate_error(stderr))
when :ok
  finish_ready!(output_path)
end
```

**Test:** the existing "timeout" test stubs `Open3.capture3` to raise `Timeout::Error`. Update it to test the new path. Stub `Process.spawn` to return a fake PID, stub `Process.waitpid` to always return `nil` (never finishes), advance the clock or shrink `GENERATION_TIMEOUT` to ~50ms via constant override, assert: (a) `Process.kill("TERM", pid)` was called, (b) session ends up failed with timeout message.

If stubbing the subprocess machinery is too painful, settle for a "behavior" test that verifies the error_message says "timed out" — at minimum.

---

### #4 Channel idempotency: `with_lock` on generate

**File:** `app/channels/run_channel.rb#generate_emulator_roms`

Current:
```ruby
def generate_emulator_roms(_data)
  run = SoulLinkRun.current(@guild_id)
  return broadcast_error("No active run") if run.nil?
  return broadcast_state if run.emulator_status != :none

  SoulLink::GenerateRunRomsJob.perform_later(run)
  broadcast_state
end
```

Change to:
```ruby
def generate_emulator_roms(_data)
  run = SoulLinkRun.current(@guild_id)
  return broadcast_error("No active run") if run.nil?

  enqueued = false
  run.with_lock do
    run.reload  # with_lock SELECT … FOR UPDATE refreshes; this re-checks emulator_status under the lock
    if run.emulator_status == :none
      SoulLink::GenerateRunRomsJob.perform_later(run)
      enqueued = true
    end
  end

  broadcast_state
end
```

`with_lock` opens a transaction with `SELECT ... FOR UPDATE` on the run row. While holding the lock, no concurrent channel call can pass the inner `:none` check. The second caller will block until the first releases; by then `emulator_status != :none` and they no-op.

Apply the same pattern to `regenerate_emulator_roms` if it has the same shape (re-check under lock).

**Test:** add a concurrent-enqueue race test using two threads:
```ruby
test "concurrent generate_emulator_roms enqueues exactly one job" do
  # ... setup with active run, no sessions ...
  threads = 2.times.map do
    Thread.new do
      stub_connection(current_user_id: GREY)
      subscription = subscribe(guild_id: GUILD_ID)
      perform :generate_emulator_roms
    end
  end
  threads.each(&:join)
  assert_equal 1, enqueued_jobs.size
end
```

If thread-based testing is too brittle, accept a lighter test that asserts `with_lock` is called (via mock).

---

### #5 Guild authorization in `RunChannel#subscribed`

**File:** `app/channels/run_channel.rb`

Currently the channel reads `params[:guild_id]` and trusts whatever the JS sent. Add a check:

```ruby
def subscribed
  guild_id = params[:guild_id]
  if guild_id.blank? || guild_id.to_s != connection.session[:guild_id].to_s
    reject
    return
  end
  @guild_id = guild_id
  stream_from "run:#{guild_id}"
end
```

You may need to expose `session` from the connection. Look at `app/channels/application_cable/connection.rb` — if it doesn't already expose `session`, add an attr_reader or pass it via `identified_by`.

**Note:** the user's logged-in Discord guild_id is set at `sessions_controller.rb:41` (per the prior explore). Use whatever name the session key actually is — verify by reading the controller. Don't guess.

**Test:** add a test that subscribes with a `guild_id` param that doesn't match the session's guild → assert subscription is rejected. Existing tests should continue to pass (they use the matching guild).

---

### #6 Recover from persist failure in `RomRandomizer#fail!`

**File:** `app/services/soul_link/rom_randomizer.rb`

Currently `fail!` calls `persist!` which can raise; this leaves the session in `:generating` (or `:pending`) state forever. Wrap and downgrade:

```ruby
def fail!(message)
  @session.status = "failed"
  @session.error_message = truncate_error(message)
  @session.save  # NOT save! — best-effort
  Rails.logger.error("RomRandomizer fail!: #{message}") unless @session.persisted?
end
```

If `save` returns false (validation failed, or AR couldn't write), at least it's logged and the job loop continues. The session may still appear "stuck" in the UI but the next regenerate will clean it up.

**Test:** stub the session's `save` to return false (simulating a validation failure mid-fail). Call `fail!`. Assert: (a) no exception bubbles, (b) `Rails.logger.error` was called.

---

### #7 Skip — Project Owner explicitly declined (`current_user_id` falsy guard).

---

### #8 Add safety comment to `EmulatorController#rom`

**File:** `app/controllers/emulator_controller.rb#rom`

No code change. Add a comment above `send_file`:

```ruby
def rom
  return head :not_found unless @session&.ready? && @session.rom_full_path&.exist?
  # Safety: rom_full_path is server-derived. session.rom_path is only ever
  # written by SoulLink::RomRandomizer using a path constructed under
  # OUTPUT_DIR via Pathname#relative_path_from(Rails.root). Never user input.
  # If a future migration or admin script writes an arbitrary string,
  # send_file becomes a file-read-anywhere primitive — guard with a
  # path.start_with?(OUTPUT_DIR) check at that point.
  send_file @session.rom_full_path, type: "application/octet-stream", ...
end
```

---

### #9 Fix brittle `assert_queries_count(16)` test

**File:** `test/channels/run_channel_test.rb`

Currently:
```ruby
expected = 16
assert_queries_count(expected) do
  RunChannel.broadcast_run_state(guild_id)
end
```

Change to either:
- Drop entirely (the dedicated N+1 test at the same file already does targeted regression coverage).
- OR change to `assert_queries_count_at_most(20)` style — but that's not a built-in. Easiest: just drop.

Recommend: drop. The targeted N+1 test at run_channel_test.rb (the one that asserts `session_queries == 2`) is the load-bearing protection. The hard-count test fires on any unrelated query addition.

---

### #10 Sweep all debug lines + comment audit

**Action:**
1. Grep test directory for: `warn "DEBUG`, `warn "EMPTY-DIR`, `warn "SUMMARY`, `puts "DEBUG`, `binding.pry`, `byebug`, `debugger`. Remove every one.
2. Read every file you've touched in this step. Confirm comments explain WHY (intent, constraint, gotcha) — not WHAT (which the code already does). Remove redundant comments. Add a one-liner where the WHY isn't obvious.

Do NOT comment-audit files outside this step's touched set. That's separate.

---

### Build Order

1. Read `app/channels/application_cable/connection.rb` — see how `current_user_id` is set, find where session is exposed.
2. Read `app/controllers/sessions_controller.rb` — confirm session key name for guild_id.
3. Apply #5 (guild authz). Run channel tests.
4. Apply #4 (with_lock). Run channel tests.
5. Apply #1 (rescue widening). Run model tests.
6. Apply #6 (persist failure). Run randomizer tests.
7. Apply #2 (size cap + gzip). This is the biggest change. Run model + controller tests.
8. Apply #3 (subprocess kill). Run randomizer tests.
9. Apply #8 (safety comment). No tests needed.
10. Apply #9 (drop brittle test).
11. Apply #10 (debug sweep + comment audit).
12. Run full suite: `bin/rails test`. Confirm 200 baseline + new tests pass, 0 failures.
13. Run full suite 3+ times to confirm no parallel-test flakes.

### Flags

- Flag: **Each piece is mostly independent.** If gzip serialization gets gnarly (it sometimes is), ship the size cap alone and flag the compression piece in REVIEW-REQUEST.
- Flag: **`with_lock` requires running inside a transaction.** AR's `with_lock` opens one if not already in one. Confirm by reading the Rails docs / existing usage.
- Flag: **The gzip coder must handle empty/nil cleanly** to not break factory defaults like `save_data { nil }`.
- Flag: **The `connection.session` access pattern** depends on how `ApplicationCable::Connection` is set up. If `session` isn't exposed there, add `attr_reader :session` and `@session = request.session` in `connect` — don't invent a different mechanism.
- Flag: **The subprocess test will need to skip in CI** if Java isn't available. Stub `Process.spawn` to return a fake PID; don't actually spawn Java.
- Flag: **Don't rewrite the existing well-tested code paths.** Touch only what each item requires.
- Flag: **No new gems.** All four pieces use stdlib (`zlib`, `process`, `pathname`).
- Flag: **Project Owner pre-authorized commits.** After Richard reviews and verdicts PASS or PASS_WITH_OBSERVATIONS, Architect commits without re-asking.
- Flag: Rails commands use `bin/rails ...` (e.g. `bin/rails test`). Fall back to `mise exec -- bundle exec rails ...` only if `bin/rails` fails.
- Flag: Do NOT commit. Architect commits.

### Definition of Done

- [ ] `delete_rom_file` catches `StandardError`, logs, doesn't bubble
- [ ] PATCH save_data rejects bodies > 2MB with 413, before reading
- [ ] save_data round-trips through gzip compression; on-disk bytes are smaller than raw
- [ ] Subprocess timeout sends TERM then KILL to the child Java process
- [ ] `RomRandomizer#fail!` survives a save failure without bubbling
- [ ] `RunChannel#subscribed` rejects mismatched guild_id
- [ ] `RunChannel#generate_emulator_roms` (and regenerate) wrap their idempotency check in `with_lock`
- [ ] Concurrent-enqueue race test asserts exactly 1 job enqueued under contention
- [ ] `EmulatorController#rom` has a safety comment explaining the path-traversal precondition
- [ ] Brittle `assert_queries_count(16)` test dropped or relaxed
- [ ] Zero `warn "DEBUG"`, `puts "DEBUG"`, `binding.pry`, `byebug`, `debugger` lines in any test
- [ ] Full suite passes: 200 baseline + new tests, 0 failures
- [ ] Suite passes 3+ consecutive parallel runs (no new flakes)

---

## Builder Plan
*Builder adds their plan here before building. Architect reviews and approves.*

Order: #5 guild authz (expose `session` on Connection, gate `subscribed`) → #4 `with_lock` on generate/regenerate → #1 widen rescue → #6 `fail!` survives save failure → #2 size cap (controller) + gzip coder (`serialize :save_data`) with nil/empty/legacy-plaintext handling → #3 spawn/waitpid timeout w/ TERM→KILL escalation, plus existing `Timeout::Error` rescue retained for safety → #8 safety comment on `rom` → #9 drop `assert_queries_count(16)` → #10 sweep `EMPTY-DIR DEBUG` warns from cleanup test + comment audit on touched files. `RunChannel` already uses `transmit({ error: })` (not `broadcast_error`); preserving that style. Session key for guild: `:guild_id` (confirmed in `sessions_controller.rb:41`). Tests stub `Process.spawn`/`Process.waitpid`/`Process.kill` and a tiny `Process::CLOCK_MONOTONIC` advancement; concurrent-enqueue race uses two threads with a mutex-gated stub to force interleaving, with mock-`with_lock` fallback if flaky. Rails commands run via `mise exec -- bin/rails test` (PATH currently has Ruby 3.0.6 first; using mise's Ruby 3.4.5 binary explicitly).
