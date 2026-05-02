# Review Request
*Written by Builder. Read by Reviewer.*
*Session-scoped — archived and reset at session end.*

Ready for Review: YES

---

## Step 14 — Gym Draft Final-2 Picks: Unified Nominate-or-Endorse Model

**Builder:** Bob
**Tests:** 343 → 370 (+27). 0 failures, 0 errors.
**Lint:** `bundle exec rubocop` — 0 offenses across 152 files.
**TCG-coin path:** **PRIMARY** (pokeball + character two-face 3D coin). Not the fallback escape hatch.

---

## Files Changed

### Created (4)

| Path | Lines | Purpose |
|------|-------|---------|
| `db/migrate/20260501192916_add_player_avatars_to_soul_link_runs.rb` | 1-5 | Adds `player_avatars` JSON column to `soul_link_runs`. Drives the avatar caching layer. |
| `db/migrate/20260501192917_cleanup_current_nomination_from_inflight_drafts.rb` | 1-25 | One-time cleanup of the now-defunct `state_data["current_nomination"]` sub-key for any draft parked in `nominating`. Idempotent (`next unless data.key?`); seeds `candidates: []` and a fresh `current_turn_started_at` so the new model code can pick up. Down is a documented no-op. |
| `app/helpers/gym_draft_helper.rb` | 1-22 | `player_avatar_image(run, uid, size: 32)`. `image_tag` when the run has a cached URL; deterministic `gb-avatar--initial gb-avatar--cN` circle (uid % 4) otherwise. Helper is pure — no controller/session state. |
| `test/helpers/gym_draft_helper_test.rb` | 1-58 | 5 tests: image branch, fallback branch, deterministic-color sanity check, nil-`player_avatars` handling, custom size. |

### Modified (10)

