# Build Log
*Owned by Architect. Updated by Builder after each step.*

`Current Status` and `Step History` are session-scoped — archived to
`handoff/archive/` at session end and reset.
`Known Gaps` and `Architecture Decisions` are durable — they survive session
reset until the gap is addressed or the decision is replaced.

---

## Current Status
*Session-scoped.*

**Active step:** Step 8 — Final Sweep: Delete Fixtures + Drop Hybrid Convention. **Awaiting review.**
**Last committed:** Step 7 (`a18a27f`) shipped + merged to `main`. Step 8 not yet committed.
**Pending deploy:** N/A — Step 8 is test/docs only.

**Parked plan:** Archived to `handoff/archive/2026-04-30-factorybot-conversion.md` with COMPLETE status marker. The FactoryBot conversion is fully done — Steps 4-8.

**Parked plan:** FactoryBot conversion. Phases 1+2 land in this step (Step 4); Phase 3+ in Steps 5–6. See `handoff/parked-plans/factorybot-conversion.md`.

---

## Step History
*Session-scoped.*

### Step 8 — Final Sweep: Delete Fixtures + Drop Hybrid Convention — 2026-04-30
**Status:** Awaiting review.

**Files deleted (7 fixture YAMLs):**
- `test/fixtures/gym_drafts.yml`
- `test/fixtures/gym_results.yml`
- `test/fixtures/soul_link_pokemon.yml`
- `test/fixtures/soul_link_pokemon_groups.yml`
- `test/fixtures/soul_link_runs.yml`
- `test/fixtures/soul_link_team_slots.yml`
- `test/fixtures/soul_link_teams.yml`

`test/fixtures/files/` (ActiveStorage attachment dir) preserved.

**Files modified:**
- `test/test_helper.rb` — dropped the `fixtures :all` line + the comment block above it; updated the FactoryBot-syntax comment to no longer mention "Legacy fixture-based tests" coexistence (no longer true). Also fixed 1 pre-existing rubocop offense on line 36 (`Layout/SpaceInsideArrayLiteralBrackets` on the Faraday stub `fake_response` line) to satisfy the touched-files-clean acceptance criterion.
- `CLAUDE.md` — Testing-conventions section: replaced the 2-bullet "New tests / Legacy tests" hybrid note with a single bullet "All tests use FactoryBot factories from `test/factories/`. Fixtures (`test/fixtures/*.yml`) were removed during the 2026-04-30 conversion sweep." Factories-minimum-viable bullet preserved.
- `handoff/BUILD-LOG.md` — durable § Architecture Decisions § Carried over: replaced the legacy-fixture line with "All tests use FactoryBot factories from `test/factories/`. Fixtures and the `fixtures :all` test_helper line were removed in Step 8 (2026-04-30)."
- 7 controller tests (`emulator`, `save_slots`, `species_assignments`, `teams`, `pokemon`, `pokemon_groups`, `gym_drafts`) — removed the dead `SoulLinkRun.where(guild_id: LoginHelper::GUILD_ID).destroy_all` line from each setup. Removed the explanatory 4-line comment block from `emulator_controller_test.rb`. Also removed the dead in-test `SoulLinkTeam.where(discord_user_id: GREY).destroy_all` line + comment from `teams_controller_test.rb`'s "show creates team if none exists" test.

**Files renamed:**
- `handoff/parked-plans/factorybot-conversion.md` → `handoff/archive/2026-04-30-factorybot-conversion.md` via `git mv`. Added `> Status: COMPLETE` marker at top with commit references for Steps 4-8. The original discovery-doc body is preserved as historical record. `handoff/parked-plans/` is now empty.

**Files modified (handoff):**
- `handoff/ARCHITECT-BRIEF.md` — Step 8 brief (overwritten from Step 7)
- `handoff/REVIEW-REQUEST.md` — Step 8 review request
- `handoff/REVIEW-FEEDBACK.md` — Reviewer's Step 8 verdict

**Key decisions:**
- **`git mv` for the parked-plan archive** so the move shows as a rename in `git log --follow`. Matches the existing archive convention (`2026-04-12-pixeldex-calculator.md`, `2026-04-29-emulator-deploy-and-polish.md`) — date-prefixed, descriptive filename.
- **Pre-existing rubocop offense in `test_helper.rb:36` fixed.** Same lesson as Step 5/6/7 — when a file is touched, fix any rubocop offenses surfaced on it. Pre-existing offenses outside touched files remain (Known Gap from Step 1).
- **Bulk fixture deletion via `git rm`** so the deletions show as deletions in the diff (vs untracked-removal). User explicitly OK'd these — "the fixture deletions are bulk file removals from a versioned directory — that IS the work, not a destructive accident."
- **`parallelize(workers: :number_of_processors)` preserved** in test_helper. The Step 5/6/7/8 conversion work doesn't change parallelization semantics; only fixture loading was removed.
- **`test/fixtures/files/.keep` preserved.** Standard Rails ActiveStorage attachment fixture dir; unrelated to the YAML conversion.

**Tests:** 305/305 passing. Per-file counts unchanged from Step 7.

**Flake check:** 20 reps total. 19 clean reps, 1 transient failure on the very first rep (seed 13579) that did not reproduce when re-run with the same seed or across 19 subsequent runs (5 fresh + 10 more + 5 more). The lost stacktrace prevented identifying the specific test, but the failure-rate dropped to 0/19 ≈ 0% post-discovery, suggesting a one-time timing artifact (possibly fresh-cache or disk contention from the earlier rubocop run / file-write boundary) rather than a systemic race. The `parallelize(workers: :number_of_processors)` setup uses Rails' default per-worker test database isolation, so cross-fork uniqueness conflicts on `(guild_id, run_number)` shouldn't manifest. Documented for transparency; not a Condition.

