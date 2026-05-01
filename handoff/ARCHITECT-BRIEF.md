# Architect Brief
*Written by Architect. Read by Builder and Reviewer.*
*Overwrite this file each step — it is not a log, it is the current active brief.*

---

## Step 7 — Convert Channel Test from Fixtures to FactoryBot

### Context

Step 6 (commit `f7203b0`, merged to main) closed out controller + model conversions. After Step 6, only one file in `test/` still references fixtures by name: `test/channels/gym_draft_channel_test.rb` with 8 fixture-helper calls. Step 7 converts this file. After Step 7, **zero** test files use `soul_link_runs(:..)`, `soul_link_pokemon_groups(:..)`, `gym_drafts(:..)`, etc. Step 8 (deferred) will then mechanically delete `test/fixtures/*.yml`, drop `fixtures :all` from `test/test_helper.rb`, and update `CLAUDE.md`'s testing convention section.

This step is small (1 file, 9 tests, 8 fixture calls) but has its own shape because channel tests extend `ActionCable::Channel::TestCase` instead of `ActionDispatch::IntegrationTest`. The channel test's setup creates the same world as Step 5's `gym_draft_test.rb` (run + 6 groups + lobby draft) plus a `stub_connection(current_user_id: GREY)` line — channel tests bypass the HTTP login flow.

### Project Owner decisions (locked)

- **Auto-accept mode for this work.** Bob can act decisively; Reviewer + tests are the backstop.
- **Convert exactly one file.** No bundle creep.
- **Preserve every test.** Same test name, same assertions, same behavior. 9 tests in.
- **Don't touch fixtures, factories, test_helper, or app code.** Step 7 only edits the one target file.
- **`create(...)`, not `build(...)`.** Persisted records.

### Files to Convert (1 total)

#### `test/channels/gym_draft_channel_test.rb` (8 fixture-helper calls)

Current setup:
```ruby
setup do
  @run = soul_link_runs(:active_run)
  @draft = gym_drafts(:lobby_draft)
  @groups = [
    soul_link_pokemon_groups(:group_route201),
    soul_link_pokemon_groups(:group_route202),
    soul_link_pokemon_groups(:group_route203),
    soul_link_pokemon_groups(:group_route204),
    soul_link_pokemon_groups(:group_route205),
    soul_link_pokemon_groups(:group_route206)
  ]
  stub_connection(current_user_id: GREY)
end
```

