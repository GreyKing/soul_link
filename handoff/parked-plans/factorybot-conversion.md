# Parked Plan — FactoryBot Conversion

Status: **Parked.** Inventory complete. Conversion deferred until SRAM Phase 1 ships.
Origin: Project Owner asked to begin the rewrite on 2026-04-29; chose to ship SRAM Phase 1 first.
Discovery agent run: 2026-04-29.

This document is the single source of truth for the conversion plan. When ready to execute, the Architect should use this to write step-by-step briefs.

---

## Goal

Convert all legacy fixture-based tests to FactoryBot. Hybrid testing convention currently allows new tests to use factories while legacy tests stay on fixtures; this plan eliminates the legacy half.

## Fixture Inventory

| File | Model | Entries | Cross-refs |
|---|---|---|---|
| `soul_link_runs.yml` | `SoulLinkRun` | 1 (`active_run`) | None — root |
| `soul_link_teams.yml` | `SoulLinkTeam` | 1 (`grey_team`) | → `active_run` |
| `soul_link_pokemon_groups.yml` | `SoulLinkPokemonGroup` | 6 (`group_route201`–`group_route206`) | → `active_run` |
| `soul_link_pokemon.yml` | `SoulLinkPokemon` | ~24 ERB-generated (6 routes × 4 players) | → `active_run` + groups |
| `soul_link_team_slots.yml` | `SoulLinkTeamSlot` | 2 (`grey_slot_1/2`) | → `grey_team` + groups |
| `gym_drafts.yml` | `GymDraft` | 1 (`lobby_draft`) | → `active_run` |
| `gym_results.yml` | `GymResult` | 0 (empty) | — |

## Existing Factories

- `test/factories/soul_link_runs.rb` — `SoulLinkRun` with `run_number: 1000+n` sequence (avoids fixture collision)
- `test/factories/soul_link_emulator_sessions.rb` — `SoulLinkEmulatorSession` with `:ready` / `:claimed` / `:generating` traits

**Missing factories:** `SoulLinkPokemonGroup`, `SoulLinkPokemon`, `SoulLinkTeam`, `SoulLinkTeamSlot`, `GymDraft`, `GymResult`.

## Test Files Using Fixtures (47 total fixture-helper calls)

| File | Calls | Notes |
|---|---|---|
| `test/models/soul_link_pokemon_test.rb` | 9 | Heaviest user; refs specific named pokemon |
| `test/models/gym_draft_test.rb` | 8 | 6-group setup; ID assertions on JSON state |
| `test/controllers/gym_drafts_controller_test.rb` | 8 | Mirrors model test patterns |
| `test/channels/gym_draft_channel_test.rb` | 8 | Mirrors model test patterns |
| `test/controllers/pokemon_groups_controller_test.rb` | 3 | Lighter |
| `test/controllers/pokemon_controller_test.rb` | 3 | Lighter |
| 6 other files | mixed | Already partially using factories |

## Cross-Fixture Dependency Tree

```
soul_link_runs (root)
  └── active_run
       ├── soul_link_teams:grey_team
       │    └── soul_link_team_slots (2 slots)
       │         ├── grey_slot_1 → soul_link_pokemon_groups:group_route201
       │         └── grey_slot_2 → soul_link_pokemon_groups:group_route202
       ├── soul_link_pokemon_groups (6 groups: route201–206)
       │    └── soul_link_pokemon (~24 across all groups)
       └── gym_drafts:lobby_draft
```

## Sticky Points (Risks)

### 1. Fixture names hardcoded in tests
- `soul_link_pokemon(:pkmn_route201_grey)` and similar referenced by name in test logic
- Factories must either generate matching trait names OR test setup must be rewritten to use `create()` + local variable refs

### 2. Cardinality assumption in `gym_draft_test.rb`
- Setup assumes exactly 6 groups in routes 201–206 order
- Factory setup must produce 6 groups deterministically OR test must compute 6 explicitly

