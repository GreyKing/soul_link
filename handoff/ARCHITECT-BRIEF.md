# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 2 — `SoulLink::RomRandomizer` Service + `GenerateRunRomsJob`

Context: Step 1 created the `SoulLinkEmulatorSession` data layer. This step adds the service that wraps the Universal Pokemon Randomizer JAR, plus the background job that batch-creates 4 sessions per run and generates their ROMs. No controllers, routes, or views — Step 4 wires those. Run-creator clicks "Generate Emulator ROMs" (Step 4 button) → controller enqueues the job → 4 differently-seeded ROMs land on disk.

### Files to Create

- `app/services/soul_link/rom_randomizer.rb`
- `app/jobs/soul_link/generate_run_roms_job.rb`
- `test/services/soul_link/rom_randomizer_test.rb`
- `test/jobs/soul_link/generate_run_roms_job_test.rb`
- `storage/roms/base/.keep`
- `storage/roms/randomized/.keep`
- `lib/randomizer/.keep`

### Files to Modify

- `.gitignore` — add `/storage/roms/*` (allow `.keep` files), `/lib/randomizer/randomizer.jar`. Suggested:
  ```
  /storage/roms/base/*.nds
  /storage/roms/randomized/
  /lib/randomizer/randomizer.jar
  ```
  Adjust to keep `.keep` files tracked.
- `test/factories/soul_link_emulator_sessions.rb` — extend traits only if a test needs a state not currently buildable. Don't gold-plate.

### Service: `app/services/soul_link/rom_randomizer.rb`

```ruby
module SoulLink
  class RomRandomizer
    JAR_PATH       = Rails.root.join("lib", "randomizer", "randomizer.jar")
    BASE_ROM_PATH  = Rails.root.join("storage", "roms", "base", "platinum.nds")
    SETTINGS_PATH  = Rails.root.join("config", "soul_link", "randomizer_settings.rnqs")
    OUTPUT_DIR     = Rails.root.join("storage", "roms", "randomized")
    GENERATION_TIMEOUT = 30 # seconds

    class GenerationError < StandardError; end

    def initialize(session)
      @session = session
    end

    # Returns true on success, false on handled failure.
    # Mutates @session: status, rom_path, error_message.
    def call
      # 1. Preconditions (java, base rom, jar, settings) — set status=failed and return false
      # 2. Mark session generating
      # 3. Build output path: OUTPUT_DIR/run_<run_id>/session_<id>.nds (mkdir_p the dir)
      # 4. Open3.capture3 with timeout — pass jar path, base rom, output, settings, seed
      # 5. On exit_status.success?: set rom_path (relative to Rails.root), status=ready, save!
      # 6. On non-zero exit / Timeout::Error: set status=failed, error_message=stderr or timeout msg, save!
    end

    private

    def java_available?
      system("command -v java > /dev/null 2>&1")
    end

    # Other privates as needed: precondition_error, build_command, run_with_timeout
  end
end
```

**Behavior contract:**

- `call` is **synchronous** — runs in the current process for the configured timeout.
- Pre-condition check returns false WITHOUT raising. Sets `session.status = "failed"` and `session.error_message = "<friendly reason>"`.
- Successful generation sets `session.rom_path` to a path **relative to Rails.root** (e.g., `"storage/roms/randomized/run_5/session_42.nds"`) so `SoulLinkEmulatorSession#rom_full_path` resolves correctly.
- On timeout, kill the subprocess if possible, mark session failed with `"Generation timed out after #{GENERATION_TIMEOUT}s"`.
- On non-zero exit, store a truncated `stderr` (max 500 chars) in `error_message`.
- The service NEVER raises in normal failure paths; it returns `false`. It MAY raise `GenerationError` if the session record itself can't be saved (DB error) — that's a real bug.

**Command shape** (verify with the JAR's CLI; if Bob's first run fails because of CLI flag mismatch, escalate to Architect — do not invent flags):
```
java -jar <JAR_PATH> -i <BASE_ROM_PATH> -o <OUTPUT_PATH> -s <SETTINGS_PATH> -seed <session.seed>
```

