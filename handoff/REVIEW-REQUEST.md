# Review Request — Step 4

**Ready for Review:** YES

## Summary

Step 4 adds the run-creator-facing trigger for ROM generation. The flow is pure ActionCable (no HTTP route, no controller): a new "Generate Emulator ROMs" button on the runs page calls `RunChannel#generate_emulator_roms`, which idempotently enqueues `SoulLink::GenerateRunRomsJob`. The job now broadcasts run state on completion (in an `ensure` block) so the UI reconciles without a refresh.

## Files Changed

### Production

| File | Lines | Change |
|------|-------|--------|
| `app/models/soul_link_run.rb` | 8, 47–58, 73 | Added `has_many :soul_link_emulator_sessions, dependent: :destroy`; added `#emulator_status` returning `:none` / `:generating` / `:ready` / `:failed` (failed-priority); added `emulator_status:` to `#broadcast_state`. |
| `app/channels/run_channel.rb` | 61–80 | New `generate_emulator_roms` action mirroring `setup_discord` shape — same `transmit({ error: ... })` pattern, idempotent no-op when status != `:none`, otherwise enqueues the job and broadcasts state. `setup_discord` left untouched. |
| `app/jobs/soul_link/generate_run_roms_job.rb` | 30–34 | Added `ensure` block calling `RunChannel.broadcast_run_state(soul_link_run.guild_id) if soul_link_run&.persisted?` — fires on success, partial failure, and hard crash. |
| `app/javascript/controllers/run_management_controller.js` | 9, 89–91, 124–134 | New `generateRomsButton` target; new `generateEmulatorRoms()` action; extended existing `render()` (no parallel handler) to toggle the button by `current_run.emulator_status` — visible on `"none"`/`"failed"`, hidden otherwise. String comparison only — no Ruby symbol leakage. |
| `app/views/runs/index.html.erb` | 53–57 | New sibling button next to "Setup Discord", initial visibility `'hidden' if @current_run&.emulator_status != :none` per brief. |

### Tests

| File | Lines | Change |
|------|-------|--------|
| `test/models/soul_link_run_test.rb` | 1–67 (new) | 8 new tests covering all four `#emulator_status` outcomes (incl. failed-over-generating priority + default-pending case) and two `#broadcast_state` inclusion tests. |
| `test/channels/run_channel_test.rb` | 1–62 (new) | 5 new tests — subscribes/streams, enqueues+broadcasts happy path, idempotent no-op (4 sessions exist), idempotent no-op (still generating), error transmission when no active run. Uses a separate `GUILD_ID` (888…) to avoid collision with the `active_run` fixture (999…). |
| `test/jobs/soul_link/generate_run_roms_job_test.rb` | 4, 117–134 | Added `include ActionCable::TestHelper` and 2 new tests: broadcast fires on completion (success path) and broadcast fires even when the randomizer raises. |

## Test Results

```
mise exec -- ruby -S bundle exec rails test
146 runs, 437 assertions, 0 failures, 0 errors, 0 skips
```

Baseline 131 + 15 new = 146. Targeted run on the three changed test files: 20 runs, 67 assertions, 0 failures.

Rubocop clean on all changed files.

## DoD Checklist

- [x] `SoulLinkRun has_many :soul_link_emulator_sessions, dependent: :destroy`
- [x] `SoulLinkRun#emulator_status` returns the right symbol for each session combination (covered by 6 model tests)
- [x] `SoulLinkRun#broadcast_state` includes `emulator_status` (covered by 2 model tests)
- [x] `RunChannel#generate_emulator_roms` enqueues the job, idempotent, broadcasts state
- [x] `GenerateRunRomsJob` broadcasts `RunChannel.broadcast_run_state(guild_id)` after `perform` (success + raise paths both covered)
- [x] Stimulus controller has `generateEmulatorRoms()` method + `generateRomsButton` target + broadcast-driven visibility toggle
- [x] View has the new button next to Setup Discord, with correct initial visibility (`!= :none` hides per brief)
- [x] Channel tests cover: enqueue happy path, idempotent no-op (sessions exist), no-active-run error
- [x] Model tests cover: each `emulator_status` outcome + broadcast_state inclusion
- [x] Job test asserts post-completion broadcast
- [x] Full suite: 131 + 15 new tests, all passing
- [x] Manual smoke test reported (see below — honest gap statement)