| Path | Lines | Change |
|------|-------|--------|
| `app/models/gym_draft.rb` | 1-372 | Major rewrite. **Removed:** `current_nomination`, `submit_nomination!`, `vote_on_nomination!`, `resolve_nomination!` (singular). **Added:** `candidates` / `tiebreak` accessors, `current_turn_started_at`, `grace_elapsed?`, `current_nominator_id`, `nomination_picks_made`, `nominate!(picker_uid, group_id)` (unified action — auto-detects new-vs-endorse), `resolve_nominations!` (plural, greedy-fill voter-count-desc with same-count-group tiebreak detection). `make_pick!` and `skip_turn!` seed/maintain `current_turn_started_at`. `skip_turn!` now takes `requester_uid` and enforces nominator-OR-grace. `broadcast_state` drops `current_nomination`, adds the 5 new fields. New constants `NOMINATION_GRACE_SECONDS = 60` and `NOMINATION_FINAL_SLOTS = 2`. |
| `app/channels/gym_draft_channel.rb` | 1-65 | **Removed** `vote_nomination` action. `nominate` calls `@draft.nominate!`. `skip` passes `current_user_id`. |
| `app/models/soul_link_run.rb` | 47-79 | Added `avatar_for(discord_user_id)` and `upsert_avatar!(discord_user_id, url)`. Idempotent — early-return if URL unchanged. Blank URL deletes the entry. Blank uid is a silent no-op. |
| `app/controllers/sessions_controller.rb` | 38-44 | After `session[:guild_id] = run.guild_id`, calls `run.upsert_avatar!(discord_user_id, avatar_url)` gated on `avatar_url.present?`. Skip-when-no-active-run is implicit because `run` is required earlier in the flow. |
| `app/views/gym_drafts/show.html.erb` | 1-198 | Nominating panel rewritten: 6 team slots, pick-order strip, status + grace countdown line, candidates row, pokemon grid with NOMINATE/ENDORSE labels. TCG coin-flip modal added at the bottom inside the controller wrapper. Q5 fix: complete-panel "BACK TO GYM READY" demoted from `gb-btn-primary` to `gb-btn`; MARK BEATEN remains the only primary CTA. New `data-gym-draft-player-avatars-value` JSON wired from `@draft.soul_link_run.player_avatars`. |
| `app/javascript/controllers/gym_draft_controller.js` | 1-490 | Major rewrite. **Removed targets:** `nomVoteArea`, `nomVotePrompt`. **Added targets:** `nomOrderStrip`, `nomGraceCountdown`, `nomSkipButton`, `nomCandidatesList`, `coinFlipModal`, `coinFlipMessage`, `coinFlipCoin`, `coinFlipResult`. **Added value:** `playerAvatars: Object`. **Removed actions:** `approveNomination`, `rejectNomination`, `nominatePokemon`. **Added actions:** `nominateOrEndorse`. **Added render branches:** `renderNomOrderStrip`, `renderCandidates`, `renderNomPokemonGrid`, `renderNomGraceCountdown`, `maybeShowCoinFlip`, `runCoinFlipAnimation`. **Added helpers:** `buildAvatar(uid)` (mirrors `player_avatar_image` for client rendering), `showNomSkipButton`, `hideNomSkipButton`, `clearGraceTick`, `clearCoinFlipTimers`. Coin flip dedupes via `coinFlipShownFor = JSON.stringify(state.tiebreak)`. |
| `app/assets/stylesheets/pixeldex.css` | 1067-1199 | New tokens namespaced under existing `gb-*` family: `.gb-avatar`, `.gb-avatar--32/--24/--initial/--c0..c3`, `.gb-avatar-pile`, `.gb-candidate-card` + `--leading`, `.tcg-coin-stage`, `.tcg-coin`, `.tcg-coin__face` + `--pokeball/--character`, `.tcg-coin--flipping`, `@keyframes tcgCoinFlip`. No bare `.avatar` or `.candidate` collisions. |
| `test/models/gym_draft_test.rb` | 1-409 | **Removed 6 stale tests:** `submit_nomination creates...`, `submit_nomination raises for already picked group`, `submit_nomination raises when nomination is pending`, `vote_on_nomination records vote`, `nomination approved with majority adds pick`, `nomination rejected clears nomination without adding pick`, `six total picks transitions to complete`. **Added 17 new tests:** all 5 tally splits (3/1, 2/2, 2/1/1, 1/1/1/1, 4/0 consensus), `nominate creates a new candidate`, `endorsement adds voter to existing candidate`, `nominate raises for already-picked individual group`, `nominate raises when not your turn`, `double-endorse by same player raises`, `current_turn_started_at advances on each nominate`, `current_turn_started_at is set on transition into nominating`, grace_elapsed truth-table (true after 60s, false within), skip auth (3 cases), broadcast_state Step-14 fields, broadcast_state stores voter ids as integers. Includes `ActiveSupport::Testing::TimeHelpers` for `travel`. |
| `test/channels/gym_draft_channel_test.rb` | 1-148 | **Removed** stale `vote_nomination action records vote`. **Added 5 new tests:** `nominate action creates a new candidate`, `nominate action endorses an existing candidate`, `skip rejected for non-nominator before grace`, `skip allowed for non-nominator after grace`, `vote_nomination action no longer exists` (asserted via `GymDraftChannel.action_methods` because ActionCable test `perform` silently no-ops on missing actions). Includes `ActiveSupport::Testing::TimeHelpers`. |
| `test/models/soul_link_run_test.rb` | 1-148 | Added 6 avatar-cache tests + `include ActiveSupport::Testing::TimeHelpers` at the top of the class. |

### Handoff (2)

| Path | Change |
|------|--------|
| `handoff/BUILD-LOG.md` | New Step 14 entry under Step History; `Active step` updated to Step 14; the Step 13-vintage parked-plan note was tightened to reflect that the FactoryBot conversion has fully landed. |
| `handoff/REVIEW-REQUEST.md` | Overwritten with this Step 14 review request. |

---

## Self-Review — Reviewer's 17 Focus Areas

1. **Tally algorithm correctness on all 5 splits.** The greedy-fill loop in `resolve_nominations!` (`gym_draft.rb:330-365`) walks `ranked` in voter-count-desc order, taking the entire same-count-group when it fits in `remaining_slots` or shuffling-and-truncating when it doesn't. Tests cover 3/1 (2 distinct counts, both fit, no tiebreak), 2/2 (1 count of size 2, fits exactly, no tiebreak), 2/1/1 (winner of count 2 fills slot 5, the count-1 group of size 2 hits the threshold and tiebreaks → `second_place`), 1/1/1/1 (single count-1 group of size 4 hits the threshold → `n_way`), 4/0 consensus (single candidate fills slot 5; loop ends with `i >= ranked.size` so slot 6 stays empty). The smoke harness output in BUILD-LOG confirms each split end-to-end with real model objects.