### 3. ID assertions on fixture-derived state
- `gym_draft_test.rb:99` — `assert_equal @groups[0].id, @draft.picks.first["group_id"]` — relies on draft state matching fixture group IDs
- `gym_draft_test.rb:188` — `assert_equal @groups[4].id, @draft.picks.last["group_id"]` — same
- Fix: make `@groups` an array from factory output; assertions become "first picked group's ID matches first created group's ID" — semantically equivalent

### 4. `soul_link_pokemon.yml` is ERB-generated
- 6 routes × 4 players nested loop
- Factory replacement must preserve the per-route × per-player structure or tests must adjust expectations

## Proposed Conversion Order

### Phase 1 — Build leaf-most factories (1 TMT step)
- `SoulLinkPokemonGroup` factory (simple, single FK to run)
- `SoulLinkTeam` factory (simple)
- `SoulLinkTeamSlot` factory (FKs to team + group)
- `GymDraft` factory (FK to run + JSON state)
- `GymResult` factory (low risk, low usage)
- All factories include traits matching the named fixtures (`:route201`, `:grey_team`, etc.) so test setup can be drop-in

### Phase 2 — Build `SoulLinkPokemon` factory (1 TMT step)
- Most complex: 24 fixture entries with named scoping
- Use traits `:route201_grey`, `:route201_aratypuss`, etc. to mirror fixture names exactly
- Document the trait-naming convention so callers feel familiar

### Phase 3 — Convert model unit tests (1-2 TMT steps)
- `soul_link_pokemon_test.rb` (9 calls — heaviest)
- `gym_draft_test.rb` (8 calls — sticky cardinality)
- `gym_result_test.rb` (already mostly factory-based)
- Per-file: replace fixture helpers with factory traits; ensure same test count + same assertions

### Phase 4 — Convert controller integration tests (1-2 TMT steps)
- `pokemon_controller_test.rb` (3 calls — light)
- `pokemon_groups_controller_test.rb` (3 calls — light)
- `gym_drafts_controller_test.rb` (8 calls — match the patterns from Phase 3 model conversion)

### Phase 5 — Convert channel test (1 TMT step)
- `gym_draft_channel_test.rb` (8 calls)

### Phase 6 — Delete fixtures + sweep (1 TMT step)
- Remove `test/fixtures/*.yml` files (one by one or all at once)
- Run full suite, confirm 221+ pass
- Run 3+ parallel runs for flake check
- Update `CLAUDE.md` Testing conventions section to drop the hybrid note (now: "tests use FactoryBot factories")
- Update `test/test_helper.rb` to drop `fixtures :all` (or scope it tighter)

**Estimated total: 5-7 TMT steps.** Pure mechanical refactor, well-scoped per step. Recommend doing in a focused session with no feature overlap.

## Risk Assessment

**Highest risk:** named fixture references in tests. Phase 2's trait-naming convention is the key — if `create(:soul_link_pokemon, :route201_grey)` builds the same record shape as `soul_link_pokemon(:pkmn_route201_grey)`, conversion is mechanical. If trait names diverge, every test conversion becomes a manual re-write.

**Second risk:** test runtime regression. Fixtures load once per process via transactional fixtures; factories create rows per test. The hybrid suite is fast (1.1s for 221 tests). Pure-factory equivalent could be 1.5-2× slower. Acceptable for a 4-friend project; benchmark before/after to confirm.

**Third risk:** in-flight feature work overlapping. The conversion touches every model that has a fixture — same models touched by SRAM, gym draft updates, etc. Should run as its own session with no parallel feature work.

## Pre-flight Checklist

Before starting Phase 1:
- [ ] Confirm SRAM Phase 1 (and any other in-flight feature) is shipped
- [ ] No active ARCHITECT-BRIEF.md occupied by other work
- [ ] Project Owner explicitly approves "no feature work this session"
- [ ] Run baseline benchmark: `time bin/rails test` — record current suite time
- [ ] Confirm `git status` is clean
