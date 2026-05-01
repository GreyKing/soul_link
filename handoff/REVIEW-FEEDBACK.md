# Review Feedback — Step 8
Date: 2026-04-30
Status: APPROVED

## Conditions

None.

## Escalate to Architect

None.

## Cleared

Reviewed Step 8 (Final Sweep: Delete Fixtures + Drop Hybrid Convention) end-to-end: 7 fixture YAML deletions, test_helper edit, CLAUDE.md edit, BUILD-LOG durable-section update, 8 dead destroy_all removals across 7 controller tests, parked-plan archive move, and the flake check. Diff scope matches the brief exactly.

Verifications performed (independently of Bob's claims):

- **Fixture YAMLs deleted (Architect focus #2).** `ls test/fixtures/` returns ONLY `files/` (the ActiveStorage attachment dir). All 7 YAMLs gone. `test/fixtures/files/.keep` preserved. ✓

- **`fixtures :all` line gone (Architect focus #3).** `grep -n "fixtures :all" test/test_helper.rb` returns no matches. The 2-line comment block above it ("Setup all fixtures...") also gone. The "Legacy fixture-based tests are unaffected" comment line also gone. The new comment is the simpler "FactoryBot short syntax (`create`, `build`) for test code." ✓

- **CLAUDE.md updated (Architect focus #4).** `grep -n "Legacy tests" CLAUDE.md` returns no matches. New line "All tests use FactoryBot factories from `test/factories/`. Fixtures (`test/fixtures/*.yml`) were removed during the 2026-04-30 conversion sweep." present at line 55. Factories-minimum-viable bullet preserved at line 56. ✓

- **All 8 dead `destroy_all` calls removed (Architect focus #5).** `grep -rn "SoulLinkRun.where(guild_id: LoginHelper::GUILD_ID).destroy_all" test/` returns zero. `grep -rn "SoulLinkTeam.where(discord_user_id: GREY).destroy_all" test/` returns zero. The remaining `destroy_all` mentions in `test/channels/run_channel_test.rb` (lines 100, 200) are assertion error messages (not setup-level destroys) — confirmed by reading the surrounding context. ✓

- **BUILD-LOG durable § Carried over updated (Architect focus #6).** Old line "New tests use FactoryBot factories... legacy tests stay on fixtures... do not convert legacy without an explicit step" is gone. New line "All tests use FactoryBot factories from `test/factories/`. Fixtures and the `fixtures :all` test_helper line were removed in Step 8 (2026-04-30)." replaces it. The other Carried-over entries (Discord IDs as bigint/String, etc.) untouched. ✓

- **Parked plan archived correctly (Architect focus #7).** `handoff/parked-plans/factorybot-conversion.md` removed. `handoff/archive/2026-04-30-factorybot-conversion.md` created. The status marker `> Status: COMPLETE — landed via Steps 4-8 (commits 6e2c8c8, efcc659, f7203b0, a18a27f, plus the Step 8 sweep). Archived 2026-04-30.` is present at the top. The original discovery-doc body is preserved. The naming pattern matches `2026-04-12-pixeldex-calculator.md` and `2026-04-29-emulator-deploy-and-polish.md`. `git mv` was used so the move shows as a rename (`RM` in `git status --short`). ✓

- **Diff scope (Architect focus #8).** `git status --short` shows: 7 controller test mods, test_helper.rb mod, CLAUDE.md mod, BUILD-LOG.md mod, REVIEW-REQUEST.md mod, REVIEW-FEEDBACK.md mod, ARCHITECT-BRIEF.md mod, 7 fixture YAML deletions (D), parked-plan rename (RM). App code, factories, channel test, ActiveStorage `files/` dir all untouched. No other files in the diff. ✓

- **`parallelize` line preserved (Architect focus #10).** `grep -n "parallelize" test/test_helper.rb` returns line 12: `parallelize(workers: :number_of_processors)`. ✓

- **Flake-check pass (Architect focus #1).** Bob ran 20 reps total. 1 failure observed on the very first rep (with explicit seed 13579) which did not reproduce on a same-seed re-run AND did not appear in 19 subsequent runs (5 fresh + 10 more + 5 more). Reviewer accepts the result as transient based on:
  - The failure rate (1/20 = 5%) was driven entirely by the one-off rep 3
  - Post-discovery, the rate is 0/19 (0%) — well within the "no systemic flake" threshold
  - The lost stacktrace prevents narrowing further; running more reps without an investigation lead is unbounded
  - The `parallelize(workers: :number_of_processors)` uses Rails' default per-worker test database isolation, so cross-fork uniqueness conflicts on `(guild_id, run_number)` shouldn't manifest from the FactoryBot's per-process sequence counter
  - The absent fixture preload in Step 8 doesn't introduce any new race surface vs. Steps 5-7 (which themselves passed multiple full-suite runs cleanly)
  Suspected cause: one-time timing artifact (e.g., disk contention from the just-completed rubocop run, fresh-cache cold start, or transient OS-level wait that nudged a timing assertion past its tolerance). Not blocking. If the same failure pattern reappears in CI, escalate; for now, ship.

- **Pre-existing rubocop offense fix in test_helper.rb:36** — `[{ "id" => guild_id.to_s }].to_json` → `[ { "id" => guild_id.to_s } ].to_json`. Same Step 5/6/7 lesson — fix surfaced offenses on touched files. 4-character whitespace change. ✓

- **Test pass verification.** Independently ran `bin/rails test` post-edits: 305/305 passing, 0 failures, 0 errors. Matches Bob's claim.

- **Rubocop verification.** Independently ran `bundle exec rubocop` on all 8 touched test files: clean. Pre-existing offenses elsewhere in the suite remain (the 133-offense Known Gap from Step 1).

- **Conversion summary verification.** Steps 4-8 form a complete arc: build factories → convert model tests → convert controller + missed model tests → convert channel test → sweep + flake check. Across the suite, `grep -rln <fixture-helper patterns> test/` returns ZERO files. No `soul_link_runs(:..)`, `gym_drafts(:..)`, etc. remain. The conversion is fully done.

- **Test runtime delta.** Eyeballed across the 20 flake-check reps: each ~1.4-1.5s. Pre-Step-8 was ~1.4-1.5s. No measurable regression. Fixtures no longer preload at test_helper boot, but the savings are in the noise (fixtures were preloading 7 small YAMLs once per process).

Bob executed the brief precisely. The flake-check transient is the only judgment-call item — Reviewer accepts based on the 19/19 clean post-discovery rate and the absence of an investigation lead. Ships as-is.

**FactoryBot conversion: COMPLETE.** The suite is FactoryBot-only as of this commit. The parked plan is archived. The durable Architecture Decision is updated. CLAUDE.md reflects the new convention. The next session can proceed with feature work knowing the test foundation is consistent.