2. **`tiebreak.winners` is set server-side, not by the client.** Set inside `resolve_nominations!` via `same_count_group.shuffle.first(remaining_slots)` and persisted to `state_data["tiebreak"]["winners"]`. The Stimulus `runCoinFlipAnimation(tiebreak)` reads `tiebreak.winners` — never picks them. Modal reveal is purely presentational. The coin's `tcgCoinFlip` keyframe always lands on the opposite face regardless of result; the result text is read out from the server payload.

3. **No `current_nomination` references survive.** Grepped `app/`, `test/`, `db/migrate/` — only the cleanup-migration body and one defensive test assertion (`assert_not state.key?(:current_nomination)` in `gym_draft_test.rb:399`) reference the string, both intentional. The `resolve_nominations!` (plural — new) hits also showed up; that's expected.

4. **Skip auth enforces both branches.** `skip_turn!` (`gym_draft.rb:233-263`) checks `is_current = current_nominator_id == requester_uid.to_i` and raises unless `is_current || grace_elapsed?`. Tests verify all three paths: pre-grace non-nominator raises (`skip_turn raises if requester is not current nominator and grace not elapsed`), current nominator any time succeeds (`skip_turn succeeds for current nominator any time`), post-grace non-nominator succeeds (`skip_turn succeeds for non-nominator after grace`).

5. **`current_turn_started_at` is updated on every turn change.** `make_pick!` writes it on the drafting → nominating transition (`gym_draft.rb:158-167`). `nominate!` writes it on each non-terminating call (`gym_draft.rb:213`). `skip_turn!` writes it on both the drafting→nominating transition (`gym_draft.rb:243-250`) and on the nominating-skip itself (`gym_draft.rb:259`). The `current_turn_started_at advances on each nominate` test wraps a `travel 5.seconds` block and asserts `after > initial`.

6. **Endorsement on already-endorsed-by-self raises.** Guard in `nominate!`: `raise "You already endorsed this nomination" if existing["voters"].include?(picker_uid.to_i)` (`gym_draft.rb:194`). The `double-endorse by same player raises` test forces the index back so the same player tries a second time and asserts the raise.

7. **Avatar upsert handles missing run gracefully.** In `SessionsController#create` the redirect-with-alert in the no-run branch returns early (`sessions_controller.rb:31-35`) BEFORE the upsert call, so `run.upsert_avatar!` only runs when `run` is non-nil. The `upsert_avatar!` method itself early-returns on blank user id. There's no test for "no run found" because the early return makes it structurally impossible to hit; the relevant unit-level guarantees are covered by the SoulLinkRun avatar tests.

8. **Avatar fallback color is deterministic per discord_user_id.** Helper picks `discord_user_id.to_i % 4` — same uid always picks the same color slot. Test `player_avatar_image fallback color is deterministic per discord_user_id` calls the helper twice and asserts the rendered HTML is byte-identical.

9. **The cleanup migration is idempotent.** `next unless data.key?("current_nomination")` short-circuits drafts that already had the key removed (e.g., from a prior migration run). Down is a documented no-op. Did not write a test for the migration itself; the guard is structurally trivial.

10. **`gym_draft_test.rb` legacy tests for `submit_nomination!` and `vote_on_nomination!` are GONE.** All 6 listed in the brief have been deleted from the file (verified by re-reading the file post-edit; only one new `nominate ...` style test exists now). Not skipped, not renamed — actually deleted.

11. **Coin-flip modal dedupes across `render()` calls.** `maybeShowCoinFlip` (`gym_draft_controller.js:255-275`) keys on `JSON.stringify(state.tiebreak)`; once `coinFlipShownFor === key`, subsequent `render()` calls early-return. The flag is initialized to `null` in `connect()`, so on a fresh page load with a complete-state-with-tiebreak draft the modal animates exactly once.

12. **`Q5` is applied surgically.** Only the complete panel's two buttons (`MARK GYM N AS BEATEN` stays `gb-btn-primary`; `BACK TO GYM READY` drops to `gb-btn`). No sweep of every primary button on the page — verified by grepping `gb-btn-primary` in the diff: the only delta is the BACK button.

