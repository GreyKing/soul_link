# Review Request — Step 5: Gym Result: Mark Beaten + Team Snapshot + Backfill
*Written by Builder. Read by Reviewer.*

Ready for Review: YES

---

## Files Changed

### New Files

| File | Lines | Description |
|------|-------|-------------|
| `db/migrate/20260412180452_create_gym_results.rb` | 1-16 | Migration creating gym_results table with run FK, gym_number (unique per run), beaten_at, optional gym_draft FK, JSON team_snapshot. |
| `app/models/gym_result.rb` | 1-49 | GymResult model with validations (gym_number 1-8, unique per run) and three snapshot builder class methods: from_groups, from_draft, from_group_ids. |
| `app/controllers/gym_results_controller.rb` | 1-35 | Backfill controller -- PATCH update accepts group_ids, builds snapshot, saves to existing GymResult. |
| `app/javascript/controllers/gym_backfill_controller.js` | 1-86 | Stimulus controller for backfill picker modal -- grid of selectable group cards (max 6), SAVE/CANCEL, PATCH to GymResultsController, reload on success. All user data via textContent. |

### Modified Files

| File | Lines | Description |
|------|-------|-------------|
| `app/models/soul_link_run.rb` | 7 | Added `has_many :gym_results, dependent: :destroy`. |
| `app/controllers/gym_progress_controller.rb` | 4-29 | Replaced simple counter toggle with GymResult create/destroy + counter sync. Mark creates a GymResult (no snapshot), unmark destroys and recalculates max. |
| `app/controllers/gym_drafts_controller.rb` | 42-89 | Added `@next_gym_number`, `@gym_already_marked`, `@next_gym_info` to show action (inside complete? block). Added `mark_beaten` action that creates GymResult with draft snapshot. |
| `app/controllers/dashboard_controller.rb` | 64-65 | Added `@gym_results` (indexed by gym_number) and `@caught_groups_for_backfill` loading. |
| `config/routes.rb` | 30-34 | Wrapped gym_drafts with `member { post :mark_beaten }`. Added `resources :gym_results, only: [:update]`. |
| `app/views/gym_drafts/show.html.erb` | 153-159 | Added mark beaten button in the complete panel (conditional on next gym available and not already marked). |
| `app/views/dashboard/_gyms_content.html.erb` | 27-84 | Reworked gym leaders list: next gym row has MARK BEATEN button, defeated gyms show team snapshot (if present) or ADD TEAM backfill button (if no snapshot). |
| `app/services/soul_link/game_state.rb` | 48-51 | Added `gym_info_by_number(n)` helper using existing GYM_KEYS lookup. |

---

## Key Decisions

1. **gym_info_by_number**: Added as a 3-line class method on GameState rather than inlining the lookup in views/controllers. Uses existing `GYM_KEYS[n - 1]` pattern.
2. **Counter sync**: GymProgressController now creates/destroys GymResult records and derives gyms_defeated from the max gym_number. This keeps the counter in sync with the source-of-truth GymResult records.
3. **No snapshot from dashboard MARK BEATEN**: The gym progress path (dashboard button) creates a GymResult without a team snapshot -- the user can backfill later. Only the gym draft path captures a snapshot automatically.

## Open Questions

None. Brief was complete and unambiguous.

## Reviewer Fixes Applied

1. **GymDraft `has_many :gym_results`** (`app/models/gym_draft.rb`): Added `has_many :gym_results, dependent: :nullify` so the inverse of `GymResult.belongs_to :gym_draft` is declared and Rails can manage the association properly.
2. **Only allow unmark of highest gym** (`app/controllers/gym_progress_controller.rb`): Unmark branch now checks that the gym_number equals the highest completed gym before destroying. Returns 422 if trying to unmark a gym that is not the most recent.
3. **RecordNotUnique rescue in mark_beaten** (`app/controllers/gym_drafts_controller.rb`): Added `rescue ActiveRecord::RecordNotUnique` to handle the race condition where two requests try to mark the same gym simultaneously -- the DB unique index catches the duplicate and the user sees a friendly alert.

## Known Gaps

- `mise exec --` bundler shim resolves to Ruby 3.0.6 instead of 3.4.5. Migration was run using direct binary path. Local environment issue only -- does not affect deployment.
