# Review Feedback — Step 4
Date: 2026-04-30
Status: APPROVED

## Conditions

None.

## Escalate to Architect

None.

## Cleared

Reviewed Step 4 (Build All Missing FactoryBot Factories) end-to-end: the 6 new factory files, plus the handoff updates. Diff scope matches the brief exactly — only `test/factories/*.rb` (new) and `handoff/*.md` (updated). No app/test/fixture files touched.

Verifications performed (independently of Bob's claims):

- **Trait-name → fixture-name correspondence (Architect focus #1).** Cross-walked each trait against its fixture row:
  - Group fixtures: `group_route201..group_route206` (ROY/TOMMY/RACHEL/SPIKE/LUNA/BLAZE, positions 1-6, caught_at 6..1 days ago) ↔ traits `:route201..:route206` produce identical records (verified via runner: nickname, location, position, caught_at all match).
  - Pokemon fixtures: 24 entries `pkmn_route20N_<player>` (4 players × 6 routes) ↔ traits `:route20N_<player>`. Player IDs verified (Grey 153665622641737728, ARatypuss 600802903967531093, Scythe461 189518174125817856, Zealous 182742127061630976). Species per route × player verified against the fixture's ERB grid. discord_user_id, species, name (=species), location, status all match.
  - Team fixture: `grey_team` (uid 153665622641737728) ↔ trait `:grey_team` matches.
  - Team slot fixtures: `grey_slot_1` (position 1), `grey_slot_2` (position 2) ↔ traits `:slot_1`, `:slot_2` match. No association defaults; caller passes team + group as documented.
  - Gym draft fixture: `lobby_draft` (status "lobby", round 0, player_index 0, empty arrays in JSON) ↔ trait `:lobby` produces matching state_data exactly: `{ "ready_players" => [], "first_pick_votes" => {}, "picks" => [] }` and `pick_order: []`.
  - Gym result fixture: empty (commented placeholder). The base factory provides minimum-valid defaults (gym_number 1..8, beaten_at present); produces persistable records.

- **Pokemon factory metaprogrammed traits (Architect focus #2).** Trait names follow `:route<N>_<player_lowercase>` exactly (`:route201_grey`, `:route201_aratypuss`, `:route201_scythe461`, `:route201_zealous`, …, `:route206_zealous`). Closure-capture pattern is correct: `trait_species`, `trait_uid`, `trait_location`, `trait_name` are pinned to local variables INSIDE the inner loop body BEFORE entering the `trait` block, so each generated trait closes over its own bindings — no late-binding bug where every trait would resolve to the final iteration. Verified via the smoke runner: 24 distinct species/uid/location combinations, no two traits collide.

- **Validations satisfied (Architect focus #3).** Smoke runner constructed one record per factory (32 records total) and asserted `valid?` + presence/correctness of model-required fields. Group factory's `before_create :set_position`/`set_caught_at` are correctly overridden by the trait's `after(:create) update_columns(position:, caught_at:)`. Pokemon factory's base provides `species`/`name`/`location`/`discord_user_id` defaults so a bare `create(:soul_link_pokemon)` (no trait) still passes `species` (when group is bound), `name`, `location`, `discord_user_id` presence + uniqueness scoped to group. Team factory's `discord_user_id` sequence dodges the `(run_id, discord_user_id)` uniqueness constraint. Team slot factory has no defaults — caller-required associations confirmed by the smoke runner's explicit `soul_link_team:` + `soul_link_pokemon_group:` keyword args. Gym draft `:lobby` trait satisfies `inclusion: %w[lobby voting drafting nominating complete]`. Gym result `gym_number` modulo-8 sequence + `beaten_at: Time.current` satisfies presence + inclusion + uniqueness.

- **No test-file changes (Architect focus #4).** `git status` shows untracked `test/factories/*.rb` only — fixtures, model tests, controller tests, channel tests untouched. Step 5 will convert tests; Step 6 deletes fixtures. The hybrid suite contract (legacy fixture-based tests + new factory tests) holds.

- **Style consistency (Architect focus #5).** All 6 new factories follow the same pattern as the existing 3 (`soul_link_runs.rb`, `soul_link_emulator_sessions.rb`, `soul_link_emulator_save_slots.rb`): top-of-file frozen-string magic comment NOT present (existing factories also omit), `FactoryBot.define do ... end`, `factory :name do ... end`, `association :foo`, traits as `trait :name do ... end`. The Pokemon factory's metaprogramming is the only divergence — justified by the 24-trait scale and explicitly encouraged by the brief. Data tables hoisted to top of factory file (constants), mirroring the fixture's ERB shape. No `before(:create)` blocks anywhere. The one `after(:create)` on the group factory is the documented exception for the `before_create` callback override.

- **Pokemon factory base-vs-trait association split (Architect focus #6).** Base factory has `association :soul_link_pokemon_group` (and `association :soul_link_run`). The 24 traits do NOT override `soul_link_pokemon_group` — they only set `discord_user_id`, `species`, `name`, `location`, `status`. Confirmed by reading every trait body. When a test calls `create(:soul_link_pokemon, :route201_grey, soul_link_pokemon_group: groups[0])`, the explicit kwarg overrides the base default; when a test omits the kwarg, the base default builds a fresh group (acceptable for tests that don't care about group identity). The brief's contract is preserved.

- **`update_columns` callback bypass (group factory).** Verified by reading the model: `before_create :set_position` writes `max + 1`, `before_create :set_caught_at` writes `Time.current`. Without the trait's `after(:create) update_columns(...)`, calling `create(:soul_link_pokemon_group, :route201)` followed by `:route202` would produce positions [1, 2] (matching fixture by accident on a fresh run) but `caught_at` would be `Time.current` for both — diverging from the fixture's `6.days.ago` / `5.days.ago`. The `update_columns` correctly pins both fields. Verified via the smoke runner: position matches the trait's spec value, not the auto-incremented value, and caught_at is in the past.

- **`gym_result.gym_number` modulo-8 sequence.** Verified `((n - 1) % 8) + 1` produces 1, 2, 3, …, 8, 1, 2, … — first 8 calls cycle through 1..8 distinct values, satisfying the per-run uniqueness constraint. Bob's design choice accepts collision on the 9th call within the same run; given that no current or imminent test scenario creates more than 8 results per run, this is fine.

- **Gym draft `:lobby` trait redundancy.** The `:lobby` trait body mirrors the base factory attributes exactly (status, round, player_index, pick_order, state_data). The model's `after_initialize :set_defaults` would also populate `state_data` and `pick_order` on `new` if not provided, so technically the base could omit those two attrs and let the callback fill them in. Bob's explicit pinning makes the trait self-documenting per the brief's instruction. Acceptable.

- **`soul_link_team_slot` no-defaults pattern.** Confirmed: the factory body has only `trait :slot_1` and `trait :slot_2`, no top-level `association` calls. `create(:soul_link_team_slot, :slot_1)` without explicit `soul_link_team:` and `soul_link_pokemon_group:` kwargs will fail with `Soul link team must exist` and `Soul link pokemon group must exist`. This is by design per the brief and is what tests will provide via local variables.

- **Tests** — ran `bin/rails test` locally: **305 runs, 0 failures, 0 errors** (matches Bob's claim; baseline preserved since the factories are inert until tests reference them).

- **Rubocop** — ran `bundle exec rubocop` on all 6 new factory files locally: **clean** (matches Bob's claim).

- **Smoke runner** — re-ran `/tmp/factory_smoke.rb` independently: all 32 trait records constructed successfully and matched their fixture counterparts field-by-field. The runner is the empirical proof that the trait-name correspondence is exact.

Bob built exactly what the brief specified. The five flagged self-review items (closure capture, `update_columns` rationale, `:lobby` trait redundancy, no-defaults on team slot, modulo-8 gym_number) are all well-reasoned and consistent with the brief. No deviations from the brief in the diff. Ships as-is.
