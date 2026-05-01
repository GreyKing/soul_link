# Project Review — 2026-04-30
*Architect-mode diagnostic pass. Soft points + Knowledge Gaps + UI/UX quick wins.*
*Worktree at `64364d9` (post-Step-8). Diagnostic only — nothing implemented.*

This is a project-wide audit, not a step. Items below are ranked by ROI (impact / effort) within each section. Each entry has a file:line ref, 1-2 sentence diagnosis, and a 1-line fix proposal. The Project Owner picks what to act on.

---

## § Soft Points / Risk Surfaces

### Tier 1 — Structural risks (worth scheduling work for)

1. **`app/services/soul_link/discord_bot.rb` is a 978 LOC god object.** Holds bot setup, slash commands, modal handlers, button handlers, embed builders, and panel-update logic — 11 separate `rescue => e` blocks suggest the surface area exceeds what one class can keep coherent. **Fix:** carve out `DiscordBotEventRouter` (handler dispatch) + `DiscordBotEmbedBuilder` (UI construction). Tests don't exist for this file at all — extracting will let the carved-out classes get unit tests.

2. **No tests for `discord_bot.rb`, `discord_api.rb`, `type_chart.rb`, `game_state.rb`, `run_channel.rb`, `gym_schedule_channel.rb`.** The recent FactoryBot conversion (Steps 4-8) tightened model/controller coverage, but services + channels are uncovered. Highest-risk gap: `discord_bot.rb` (28KB, runs as a separate process, hardest to verify in production). **Fix:** start with a thin smoke test per channel (subscribe + perform happy-path), then expand to type_chart and game_state which are pure-function-friendly.

3. **`SoulLinkRun.current(guild_id)` is a soft invariant, not a hard one.** Multiple `active: true` runs per guild are allowed by validations; only `(guild_id, run_number)` is unique. The Step 6 fixture-coexistence problem was a manifestation of this — the same root cause could bite again in any path that calls `current(guild_id)`. **Fix:** add `validate :only_one_active_per_guild`, or a partial unique index on `(guild_id) WHERE active = true` (MySQL 8 supports this via generated column).

4. **`DashboardController#show` is doing the work of a presenter.** [app/controllers/dashboard_controller.rb:5-84](app/controllers/dashboard_controller.rb:5) sets up 18 ivars, makes 5+ calls into `SoulLink::GameState`, computes type analysis, gym progression, calculator quick-pick, and PC-box categorization — all in one action. Hard to test, hard to extend. **Fix:** extract a `DashboardPresenter` (or `DashboardViewModel`) that the action instantiates with `@run`; ivars become methods.

5. **`SoulLinkEmulatorSession::GzipCoder` is a nested module used by another model.** [app/models/soul_link_emulator_session.rb:25-50](app/models/soul_link_emulator_session.rb:25). `SoulLinkEmulatorSaveSlot` reaches into `SoulLinkEmulatorSession::GzipCoder` to serialize its own bytes. Step 3 brief deferred extraction; this is the deferred refactor. **Fix:** move to `app/models/concerns/gzip_coder.rb` and update both models. Trivial mechanical change.

6. **`DashboardController#current_run` and 6+ other controllers duplicate the same private method.** Every controller that needs the run does `guild_id = session[:guild_id]; SoulLinkRun.current(guild_id)`. **Fix:** extract a `CurrentRun` controller concern (already a `app/controllers/concerns/` directory exists) with `before_action :load_current_run`.

### Tier 2 — Concurrency / hot paths

7. **Channel `.reload` pattern is repetitive defensive code.** [app/channels/gym_draft_channel.rb:13,21,29,37,45,53,63](app/channels/gym_draft_channel.rb:13) — 7 methods each call `.reload` before mutating, then `broadcast_state` calls `.reload` again. The double-reload is both wasteful and a smell that the state machine isn't transactionally hardened. Same pattern in [gym_schedule_channel.rb:13,22,32](app/channels/gym_schedule_channel.rb:13). **Fix:** wrap each mutation in `with_lock { ... }` or `transaction { ... }`; one reload per request, drop the second.