### Job: `app/jobs/soul_link/generate_run_roms_job.rb`

```ruby
module SoulLink
  class GenerateRunRomsJob < ApplicationJob
    queue_as :default

    SESSIONS_PER_RUN = 4

    def perform(soul_link_run)
      # 1. Idempotency: if SESSIONS_PER_RUN sessions already exist for this run, return early.
      # 2. Inside a transaction, create the 4 sessions with random seeds and status: "pending".
      # 3. Outside the transaction, iterate sessions, call SoulLink::RomRandomizer.new(session).call.
      #    Continue on individual failures — each session carries its own status/error.
    end

    private

    def random_seed
      SecureRandom.random_number(2**63).to_s
    end
  end
end
```

**Contract:**

- Idempotent on count: if 4 sessions exist (any status), return without doing anything.
- Session creation in a transaction; ROM generation outside the transaction (DB locks shouldn't span subprocesses).
- Failures of individual ROMs do NOT stop generation of the others — each session reflects its own outcome.
- Seed format: positive 63-bit integer as a String (fits Java `long`, avoids signed-overflow surprises).

### Tests — `test/services/soul_link/rom_randomizer_test.rb`

Use FactoryBot (new convention from Step 1). Stub `Open3.capture3` and `system` to keep tests hermetic — no real Java invocation, no real file writes to repo paths.

Cover:

- **Java missing** — `system("command -v java ...")` → false. `call` returns false; session.status == "failed"; error_message mentions Java.
- **Base ROM missing** — stub `File.exist?(BASE_ROM_PATH)` to false. Same shape.
- **JAR missing** — same shape.
- **Settings missing** — same shape.
- **Successful generation** — stub `Open3.capture3` to return `["stdout", "", success_exit_status]`. Session ends up with status="ready", rom_path set to the expected relative path, error_message nil. Verify the output directory was created (or that `mkdir_p` was called — your call which is more reliable to assert).
- **Non-zero exit** — stub returns `["", "boom: bad rom", failure_exit_status]`. Session.status="failed"; error_message includes the truncated stderr.
- **Timeout** — simulate by stubbing `Open3.capture3` to raise `Timeout::Error` (or use `Timeout.timeout` block stub). Session.status="failed"; error_message mentions timeout.
- **Status transitions** — assert session was `generating` mid-call (use a partial stub if practical, otherwise verify via the final state and skip the mid-state check).
- **Path is relative to Rails.root** — assert `rom_path` does NOT start with a slash and starts with `storage/`.

### Tests — `test/jobs/soul_link/generate_run_roms_job_test.rb`

- Inherit from `ActiveJob::TestCase`. Use `perform_enqueued_jobs` or just `.perform_now` for direct execution.
- **Creates 4 sessions** — given a run with no sessions, perform_now → 4 SoulLinkEmulatorSession rows exist for that run. All have unique seeds. All have `discord_user_id: nil` (unclaimed).
- **Idempotency** — given a run that already has 4 sessions, perform_now is a no-op. No new rows, no service calls.
- **Calls randomizer for each session** — stub `SoulLink::RomRandomizer#call` to return true; assert it was called 4 times.
- **Continues on individual failure** — stub randomizer to fail on the second call only; remaining 3 still proceed; the run ends up with 3 ready + 1 failed.

### Build Order

1. Create the directory placeholders: `mkdir -p storage/roms/base storage/roms/randomized lib/randomizer && touch storage/roms/base/.keep storage/roms/randomized/.keep lib/randomizer/.keep`
2. Update `.gitignore`.
3. Create the service file.
4. Create the service test, run it: `mise exec -- ruby -S bundle exec rails test test/services/soul_link/rom_randomizer_test.rb`. Iterate until green.
5. Create the job file.
6. Create the job test, run it: `mise exec -- ruby -S bundle exec rails test test/jobs/soul_link/generate_run_roms_job_test.rb`. Iterate.
7. Run full suite: `mise exec -- ruby -S bundle exec rails test`. Confirm 116 + new tests, 0 failures.

### Flags

- Flag: **No real Java invocation in tests.** All `Open3.capture3` and `system("command -v java ...")` calls must be stubbed. CI does not have Java.
- Flag: **No real ROM file writes in tests.** Stub `FileUtils.mkdir_p` if needed, or use `Dir.mktmpdir` for the rare test that genuinely needs a directory.
- Flag: **rom_path is relative to Rails.root**, not absolute. The model's `rom_full_path` resolves it.
- Flag: **Use FactoryBot** for all test data (`create(:soul_link_run)`, `create(:soul_link_emulator_session, :pending, soul_link_run: run)`, etc). Add traits to the factory file only if a state isn't already buildable.
- Flag: **Discord IDs are bigint** in the DB — but this step doesn't touch them directly. Just don't accidentally introduce String anywhere.
- Flag: **Service is sync. Job is async via Rails 8 :async adapter.** Don't add SolidQueue config — it's deliberately not in use.
- Flag: **Defensive Java check** (`command -v java`) is required so the app surfaces a friendly error if the VPS ever loses Java. The check is on every `call`, not memoized — server state can change.
- Flag: **No controllers, routes, views, or button additions in this step.** Step 4 wires the trigger.
- Flag: **If the CLI flags for the randomizer JAR are not exactly `-i / -o / -s / -seed`**, do NOT guess — escalate to the Architect via REVIEW-REQUEST with the actual CLI help output. The brief assumes those flags from the original plan; if the JAR uses different ones, that's a real correction.
- Flag: All Rails commands prefixed `mise exec -- ruby -S bundle exec`.
- Flag: Do NOT commit. Architect commits.

### Definition of Done

- [ ] `app/services/soul_link/rom_randomizer.rb` exists and matches contract above
- [ ] `app/jobs/soul_link/generate_run_roms_job.rb` exists and matches contract above
- [ ] Service tests cover all listed scenarios; all green
- [ ] Job tests cover all listed scenarios; all green
- [ ] Full suite passes (116 + new tests, 0 failures)
- [ ] `.gitignore` updated; `.keep` files committed
- [ ] No real Java or filesystem writes in tests
- [ ] All test data via FactoryBot — no fixture references in new tests

---

## Builder Plan
*Builder adds their plan here before building. Architect reviews and approves.*

1. Drop `.keep` files into `storage/roms/{base,randomized}` and `lib/randomizer`, then extend `.gitignore` so the dirs stay tracked but contents (jar, .nds) are ignored.
2. Build `SoulLink::RomRandomizer`: precondition checks (java, base ROM, jar, settings) → `status=failed` and friendly `error_message`; on green, mkdir output dir, set `generating`, save mid-flight, run `Open3.capture3` under `Timeout.timeout(GENERATION_TIMEOUT)`; success persists relative `rom_path` + `status=ready`; non-zero exit truncates stderr to 500 chars; `Timeout::Error` (rescued in service) marks failed.
3. Service test scaffolding: stub `system("command -v java …")` via `Kernel.stub`, stub `File.exist?` only for the four guarded paths (default-through to original for everything else), stub `FileUtils.mkdir_p` to a no-op, stub `Open3.capture3` per scenario including a `Timeout::Error` raise. Cover all 9 listed scenarios; assert `rom_path` is relative.
4. Build `SoulLink::GenerateRunRomsJob`: idempotency early-return on count == 4, transactional creation of 4 `pending` sessions with unique 63-bit string seeds, then iterate outside the txn calling `RomRandomizer#call` per session — failures don't halt the loop.
5. Job test: stub `RomRandomizer#call` (via `any_instance` or `stub_any_instance`) to count invocations and selectively fail one; assert 4 sessions, idempotent re-run, partial-failure tolerance. Run focused suite, then full suite, then write REVIEW-REQUEST.md.
