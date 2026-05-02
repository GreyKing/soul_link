# Review Feedback — Step 14
Date: 2026-05-01
Ready for Builder: YES

## Must Fix

None.

## Should Fix

- `test/models/gym_draft_test.rb:405` — The test name says
  "broadcast_state stores voter ids as integers in state_data" but the
  body asserts directly on `@draft.candidates.first["voters"]`, not on
  the `broadcast_state` payload. The assertion is correct and useful
  (it pins the underlying storage shape — broadcast_state is what
  stringifies for the wire), but the name reads as if it inspects
  `state[:candidates]`. Recommendation: rename to
  "voter ids are stored as Integers in state_data," or move the
  assertion onto `broadcast_state`. Inline-fix scale; not blocking.

- `app/models/gym_draft.rb:191` — `nominate!` does
  `next_index = current_player_index + 1` without a `% pick_order.size`
  wrap, unlike `skip_turn!` at line 248 which does wrap. Today this is
  safe: the resolve branch fires at exactly `pick_order.size` picks, and
  `current_nominator_id` (line 79) reads with modulo so the unwrapped
  index is never observed. Worth flagging because a future mid-flow
  change could expose it. Recommendation: wrap with `% pick_order.size`
  here too for symmetry, or pin the invariant with an inline comment.

## Escalate to Architect

None.

## Cleared

All 17 reviewer focus areas pass:

1. Tally walked through `resolve_nominations!` for 3/1, 2/2, 2/1/1,
   1/1/1/1, and 4/0; each split has a dedicated test
   (`gym_draft_test.rb:220-311`) that asserts the expected `tiebreak`
   payload (or its absence). The greedy-fill `same_count_group` loop
   classifies "n_way" vs "second_place" correctly via
   `same_count_group.size == cands.size`.
2. `tiebreak.winners` is set server-side in `resolve_nominations!:348`
   via `same_count_group.shuffle.first(remaining_slots)`. The Stimulus
   controller (`gym_draft_controller.js:435-457`) reads it for display
   text only — never picks winners.
3. Zero `current_nomination` references survive in `app/`. The only
   surviving hits are the cleanup migration, one defensive
   `assert_not state.key?(:current_nomination)` test, and one
   `refute_respond_to` test — all intentional.
4. Skip auth covers both branches:
   `gym_draft_test.rb:341,350,359` for the model and
   `gym_draft_channel_test.rb:92,100` for the channel.
5. `current_turn_started_at` is written on every turn change:
   `gym_draft.rb:159` (drafting→nominating via make_pick),
   `gym_draft.rb:210` (each non-resolving nominate),
   `gym_draft.rb:235` (drafting→nominating via skip),
   `gym_draft.rb:251` (nominating skip).
6. `gym_draft.rb:185` raises on already-endorsed-by-self;
   `gym_draft_test.rb:190` covers it.
7. `SessionsController#create` early-returns at line 33 when no run
   exists, so `upsert_avatar!` is unreachable in that path.
   `upsert_avatar!:68` additionally guards a blank uid.
8. Avatar fallback color in `gym_draft_helper.rb:17` is
   `discord_user_id.to_i % 4` — deterministic. Test
   `gym_draft_helper_test.rb:33` calls the helper twice and asserts
   byte-equality.
9. The cleanup migration is idempotent via
   `next unless data.key?("current_nomination")` at line 14. Down is a
   documented no-op.
10. `submit_nomination` and `vote_on_nomination` produce zero hits in
    `test/models/gym_draft_test.rb` and
    `test/channels/gym_draft_channel_test.rb` — actually deleted, not
    skipped or renamed.
11. Coin-flip modal dedupes on
    `coinFlipShownFor === JSON.stringify(state.tiebreak)` at
    `gym_draft_controller.js:420-422`. Initial value `null` in
    `connect()`.
12. Q5 is applied surgically — the only `gb-btn-primary` on the
    complete panel is MARK GYM N AS BEATEN (`show.html.erb:161`); the
    BACK TO GYM READY link drops to `gb-btn` (line 166). The other
    `gb-btn-primary` in the file is the lobby READY button (line 51) —
    untouched.
13. Stimulus targets array at `gym_draft_controller.js:5-15` adds
    `nomOrderStrip`, `nomGraceCountdown`, `nomSkipButton`,
    `nomCandidatesList`, `coinFlipModal`, `coinFlipMessage`,
    `coinFlipCoin`, `coinFlipResult`. `nomVoteArea` and `nomVotePrompt`
    grep to zero hits across `app/`.
14. `broadcast_state` (`gym_draft.rb:258-280`) includes `candidates`,
    `current_turn_started_at`, `current_nominator_id`, `tiebreak`, and
    `nomination_picks_remaining`; does NOT include `current_nomination`.
    Asserted directly in `gym_draft_test.rb:387-403`.
15. CSS additions are namespaced — all under `gb-avatar*`,
    `gb-candidate-card*`, `tcg-coin*` (`pixeldex.css:1073-1199`). No
    bare `.avatar` or `.candidate` selectors.
16. The 1-candidate edge case (4/0) yields `picks.size == 5` and
    `status == "complete"`, with no special-casing in the resolver —
    the loop just terminates when `i >= ranked.size` and the residual
    slot stays unfilled. Test at `gym_draft_test.rb:297-311`.
17. Manual smoke deferral is documented in REVIEW-REQUEST and the
    Step 14 BUILD-LOG entry. The unrun in-browser items (TCG-coin
    visual fidelity, per-second grace tick, avatar-pile image branch)
    are acceptable for this surface area: the underlying logic is
    test-covered, and the deferral mirrors the Step 13 environmental
    quirk Bob already logged. Pick it up next dashboard- or
    draft-touching step that gets `bin/dev` running.

Step 14 is clear.
