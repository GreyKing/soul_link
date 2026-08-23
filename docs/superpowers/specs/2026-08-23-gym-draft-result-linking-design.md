# Gym Draft → Gym Result Linking

**Date:** 2026-08-23

## Problem

`GymResult` already carries `gym_draft_id` and `team_snapshot`, but only one of
the three "mark gym beaten" paths fills them in:

| Path | Draft linked? |
|------|---------------|
| MARK BEATEN on the draft's complete page (`GymDraftsController#mark_beaten`) | yes |
| Auto-mark from save parsing (`SoulLink::GymBeatenCoordinator.attempt_auto_mark`) | no |
| Dashboard MARK BEATEN (`GymProgressController#update`) | no |

If players complete a draft and the gym is then marked via either of the last
two paths, the gym result has no team recorded.

## Design

Add `GymResult.record_beaten!(run, gym_number, draft: nil)`:

1. Resolve the draft: the explicit `draft:` if given, otherwise the run's most
   recently completed `GymDraft` that has no `GymResult` attached yet
   (`run.gym_drafts.where(status: "complete").where.missing(:gym_results).order(updated_at: :desc).first`).
2. Inside a transaction, `create!` the result with `gym_number`, `beaten_at: Time.current`,
   and — when a draft was found — `gym_draft` and `team_snapshot: GymResult.snapshot_from_draft(draft)`.
3. Bump `run.gyms_defeated` to `max(current, gym_number)`.
4. Return the result.

All three callers use this method. Uniqueness / suppression / all-4 guards stay
in the callers where they live today; the method only owns "create the result
with the right team".

A draft already attached to a result is never reused for a later gym. Manual or
auto marks with no unattached draft behave as today (empty snapshot, editable via
`GymResultsController#update`).

## Testing

- `record_beaten!` links the newest unattached complete draft and snapshots it.
- Skips drafts already attached to a result; ignores non-complete drafts.
- Coordinator auto-mark and `GymProgressController#update` produce a result with
  the draft linked when one exists.
- Existing draft-page `mark_beaten` behaviour unchanged.