8. **`type_chart.rb:88,96` calls `GameState.types_for(species)` in a tight loop.** Every call hits the YAML-loaded pokedex; for a 6-pokemon team that's 6 hash lookups, but for run-wide analyses it's worse. **Fix:** load `all_types = SoulLink::GameState.pokemon_types` once, look up via `all_types[species]` in the loop.

9. **`SoulLinkRun.current` gets called on every channel action AND most controller paths.** The query is well-indexed on `(guild_id, active)`, so DB-side fine, but the call-site duplication (point #6) is what costs. **Fix:** memoize per-request in `ApplicationController`'s concern.

10. **Run-channel idempotency uses row-lock, not advisory.** [app/channels/run_channel.rb:86](app/channels/run_channel.rb:86) — `run.with_lock` then re-check `emulator_status == :none`; comment notes advisory locks would be slower. Under high contention (4 players spam-clicking generate), check-then-enqueue can race if a job lands between unlock and enqueue. **Fix:** add `enqueued_at` column to `soul_link_runs`; check that column under the lock instead of `emulator_status`.

### Tier 3 — Cross-cutting

11. **`PokemonGroupsController#destroy` has no per-user authz.** [app/controllers/pokemon_groups_controller.rb:122-136](app/controllers/pokemon_groups_controller.rb:122) — any logged-in player in the guild can destroy any group. For 4 trusted friends this is fine, but there's no audit trail and no "who deleted X" record. **Fix:** add `created_by_id` and `deleted_by_id` columns, set them from `current_user_id`. Pure logging, no behavior change.

12. **`PokemonGroupsController#create` returns HTTP 207 Multi-Status for partial success.** [app/controllers/pokemon_groups_controller.rb:46](app/controllers/pokemon_groups_controller.rb:46). This is a JSON API, not WebDAV — frontends rarely handle 207 cleanly. **Fix:** always return 200 with a `{status, group_id, errors}` shape; let JS dispatch on the `errors` array.

13. **`game_state.rb` uses `YAML.load_file` on config files.** [app/services/soul_link/game_state.rb:17-134](app/services/soul_link/game_state.rb:17). Files are project-trusted today, but `YAML.load_file` instantiates arbitrary Ruby objects — if cheats config is ever editable from a less-trusted path (Discord input?), it's a vector. **Fix:** `YAML.safe_load(File.read(path), permitted_classes: [Symbol])`.

14. **`game_state.rb:137` defines `reload!` but nothing ever calls it.** No way to invalidate the YAML cache without a process restart. **Fix:** add `rake soul_link:reload_config` task; if Discord config changes mid-run (e.g., player joins), this becomes critical.

15. **`rom_randomizer.rb` truncates error messages to 255 chars silently.** [app/services/soul_link/rom_randomizer.rb:209,225](app/services/soul_link/rom_randomizer.rb:209). Java OOM stacktraces get cut off mid-sentence; user sees "[Java exception class na" with no clue what to do. **Fix:** truncate with `...` marker; log full message to `Rails.logger` server-side.

16. **`discord_api.rb:42` swallows JSON::ParserError silently.** `body = JSON.parse(...) rescue {}` — Discord API returning malformed JSON looks identical to a 200 with empty body. **Fix:** `rescue JSON::ParserError => e; Rails.logger.error(...)` before fallback.

### Tier 4 — Smaller items

17. **`save_parser.rb:153` has a `rescue StandardError => nil` fallback path with zero test coverage.** [app/services/soul_link/save_parser.rb:153](app/services/soul_link/save_parser.rb:153). Existing tests cover the happy path; a regression in the fallback would be invisible. **Fix:** add `assert_nil SaveParser.parse("garbage")` and `assert_nil SaveParser.parse(bad_crc)` tests.

18. **`MAP_ID_OFFSET = 0x1234` is a documented placeholder.** [app/services/soul_link/save_parser.rb](app/services/soul_link/save_parser.rb), already a Known Gap. Listed below in § Knowledge Gaps for ROI ranking.

19. **`discord_bot.rb:790-954` has a fragile modal-event-extraction routine** that tries 3 different `event.*` paths because discordrb's API isn't documented for which event type uses which. Defensive code, but masks gem-version drift. **Fix:** extract to `DiscordBotEventParser` with named methods per event type; add tests stubbing each event class.

20. **Controllers do not consistently use the same auth concern.** Most use `before_action :require_login` from `DiscordAuthentication` concern, but some (e.g., `RunsController` is 16 lines) just rely on routes. Audit for any unprotected endpoints. **Fix:** grep `app/controllers/*.rb` for actions without `before_action :require_login`; whitelist intentionally-public routes.

---

## § Knowledge Gaps Review (per `handoff/BUILD-LOG.md` § Known Gaps)

The canonical list is in [handoff/BUILD-LOG.md](handoff/BUILD-LOG.md) § Known Gaps — 17 items across three origin sessions. Ranked here by **ROI for closing**, with explicit flags for ones that **unlock UI/UX improvements**.

### High-ROI gaps to close (≤2 hours each, meaningful UX impact)

| # | Gap | UX impact | Effort | Fix sketch |
|---|---|---|---|---|
| KG-1 | **No real-time updates on run roster sidebar** | 🔥 unlocks "X just saved" / "X caught Pokemon" live UX | ~1h | Hook a turbo_stream broadcast on `SoulLinkEmulatorSaveSlot.after_update_commit`; client morphs the corresponding `<li>` |
| KG-2 | **No real-time broadcast of species change to other players' dashboards** | 🔥 huge for the 4-player workflow | ~1h | Same pattern: turbo_stream on `SoulLinkPokemon.after_update_commit`, target the dashboard's player-grid partial |
| KG-3 | **No loading state on EVOLVE button** | medium — current "status text only" feels broken on slow networks | ~15min | Add `data-disable-with` (Turbo) or Stimulus `disabled` toggle on click |
| KG-4 | **`#d4b14a` amber color inline in run-sidebar** | low UX, but high cleanup ROI | ~10min | Promote to `--amber` palette token in `pixeldex.css`; replace ~3 inline usages |
| KG-5 | **Pre-existing rubocop offenses** (133 across 127 files) | none directly, but trivial cleanup unlocks "rubocop clean" CI gate | ~30min | `bundle exec rubocop -A` in a dedicated PR; review the auto-fixes |
| KG-6 | **Map ID → name lookup (Phase 2 SRAM)** | 🔥 sidebar shows "Eterna City" instead of `426` | ~1h | Build `config/soul_link/maps.yml` (Gen IV map IDs are well-documented); hook into `SaveParser`'s parsed_map_id rendering |

### Medium-ROI gaps (close when convenient)

| # | Gap | Notes |
|---|---|---|
| KG-7 | **Real-save offset verification outstanding** (SRAM Phase 1) | Needs Project Owner to provide a real `.sav` to compare; pure validation work, ~30min once a sample exists |
| KG-8 | **Channel-layer guild authz cached at login** | Mid-session guild change is unsupported; same root issue as Soft Point #3 (no hard "one active per guild") — fix that and this becomes simpler |
| KG-9 | **`error_message` column at varchar(255)** | Widen to `text` only when prod stack traces prove limiting; current SRAM Phase 1 logs already get truncated per Soft Point #15 |
| KG-10 | **Destructive regenerate wipes save_data on `:failed` sessions** | Acceptable v1; revisit when Project Owner has real saves on non-:ready sessions to preserve |

### Low-ROI / deferred (intentionally parked)

| # | Gap | Why parked |
|---|---|---|
| KG-11 | **Co-evolution of soul-link partners** | Deliberate game-design decision; Project Owner hasn't requested |
| KG-12 | **No level/method gating on EVOLVE button** | "Player owns in-game timing" — design choice |
| KG-13 | **Tier 2 SRAM parsing** (party count etc.) | Real engineering effort; covered by SRAM phases 4-5 below |
| KG-14 | **Phase 4 deferred: Pokemon party data** | Encrypted/PRNG-scrambled; significant Pokemon-internals work |
| KG-15 | **Phase 5 deferred: PC boxes** | Same scrambling complexity |
| KG-16 | **Phase 3 deferred: multi-language char tables** | Not blocking — project is English-only |
| KG-17 | **No automated browser test harness** | Manual smoke tests work for 4-player project; add Playwright only if regressions become a problem |
| KG-18 | **Randomizer settings file is basic** | Re-export from GUI when richer randomization is wanted |

### Synthesis: "Cheapest closes that unlock UX"

The biggest UX wins for the smallest effort are **KG-1 + KG-2** (real-time roster + species broadcasts) and **KG-6** (map-ID lookup). Together: ~3 hours, dramatically improves the 4-player live-collaboration feel.

**KG-3 + KG-4** are 25-minute polish items.

**KG-5** (rubocop sweep) is mechanical and unblocks future CI gating. Worth doing in its own PR.

---

## § UI/UX Quick Wins

Ranked by ROI. All items target <1 hour of work. Items marked 🚨 are data-integrity / "user is confused or losing work" — fix first.

### Tier A — 🚨 Data integrity / silent failure

1. **🚨 `save_slots_controller.js:54,75,142` silently `console.error`s on slot DELETE/PATCH failure.** [app/javascript/controllers/save_slots_controller.js](app/javascript/controllers/save_slots_controller.js). For a Nuzlocke (permadeath) run, a silent save-slot failure can lose a save the player thinks landed. **Fix:** `window.alert("Save slot operation failed. Try again or contact the run creator.")` on all error branches; ~5 min.

2. **🚨 Gym draft ActionCable errors silent.** [app/javascript/controllers/gym_draft_controller.js:41](app/javascript/controllers/gym_draft_controller.js:41) — `if (data.error) { console.error(...) ; return }`. Voting/picking is competitive; silent rejection breaks trust. **Fix:** call `this.showError(data.error)` (pattern already exists in `run_management_controller.js`).

3. **🚨 `team_builder_controller.js:72,85,89,92` writes Tailwind classes (`text-yellow-400` etc.) to a save-status element, but the project uses `pixeldex.css` not Tailwind utilities.** Save status is invisible. **Fix:** replace with pixeldex CSS classes (`color: var(--accent-yellow)` etc.); ~10 min.

4. **🚨 Save-slot action buttons remain clickable during overwrite-pending mode.** [app/views/emulator/_save_slots_sidebar.html.erb:111-127](app/views/emulator/_save_slots_sidebar.html.erb:111). User can accidentally Delete a slot while trying to Overwrite a different one. **Fix:** toggle `disabled` on Download / Make Active / Delete during overwrite mode via Stimulus class binding; ~15 min.

5. **🚨 Pokemon modal SAVE button doesn't disable during in-flight request.** [app/views/dashboard/_pokemon_modal.html.erb:113](app/views/dashboard/_pokemon_modal.html.erb:113). User can submit twice; last write wins (race). **Fix:** add `disabled` toggle in `pixeldex_controller.js#savePokemon`; ~15 min.

### Tier B — UX clarity / button states

6. **Gym draft action buttons (READY / VOTE / PICK / NOMINATE) don't disable during ActionCable round-trip.** [app/javascript/controllers/gym_draft_controller.js:59-79](app/javascript/controllers/gym_draft_controller.js:59). Spam-clicks possible. **Fix:** `event.currentTarget.disabled = true` at start of each action; re-enable on next `render()`; ~15 min.

7. **Cancel button styled with `opacity: 0.6` makes it look disabled.** [app/views/gym_schedules/show.html.erb:66](app/views/gym_schedules/show.html.erb:66). UX anti-pattern (looks disabled but isn't). **Fix:** drop the inline `opacity` style; ~1 min.

8. **`run_management_controller.js:50` error messages don't auto-dismiss.** [app/javascript/controllers/run_management_controller.js:50](app/javascript/controllers/run_management_controller.js:50). Stale error sticks around forever. **Fix:** add `setTimeout(() => this.clearError(), 8000)` (pattern already in gym_draft_controller); ~5 min.

9. **No empty state for gym drafts when no draft exists.** [app/views/gym_drafts/show.html.erb](app/views/gym_drafts/show.html.erb). Page renders blank. **Fix:** add a "No draft started — CREATE DRAFT" card; ~10 min.

10. **Gym schedule form vanishes silently when a schedule already exists.** [app/views/gym_schedules/index.html.erb:7-18](app/views/gym_schedules/index.html.erb:7). Users think the UI is broken. **Fix:** add an `<%= else %>` block: "A schedule is already active — see below."; ~5 min.

11. **No "no species assigned yet" placeholder on group cards.** [app/views/species_assignments/](app/views/species_assignments/). Empty group looks like a bug. **Fix:** if `group.soul_link_pokemon.empty?`, render `<span style="color: var(--d2);">No species assigned yet</span>`; ~5 min.

### Tier C — Accessibility

12. **Form label not associated with input.** [app/views/gym_schedules/index.html.erb:12](app/views/gym_schedules/index.html.erb:12) — `<label for="scheduled_at">` exists but the input lacks `id="scheduled_at"`. Screen readers can't link them. **Fix:** add `id: "scheduled_at"` to the input tag; ~1 min.

13. **Avatar alt text is generic "avatar".** [app/views/layouts/application.html.erb:46](app/views/layouts/application.html.erb:46). **Fix:** `alt="<%= current_username %>'s avatar"`; ~2 min.

14. **Modal close buttons (`&times;`) have no `aria-label`.** Various modals. Screen readers say "X" instead of "Close". **Fix:** add `aria-label="Close modal"` to every `.gb-modal-close`; ~5 min total.

### Tier D — Mobile / responsive

15. **Emulator page hardcodes `grid-template-columns: 280px minmax(0, 1fr) 280px`.** [app/views/emulator/show.html.erb:66](app/views/emulator/show.html.erb:66). On a 375px-wide phone, the center canvas is negative-width. **Fix:** wrap the column rule in `@media (min-width: 900px) { ... }`; below 900px, stack vertically with `grid-template-columns: 1fr`; ~10 min.

16. **Save-slot operations hard-reload the page (`window.location.reload()`).** [app/javascript/controllers/save_slots_controller.js:78,147](app/javascript/controllers/save_slots_controller.js:78). Loses emulator in-memory state, closes any open modal. **Fix:** turbo_stream the slot column on the server side; deletion broadcasts a `replace` to `<turbo-frame id="save-slots">`; ~25 min. (Compounds with KG-1 above — same broadcast plumbing.)

### Tier E — Domain / Nuzlocke-specific

17. **"Mark Dead" uses native `confirm()`.** [app/javascript/controllers/dashboard_controller.js](app/javascript/controllers/dashboard_controller.js). Permadeath in a Nuzlocke is irreversible — generic browser dialog feels insufficient. **Fix:** custom modal showing Pokemon name + sprite + species + "This permanently removes <name> from all teams. Are you sure?"; ~25 min.

18. **PC Box headers ("FALLEN") may confuse new users.** [app/views/dashboard/_pc_box_content.html.erb](app/views/dashboard/_pc_box_content.html.erb). Is FALLEN different from DEAD? **Fix:** add `title="Pokemon that died this run"` tooltip on the FALLEN header; ~3 min.

---

## Recommended sequencing

If the Project Owner wants a single small batch first, I'd ship:
- **All Tier A items (1-5)** — silent-failure fixes, ~50 min total
- **KG-1 + KG-2** (real-time roster broadcasts) — ~2 hours, biggest UX delta
- **KG-3 + KG-4** (loading state + amber token) — ~25 min

That's roughly a half-day of work for a meaningful improvement in trust + collaborative feel.

After that, the Tier-1 soft points (god-object decomposition, presenter extraction, GzipCoder concern) become the natural next investment — pure refactors with no user-visible effect, but they unlock cheaper feature work going forward.

---

*This document is diagnostic only. No code changes were made. Each item is independent — pick whatever the Project Owner is most excited about and run a TMT step on it.*
