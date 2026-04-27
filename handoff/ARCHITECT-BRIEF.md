# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 4 — Run-Creator ROM-Generation Trigger

Context: Steps 1–3 built the data layer, the randomizer service+job, and the EmulatorJS asset task. This step adds the **run-creator-facing** trigger on the runs page — a button that enqueues `SoulLink::GenerateRunRomsJob` for the current run. Player-facing emulator routes/controller/view come in Step 5.

**Pattern match:** Soul Link does run-level actions through `RunChannel` (ActionCable), not HTTP. Read `app/channels/run_channel.rb` and look at the existing `setup_discord` action — yours mirrors it exactly. The button on the runs page is just a Stimulus action that calls `subscription.perform("generate_emulator_roms")`. No HTTP route, no controller.

### Files to Modify

- `app/channels/run_channel.rb` — add `generate_emulator_roms` action (mirror `setup_discord` shape)
- `app/models/soul_link_run.rb` — add `emulator_status` method; extend `broadcast_state` to include the new field
- `app/jobs/soul_link/generate_run_roms_job.rb` — add a post-completion broadcast so the UI updates when ROMs are ready
- `app/javascript/controllers/run_management_controller.js` — add `generateEmulatorRoms()` method, add `generateRomsButton` target, update the broadcast-received handler to toggle the new button by `emulator_status`
- `app/views/runs/index.html.erb` — add the new button right next to "Setup Discord" (line 48-ish, inside the current-run panel)
- `test/channels/run_channel_test.rb` — extend with tests for `generate_emulator_roms`
- `test/models/soul_link_run_test.rb` — extend (or create if missing) with tests for `emulator_status`
- `test/jobs/soul_link/generate_run_roms_job_test.rb` — extend with an assertion that the post-completion broadcast fires

### `SoulLinkRun#emulator_status` Spec

Returns one of: `:none`, `:generating`, `:ready`, `:failed`.

```ruby
def emulator_status
  sessions = soul_link_emulator_sessions  # add has_many :soul_link_emulator_sessions association
  return :none if sessions.empty?
  return :failed if sessions.any? { |s| s.status == "failed" }
  return :generating if sessions.any? { |s| %w[pending generating].include?(s.status) }
  :ready
end
```

`:failed` takes priority over `:generating` so a partial failure is visible to the user. `:ready` requires ALL sessions to be ready.

**Required association:** `has_many :soul_link_emulator_sessions, dependent: :destroy` on `SoulLinkRun`. Verify the inverse `belongs_to :soul_link_run` on `SoulLinkEmulatorSession` (Step 1 added it — confirm).

### `SoulLinkRun#broadcast_state` Extension

Add to the returned hash:
```ruby
emulator_status: emulator_status
```

Don't change the existing fields. Don't add anything else this step doesn't need.

### `RunChannel#generate_emulator_roms` Spec

```ruby
def generate_emulator_roms(_data)
  run = SoulLinkRun.current(@guild_id)
  return broadcast_error("No active run") if run.nil?
  return broadcast_state if run.emulator_status != :none  # idempotent — silent no-op if already triggered

  SoulLink::GenerateRunRomsJob.perform_later(run)
  broadcast_state
end
```

**Idempotency:** if `emulator_status` is anything other than `:none`, do nothing (just re-broadcast state so the client sees current state). The job itself is also idempotent on count, but the channel layer should not even enqueue redundantly.

**Error handling:** `broadcast_error` (or whatever the existing pattern is — check `setup_discord`). Don't invent a new error mechanism.

### `GenerateRunRomsJob` — Post-Completion Broadcast

Add at the end of `perform` (and also on rescue if applicable):

```ruby
ensure
  RunChannel.broadcast_run_state(soul_link_run.guild_id) if soul_link_run.persisted?
end
```

Verify `RunChannel.broadcast_run_state` exists and accepts a guild_id (the explore confirmed this; Bob: read the file to confirm signature).

This means: after generation finishes (success, partial-failure, total failure), the UI gets a state broadcast and updates the button accordingly. Without this, the button stays in `:generating` state until the user refreshes.

### Stimulus: `run_management_controller.js`

