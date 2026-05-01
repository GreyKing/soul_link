# Review Request
*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

Ready for Review: YES

---

## Step 4 — Build All Missing FactoryBot Factories

**Builder:** Bob
**Tests:** 305/305 passing, 0 failures, 0 errors (unchanged from Step 3 — purely additive step)
**Lint:** `bundle exec rubocop` clean on all 6 new files
**Smoke check:** `/tmp/factory_smoke.rb` runner constructs one record per factory and trait (32 records total), asserts field-by-field match against fixture data, all green

---

## Files Changed

### Created (6 files, all under `test/factories/`)

| Path | Lines | Purpose |
|------|-------|---------|
| `test/factories/soul_link_pokemon_groups.rb` | 1-37 | Base factory + 6 traits (`:route201`–`:route206`); `after(:create) update_columns` overrides model's `before_create` callbacks to lock `position` + `caught_at` to fixture values |
| `test/factories/soul_link_pokemon.rb` | 1-54 | Base factory + 24 metaprogrammed traits (`:routeN_<player>` for 6 routes × 4 players); per-iteration variable capture avoids late-binding closure bug |
| `test/factories/soul_link_teams.rb` | 1-14 | Base factory with `discord_user_id` sequence (uniqueness scope) + `:grey_team` trait |
| `test/factories/soul_link_team_slots.rb` | 1-17 | `:slot_1` / `:slot_2` traits only; no association defaults — caller passes `soul_link_team:` + `soul_link_pokemon_group:` |
| `test/factories/gym_drafts.rb` | 1-24 | Base factory + `:lobby` trait, both pinning JSON state to match `lobby_draft` fixture |
| `test/factories/gym_results.rb` | 1-15 | Base factory only (fixture is empty); `gym_number` sequence cycles 1..8 to dodge per-run uniqueness |

### Modified (0 app/test files)

Per the brief, Step 4 is purely additive. Fixtures (`test/fixtures/*.yml`) untouched. Test files untouched (Step 5 converts them). App code untouched.

### Modified (handoff)

- `handoff/ARCHITECT-BRIEF.md` — Architect already overwrote this with Step 4 brief at session start
- `handoff/BUILD-LOG.md` — Step 4 history entry appended (this commit)
- `handoff/REVIEW-REQUEST.md` — this document

---

## Self-Review

### What would Reviewer most likely flag?

1. **Pokemon factory's metaprogramming closure-capture pattern.** I capture `trait_species`, `trait_uid`, `trait_location` into local variables BEFORE entering the `trait` block. Without this, every generated trait would resolve to the LAST loop iteration's `route`/`player` values (Ruby late-binds block-level variables to the enclosing scope, but `each` rebinds the block parameter on each call — so iterating through `route` and `player` works correctly, but referencing `route[:species][idx]` inside the trait would re-evaluate `idx` at trait-execution time). The local-variable capture defensively pins the values at definition time. Verified via the smoke script: each trait produces the right species/uid/location.

2. **`update_columns` in the group factory's `after(:create)` hook.** The model has `before_create :set_position` (writes `max + 1`) and `before_create :set_caught_at` (writes `Time.current`). The fixture's hardcoded `position: 1` and `caught_at: <%= 6.days.ago %>` bypass these callbacks because fixtures use raw SQL INSERT. To reproduce this in a factory, I run `update_columns` (which also skips callbacks + validations) inside `after(:create)` to overwrite the values the `before_create` callbacks just set. Cleaner alternative would be `to_create { |r| r.save(validate: false) }` + skipping callbacks — but that requires more surgery and doesn't expose intent as cleanly.

3. **Gym draft `:lobby` trait duplicates base factory attributes.** Brief said "the `:lobby` trait pins those values explicitly to keep the trait's intent self-documenting." Followed verbatim. Reviewer may flag this as redundant; the rationale is that Step 5 conversions will write `create(:gym_draft, :lobby)` which surfaces the lobby intent at the call site even though the trait body matches the default.

4. **`soul_link_team_slot` has no association defaults.** Brief decision. Calling `create(:soul_link_team_slot, :slot_1)` without `soul_link_team:` / `soul_link_pokemon_group:` will fail with `must exist` validation errors — that's intentional per the spec (`Tests construct create(:soul_link_team_slot, :slot_1, soul_link_team: t, soul_link_pokemon_group: g)`). If Reviewer prefers defaulted associations, they would create stray records that don't connect to test setup; the brief's pattern is the correct one.

5. **`gym_result.gym_number` modulo-8 sequence.** Strictly only `inclusion: { in: 1..8 }` is required. A sequence that wraps modulo 8 lets a single test create up to 8 results per run before colliding on `(soul_link_run_id, gym_number)`. Brief didn't specify the exact sequencing — I picked the wrap because Step 5 may convert tests that walk through all 8 gyms.

### Did every item in the brief ship?

- [x] All 6 factory files exist under `test/factories/`
- [x] `:route201`–`:route206` traits on group factory match fixture (nickname, location, position, caught_at, status)
- [x] 24 traits on pokemon factory using metaprogrammed loop with data table at top of file
- [x] Each pokemon trait sets discord_user_id, species, name (=species), location, status — and does NOT set `soul_link_pokemon_group` association (caller passes it)
- [x] `:grey_team` trait on team factory matches fixture; base uses sequence for uniqueness
- [x] `:slot_1` / `:slot_2` traits on team_slot factory; no association defaults
- [x] `:lobby` trait on gym_draft factory matches fixture state exactly
- [x] gym_result base factory passes validations (gym_number 1..8, beaten_at present)
- [x] All factories produce valid records (smoke-checked via runner)
- [x] 305/305 tests still passing
- [x] `bundle exec rubocop` clean
- [x] No app/test/fixture files touched

### What does the user see if data is empty or a request fails?

N/A — this step adds no user-facing code. The factories are blueprints invoked only from tests. If a future test passes invalid data through a factory, the underlying model validations catch it (factories don't suppress validation errors).

---

## Open Questions / Notes

1. **No factory for `soul_link_emulator_session` traits beyond what's already present** — the existing factory has `:ready` / `:claimed` / `:generating` traits which are sufficient for current tests. Step 5 may surface gaps; out of scope here.

2. **The `:lobby` trait duplicates base factory state** — flagged in self-review #3. If Reviewer wants a leaner approach (drop the trait body and just register `:lobby` as a name), I can refactor — but the brief was explicit that the trait should be self-documenting.

3. **Brief mentioned a `:caught` / `:dead` status split for groups** — actually it didn't; status is always "caught" in the fixture. I considered adding a `:dead` trait for forward compatibility but stayed in scope (brief: "fields the test doesn't need" should be omitted).

4. **No `before(:create)` blocks** — every trait composes via straight attribute assignment + (in one case) an `after(:create) update_columns`. Per brief constraint: "DO NOT use before(:create) unless necessary."

5. **Pokemon factory base default `species` / `discord_user_id` sequences** — included so a bare `create(:soul_link_pokemon)` (without any trait) still produces a valid record. Not strictly required by the brief but it's consistent with the existing factory style and keeps the factory usable in non-trait contexts.

6. **No test files were touched.** Confirmed via `git status` — only `test/factories/*.rb` (new) + `handoff/*.md` (modified) + `.claude/settings.local.json` (session-scoped, gitignored).

---

**Ready for Review: YES**