**Lint:** `bundle exec rubocop` clean on all 8 touched test files (test_helper.rb + 7 controller tests). The pre-existing offense in test_helper.rb:36 was fixed (4-character whitespace change).

**Diff scope:** 7 controller test files modified, `test/test_helper.rb` modified, 7 fixture YAMLs deleted, `CLAUDE.md` modified, `handoff/BUILD-LOG.md` modified (durable section + Step 8 entry), `handoff/REVIEW-REQUEST.md` modified, `handoff/REVIEW-FEEDBACK.md` modified, `handoff/ARCHITECT-BRIEF.md` modified, parked plan moved from `handoff/parked-plans/` to `handoff/archive/2026-04-30-factorybot-conversion.md`. App code, factories, channel test, ActiveStorage `files/` dir all untouched.

**Conversion summary:** Steps 4-8 converted the entire test suite from fixture-based to FactoryBot:
- Step 4 (`6e2c8c8`): built 6 missing factories with traits matching every fixture row
- Step 5 (`efcc659`): converted 3 model unit tests (gym_draft, gym_result, soul_link_pokemon)
- Step 6 (`f7203b0`): converted 8 controller tests + 1 missed model test (soul_link_pokemon_group); discovered + handled the fixture-coexistence constraint
- Step 7 (`a18a27f`): converted 1 channel test (gym_draft_channel)
- Step 8 (this commit): deleted fixtures, dropped `fixtures :all`, updated CLAUDE.md + durable BUILD-LOG decision, removed dead defensive code from Step 6, archived parked plan, ran 20-rep flake check

305/305 tests pass; suite is FactoryBot-only.

---

### Step 7 — Convert Channel Test from Fixtures to FactoryBot — 2026-04-30
**Status:** Awaiting review.

**Files modified (1):**
- `test/channels/gym_draft_channel_test.rb` — setup replaced with the proven Step 5 pattern: `@run = create(:soul_link_run)`, `@groups = %i[route201..route206].map { |t| create(:soul_link_pokemon_group, t, soul_link_run: @run) }`, `@draft = create(:gym_draft, :lobby, soul_link_run: @run)`. The channel-specific `stub_connection(current_user_id: GREY)` line stays at the end of setup. All 9 test bodies + 3 private helpers (`move_to_voting!` / `move_to_drafting!` / `move_to_nominating!`) unchanged. Also fixed 1 pre-existing rubocop offense on line 8 (`Layout/SpaceInsideArrayLiteralBrackets` on `ALL_PLAYERS = [GREY, ARATY, SCYTHE, ZEALOUS]`). Test count: 9 (unchanged).

**Files modified (handoff):**
- `handoff/ARCHITECT-BRIEF.md` — Step 7 brief (overwritten from Step 6)
- `handoff/BUILD-LOG.md` — this entry
- `handoff/REVIEW-REQUEST.md` — Step 7 review request
- `handoff/REVIEW-FEEDBACK.md` — Reviewer's Step 7 verdict

**Key decisions:**
- **No `destroy_all` guild guard.** Channel tests bypass HTTP — `stub_connection(current_user_id: GREY)` sets the connection identifier directly, the channel looks up the draft via `params[:draft_id]`, never goes through `SoulLinkRun.current(guild_id)`. The Step 6 controller-coexistence guard would be cargo-cult here. Architect brief explicitly forbade it; Builder verified by running the test green without it.
- **Setup pattern is identical to Step 5's `gym_draft_test.rb`** (the model unit test for the same draft state machine). Only difference is the trailing `stub_connection` line. This matches the architect's "channel tests have a distinct subscribe + perform setup" guidance — the data setup is the same, only the channel test machinery differs.
- **Pre-existing rubocop fix.** `ALL_PLAYERS = [GREY, ARATY, SCYTHE, ZEALOUS].freeze` → `[ GREY, ARATY, SCYTHE, ZEALOUS ]`. Same offense + same fix as Step 5's `gym_draft_test.rb`. Two-character whitespace change.

**Tests:** 305/305 passing across the full suite. Per-file: 9/9 (unchanged). 0 failures, 0 errors.

**Lint:** `bundle exec rubocop test/channels/gym_draft_channel_test.rb` clean.

**Diff scope:** 1 test file + 4 handoff files. App code, fixtures, factories, test_helper.rb, all other test files untouched.

**Fixture-helper grep verification:** zero matches in the converted file. **Across the entire `test/` tree, ZERO files use fixture helpers** — Step 7 closes out the test-side conversion. Step 8 is now purely mechanical: delete `test/fixtures/*.yml`, drop `fixtures :all` from `test_helper.rb`, update `CLAUDE.md`'s testing convention section, run a flake check.

---

### Step 6 — Convert 8 Controller Tests + 1 Missed Model Test — 2026-04-30
**Status:** Awaiting review.

