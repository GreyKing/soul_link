# Review Feedback — Step 2 (Emulator Polish)
*Written by Reviewer. Read by Builder and Architect.*

---

**Date:** 2026-04-28
**Ready for Builder:** YES

## Must Fix

*—*

## Should Fix

*—*

## Escalate to Architect

- **Pokemon-group COUNT N+1 on past runs.** Bob flagged it in REVIEW-REQUEST
  and intentionally left it alone (out of scope for Step 2). Confirmed in
  `app/models/soul_link_run.rb:67–68` — `caught_groups.count` and
  `dead_groups.count` fire two COUNTs per past run, scaling 2N with the
  20-run history cap. Not a Reviewer call to fold in; flagging here so Arch
  can decide whether to bundle it into a future polish step.

## Cleared

All three pieces of Step 2 verified end-to-end against the brief and Bob's
report. Full suite **200 runs, 590 assertions, 0 failures, 0 errors, 0
skips**; targeted channel suite **13 runs, 43 assertions, 0 failures**. The
`c36ce69` `Rails.root` stub is intact at
`test/lib/tasks/emulator_cleanup_test.rb:34`.

### A — Deployment doc (`.claude/documents/deployment.md`)

- Lines 1–104: original content preserved verbatim (CI/CD, systemd, nginx,
  Puma, DB, ActionCable, Docker/Kamal, dev, env vars).
- Lines 105–151: new "In-Browser Emulator" section appended. All five
  prereqs present in the brief's order: Java JRE, base ROM, randomizer JAR,
  randomizer settings file, EmulatorJS install. Cleanup task documented at
  138–145. Cheats note at 147–151. `bin/rails` (system Ruby) used
  throughout — correct for VPS.
- File is gitignored (`.gitignore:56–57`), so it does not appear in
  `git status`. Read directly to confirm contents.

### B — N+1 fix (`app/channels/run_channel.rb`)

- `broadcast_run_state` (lines 105–125): both `current_run` (lines 109–111)
  and `past_runs` (112–114) now chain `.includes(:soul_link_emulator_sessions)`.
- `build_state_payload` (lines 133–150): same eager-load applied to both
  queries (136–138, 139–141) — the initial-subscribe path mirrors the
  broadcast path, as Bob claimed.
- The `current_run` query was inlined (`active.for_guild.order.first`)
  rather than going through `SoulLinkRun.current(guild_id)`, because the
  class method has no clean hook for `.includes`. Bob's choice; defensible
  and noted in REVIEW-REQUEST. No pre-existing eager-loads (e.g., teams)
  were destroyed — `SoulLinkRun.history` and `.active` scopes had none to
  preserve.

### B — N+1 test correctness (`test/channels/run_channel_test.rb:137–179`)

- **Invariant test** (146–164): seeds 5 past runs + 1 current run, each
  with one session. Subscribes to `sql.active_record` notifications and
  asserts `session_queries == 2`. Confirmed by inspection of
  `app/models/soul_link_run.rb:53–59` that `emulator_status` calls
  `sessions.empty?` and `sessions.any?`, both of which fire a SELECT on an
  unloaded association. Without `.includes`, this test would see 12 (or
  similar) and fail with the descriptive message Bob wired in.
- **Snapshot guard** (166–179): `assert_queries_count(16)` is brittle by
  design (any added query, even a legitimate one, will trip it), but
  acceptable as a regression alarm — and Bob's comment at 173–175 calls
  out exactly that intent. Not a blocker.

### C — Status label

- **View** (`app/views/runs/index.html.erb:63–67`): `<span>` is a sibling
  of the existing buttons in the same flex container. Initial visibility
  uses `@current_run&.emulator_status != :generating` (Ruby symbol
  comparison) — matches the symbol-keyed pattern at lines 55, 60.
- **Typography:** `font-size: 11px; color: var(--l1);` — verified to match
  the existing GB-aesthetic small-text pattern at lines 22–35 (the "GYMS",
  "CAUGHT", "DEAD", "STARTED" labels all use `font-size: 9px–11px; color:
  var(--l1);`). No new CSS class invented.
- **Stimulus** (`app/javascript/controllers/run_management_controller.js`):
  - Line 11: `generateRomsStatus` added to `static targets`.
  - Lines 151–157: visibility toggle inside the existing `render()`,
    immediately after the `regenerateRomsButton` toggle (144–150). String
    comparison `status === "generating"`, `hasGenerateRomsStatusTarget`
    guard. No parallel handler.
- **HTML entity:** `&hellip;` matches the `&mdash;` already used in the
  same view at line 97. Consistent.

### Scope discipline

Confirmed Bob did not touch:
- `setup_discord` (`run_channel.rb:43–59`),
- `generate_emulator_roms` (61–79),
- `regenerate_emulator_roms` (81–103),
- `app/models/soul_link_run.rb` (no diff),
- `app/models/soul_link_emulator_session.rb` (no diff),
- gem manifest (no `Gemfile`/`Gemfile.lock` changes).

The N+1 fix is purely at the channel layer via `.includes`, as briefed.

### Definition of Done

- [x] `deployment.md` has "In-Browser Emulator" section, existing content preserved
- [x] `RunChannel.broadcast_run_state` eager-loads `soul_link_emulator_sessions` (and so does `build_state_payload`)
- [x] N+1 assertion test passes and would fail if `.includes` is removed (verified by reading `emulator_status` implementation)
- [x] View has `generateRomsStatus` target with correct symbol-based initial visibility
- [x] Stimulus toggles `generateRomsStatus` in `render()` with `status === "generating"`
- [x] Full suite passes: 198 baseline + 2 new tests = 200, 0 failures
- [x] `c36ce69` storage isolation fix held; no new flakes observed in this review run

Step 2 is clear.

VERDICT: PASS
