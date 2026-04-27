# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 7 — Cleanup + Polish (Final Step)

Context: Steps 1–6 ship a working in-browser emulator with cheats. This is the final step of the feature. Three pieces, all small:

1. **ROM cleanup rake task** — frees disk by removing ROM files (and save_data) for inactive runs.
2. **Deployment doc update** — captures all the manual setup the run-creator needs on the VPS.
3. **Failed-state regeneration UX** — destructive "Regenerate ROMs" channel action + button shown only when emulator_status is `:failed`.

After this step, all 7 emulator-feature steps are done.

### Files to Create

- `lib/tasks/emulator_cleanup.rake`
- `test/lib/tasks/emulator_cleanup_test.rb` (rake task test — see project pattern; if no test/lib/tasks/ dir exists, create it)

### Files to Modify

- `app/models/soul_link_emulator_session.rb` — add `after_destroy :delete_rom_file` callback that deletes the on-disk file (rescues Errno::ENOENT)
- `app/channels/run_channel.rb` — add `regenerate_emulator_roms` action mirroring the existing `generate_emulator_roms` shape, with explicit `:failed`-state guard + destroy_all + re-enqueue
- `app/javascript/controllers/run_management_controller.js` — add `regenerateRomsButton` target + `regenerateEmulatorRoms()` method (with `confirm()` dialog) + visibility toggle (`:failed` only)
- `app/views/runs/index.html.erb` — add second sibling button "Regenerate ROMs" right next to "Generate Emulator ROMs"; initial visibility hidden unless `emulator_status == :failed`
- `.claude/documents/deployment.md` — append "In-Browser Emulator" subsection with prerequisites
- `test/channels/run_channel_test.rb` — extend with regenerate tests
- `test/models/soul_link_emulator_session_test.rb` — extend with `after_destroy` callback test

### ROM Cleanup Rake Task

```ruby
# lib/tasks/emulator_cleanup.rake
namespace :soul_link do
  desc "Delete ROM files and save data for inactive runs"
  task cleanup_roms: :environment do
    deleted_files = 0
    cleared_saves = 0
    inactive_runs = SoulLinkRun.inactive
    inactive_runs.find_each do |run|
      run.soul_link_emulator_sessions.find_each do |session|
        if session.rom_full_path&.exist?
          session.rom_full_path.delete
          deleted_files += 1
        end
        cleared_saves += 1 if session.save_data.present?
        session.update_columns(rom_path: nil, save_data: nil)
      end
      # Try to remove the now-empty run dir.
      run_dir = Rails.root.join("storage", "roms", "randomized", "run_#{run.id}")
      run_dir.rmdir if run_dir.exist? && run_dir.children.empty?
    end
    puts "Cleaned #{deleted_files} ROM file(s) and #{cleared_saves} save(s) from #{inactive_runs.count} inactive run(s)."
  end
end
```

