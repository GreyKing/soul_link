# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 2 — Emulator Polish (deployment doc + N+1 fix + status label)

Context: emulator feature (Steps 1–7 of an earlier session) shipped via commits `574fa7f`–`c33c8b8` plus the test-flake fix `c36ce69`. Three small follow-ups to close it out cleanly. After this lands, only manual browser verification remains (Project Owner's job).

Three independent pieces in one step. No tight coupling between them — each touches different files.

### Files to Create

- `.claude/documents/deployment.md` (or extend if it already exists; check first — preserve existing content)

### Files to Modify

- `app/channels/run_channel.rb` — N+1 fix: eager-load `:soul_link_emulator_sessions` on past runs in `broadcast_run_state`
- `app/views/runs/index.html.erb` — add a `generateRomsStatus` target element ("ROMs generating…") next to the existing buttons
- `app/javascript/controllers/run_management_controller.js` — toggle the new target's visibility in the existing `render()` based on `emulator_status === "generating"`
- `test/channels/run_channel_test.rb` — extend with N+1 assertion (likely `assert_no_queries` after eager-load)

---

### A. Deployment doc — `.claude/documents/deployment.md`

**First check** if the file exists. If it does, append the section below; do NOT overwrite existing content. If not, create with just this content.

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
   Source: <https://github.com/Ajarmar/universal-pokemon-randomizer-zx>

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

The deployment doc uses `bin/rails ...` (no `mise exec`) because the VPS runs system Ruby, not mise. Don't change that.

---

### B. N+1 fix in `RunChannel.broadcast_run_state`

**The problem:** the broadcast includes past runs (up to 20). Each past run's `broadcast_state` calls `emulator_status`, which queries `soul_link_emulator_sessions` for that run. ~20 extra SELECTs per broadcast.

**The fix:** read `RunChannel.broadcast_run_state` and add `.includes(:soul_link_emulator_sessions)` to the past_runs query (and the current_run query too, even though it's a single record — consistency).

```ruby
# Inside RunChannel.broadcast_run_state — find this line or similar:
past_runs = SoulLinkRun.history(guild_id).limit(20)
# Change to:
past_runs = SoulLinkRun.history(guild_id).includes(:soul_link_emulator_sessions).limit(20)
```

If `current_run` is also fetched via `SoulLinkRun.current(guild_id)` (which uses `.first`, not includes), apply `.includes(:soul_link_emulator_sessions)` there too. Read the actual implementation; I'm describing intent.

**Test:** add a test to `test/channels/run_channel_test.rb` that:
1. Sets up an active run + several past runs (5 is enough for an N+1 to be visible)
2. Each past run has at least one emulator session
3. Calls `RunChannel.broadcast_run_state(guild_id)`
4. Asserts no per-row session SELECTs fire after eager-load

The cleanest assertion shape (Rails 7.2+):
```ruby
test "broadcast_run_state does not N+1 over past runs' emulator_status" do
  # ... setup with multiple past runs each having sessions ...
  expected_query_count = 8  # measure once, hard-code; should be small + constant
  assert_queries_count(expected_query_count) do
    RunChannel.broadcast_run_state(guild_id)
  end
end
```

If `assert_queries_count` isn't available, use the `ActiveSupport::Notifications` fallback:
```ruby
queries = []
callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
  RunChannel.broadcast_run_state(guild_id)
end
session_queries = queries.count { |q| q.include?("soul_link_emulator_sessions") }
# With eager-load, this should be 1 (the IN-clause batch), not N (one per past run).
assert_equal 1, session_queries, "N+1 detected: #{session_queries} session queries fired"
```

Prefer `assert_queries_count` if available.

---

### C. Inline "ROMs generating…" status label

**The problem:** when ROM generation is in flight, both buttons hide. The user has no feedback that anything is happening except the button vanishing.

**The fix:** show a small inline label "ROMs generating…" while `emulator_status === "generating"`. Hidden otherwise.

**View — `app/views/runs/index.html.erb`:**

Add the label as a sibling of the buttons (read the surrounding HTML to find the right container — look for the `gb-btn-primary` buttons added in Step 4 / Step 7):

```erb
<span data-run-management-target="generateRomsStatus"
      class="gb-status-text <%= 'hidden' if @current_run&.emulator_status != :generating %>">
  ROMs generating…
</span>
```

If there's no existing `gb-status-text` class, use whatever class the surrounding GB-aesthetic typography uses. Look for adjacent text labels — there might already be a small-text class. Don't invent a new one.

**Stimulus — `app/javascript/controllers/run_management_controller.js`:**

Add `generateRomsStatus` to `static targets`. In the existing `render()` (after the existing button toggles for `generateRomsButton` and `regenerateRomsButton`):

```js
if (this.hasGenerateRomsStatusTarget) {
  if (status === "generating") {
    this.generateRomsStatusTarget.classList.remove("hidden")
  } else {
    this.generateRomsStatusTarget.classList.add("hidden")
  }
}
```

**Test:** if there's an easy view-rendering test path, assert the label is present in the response with the right `.hidden` class for `:none`, `:generating`, `:ready`, `:failed` states. If view tests aren't easy to add, skip — the Stimulus toggle is small enough to verify by inspection. Don't gold-plate.

---

### Build Order

1. Read `app/channels/run_channel.rb` — confirm method names and current shape.
2. Read `app/views/runs/index.html.erb` — find the buttons + identify GB typography classes.
3. **A: Deployment doc.** Check if `.claude/documents/deployment.md` exists; create or append accordingly.
4. **B: N+1 fix.** Add `.includes(:soul_link_emulator_sessions)`. Write `assert_queries_count` test. Iterate.
5. **C: Status label.** View target + Stimulus toggle + (optional) rendering test.
6. Run targeted: `mise exec -- ruby -S bundle exec rails test test/channels/run_channel_test.rb`
7. Run full suite: `mise exec -- ruby -S bundle exec rails test`. Confirm 198 + new tests pass.
8. **Run full suite 3 more times** to confirm no new flakes (`c36ce69` fixed the previous one — should stay clean).

### Flags

- Flag: **All three pieces are independent.** If one stalls, ship the others. Note any holdouts in REVIEW-REQUEST.
- Flag: **Deployment doc uses `bin/rails`** (system Ruby on VPS). All local test commands use `mise exec -- ruby -S bundle exec`.
- Flag: **No new gems.** Use `assert_queries_count` if Rails version supports it (8.x does); otherwise the Notifications fallback.
- Flag: **Don't touch `setup_discord`, `generate_emulator_roms`, or `regenerate_emulator_roms` actions.** Stable.
- Flag: **Match existing GB-aesthetic typography.** No new CSS vars/classes unless the project already uses them.
- Flag: **Symbols vs strings:** server-rendered initial visibility uses Ruby symbols (`!= :generating`); JS broadcast comparison uses strings (`"generating"`). Match existing pattern.
- Flag: All Rails commands prefixed `mise exec -- ruby -S bundle exec`.
- Flag: Do NOT commit. Architect commits.

### Definition of Done

- [ ] `.claude/documents/deployment.md` has the "In-Browser Emulator" section (existing content preserved if file existed)
- [ ] `RunChannel.broadcast_run_state` eager-loads `soul_link_emulator_sessions`
- [ ] N+1 assertion test passes and would fail if eager-load is removed
- [ ] View has `generateRomsStatus` target with correct initial visibility based on `emulator_status`
- [ ] Stimulus toggles `generateRomsStatus` in `render()` based on `emulator_status === "generating"`
- [ ] Full suite passes: 198 baseline + new tests, 0 failures
- [ ] Suite passes 3+ consecutive parallel runs (no flakes)

---

## Builder Plan
*Builder adds their plan here before building. Architect reviews and approves.*

A. Append "In-Browser Emulator" section to existing `.claude/documents/deployment.md` (file exists, preserve all content).
B. Add `.includes(:soul_link_emulator_sessions)` to both `current_run` and `past_runs` queries in `RunChannel.broadcast_run_state` (and matching `build_state_payload` for consistency on initial subscribe). New test seeds 5 past runs each with sessions, then asserts only 1 `soul_link_emulator_sessions` query fires using `assert_queries_count` shape — measure baseline first to hard-code the count.
C. Add `generateRomsStatus` span next to existing buttons using same `gb-btn-sm` row container; reuse existing typography (no new `gb-status-text` class — use inline style matching adjacent small-text patterns at `font-size: 11px; color: var(--l1)`). Stimulus toggles via `status === "generating"` string comparison; ERB initial visibility uses `:generating` symbol. Extending existing `render()`, not adding parallel handler.
Rails 8.1.1 confirmed — `assert_queries_count` is supported. No new gems.