Replacement (mirrors Step 5's `gym_draft_test.rb` setup exactly, plus the `stub_connection` line):
```ruby
setup do
  @run = create(:soul_link_run)
  @groups = %i[route201 route202 route203 route204 route205 route206].map do |trait|
    create(:soul_link_pokemon_group, trait, soul_link_run: @run)
  end
  @draft = create(:gym_draft, :lobby, soul_link_run: @run)
  stub_connection(current_user_id: GREY)
end
```

Order matters: `@groups` before `@draft` (consistent with Step 5).

`@groups` stays an Array indexed `[0..5]` — tests reference `@groups[0]` (route201), `@groups[4]` (route205 for nomination), unchanged in spirit.

The 9 test bodies and 3 private helpers (`move_to_voting!`, `move_to_drafting!`, `move_to_nominating!`) are unchanged — they reference `@run`, `@draft`, `@groups[i]`, `ALL_PLAYERS`, all of which exist post-conversion with identical semantics.

### Channel-test specifics (do NOT change)

These channel-test methods stay as-is — Bob does not need to convert them, only the data setup:
- `stub_connection(current_user_id: GREY)` — establishes the connection identifier; bypasses HTTP login. Stays.
- `subscribe(draft_id: @draft.id)` — subscribes to the channel with params. Stays.
- `perform :action, payload` — invokes a channel action.
- `assert_broadcasts(stream, n) { ... }` — Action Cable assertion.
- `assert_has_stream_for @draft` — assertion on `stream_for @record` setup.
- `transmissions` — channel test helper for messages sent back.
- `subscription.confirmed?` — subscription state.

Channel tests do NOT go through the HTTP controller stack, so the fixture-vs-factory `SoulLinkRun.current(guild_id)` collision discovered in Step 6 does NOT apply here. **Don't add a `SoulLinkRun.where(guild_id: ...).destroy_all` guard** — it's unnecessary and would be cargo-culted from the controller pattern. The channel looks up the draft via `params[:draft_id]` directly. Coexistence with fixtures is harmless because the channel never goes through `current(guild_id)`.

(If, while running tests, Bob discovers the fixture coexistence DOES cause a failure — for example, the channel performs some "find active draft for the run" lookup that picks up the fixture's lobby_draft instead of the factory @draft — escalate. Architect's expectation is that this won't happen.)

### Pre-existing rubocop offense

Line 8: `ALL_PLAYERS = [GREY, ARATY, SCYTHE, ZEALOUS].freeze` has the same `Layout/SpaceInsideArrayLiteralBrackets` offense Step 5 fixed in `gym_draft_test.rb`. Fix to satisfy "rubocop clean" acceptance criterion. 2-character whitespace change to `[ GREY, ARATY, SCYTHE, ZEALOUS ]`.

### Out of Scope (do NOT expand)

- Other test files (everything else is converted)
- Fixtures (`test/fixtures/*.yml`) — Step 8 deletes them
- `test/test_helper.rb` `fixtures :all` line — Step 8 removes it
- `CLAUDE.md` testing convention update — Step 8
- Any factory file
- App code, models, controllers, channels, views, JS
- Refactoring the `move_to_voting!` / `move_to_drafting!` / `move_to_nominating!` helpers (preserve as-is)
- Adding new tests or removing existing ones — preserve test count exactly: 9
- Pre-existing rubocop offenses outside the lines Bob touches (same Step 5/6 lesson)

### Constraints / Flags

- **Run the channel test after conversion**, then full suite. Sequence: convert → `bin/rails test test/channels/gym_draft_channel_test.rb` → full `bin/rails test`.
- **305/305 must pass at the end.**
- **`@groups` stays an Array.** Don't refactor to Hash — tests use positional indexing.
- **No `let` / `subject` / `before(:each)`.** Match Minitest `setup` + ivars convention.
- **Don't reorder tests.** Tests are in semantic groups (subscribe → ready → vote → pick → nominate → vote_nomination → wrong phase).
- **Don't introduce new factory traits.**
- **Don't add the `destroy_all` guild guard from Step 6** — channel tests don't need it (see "Channel-test specifics" above).
- **Zero fixture-helper calls remaining in this file.** Verify with grep.

### Acceptance Criteria

- File compiles and runs green: `bin/rails test test/channels/gym_draft_channel_test.rb` → 9/9 passing.
- Full suite green: `bin/rails test` → 305/305 passing, 0 failures, 0 errors.
- `bundle exec rubocop test/channels/gym_draft_channel_test.rb` clean.
- `grep -E "soul_link_pokemon\(|soul_link_runs\(|soul_link_pokemon_groups\(|soul_link_teams\(|soul_link_team_slots\(|gym_drafts\(|gym_results\(" test/channels/gym_draft_channel_test.rb` returns zero matches.
- After Step 7, `grep -rln <fixture-helper patterns> test/` returns ZERO files. Verify this — it's the proof Step 7 finished and the conversion is functionally complete (fixture deletion + helper removal happens in Step 8).
- Diff scope: only `test/channels/gym_draft_channel_test.rb` + 4 handoff files (`ARCHITECT-BRIEF.md` is already overwritten as this brief; `BUILD-LOG.md`, `REVIEW-REQUEST.md`, `REVIEW-FEEDBACK.md` get updated). App code, fixtures, factories, test_helper.rb, all other test files untouched.

### Files Bob Should Read

- `test/channels/gym_draft_channel_test.rb` — the file Bob is converting
- `test/models/gym_draft_test.rb` — Step 5's already-converted reference for the proven setup pattern (Bob copies the `setup do` shape)
- `test/factories/soul_link_pokemon_groups.rb`, `soul_link_pokemon.rb`, `gym_drafts.rb`, `soul_link_runs.rb` — what's available
- `handoff/parked-plans/factorybot-conversion.md` — for context

DO NOT load `app/channels/`, `app/models/gym_draft.rb`, or any app code. The channel + model semantics are not changing.

### Files Bob Should Update at the End

- `handoff/REVIEW-REQUEST.md` — files-changed table, self-review answers, open questions, `Ready for Review: YES`
- `handoff/BUILD-LOG.md` — Step History entry for Step 7 (status: Awaiting review)

---

## Notes for Reviewer

When this lands on your desk, focus on:

1. **Test count + name preservation.** Run `grep -c "^  test " test/channels/gym_draft_channel_test.rb` — expected 9. Compare names against pre-conversion via `git show HEAD~1:test/channels/gym_draft_channel_test.rb | grep "^  test "`.

2. **Setup pattern matches Step 5's `gym_draft_test.rb`.** Same trait list `%i[route201..route206]`, same order, same `:lobby` trait for the draft. The only addition is the `stub_connection(current_user_id: GREY)` line at the end of setup.

3. **`@groups` array order.** `@groups[0]` must be route201, `@groups[4]` route205 (nominate test), `@groups[5]` route206 (unused but stays for symmetry). Test references at lines 61, 64, 70, 78 rely on positional indexing.

4. **`stub_connection`, `subscribe`, `perform`, `assert_broadcasts`, `assert_has_stream_for`, `transmissions` calls all unchanged.** These are Action Cable test helpers — Bob should not touch them.

5. **Private helpers (`move_to_voting!`, `move_to_drafting!`, `move_to_nominating!`) unchanged.** Same as Step 5 — they reference `@run`, `@draft`, `@groups`, `ALL_PLAYERS`, all of which exist post-conversion.

6. **No `destroy_all` guild guard added.** Channel tests bypass HTTP, so the Step 6 controller pattern is unnecessary here. If Bob added one, that's a Reviewer Condition (cargo-cult).

7. **Pre-existing rubocop offense fixed** at line 8 (`ALL_PLAYERS = [GREY, ARATY, SCYTHE, ZEALOUS].freeze` → `[ GREY, ARATY, SCYTHE, ZEALOUS ]`). Same as Step 5's fix in the model test.

8. **Zero fixture-helper calls remaining in this file** AND `grep -rln <patterns> test/` empty across the entire test tree. After Step 7, the conversion is functionally complete; Step 8 just deletes the YAML files and the `fixtures :all` line.

9. **Diff scope.** `git status --short` and `git diff --stat HEAD~1` should show only `test/channels/gym_draft_channel_test.rb` + 4 handoff files. Anything else is a Reviewer Condition.

Out-of-scope items found during review → BUILD-LOG Known Gaps. Do not bundle.