Notes:
- Uses `update_columns` to skip validations + callbacks (we want the file delete to be explicit, not via after_destroy).
- Sessions are kept as history rows (seed, status, error_message preserved) — only the heavy data (file + save_data) is removed.
- Active runs are untouched.
- Empty run dirs are cleaned up; non-empty dirs (shouldn't happen but defensive) are left alone.

### `SoulLinkEmulatorSession#delete_rom_file` Callback

```ruby
after_destroy :delete_rom_file

private

def delete_rom_file
  rom_full_path&.delete if rom_full_path&.exist?
rescue Errno::ENOENT
  # Already gone — nothing to do.
end
```

Triggered on `session.destroy` (used in the regenerate flow below). Defensive against double-deletion.

### `RunChannel#regenerate_emulator_roms` Spec

```ruby
def regenerate_emulator_roms(_data)
  run = SoulLinkRun.current(@guild_id)
  return transmit({ error: "No active run" }) if run.nil?
  return broadcast_state if run.emulator_status != :failed  # guard: only valid in failed state

  run.soul_link_emulator_sessions.destroy_all  # cascades after_destroy file cleanup
  SoulLink::GenerateRunRomsJob.perform_later(run)
  broadcast_state
end
```

**Behavioral note:** `destroy_all` is destructive. It deletes:
- All session rows (failed AND ready AND claimed)
- All ROM files on disk (via `after_destroy` callback)
- All save_data blobs (column on the destroyed row)

Players who claimed a successfully-generated ROM in a partial-failure scenario lose their progress. This is an acceptable v1 tradeoff — most failures will be all-or-nothing, and the user-facing button only appears when status is `:failed`. Carry as Known Gap: "regenerate is destructive — partial-failure with one or two ready sessions still wipes everyone's progress."

### Stimulus Update

Add to `run_management_controller.js`:

```js
static targets = [/* existing */, "regenerateRomsButton"]

regenerateEmulatorRoms() {
  if (!confirm("Regenerate ROMs? This will destroy all current ROMs and any progress players have made.")) return
  this.subscription.perform("regenerate_emulator_roms")
}
```

In the existing `render()` (or whatever broadcast handler exists), toggle `regenerateRomsButtonTarget` visibility:
- `data.emulator_status === "failed"` → show
- otherwise → hide

The existing `generateRomsButton` toggle stays as-is (`"none"` / `"failed"` shows it). After this step we'll have BOTH buttons visible in the `:failed` state — the user picks "Generate" to retry without destroying, or "Regenerate" to nuke + retry. Wait — `generate` no-ops in `:failed` state per Step 4's idempotency guard, so the buttons aren't equivalent. Adjust the Step 4 button: in `:failed`, hide the original "Generate Emulator ROMs" button and show only "Regenerate ROMs". So:
- `:none` → only "Generate Emulator ROMs" visible
- `:generating` / `:ready` → neither visible
- `:failed` → only "Regenerate ROMs" visible

Update the toggle logic for both buttons accordingly.

### View Update

Add the new button next to the existing one:

```erb
<button data-action="click->run-management#regenerateEmulatorRoms"
        data-run-management-target="regenerateRomsButton"
        class="gb-btn-primary gb-btn-sm <%= 'hidden' if @current_run&.emulator_status != :failed %>">
  Regenerate ROMs
</button>
```

Also update the existing "Generate Emulator ROMs" button visibility to `emulator_status != :none` (currently it shows on `:none` AND `:failed`; now restrict to `:none` only).

### Deployment Doc Update

Append to `.claude/documents/deployment.md`:

```markdown
## In-Browser Emulator

The emulator feature requires manual setup beyond the standard Rails deploy.

### One-time VPS prerequisites

1. **Java Runtime (JRE 8+):**
   ```bash
   sudo apt install -y openjdk-21-jre-headless
   java -version  # should print 21.x or newer
   ```

2. **Pokemon Platinum base ROM:**
   Place the .nds file at `storage/roms/base/platinum.nds` (gitignored).
   The randomizer reads from this and produces 4 differently-seeded outputs per run.

3. **Universal Pokemon Randomizer JAR:**
   Place the .jar at `lib/randomizer/randomizer.jar` (gitignored).
   Source: https://github.com/Ajarmar/universal-pokemon-randomizer-zx

4. **Randomizer settings file:**
   Export your settings from the randomizer GUI as a `.rnqs` file and place at
   `config/soul_link/randomizer_settings.rnqs`.

5. **EmulatorJS assets:**
   ```bash
   bin/rails emulatorjs:install
   ```
   Downloads the latest EmulatorJS release into `public/emulatorjs/` (gitignored).
   Re-run after each deploy that wipes `public/`, or pin a version with
   `VERSION=v4.2.3 bin/rails emulatorjs:install`.

### Periodic maintenance

Free disk by purging ROMs + save data for inactive (ended) runs:

```bash
bin/rails soul_link:cleanup_roms
```

Safe to run any time; only affects runs where `active = false`.

### Cheats

Action Replay codes live in `config/soul_link/cheats.yml`. Edit to add codes,
restart the app to pick up changes (cheats are memoized at boot).
```

If `.claude/documents/deployment.md` doesn't exist, create it with just this section. If it does exist, append the section at the bottom (preserve existing content).

### Tests

#### `test/lib/tasks/emulator_cleanup_test.rb`

Use FactoryBot. Cover:

- **Active run untouched** — given an active run with sessions having rom_path set, run task; rom_path still set, files (stubbed via Tempfile) still present.
- **Inactive run cleaned** — given an inactive run with sessions, run task; rom_path nil, save_data nil, files deleted.
- **Inactive run with missing file** — rom_path set but file already gone; task doesn't error; rom_path cleared.
- **Empty run dir removed** — after cleanup, the `run_<id>/` directory is removed (assert `Dir.exist?` returns false). Use a Tempfile-backed setup so we don't touch real `storage/roms/`.

To run a rake task in tests:
```ruby
require "rake"
Rails.application.load_tasks
# ...
Rake::Task["soul_link:cleanup_roms"].reenable
Rake::Task["soul_link:cleanup_roms"].invoke
```

#### `test/channels/run_channel_test.rb` extension

- `regenerate_emulator_roms destroys sessions and re-enqueues when status is :failed`
- `regenerate_emulator_roms is no-op when status is not :failed` (test :none, :generating, :ready)
- `regenerate_emulator_roms transmits error when no active run`
- `regenerate cascades after_destroy` — set rom_path to a Tempfile path that exists, regenerate, assert file is gone

#### `test/models/soul_link_emulator_session_test.rb` extension

- `after_destroy deletes rom file` — create session with rom_path → existing Tempfile, destroy session, assert file is gone.
- `after_destroy is safe when file is missing` — rom_path set but no file, destroy doesn't raise.
- `after_destroy is safe when rom_path is nil`.

### Build Order

1. Add `after_destroy :delete_rom_file` to model.
2. Create rake task.
3. Add `RunChannel#regenerate_emulator_roms` action.
4. Update Stimulus: new target, new method, fix existing button visibility, add new button visibility.
5. Update view: new "Regenerate ROMs" button + adjusted visibility on existing button.
6. Update `.claude/documents/deployment.md`.
7. Write tests for: model callback, rake task, channel action.
8. Run targeted tests, iterate.
9. Run full suite: `mise exec -- ruby -S bundle exec rails test`. Confirm 184 + new tests, 0 failures.

### Flags

- Flag: **Regenerate is destructive** — destroys claimed sessions, ready ROMs, and save data. Acceptable v1 tradeoff. Add a Known Gap entry: "Partial-failure regenerate wipes other players' saved progress; future iteration should preserve `:ready` sessions."
- Flag: **Use `update_columns` in the cleanup rake task** — skip validations + callbacks (especially `after_destroy`, which we don't want to fire here since we manually delete the file).
- Flag: **`destroy_all` cascades the `after_destroy` callback** — that's how we clean up files in regenerate. Confirm this is the intended path (not `delete_all` which skips callbacks).
- Flag: **Two buttons in the runs page now** — `Generate Emulator ROMs` (`:none` only) and `Regenerate ROMs` (`:failed` only). They are mutually exclusive. Update the existing button's visibility to match.
- Flag: **No `mise exec` for `bin/rails`** in deployment.md — the docs assume the VPS uses system Ruby (or whatever is set up). Locally, all test commands still use `mise exec --`.
- Flag: **Use FactoryBot.**
- Flag: **No real `storage/roms/` writes in tests** — use `Tempfile` or `Dir.mktmpdir`. Stub `Rails.root.join` paths if cleaner.
- Flag: **`.claude/documents/deployment.md`** — append to existing if present, create if not. Don't overwrite other docs in that directory.
- Flag: All Rails commands (locally) prefixed `mise exec -- ruby -S bundle exec`.
- Flag: Do NOT commit. Architect commits.

### Definition of Done

- [ ] `SoulLinkEmulatorSession#delete_rom_file` `after_destroy` callback deletes on-disk file, safe against missing files
- [ ] `lib/tasks/emulator_cleanup.rake` exists, deletes inactive run files + save_data, leaves active runs alone
- [ ] `RunChannel#regenerate_emulator_roms` destroys sessions + re-enqueues only on `:failed` state, broadcasts state
- [ ] Stimulus has `regenerateRomsButton` target + `regenerateEmulatorRoms()` method (with confirm) + visibility toggle for both buttons
- [ ] View has "Regenerate ROMs" sibling button; existing "Generate" button restricted to `:none` only
- [ ] `.claude/documents/deployment.md` has "In-Browser Emulator" subsection with all prerequisites + cleanup task + cheats
- [ ] Rake task tests cover: active untouched, inactive cleaned, missing file safe, empty dir removed
- [ ] Channel tests cover: regenerate happy path, no-op on non-failed states, error on no active run, cascades file delete
- [ ] Model tests cover: after_destroy file delete, missing file safe, nil path safe
- [ ] Full suite: 184 baseline + new tests, 0 failures

---

## Builder Plan
*Builder adds their plan here before building. Architect reviews and approves.*

1. Add `after_destroy :delete_rom_file` to `SoulLinkEmulatorSession` (rescues `Errno::ENOENT`); create `lib/tasks/emulator_cleanup.rake` per spec; create `test/lib/tasks/` directory.
2. Extend `RunChannel#regenerate_emulator_roms` with `:failed`-only guard, `destroy_all` cascade, and re-enqueue of `GenerateRunRomsJob`; mirror error handling style of existing actions.
3. Stimulus: add `regenerateRomsButton` target + `regenerateEmulatorRoms()` (with `confirm()`); change existing button toggle to show only on `:none`; add new toggle to show new button only on `:failed`.
4. View: add sibling "Regenerate ROMs" button next to existing button; tighten existing button visibility to `emulator_status == :none`.
5. Append "In-Browser Emulator" section to existing `.claude/documents/deployment.md` (preserve existing content); write tests using FactoryBot + `Tempfile`/`Dir.mktmpdir` (no real `storage/roms/` writes); run targeted then full suite via `mise exec -- ruby -S bundle exec rails test`.

## Resume Plan (post-abandonment, tests + docs only)

Verified the 5 production-code files match the brief verbatim — no rewrites. Three remaining gaps:

1. **`test/models/soul_link_emulator_session_test.rb` — extend** with three `after_destroy` cases:
   - file present at `rom_path` → destroy → file gone
   - file missing at `rom_path` → destroy → no raise (covers `Errno::ENOENT` and the `exist?` short-circuit)
   - `rom_path` nil → destroy → no raise
   Use `Tempfile.create` for the on-disk path; copy the path into the session's `rom_path` as a relative-to-`Rails.root` string (the model joins with `Rails.root`, so we'll seed Tempfile under `Rails.root.join("tmp")` and store the relative segment).

2. **`test/channels/run_channel_test.rb` — extend** with four `regenerate_emulator_roms` cases:
   - happy path: status `:failed` → `destroy_all` cascades + `GenerateRunRomsJob` enqueued + 1 broadcast.
   - no-op when status is `:none`, `:generating`, or `:ready` (one test each, three subtests in one `test` block via inner setup is messier — use three separate `test` blocks for readability).
   - error transmit when no active run.
   - cascade: tempfile-backed `rom_path`, regenerate, file gone (integration of channel + model callback).

3. **`test/lib/tasks/emulator_cleanup_test.rb` — new file**, with four cases:
   - active run untouched: rom_path + tempfile remain after task.
   - inactive run cleaned: rom_path nil, save_data nil, file gone.
   - inactive run with missing file: no raise; rom_path nil.
   - empty `run_<id>/` dir removed via tempdir-rooted setup. Stub `Rails.root` (or use a `Pathname` indirection) so we don't write to real `storage/roms/`. Cleanest: use `Dir.mktmpdir` + stub `Rails.root` to that tmp path for the duration of the test.
   Load tasks at top of test file: `require "rake"; Rails.application.load_tasks`. Per-test: `Rake::Task["soul_link:cleanup_roms"].reenable; Rake::Task["soul_link:cleanup_roms"].invoke`. Capture stdout to silence the `puts`.

4. Append "In-Browser Emulator" subsection to existing `.claude/documents/deployment.md` (preserve existing content).

5. Run targeted (`test/models/soul_link_emulator_session_test.rb`, `test/channels/run_channel_test.rb`, `test/lib/tasks/emulator_cleanup_test.rb`), then full suite (expect 184 + 11 = 195 runs, 0 failures).

6. Overwrite `handoff/REVIEW-REQUEST.md` with fresh Step 7 content (file table, test counts, DoD, deployment.md summary). Stop. Architect commits.
