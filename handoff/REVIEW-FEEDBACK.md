# Review Feedback -- Step 5
Date: 2026-04-12
Ready for Builder: NO

## Must Fix

- **app/models/gym_draft.rb** -- GymDraft has no `has_many :gym_results` with `dependent: :nullify`. The migration creates a FK from `gym_results.gym_draft_id` to `gym_drafts.id`. If a GymDraft record is ever destroyed, the FK constraint will raise a database error because the referencing GymResult rows still point to it. Add `has_many :gym_results, dependent: :nullify` to GymDraft so that destroying a draft sets the FK to NULL on associated results rather than blowing up.

- **app/controllers/gym_progress_controller.rb:19** -- Unmark logic uses `run.gym_results.maximum(:gym_number)` to derive the new `gyms_defeated` counter. This creates an inconsistent state when non-sequential gyms exist. Example: gyms 1, 2, 3 are marked, then gym 2 is unmarked via a crafted request. `gyms_defeated` stays at 3. The dashboard renders gym 2 as defeated (because `2 <= 3`) but no GymResult record exists for it -- no snapshot, no backfill button, no way to fix from the UI. Fix: only allow unmarking the highest-numbered gym. If `gym_number != run.gym_results.maximum(:gym_number)`, reject the request. This matches the UI constraint (dashboard only shows MARK BEATEN on the next gym) and prevents gaps.

## Should Fix

- **app/controllers/gym_drafts_controller.rb:92-98** -- `mark_beaten` calls `create!` without rescuing `ActiveRecord::RecordNotUnique`. The unique index on `[soul_link_run_id, gym_number]` will raise this if two requests race past the `exists?` guard at line 86. Wrap in a `rescue ActiveRecord::RecordNotUnique` that redirects with a notice instead of producing a 500.

- **app/controllers/gym_drafts_controller.rb:63** -- `@next_gym_number` is `run.gyms_defeated + 1`, which is 9 when all 8 gyms are beaten. The view guards with `@next_gym_number.between?(1, 8)` so the button hides correctly and `@next_gym_info` ends up nil harmlessly. No bug, but assigning `@next_gym_info` only when `@next_gym_number <= 8` avoids the unnecessary nil lookup and makes intent clearer.

- **app/views/dashboard/_gyms_content.html.erb:55-89** -- The view assumes every defeated gym has a GymResult record. If a defeated gym somehow lacks a result (e.g., the gap scenario from the Must Fix above, or a manually deleted record), nothing renders for that gym's detail row -- no snapshot, no backfill, no error. After the Must Fix for GymProgressController is resolved this edge case becomes unreachable from the UI, but a defensive `else` clause rendering a simple dash or "no data" would be more robust.

## Escalate to Architect

- None.

## Cleared

Migration (correct schema, unique composite index, nullable gym_draft FK). GymResult model (snapshot builders properly scope to run, include pokemon, use `to_s` on discord_user_id for JSON safety). GymResultsController (auth via require_login, scoped to current_run, group_ids capped at 6, snapshot scoped to run's own groups). gym_backfill_controller.js (all user data rendered via textContent, no innerHTML, max 6 selection enforced, CSRF token passed). SoulLinkRun `has_many :gym_results, dependent: :destroy` (correct). DashboardController (gym_results indexed by gym_number, caught_groups loaded with includes). Routes (member post for mark_beaten, resources for gym_results update-only). Gym draft complete panel view (ERB auto-escapes, button conditional correct, button_to generates proper form). GameState `gym_info_by_number` (3-line helper using existing GYM_KEYS, bounds-checked).