**Files modified (9):**
- `test/models/soul_link_pokemon_group_test.rb` — setup creates `@run`, `@group` (route201 trait), and 4 player pokemon (`:route201_grey/aratypuss/scythe461/zealous`). Required for `species_for` and `complete?` tests. 7 tests, unchanged.
- `test/controllers/emulator_controller_test.rb` — setup destroys fixture run for guild + creates factory run. 44 tests, unchanged. Heaviest controller file by test count.
- `test/controllers/save_slots_controller_test.rb` — same destroy-then-create setup pattern. 33 tests, unchanged.
- `test/controllers/species_assignments_controller_test.rb` — setup pattern + inline seed of route201 group + grey-pokemon in the duplicate-rejection test. 5 tests, unchanged.
- `test/controllers/teams_controller_test.rb` — setup pattern + inline group/pokemon seeds in `update_slots saves valid group ids` and `update_slots rejects more than 6`. The "rejects more than 6" test seeds 6 groups with grey-pokemon + 1 group without (so the 7th gets filtered by `allowed_ids`, mirroring the fixture-era invariant where `.limit(7).pluck(:id)` returned 6). Also fixed 1 pre-existing rubocop offense on a non-touched line for acceptance criterion. 6 tests, unchanged.
- `test/controllers/pokemon_controller_test.rb` — setup pattern + inline route201 group + grey/aratypuss seeds in two tests. 5 tests, unchanged.
- `test/controllers/pokemon_groups_controller_test.rb` — setup pattern + inline route206 group in two tests. 6 tests, unchanged.
- `test/controllers/gym_drafts_controller_test.rb` — setup builds `@run`, `@draft` from `:lobby` trait; "type analysis" test seeds 6 groups via `%i[route201..route206].map`. Same pattern as Step 5's gym_draft model test. 5 tests, unchanged.

**Files modified (handoff):**
- `handoff/ARCHITECT-BRIEF.md` — Step 6 brief (overwritten from Step 5)
- `handoff/BUILD-LOG.md` — this entry
- `handoff/REVIEW-REQUEST.md` — Step 6 review request
- `handoff/REVIEW-FEEDBACK.md` — Reviewer's Step 6 verdict

**Key decisions:**
- **Discovered constraint: fixture run still loads via `fixtures :all` and shares guild_id with the factory.** Two `active: true` runs for guild 999... coexist; `SoulLinkRun.current(guild_id)` orders by `run_number desc` and returns the factory run (run_number 1000+n) by default — but tests that deactivate `@run` and expect "no active run" fall back to the fixture (run_number 1) instead. Fix applied in every controller test's setup: `SoulLinkRun.where(guild_id: LoginHelper::GUILD_ID).destroy_all` before `create(:soul_link_run)`. Step 8 deletes the fixtures and the destroy_all becomes a no-op. The model test (`soul_link_pokemon_group_test`) doesn't go through HTTP, so it doesn't need this guard.
- **`teams_controller_test` "update_slots rejects more than 6" test honesty.** The original fixture-era test asserted SUCCESS while named "rejects more than 6" — relying on the fact that `.limit(7).pluck(:id)` returned only 6 IDs (only 6 groups existed) and thus passed under MAX_SLOTS. Direct conversion (seeding 7 groups with grey-pokemon) made `allowed_ids` = 7 and the controller correctly returned 422. Fixed by seeding 6 groups with grey-pokemon + 1 group without — the 7th gets filtered by `allowed_ids`, leaving 6 valid IDs that fit under MAX_SLOTS. Preserves test name, assertion, and intent (the controller silently caps via filter, not 422).
- **`soul_link_pokemon_group_test`'s `set_position auto-increments` test** asserts `g2.position > g1.position`. Pre-conversion the run had 6 fixture groups so the new ones got positions 7+8. Post-conversion only @group exists (position 1) so the new ones get positions 2+3. Assertion `3 > 2` still holds.
- **One pre-existing rubocop offense fixed** in `teams_controller_test.rb:65` (`Layout/SpaceInsideArrayLiteralBrackets`). Same lesson as Step 5 — fix to satisfy "rubocop clean" acceptance criterion. Documented as 2-character whitespace change.