Read the existing controller. Add:
1. New target: `generateRomsButton`.
2. New method: `generateEmulatorRoms()` — calls `this.subscription.perform("generate_emulator_roms")`. Match `setupDiscord()` shape.
3. In the `received(data)` callback (or wherever broadcast state is consumed), toggle `generateRomsButtonTarget` visibility based on `data.emulator_status`:
   - `:none` → button visible
   - `:generating` → button hidden, optionally show "ROMs generating..." text (small inline label)
   - `:ready` → button hidden, optionally show "✓ ROMs ready" (small inline label)
   - `:failed` → button visible (acts as retry — user can click again to retrigger). For now, no special "retry" UX — just same button, same text.

If the existing controller doesn't have a clear pattern for inline status text, just toggle the button visibility for now and skip the labels. Don't invent UI patterns the project doesn't already have.

### View: `app/views/runs/index.html.erb`

Insert the button next to "Setup Discord" in the current-run panel. The existing button shape is:

```erb
<button data-action="click->run-management#setupDiscord"
        data-run-management-target="setupDiscordButton"
        class="gb-btn-primary gb-btn-sm <%= 'hidden' if @current_run&.discord_channels_configured? %>">
  Setup Discord
</button>
```

Add a sibling:
```erb
<button data-action="click->run-management#generateEmulatorRoms"
        data-run-management-target="generateRomsButton"
        class="gb-btn-primary gb-btn-sm <%= 'hidden' if @current_run&.emulator_status != :none %>">
  Generate Emulator ROMs
</button>
```

Server-side initial visibility uses `emulator_status != :none` to hide. The Stimulus controller takes over after the first broadcast.

### Tests

#### `test/channels/run_channel_test.rb` — extend (or create if absent)

Use FactoryBot.

- `subscribes and streams for guild`
- `generate_emulator_roms enqueues GenerateRunRomsJob and broadcasts state` — given a run with no sessions, perform the action; assert the job is enqueued for `run`, assert state is broadcast
- `generate_emulator_roms is no-op when sessions already exist` — given a run with 4 sessions, perform; assert NO job enqueued, but state IS broadcast (so the client gets current truth)
- `generate_emulator_roms broadcasts error if no active run` — guild has no active run; perform; no job enqueued; error broadcast (whatever the existing `broadcast_error` pattern is)

Use `assert_enqueued_with(job: SoulLink::GenerateRunRomsJob, args: [run])` and ActionCable test helpers (`stub_connection(current_user_id: ...)` then `subscribe(...)` then `perform(...)`). Look at `test/channels/gym_draft_channel_test.rb` for the pattern.

#### `test/models/soul_link_run_test.rb`

- Cover `emulator_status` returning each of `:none`, `:generating`, `:ready`, `:failed` with appropriate session combinations
- `broadcast_state` includes `emulator_status` key

If `test/models/soul_link_run_test.rb` doesn't exist yet, create it with just these tests. Don't backfill other coverage.

#### `test/jobs/soul_link/generate_run_roms_job_test.rb` — extend

Add:
- `broadcasts run state on completion` — stub randomizer, call `perform_now`, assert `RunChannel.broadcast_run_state` was called once with the run's guild_id

Keep existing tests intact.

### Build Order

1. Add `has_many :soul_link_emulator_sessions, dependent: :destroy` to `SoulLinkRun`. Verify inverse on `SoulLinkEmulatorSession`.
2. Add `emulator_status` method to `SoulLinkRun`.
3. Extend `broadcast_state` with the new field.
4. Add `generate_emulator_roms` action to `RunChannel`. Match the `setup_discord` shape exactly — same error patterns, same broadcast pattern.
5. Add post-completion broadcast to `GenerateRunRomsJob#perform`.
6. Update `run_management_controller.js` — new target, new method, broadcast handler.
7. Update `app/views/runs/index.html.erb` — new button next to Setup Discord.
8. Tests (channel + model + job extensions).
9. Run targeted test files. Iterate.
10. `mise exec -- ruby -S bundle exec rails test` — full suite. 131 + new tests, 0 failures.
11. **Manual smoke test:** start dev server (`bin/dev`) in another terminal, log in, click "Generate Emulator ROMs", confirm: button hides, sessions are created in DB, button stays hidden after refresh while job runs, button reappears (or stays hidden if ready) once broadcast comes through. Report observed behavior in REVIEW-REQUEST.

