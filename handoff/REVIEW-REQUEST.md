# Review Request — Step 4: Test Suite (KG-5)
*Written by Builder. Read by Reviewer.*

Ready for Review: YES

---

## Files Changed

### New Fixture Files

| File | Lines | Description |
|------|-------|-------------|
| `test/fixtures/soul_link_teams.yml` | 1-3 | Grey's team fixture linked to active_run |
| `test/fixtures/soul_link_team_slots.yml` | 1-9 | Two team slots for Grey (groups route201, route202) |
| `test/fixtures/gym_results.yml` | 1 | Empty -- tests create results inline |

### New Test Files

| File | Tests | Description |
|------|-------|-------------|
| `test/models/soul_link_pokemon_test.rb` | 7 | Validation, uniqueness, assign_to_group!, mark_as_dead!, status helpers |
| `test/models/soul_link_pokemon_group_test.rb` | 7 | Validation, species_for, complete?, mark_as_dead! cascade, set_position |
| `test/models/gym_result_test.rb` | 4 | Validation, gym_number range, uniqueness, snapshot_from_groups structure |
| `test/controllers/pokemon_groups_controller_test.rb` | 6 | Auth gate, create (valid/invalid/species), update cascade, destroy |
| `test/controllers/pokemon_controller_test.rb` | 5 | Auth gate, create (valid/duplicate/missing), ownership guard |
| `test/controllers/species_assignments_controller_test.rb` | 5 | Auth gate, show, assign_from_pokedex (valid/duplicate), unassign |
| `test/controllers/teams_controller_test.rb` | 5 | Auth gate, show auto-create, update_slots (valid/overflow/filter), index |

### Modified Files (bug fixes discovered during testing)

| File | Lines | Description |
|------|-------|-------------|
| `test/fixtures/soul_link_pokemon.yml` | 9-28 | Fixed ERB template: fixture names and group references used `route_201` (with underscore) but group fixtures are named `route201` (without). Pokemon were orphaned from their groups. |
| `app/controllers/teams_controller.rb` | 29-32 | Added `.reorder(nil)` before `.distinct.pluck(:id)` -- MySQL rejects DISTINCT with ORDER BY when the ordered column is not in the SELECT list. The `caught_groups` scope adds `order(position: :asc)` which caused the query to fail. |

---

## Test Results

76 runs, 173 assertions, 0 failures, 0 errors, 0 skips (27 existing + 49 new).

---

## Key Decisions

1. **Route name correction**: Brief specified `team_update_slots_path` but `rails routes` outputs `update_slots_team_path`. Used the actual route name.
2. **Fixture name correction**: Brief specified `pkmn_route201_araty` but the fixture template generates `pkmn_route201_aratypuss` (full display_name downcased). Used the actual generated name.
3. **Pokemon fixture fix**: The ERB template interpolated `route_201` into both the fixture key name and group reference, producing `pkmn_route_201_grey` and `group_route_201`. But group fixtures are `group_route201`. Fixed by introducing a `loc_key` mapping that strips the underscore, so references resolve correctly. This was a pre-existing bug: pokemon fixtures had `soul_link_pokemon_group_id` pointing to non-existent groups.
4. **Controller bug fix**: `TeamsController#update_slots` had a MySQL-incompatible query. The `caught_groups` scope adds `ORDER BY position`, and combining that with `.distinct.pluck(:id)` fails on MySQL 8 strict mode. Added `.reorder(nil)` to clear the ordering before the DISTINCT pluck.

## Open Questions

- The pokemon fixture bug was pre-existing (existing GymDraft tests never exposed it because they access groups directly, not through pokemon). The fix changes fixture-generated IDs, which should have no impact since nothing external references them.