## Smoke Test — Honest Gap Statement

I cannot drive a real browser session in this sandboxed environment (no display, no auth credentials for Discord OAuth, and `bin/dev` would block the only shell I have for the duration). Below is a code-trace of what *would* happen end-to-end with `bin/dev` running and a logged-in user clicking the new button:

**Initial page load (`:none`):**
- `RunsController#index` renders `app/views/runs/index.html.erb`. ERB evaluates `@current_run&.emulator_status != :none` → `false` → button is **visible** with text "Generate Emulator ROMs".
- `run-management` Stimulus controller `connect()` opens an `ActionCable` subscription. `RunChannel#subscribed` calls `transmit build_state_payload`, which arrives in the JS `received` callback as `{ type: "state_update", state: { current_run: { ..., emulator_status: "none" }, ... } }` — note Ruby symbol `:none` becomes the string `"none"` over the wire, which is why my JS compares against `"none"`/`"failed"` literals and never against symbols.
- `render()` runs; `status === "none"` → `classList.remove("hidden")` is a no-op (already visible). State is consistent.

**User clicks the button:**
- `data-action="click->run-management#generateEmulatorRoms"` fires `subscription.perform("generate_emulator_roms")`.
- `RunChannel#generate_emulator_roms` runs server-side: finds the active run, sees `emulator_status == :none`, calls `SoulLink::GenerateRunRomsJob.perform_later(run)`, then `broadcast_state` re-broadcasts.
- The job (run async) creates 4 `SoulLinkEmulatorSession` rows in `pending` status inside a transaction. The first broadcast (from the channel itself) reflects `emulator_status: "generating"` if the job ran first; or `"none"` for an instant if it hasn't, in which case the job's `ensure`-block broadcast (after sessions are created and randomizer has run) reconciles the UI.

  Worth flagging: under a double-click race, the channel-layer guard catches it — the second invocation finds `emulator_status != :none` (sessions exist), no-ops, and re-broadcasts. So even under double-click, only one job is enqueued. The job itself is also idempotent (Step 2 contract). Defense in depth held up.

- During generation, `emulator_status` is `:generating`. Broadcast → JS hides the button. User sees nothing actionable.
- When the job finishes, the `ensure` block fires `RunChannel.broadcast_run_state(...)`. UI reconciles to `:ready` (button stays hidden) or `:failed` (button reappears for retry).

**Failed-state retry:**
- Server-rendered initial visibility is `:none`-only, but a page refresh after a failure: `@current_run&.emulator_status != :none` → `:failed != :none` → button is **hidden** server-side. Then `connect()` runs, the initial broadcast arrives, JS sees `"failed"` and removes `hidden`. End user sees the button after the cable handshake completes (sub-second). This matches the brief: "For now, no special 'retry' UX — just same button, same text."

**No new HTTP routes were added.** I didn't touch `setup_discord`. I didn't add a player-facing emulator route, controller, or view.

If the architect wants a real browser smoke test before approving, that's a reasonable ask — the project owner can run `bin/dev` locally and click the button. The test suite (especially the channel-layer enqueue/idempotency/error tests and the job-broadcast tests) covers the contract; the Stimulus toggle is small enough to eyeball. But I won't pretend I drove Chrome.

## Open Questions

1. **`setupDiscord()` mutates the button text/disabled state synchronously, but `generateEmulatorRoms()` doesn't.** I deliberately kept it minimal (the brief explicitly said skip inline status text if no clear pattern exists). If you want a "Generating..." label while waiting for the broadcast, that's a one-line addition. Architect's call.
2. **`emulator_status` priority order.** `:failed` over `:generating`, per spec. If a failed-then-retried scenario produces a mix where some sessions are `failed` (from a prior attempt that wasn't cleaned up) and some are `pending` (from a retry), the user would see `:failed` and the button stays visible — but clicking it hits the channel-layer no-op since sessions exist. Step 7's "refining the failed-state UX" presumably handles cleanup-on-retry; Step 4 doesn't need to.
3. The brief says the job should also broadcast "on rescue if applicable." I used a top-level `ensure` which fires on every exit path including unrescued exceptions. Confirm this is the intended shape.

## Known Gaps

None. Build is in scope.
