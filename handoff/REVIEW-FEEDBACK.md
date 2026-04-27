# Review Feedback — Step 4
Date: 2026-04-26
Ready for Builder: YES

## Must Fix

None.

## Should Fix

None.

## Escalate to Architect

None.

## Observations

These are not blocking. Logged here so Bob and the Project Owner see what
I noticed but did not require a fix for.

- **Channel-layer race is real but small (per Architect ruling — do not block).**
  `RunChannel#generate_emulator_roms` reads `run.emulator_status` (a DB
  query) and *then* `perform_later`s the job. Two channel actions arriving
  in rapid succession — e.g. two browser tabs, or a network blip causing
  the client to retry — could both observe `:none` before either has
  enqueued. The result is two enqueued jobs, not two creation runs: the
  job's own count guard at line 15 of `generate_run_roms_job.rb`
  (`return if ... count >= SESSIONS_PER_RUN`) catches it on the worker
  side, so the user-visible behavior is still correct. Defense in depth
  held, but at the job layer, not the channel layer. The button hiding
  on first click already eliminates the common case (single-user double-
  click), and there are only four users on this server. Acceptable as-is.
  If we ever go multi-process or higher-traffic, the proper fix is a
  unique DB constraint or an advisory lock around session creation —
  not in scope for Step 4.

- **`emulator_status` does N+1 work.** `soul_link_emulator_sessions` (no
  preload) loads all sessions, then iterates with `.any?` up to twice. For
  four rows per run this is fine; if `broadcast_state` ever runs over
  the past-runs list (currently capped at 20 in `build_state_payload` /
  `broadcast_run_state`), that's up to 20 extra SELECTs per broadcast.
  Not a Step 4 problem — those past-run payloads already do `caught_count`
  and `dead_count` queries — but worth keeping in mind if broadcast
  latency ever shows up in profiling.

## Cleared

Read each of the eleven scrutiny points end-to-end. Findings, in order:

1. **`generate_emulator_roms` mirrors `setup_discord` correctly.**
   Same `unless run; transmit({ error: "No active run found" }); return; end`
   guard. Same trailing `rescue => e; transmit({ error: e.message })`.
   Same `broadcast_state` on success. The added idempotency block
   (lines 70–73) is the only structural difference, and the brief
   explicitly required it. No drift in error shape.

2. **Channel-layer idempotency is "true no-op," not "exactly-once."**
   `test/channels/run_channel_test.rb:41` uses
   `assert_no_enqueued_jobs(only: SoulLink::GenerateRunRomsJob)` —
   that asserts zero, not one. Same on line 52 (`:generating` case)
   and line 61 (no-active-run case). All three idempotency paths
   assert NO job was enqueued. Correct.

3. **Job's `ensure` block fires on every path.** Line 30 of
   `generate_run_roms_job.rb` is a true Ruby `ensure` (not
   `rescue StandardError`) attached to the `perform` method — fires on
   success, on per-session errors that the inner `rescue` swallows,
   and on hard crashes that bubble out of `perform`. Tests at line 119
   (success) and line 127 (randomizer-raises causing the whole job
   to raise) both assert the broadcast fires. The
   unrescued-StandardError test at line 139 separately confirms the
   per-session rescue works while still allowing `ensure` to fire.
   Three angles of coverage.

4. **Stimulus uses string comparisons.** Lines 128–133 of
   `run_management_controller.js`:
   `const status = current_run.emulator_status` followed by
   `if (status === "none" || status === "failed")`. Plain string
   literals. No symbol leakage, no template-string comparison, no
   truthy checks that would wrongly accept `null`/`undefined`.

5. **`emulator_status` priority is correct.** Lines 53–59 of
   `soul_link_run.rb`: empty → `:none`, then any `failed` → `:failed`,
   then any `pending`/`generating` → `:generating`, else `:ready`.
   Pending is correctly bucketed with generating per the brief
   (`%w[pending generating]`). Default-pending exercised by
   `test/models/soul_link_run_test.rb:29`.

6. **`has_many :soul_link_emulator_sessions, dependent: :destroy`
   present** at line 8 of `soul_link_run.rb`. Inverse
   `belongs_to :soul_link_run` confirmed at line 6 of
   `soul_link_emulator_session.rb`.

7. **No HTTP route, no controller, no view drift.**
   `grep -i emulator config/routes.rb` returns nothing.
   `ls app/controllers/ | grep emulator` returns nothing. The only
   view change is the new sibling button in
   `app/views/runs/index.html.erb` lines 53–57. `git diff 9ce4114`
   confirms only the five production files Bob listed are modified.

8. **`broadcast_state` extension is additive.** New key
   `emulator_status` added at line 72 of `soul_link_run.rb`. The
   Stimulus `render()` only reads `current_run.emulator_status`
   inside `if (this.hasGenerateRomsButtonTarget)` (line 127); no
   destructuring elsewhere requires the previous key set. Existing
   consumers read individual properties off `current_run`, none of
   which were touched.

9. **No `setup_discord` regression.** `git diff 9ce4114
   app/channels/run_channel.rb` shows pure addition: 20 lines added
   at line 60, zero lines deleted. `setup_discord` at lines 43–59 is
   byte-for-byte unchanged.

10. **Definition of Done — independent verification.**
    - has_many present (line 8) — checked
    - emulator_status returns each symbol (6 model tests, pass) — checked
    - broadcast_state includes emulator_status (2 model tests, pass) — checked
    - generate_emulator_roms enqueues / idempotent / broadcasts (3 channel tests, pass) — checked
    - Job ensure-block broadcast (2 job tests, pass — success + raise) — checked
    - Stimulus method, target, broadcast toggle (lines 9, 89–91, 124–134) — checked
    - View button next to Setup Discord with `'hidden' if != :none` (lines 53–57) — checked
    - No-active-run error broadcast (channel test line 57) — checked
    - Full suite: I ran the three changed test files myself —
      20 runs, 67 assertions, 0 failures, 0 errors. Bob's 146/146
      full-suite figure stands.

11. **Race / concurrency** — covered above in Observations. Not a blocker.

**Smoke test gap.** Bob explicitly stated he could not drive a real
browser. Architect ruled that the user will smoke-test locally.
Not a review issue.

VERDICT: PASS_WITH_OBSERVATIONS