**Tests:** 305/305 passing across the full suite. Per-file: 7 / 44 / 33 / 5 / 6 / 5 / 6 / 5 = 111 across the 8 controller/model files (the brief's preliminary counts undercounted emulator at 36 and teams at 5; actuals are 44 and 6 respectively, both unchanged from pre-conversion). 0 failures, 0 errors.

**Lint:** `bundle exec rubocop` clean on all 8 modified files (model + 7 controllers).

**Diff scope:** 9 test files + 4 handoff files. App code, fixtures, factories, test_helper.rb, channel test all untouched.

**Fixture-helper grep verification:** zero matches in the 9 converted files. After Step 6, the only remaining fixture-helper user in `test/` is `test/channels/gym_draft_channel_test.rb` (Step 7 target).

---

### Step 5 — Convert Model Unit Tests from Fixtures to FactoryBot — 2026-04-30
**Status:** Awaiting review.

**Files modified (3, all under `test/models/`):**
- `soul_link_pokemon_test.rb` — added `setup` block creating `@run` / `@group_201` / `@group_202` / `@pokemon`; replaced 9 fixture-helper calls with ivar references; renamed "fixture pokemon is valid" → "factory pokemon is valid" per brief. Test count preserved at 7.
- `gym_draft_test.rb` — replaced `setup` block with factory creates: `@run = create(:soul_link_run)`, `@groups = %i[route201..route206].map { |t| create(:soul_link_pokemon_group, t, soul_link_run: @run) }`, `@draft = create(:gym_draft, :lobby, soul_link_run: @run)`. The 22 test bodies (Architect's brief said 21 — it was always 22; minor undercount, not a deviation) and 3 private helpers (`move_to_voting!` / `move_to_drafting!` / `move_to_nominating!`) unchanged. Fixed 2 pre-existing rubocop offenses (`Layout/SpaceInsideArrayLiteralBrackets` on lines `ALL_PLAYERS = [ ... ]` and `assert_includes [ GREY, ARATY ], ...`) since the brief required clean lint.
- `gym_result_test.rb` — added `@groups` array creation in `setup` (parallels gym_draft pattern), inline-seeded 6 pokemon (one per group via `:routeNNN_grey` traits) inside the `snapshot_from_groups` test so `.limit(2)` finds groups with pokemon regardless of DB row order. Test count preserved at 4.

**Files modified (handoff):**
- `handoff/ARCHITECT-BRIEF.md` — Step 5 brief (overwritten from Step 4)
- `handoff/BUILD-LOG.md` — this entry
- `handoff/REVIEW-REQUEST.md` — Step 5 review request
- `handoff/REVIEW-FEEDBACK.md` — Reviewer's Step 5 verdict (added during this same session)

**Key decisions:**
- **Inline pokemon seeding in `gym_result_test.rb` snapshot test, not setup.** The test was the only one needing pokemon. Inline keeps the setup block clean for the other 3 tests in the file. Used `each_with_index` over the trait list to seed all 6 groups (matches fixture-era state where every group had pokemon — the original `.limit(2)` worked because all groups had pokemon, regardless of which 2 were picked).
- **Did NOT add `.order(:id)` to the snapshot test's `.limit(2)` query.** Brief said preserve assertions/queries. Seeding all 6 groups removes the ordering dependency without touching the test's query shape. First attempt (seed only `@groups[0]` and `@groups[1]`) failed because `.limit(2)` returned different groups; the all-6-seed fix is more robust and keeps the original query untouched.
- **Renamed "fixture pokemon is valid" → "factory pokemon is valid"** (per brief). All other test names unchanged.
- **Fixed 2 pre-existing `Layout/SpaceInsideArrayLiteralBrackets` offenses** in gym_draft_test (lines 8 + 83). Pre-existing in the file before Step 5; brief required rubocop clean on touched files. Two-line whitespace adjustment.
- **Did NOT touch fixtures, factories, test_helper.rb, or any other test file.** Step 6 will handle those.

**Tests:** 305/305 passing (file-level: 7 + 22 + 4 = 33; full suite 305). 0 failures, 0 errors. Ran each file individually post-conversion (per brief sequencing) and full suite at the end.

**Lint:** `bundle exec rubocop test/models/soul_link_pokemon_test.rb test/models/gym_draft_test.rb test/models/gym_result_test.rb` clean.

**Diff scope check:** `git status` shows only `handoff/ARCHITECT-BRIEF.md` + 3 test files modified (plus this BUILD-LOG and the two REVIEW docs as the step closes). App code, fixtures, factories, test_helper.rb, other test files all untouched per brief.

**Fixture-helper grep verification:** `grep -nE "soul_link_pokemon\(|soul_link_runs\(|soul_link_pokemon_groups\(|gym_drafts\(|gym_results\(" test/models/{soul_link_pokemon,gym_draft,gym_result}_test.rb` returns zero matches.

---

### Step 4 — Build All Missing FactoryBot Factories — 2026-04-30
**Status:** Complete, committed `6e2c8c8`, pushed to `origin/claude/gallant-bell-cb4390`. Test-only — no deploy required.

**Files created (6, all under `test/factories/`):**
- `soul_link_pokemon_groups.rb` — base factory + 6 named traits (`:route201`–`:route206`). Each trait sets `nickname`/`location`/`status` via attribute assignment and uses `after(:create) update_columns(position:, caught_at:)` to **override** the model's `before_create :set_position` and `:set_caught_at` callbacks (fixtures bypass these via raw SQL; the override reproduces fixture state exactly).
- `soul_link_pokemon.rb` — base factory + **24 metaprogrammed traits** (`:route201_grey`, `:route201_aratypuss`, …, `:route206_zealous`). Inner loop closes over a per-iteration `trait_species`/`trait_uid`/`trait_location` to avoid late-binding bugs. Data tables (`SOUL_LINK_POKEMON_PLAYERS`, `SOUL_LINK_POKEMON_ROUTES`) sit at top of file as constants for parity with the fixture's ERB shape.
- `soul_link_teams.rb` — base factory + `:grey_team` trait. Base uses `sequence(:discord_user_id)` to dodge the `(soul_link_run_id, discord_user_id)` uniqueness constraint when tests build multiple teams.
- `soul_link_team_slots.rb` — `:slot_1` / `:slot_2` traits only. **No association defaults** — the brief specifies callers pass `soul_link_team:` and `soul_link_pokemon_group:` explicitly (`create(:soul_link_team_slot, :slot_1, soul_link_team: t, soul_link_pokemon_group: g)`).
- `gym_drafts.rb` — base factory + `:lobby` trait. Both pin `status: "lobby"`, `current_round: 0`, `current_player_index: 0`, `pick_order: []`, `state_data: { ready_players, first_pick_votes, picks }` to match fixture and the model's `after_initialize :set_defaults` shape.
- `gym_results.rb` — base factory only (fixture is empty). `sequence(:gym_number) { |n| ((n - 1) % 8) + 1 }` cycles 1..8 to honor the `(soul_link_run_id, gym_number)` uniqueness constraint without colliding for the first 8 calls per run.

**Files modified:** none. Per the brief, Step 4 is purely additive — fixtures, tests, and app code are all left untouched. Step 5 will convert tests; Step 6 deletes fixtures.

**Key decisions:**
- **Pokemon factory metaprogramming pattern.** 24 traits hardcoded would be unreadable. Used a nested `each_with_index` loop, captured each trait's bindings into local variables (`trait_species`, `trait_uid`, `trait_location`) BEFORE entering the trait block to avoid the classic Ruby-closure late-binding bug where every trait would resolve to the final loop iteration's data.
- **Group factory's `after(:create) update_columns` is intentional.** The model has `before_create :set_position` (assigns max+1) and `before_create :set_caught_at` (assigns Time.current). Without `update_columns`, calling `create(:soul_link_pokemon_group, :route201)` would produce a record whose `position` reflects creation order, not the fixture's hardcoded `1`. `update_columns` skips callbacks/validations and writes raw — the same effect fixtures achieve via raw SQL INSERT.
- **Gym draft trait redundant with base.** Both base factory and `:lobby` trait set the same five attributes. The brief said "the trait pins those values explicitly to keep the trait's intent self-documenting"; followed verbatim. Future Step 5 conversions will likely call `create(:gym_draft, :lobby)` — the trait surfaces intent at the call site even when the values match the default.
- **Team slot factory has no association defaults.** Brief decision: caller-provided is correct because slot rows only make sense when bound to a specific team and group already constructed in the test's setup. A factory default would either create orphan associations or shadow the test's intended team/group references.
- **`gym_result.gym_number` sequence wraps modulo 8.** Strictly the model only requires `inclusion: { in: 1..8 }`; a sequence that never wraps would still satisfy validity for one call. But cycling lets a single test create multiple results within the same run — useful for "all 8 gyms beaten" scenarios in Step 5 conversions — without each call needing an explicit `gym_number:` override.

**Tests:** 305/305 still passing — no regressions. Fixtures untouched, so legacy fixture-based tests continue to pull from YAML; new factory files are inert (FactoryBot loads them at boot but no test uses them yet).

**Spot-check:** Wrote `/tmp/factory_smoke.rb` (Rails runner) that creates one record per factory and trait, asserting field-by-field match against the fixture data. All 32 records (6 group traits + 24 pokemon traits + 1 grey_team + 2 slots + 1 lobby_draft + 1 gym_result) build successfully and match the corresponding fixture row exactly. Output:

```
OK group :route201 → ROY / route_201 / pos 1
OK group :route202 → TOMMY / route_202 / pos 2
OK group :route203 → RACHEL / route_203 / pos 3
OK group :route204 → SPIKE / route_204 / pos 4
OK group :route205 → LUNA / route_205 / pos 5
OK group :route206 → BLAZE / route_206 / pos 6
OK 24 pokemon traits each match fixture (species/uid/location/status/name)
OK team :grey_team → uid 153665622641737728
OK team_slot :slot_1 → pos 1, :slot_2 → pos 2
OK gym_draft :lobby → state matches fixture
OK gym_result → gym_number 1, beaten_at <ts>
ALL FACTORY SMOKE CHECKS PASSED
```

**Lint:** `bundle exec rubocop` clean on all 6 files.

---

### Step 3 — Save Slots (5 per session) — 2026-04-30
**Status:** Complete, committed `29186e6`, deployed to `4luckyclovers.com`

**Files created:**
- `db/migrate/20260430143102_create_soul_link_emulator_save_slots.rb` — slots table + `active_save_slot` pointer on session; data-preservation INSERT migrates existing per-session save into slot 1; columns dropped with type args so rollback is reversible (data lost on rollback per Project Owner acceptance)
- `app/models/soul_link_emulator_save_slot.rb` — model with GzipCoder reuse, slot_number 1..5 validation + uniqueness, after_create_commit + after_update_commit parse-enqueue
- `app/controllers/save_slots_controller.rb` — index/create/update/destroy/restore/download. Authorization via `set_session` resolving to current_user_id-owned session; cross-player URLs return 404
- `app/views/emulator/_save_slots_sidebar.html.erb` — left column partial, 5 cards, banner for overwrite-pending mode, per-slot Download/MakeActive/Delete actions, Clear-All at bottom
- `app/javascript/controllers/save_slots_controller.js` — Stimulus controller; listens for `save-slots:overwrite-needed` and `save-slots:saved` window events; click overlays for overwrite mode; calls `window.EJS_emulator.gameManager.getSaveFile()` at click time to grab fresh bytes for the PATCH (Approach 2 per brief — stateless)
- `test/models/soul_link_emulator_save_slot_test.rb` — 18 tests (validations, gzip coder round-trip, parse callbacks)
- `test/controllers/save_slots_controller_test.rb` — 33 tests covering all 6 actions + cross-player authz
- `test/factories/soul_link_emulator_save_slots.rb` — factory with `:filled` and `:parsed` traits

**Files modified:**
- `app/models/soul_link_emulator_session.rb` — `has_many :save_slots dependent: :destroy`, new `active_slot` association method, removed `serialize :save_data` and the parse callback (moved to slot model). GzipCoder module retained on this class for shared use.
- `app/jobs/soul_link/parse_save_data_job.rb` — operates on a `SoulLinkEmulatorSaveSlot` parameter, not a session
- `app/controllers/emulator_controller.rb` — DELETE save_data wipes all slots + clears active_save_slot; GET reads from `@session.active_slot.save_data`; PATCH branch removed entirely; `set_session` no longer applies to PATCH route. `show` action eager-loads `:save_slots` and pre-fetches `@save_slots` for the sidebar partial.
- `app/javascript/controllers/emulator_controller.js` — added `saveSlotsUrl` Stimulus value; `_uploadSave` now POSTs to that URL; on 409 dispatches `save-slots:overwrite-needed` window event with the JSON body as detail; on 201 dispatches `save-slots:saved`
- `app/views/emulator/show.html.erb` — three-column grid (`280px minmax(0, 1fr) 280px`); save-slots sidebar on left; canvas in middle; run roster on right; canvas wrapper now also has `data-emulator-save-slots-url-value`
- `app/views/emulator/_run_sidebar.html.erb` — drops the inline Clear-Save button (moved to slot column); drops parsed-info display from the YOU card (visible in slot column); keeps parsed info on OTHER players' cards (sourced from their `active_slot`); removed `clear-save` Stimulus mount from this partial
- `config/routes.rb` — removed `patch :save_data`; nested `resources :save_slots, only: [...], param: :slot_number` under `:emulator` with `member { post :restore; get :download }`
- `lib/tasks/soul_link/debug_save.rake` — `reparse_all_saves` and `debug_save_offsets` now iterate `SoulLinkEmulatorSaveSlot.where.not(save_data: nil)`, not sessions
- `lib/tasks/emulator_cleanup.rake` — counts non-nil save bytes via `session.save_slots.where.not(save_data: nil).count`; destroys all slots; clears `active_save_slot` on inactive runs (transitively required by the schema migration)
- `test/controllers/emulator_controller_test.rb` — removed all PATCH save_data tests; updated GET save_data tests to source from active slot; updated DELETE tests to assert all slots wiped + active pointer cleared; parsed-roster tests now create slots on OTHER players (not on YOU, per the YOU-card-no-parsed change)
- `test/models/soul_link_emulator_session_test.rb` — removed save_data gzip + parse callback tests (moved to save slot model test); added save_slots association + active_slot resolution tests
- `test/jobs/soul_link/parse_save_data_job_test.rb` — exercises against a slot, not a session
- `test/lib/tasks/emulator_cleanup_test.rb` — seeds slots instead of `save_data:` on session; updated assertions to check `session.save_slots.count` and `active_save_slot`

**Key decisions:**
- Reused `SoulLinkEmulatorSession::GzipCoder` directly via `serialize :save_data, coder: SoulLinkEmulatorSession::GzipCoder` (per brief — no concern extraction yet).
- Added `after_create_commit :enqueue_parse_if_save_present` ALONGSIDE `after_update_commit :enqueue_parse_if_save_changed` on the slot model. The brief only specified after_update_commit, but the controller creates slots via `@session.save_slots.create!(slot_number:, save_data:)` — there is no update event on creation, so without the after_create_commit no parse would fire on the first save into an empty slot. Without it, slot cards would show "no parsed data" until something else triggered a parse. Worth Reviewer's eyes.
- `slot_payload`'s `saved_bytes` calculation: freshly-created records return `ActiveModel::Type::Binary::Data` from `read_attribute_before_type_cast`, not a String. Normalized via `.to_s.bytesize` so the 201-Created JSON response carries the correct on-disk size without forcing a reload.
- Migration: column drops use the type-arg form (`remove_column ..., :type, ...`) so rollback is reversible at the schema level. Brief listed bare `remove_column` — I added types to make a hypothetical `db:rollback` work cleanly (data still lost; matches Project Owner acceptance per brief).
- Run roster sidebar: parsed metadata for other players now sources from their `active_slot` (vs. the old per-session parsed_* columns). The card omits parsed lines when `active_slot` is nil OR has nil parsed fields. The YOU card no longer shows parsed info at all (slot column on the left covers it).
- Stimulus overwrite path: implemented Approach 2 from the brief — slot controller calls `window.EJS_emulator.gameManager.getSaveFile()` at click time to grab fresh SRAM bytes. Stateless; small in-game drift on overwrite-click is documented in the controller comment per brief.
- `_save_slots_sidebar.html.erb` reuses the existing `clear_save_controller` for the Clear-All button. The clear-save controller's DELETE-then-IDB-wipe-then-reload flow is unchanged; only its mount location moved.

**Tests:** 263 → 305 (+42 across model 18, controller 33, session-changes 4, parse job 7 unchanged, plus emulator-controller test rewrites). 0 failures, 0 errors.

**Lint:** `bundle exec rubocop` clean on all 16 touched files.

**Migration verified:** Ran `db:migrate` + `db:rollback` + `db:migrate` cycle in dev. Rollback reverts schema cleanly (data not preserved — accepted). Re-migrate is idempotent.

**Review:** Richard — APPROVED (no Conditions, no Escalations). Verified: migration order + raw-SQL data preservation, authorization scoping at every endpoint via `set_session`, `active_save_slot` consistency across all four mutation paths (create / overwrite / destroy-of-active / restore), Approach 2 stateless overwrite (slot Stimulus calls `gameManager.getSaveFile()` at click time, no JS-side stash), no setInterval/setTimeout re-introduction, layout regression-free.

**Deploy:** GitHub Actions run 25193821050 — test + deploy both succeeded. Migration ran cleanly on prod via the deploy script's `bin/rails db:migrate`; existing 2 saves on prod migrated to slot 1 with `active_save_slot = 1` automatically.

### Step 2 — Auto-Persist In-Game Saves to Server — 2026-04-30
**Status:** Complete, committed `2e9e934`, deployed to `4luckyclovers.com`

**Files modified:**
- `app/javascript/controllers/emulator_controller.js` — re-enabled `_fetchSave()` on `connect()`; added `window.EJS_defaultOptions = { "save-save-interval": "30" }` before loader.js boot; replaced diagnostic `EJS_ready` with: register `saveSaveFiles` listener first, then inject existing save if present, then log `"Emulator: hooks attached"` once with `hasExistingSave`/`hasEmulator` flags; added null/0-byte guard at top of `_uploadSave`; cleared `EJS_defaultOptions` in `disconnect()`. `EJS_onSaveSave` retained (manual export). `_injectExistingSave` body untouched.

**Key decisions:**
- Centralized null/0-byte guard inside `_uploadSave` so both call paths (`EJS_onSaveSave` event payload, `saveSaveFiles` direct bytes) share it. Brief asked for "defensive layering"; placing the guard in the function-under-call makes it impossible to bypass.
- Listener registration ordered BEFORE inject inside `EJS_ready` per the brief's race-condition warning (`gm.loadSaveFiles()` could trigger an auto-save tick between attach points).
- `EJS_defaultOptions` set FIRST in `connect()`, before `EJS_player`/`EJS_gameUrl`/etc. The brief said "before any EJS_* global is set"; obeyed literally to keep the ordering guarantee tight in case loader.js evolves to read globals at any point during script-tag append.

**Tests:** 255/255 pass. No backend change; suite count unchanged from Step 1.

**Lint:** No new Ruby. JS controller has no lint configured (Importmap project, no Node toolchain). Pre-existing rubocop offenses (133 across 127 files) are unrelated; documented previously in Known Gaps.

**Review:** Richard — APPROVED (no conditions, no escalations). All six Architect focus areas verified: listener order in `EJS_ready`, null/0-byte guard centralization, `EJS_defaultOptions` set position, `EJS_onSaveSave` retained, `disconnect()` cleanup, scope discipline (single code file).

**Deploy:** GitHub Actions run 25143303161 — test job 50s (255/255 pass), deploy job 17s (VPS SSH, asset precompile, web + bot service restart). All green.

---

### Step 1 — SRAM Phase 1: Trainer Block Parsing — 2026-04-29
**Status:** Complete, committed `62be21e`

**Files created:**
- `app/services/soul_link/save_parser.rb` — pure parser: slot selection (CRC16-CCITT poly 0x1021, init 0xFFFF, MSB-first), English Gen IV char decode (64 entries, 0xFFFF terminator, 0x0000 skip, U+FFFD fallback), returns nil on any error
- `app/jobs/soul_link/parse_save_data_job.rb` — async parse + `update_columns` write (skips after_update_commit recurse); sets `parsed_at` on both success and failure paths
- `app/helpers/emulator_helper.rb` — `format_play_time` helper
- `db/migrate/20260429215107_*` — 6 new columns on `soul_link_emulator_sessions`

**Files modified:**
- `app/models/soul_link_emulator_session.rb` — `after_update_commit :enqueue_parse_if_save_changed` callback (gated on `saved_change_to_attribute?("save_data")` and non-blank)
- `app/views/emulator/_run_sidebar.html.erb` — 4 new rendered fields gated on column presence; badges line gated on `parsed_trainer_name.present?` (not `parsed_at`) so failed parses don't render "Badges: 0/8"

**Key decisions:**
- Schema columns (Option A) for cached parsing; not on-demand
- English-only char table; Phase 2-5 (party, PC boxes, multi-language, map names) deferred
- Real-save offset verification NOT performed this session — offsets cited from Project Pokemon docs + pret/pokeplatinum + PKHeX (read-only). MAP_ID_OFFSET specifically is a placeholder; `safe_map_id` returns nil on zero so sidebar omits cleanly
- Architect tightened the badges gate from `parsed_at` → `parsed_trainer_name.present?` post-Bob to honor the brief's :failed → "—" contract (parsed_badges defaults to 0, would otherwise render "0/8" on failed parse)

**Tests:** 34 new (18 parser + 7 job + 6 callback + 3 controller); 221 → 255, 0 failures, 4 clean parallel runs.

**Review:** Richard — PASS_WITH_OBSERVATIONS (3 minor: badges gate UX [resolved by Architect inline], off-by-one in Bob's count breakdown [cosmetic], pre-existing rubocop offenses in `delete_rom_file` tests [not introduced by this step]).

**Open Architect rulings (escalated by Richard):**
1. Real-save offset verification still outstanding — Architect ruled "ship as-is" since infra is correct + failure modes honest. Logged as Known Gap below.
2. MAP_ID_OFFSET placeholder — same call.

---

## Known Gaps
*Durable. Items logged here instead of expanding the current step. Persists across sessions until addressed.*

### From earlier work (Evolve Button feature)
- Co-evolution of soul-link partners on evolution (deliberate; revisit if Project Owner wants paired evolution)
- No real-time broadcast of species change to other players' dashboards (they see updates on next refresh)
- No level/method gating on EVOLVE button (always available; player owns in-game timing)
- No loading state on EVOLVE button itself (status text only)

### From the emulator deploy + polish session (2026-04-29)
- **Tier 2 SRAM parsing** for in-game info (character name, time-played, money, party count, current map, badges earned) — separate feature, real engineering effort (Gen IV character set decoder + checksum/slot logic)
- **No automated browser test harness** — smoke tests are manual; Project Owner verifies UI changes
- **`#d4b14a` amber color** for pending-state status badge is inline in `_run_sidebar.html.erb`. If used in a third place, promote to a `--amber` palette token in `pixeldex.css`.
- **Randomizer settings file** (`random_basic_1.rnqs`) is small/basic — heavier randomization (abilities, types-per-move, evolutions) requires re-export from the GUI and re-scp
- **Destructive regenerate** wipes save_data for ready/claimed sessions when status is `:failed`. Acceptable v1 tradeoff; future iteration could selectively preserve `:ready` sessions.
- **`error_message` column at varchar(255)** — widen to text only if real-world stack traces prove limiting
- **Convert legacy fixture-based tests to FactoryBot** — deferred; do not bundle into feature work
- **No real-time updates on the run roster sidebar** — page-load refresh only. Could broadcast on save_data PATCH if live "X just saved" UX is wanted.
- **Channel-layer guild authz cached at login** — if user joins a new guild mid-session without re-logging-in, they won't see it. Acceptable for current use.

### From SRAM Phase 1 (2026-04-29)
- **Real-save offset verification outstanding.** Trainer-block offsets in `SoulLink::SaveParser` cited from Project Pokemon docs + pret/pokeplatinum + read-only PKHeX. Adjust constants if first real save reveals divergence. `MAP_ID_OFFSET = 0x1234` is the least-confident placeholder; `safe_map_id` returns nil on zero so sidebar omits cleanly. When Project Owner has a real `.sav`, verify all 5 fields decode to known values.
- **Pre-existing rubocop offenses** in `test/models/soul_link_emulator_session_test.rb:220, 258` (4 "Use space inside array brackets" inside `delete_rom_file` tests). Not introduced by SRAM work. Clean with `rubocop -a` in a dedicated cleanup step.
- **Phase 2 deferred:** map_id → map name lookup (config/soul_link/maps.yml or similar) so sidebar shows "Eterna City" instead of `426`
- **Phase 3 deferred:** multi-language char tables (Japanese, Korean, etc.); current parser is English-only
- **Phase 4 deferred:** Pokemon party data (encrypted/PRNG-scrambled blocks A-D, requires Pokemon-internal descrambling — significant effort)
- **Phase 5 deferred:** PC boxes (same scrambling as party + box-level layout)

---

## Architecture Decisions
*Durable. Locked decisions that cannot be changed without breaking the system. Persists across sessions.*

### Emulator infrastructure (locked 2026-04-29)
- **In-game SRAM saves are persisted via the `saveSaveFiles` event, NOT `saveSave`.** `saveSave` (loader.js auto-wires `EJS_onSaveSave`) only fires on the manual "Save File" export button. The internal SRAM commit lifecycle uses `saveSaveFiles`, fired by `gameManager.saveSaveFiles()` after every `cmd_savefiles` flush. We register `window.EJS_emulator.on("saveSaveFiles", cb)` inside `EJS_ready` and set `EJS_defaultOptions["save-save-interval"] = "30"` so the auto-save tick covers in-game saves. `EJS_onSaveSave` is retained as belt-and-suspenders for the manual button. Server is the source of truth on load: `_injectExistingSave` runs in `EJS_ready` after the listener is attached. `_uploadSave` short-circuits null / 0-byte payloads — `getSaveFile(false)` returns null pre-first-save, and an empty SRAM PATCH would clobber a real server save.
- **PokeRandoZX must be invoked with `cli` as the first arg after `-jar`.** CLI mode auto-seeds; do NOT pass `-seed`. Without the `cli` subcommand, the JAR launches a Swing GUI which fails on headless servers with `HeadlessException` but exits 0 — silent generation failure.
- **`save_data` column is gzip-compressed** via `SoulLinkEmulatorSession::GzipCoder` (custom serializer). Reads/writes are transparent. Use `read_attribute_before_type_cast("save_data")` for raw compressed bytes (e.g. for size display); regular `save_data` accessor triggers decompression.
- **Inbound PATCH `save_data` is capped at 2MB raw** (`EmulatorController::MAX_SAVE_DATA_BYTES`). Pokemon Platinum SRAM is ~512KB; cap is a generous DoS bound enforced via `request.content_length` check + post-read `bytesize` check.
- **`RunChannel#subscribed`** rejects when `params[:guild_id]` doesn't match `connection.session[:guild_id]`. Single check, applies to every channel action.
- **`RunChannel#generate_emulator_roms` and `#regenerate_emulator_roms`** wrap their idempotency check + enqueue in `run.with_lock` — prevents the channel-layer race where two concurrent clicks both pass `:none` and both enqueue.
- **Subprocess pattern: `Process.spawn` + `waitpid(WNOHANG)` poll loop + TERM→KILL on deadline.** `Open3.capture3 + Timeout.timeout` is banned (raises in calling thread but leaves child Java running — zombie leak).
- **`emulator_session.rom_path` is server-derived** — only ever set by `RomRandomizer` via `Pathname#relative_path_from(Rails.root)` of a path constructed under `OUTPUT_DIR`. Never user input. If a future writer changes this, `EmulatorController#rom`'s `send_file` becomes a file-read-anywhere primitive and needs an explicit `path.start_with?(OUTPUT_DIR)` guard.

### Carried over (still load-bearing)
- Discord user IDs are `bigint` in DB columns, `String` in Stimulus values, coerced at the controller boundary
- All tests use FactoryBot factories from `test/factories/`. Fixtures and the `fixtures :all` test_helper line were removed in Step 8 (2026-04-30).