13. **Stimulus targets array is updated.** Compared against the brief's enumeration: `nomOrderStrip` ✓, `nomGraceCountdown` ✓, `nomSkipButton` ✓, `nomCandidatesList` ✓, `coinFlipModal` ✓, `coinFlipMessage` ✓, `coinFlipCoin` ✓, `coinFlipResult` ✓. Removed: `nomVoteArea` ✓, `nomVotePrompt` ✓. The view's `data-gym-draft-target` attributes match 1:1.

14. **`broadcast_state` includes `candidates`, `current_turn_started_at`, `current_nominator_id`, `tiebreak`. Does NOT include `current_nomination`.** Walked the model test `broadcast_state includes Step 14 nominating fields` — it asserts `state.key?(:candidates)`, `:current_nominator_id`, `:current_turn_started_at`, `:nomination_picks_remaining`, `:tiebreak`, AND `assert_not state.key?(:current_nomination)`.

15. **CSS additions don't conflict with existing tokens.** New classes are namespaced (`.gb-avatar`, `.gb-avatar-pile`, `.gb-candidate-card`, `.tcg-coin*`). No bare `.avatar` or `.candidate` that could collide. `@keyframes tcgCoinFlip` is project-unique. The `gb-modal` reuse for the modal wrapper is intentional and documented in the brief.

16. **The 1-candidate edge case (4/0)** results in `picks.size == 5` and status `complete`. Verified by the `tally 4/0 consensus — only candidate fills slot 5; slot 6 stays empty` test. The implementation does NOT try to "fix" this (no extra logic in `resolve_nominations!` for the empty slot — the loop just terminates when `i >= ranked.size` with `remaining_slots > 0`, so the residual slot stays unfilled).

17. **Manual smoke documented.** `bin/dev` did not run cleanly in the sandbox (continuation of the Step 13 foreman/tailwind-v4 quirk). All 5 tally splits + skip auth + broadcast were exercised via a `rails runner` smoke harness against the test infrastructure (output captured in BUILD-LOG). What's NOT been exercised in a real browser: (a) the TCG-coin animation visual fidelity / settle bounce, (b) the per-second grace countdown tick rendering, (c) the avatar pile image-vs-initial rendering with real Discord CDN URLs. Recommendation matches Step 13's: when the next dashboard- or draft-touching step gets `bin/dev` running, click through the new nominating UX once and note it. The TCG-coin component in particular benefits from browser eyeballing — flag clearly if you want me to take another pass with `bin/dev` first before merging.

---

## Open Questions

None. The brief was unambiguous and complete.

---

## Diff Scope Validation

Per the brief's "Diff scope: 1 model + 1 channel + 1 controller (sessions) + 2 views (1 minor: complete-panel button weight; 1 major: nominating panel) + 1 stylesheet + 1 helper + 1 Stimulus + 2 migrations + 4 test files + 4 handoff files":

- **1 model:** `app/models/gym_draft.rb`. ✓ (Plus `app/models/soul_link_run.rb` for the avatar accessor — also called out in the brief's "Avatar caching layer" section, so this is in scope, not a leak.)
- **1 channel:** `app/channels/gym_draft_channel.rb`. ✓
- **1 controller (sessions):** `app/controllers/sessions_controller.rb`. ✓
- **2 views:** Both edits (Q5 fix + nominating panel rewrite) live in the same `app/views/gym_drafts/show.html.erb`, so this is one file with two edits — matches the brief's intent.
- **1 stylesheet:** `app/assets/stylesheets/pixeldex.css`. ✓
- **1 helper:** `app/helpers/gym_draft_helper.rb` (NEW). ✓
- **1 Stimulus:** `app/javascript/controllers/gym_draft_controller.js`. ✓
- **2 migrations:** `add_player_avatars_to_soul_link_runs`, `cleanup_current_nomination_from_inflight_drafts`. ✓
- **4 test files:** `test/models/gym_draft_test.rb` (modified), `test/channels/gym_draft_channel_test.rb` (modified), `test/models/soul_link_run_test.rb` (extended), `test/helpers/gym_draft_helper_test.rb` (NEW). ✓
- **4 handoff files:** `BUILD-LOG.md` (this step entry), `REVIEW-REQUEST.md` (this file). The other two (ARCHITECT-BRIEF, REVIEW-FEEDBACK) are not Builder-owned mid-cycle.

Nothing outside the brief's listed files. Zero scope expansion.