### Flags

- Flag: **No HTTP route or controller** — this is pure ActionCable. Match the `setup_discord` pattern exactly. If you find yourself adding a route, you've drifted.
- Flag: **Idempotency at the channel layer** — don't re-enqueue if sessions already exist. The job is also idempotent (Step 2 contract), but defense in depth is cheap here.
- Flag: **Use FactoryBot** for all test data.
- Flag: **`emulator_status` is a method on the model**, not a column. No migration.
- Flag: **`has_many` association is required** before `emulator_status` works. Add it first.
- Flag: **Do NOT touch `setup_discord`** — it works, leave it alone. You're adding a sibling, not refactoring.
- Flag: **Do NOT add the player-facing emulator route, controller, or view.** That's Step 5.
- Flag: **Do NOT add a "retry" or "regenerate" UI for `:failed` status.** For now, the same button serves as both initial and retry. Refining the failed-state UX is Step 7.
- Flag: **`run_management_controller.js` may have an existing broadcast handler.** Read it carefully — don't introduce a parallel handler. Extend the existing one.
- Flag: **The Stimulus button-toggle logic must match what the broadcast carries.** If `emulator_status` is sent as a String from the channel (Ruby symbols become Strings over the wire in JSON), compare against `"none"` / `"ready"` / etc, not Symbols.
- Flag: All Rails commands prefixed `mise exec -- ruby -S bundle exec`.
- Flag: Do NOT commit. Architect commits.

### Definition of Done

- [ ] `SoulLinkRun has_many :soul_link_emulator_sessions, dependent: :destroy`
- [ ] `SoulLinkRun#emulator_status` returns the right symbol for each session combination
- [ ] `SoulLinkRun#broadcast_state` includes `emulator_status`
- [ ] `RunChannel#generate_emulator_roms` enqueues the job, idempotent, broadcasts state
- [ ] `GenerateRunRomsJob` broadcasts `RunChannel.broadcast_run_state(guild_id)` after `perform`
- [ ] Stimulus controller has `generateEmulatorRoms()` method + `generateRomsButton` target + broadcast-driven visibility toggle
- [ ] View has the new button next to Setup Discord, with correct initial visibility based on `emulator_status`
- [ ] Channel tests cover: enqueue happy path, idempotent no-op, no-active-run error
- [ ] Model tests cover: each `emulator_status` outcome + broadcast_state inclusion
- [ ] Job test asserts post-completion broadcast
- [ ] Full suite: previous 131 tests + new tests, all passing
- [ ] Manual smoke test reported in REVIEW-REQUEST: button visibility transitions through `:none` → `:generating` → `:ready` (with stubbed/successful job)

---

## Builder Plan
*Builder adds their plan here before building. Architect reviews and approves.*

1. Model: add `has_many :soul_link_emulator_sessions, dependent: :destroy` + `emulator_status` method to `SoulLinkRun`; add `emulator_status: emulator_status` to `broadcast_state`. Inverse `belongs_to :soul_link_run` already present on `SoulLinkEmulatorSession`.
2. Channel: append `generate_emulator_roms(_data)` to `RunChannel` mirroring `setup_discord` shape (`transmit({ error: ... })` for nil run; idempotent `broadcast_state` if status != `:none`; else `GenerateRunRomsJob.perform_later(run)` then `broadcast_state`). Existing `RunChannel.broadcast_run_state(guild_id)` already used by `broadcast_state` private method — reuse it from the job.
3. Job: wrap `perform` body in `ensure` that calls `RunChannel.broadcast_run_state(soul_link_run.guild_id) if soul_link_run.persisted?`.
4. Stimulus: add `generateRomsButton` target + `generateEmulatorRoms()` calling `subscription.perform("generate_emulator_roms")`; in `render()` toggle `generateRomsButtonTarget.classList` based on `current_run.emulator_status === "none"` (visible) vs anything else (hidden). Skip inline status text — controller has no existing inline-text pattern.
5. View: add sibling button next to Setup Discord with `'hidden' if @current_run&.emulator_status != :none`. Tests: `test/channels/run_channel_test.rb` (new), `test/models/soul_link_run_test.rb` (new), `test/jobs/soul_link/generate_run_roms_job_test.rb` (extend with broadcast assertion).

