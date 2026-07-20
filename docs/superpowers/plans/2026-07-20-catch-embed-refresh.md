# Catch Embed Refresh + Self-Healing Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a REFRESH button to the live "NEW CATCH" Discord embed, make website group edits/deletes self-heal to Discord, and render marked-dead groups as a frozen red death embed.

**Architecture:** `SoulLink::CatchMessage` becomes status-aware (green caught embed with buttons; red dead embed with no buttons) and gains a `delete` method. A new bot button `soul_link:catch_refresh:<id>` re-runs `post_or_update` through a testable `DiscordBot.apply_catch_refresh` class method. Two controller hooks (`PokemonGroupsController#update`, `#destroy`) and one bot hook (eulogy death path) close the sync gaps.

**Tech Stack:** Rails 8.1, Ruby 3.4.5, discordrb (positional REST API), Minitest + FactoryBot, `Object#stub`.

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `app/services/soul_link/catch_message.rb` | Embed/component construction, post/edit/**delete** | Modify |
| `app/services/soul_link/discord_bot.rb` | `apply_catch_refresh` class method + button handler + eulogy hook | Modify |
| `app/controllers/pokemon_groups_controller.rb` | `#update` post hook, `#destroy` delete hook | Modify |
| `test/services/soul_link/catch_message_test.rb` | Dead embed, refresh button, delete | Modify |
| `test/services/soul_link/catch_refresh_test.rb` | `apply_catch_refresh` logic | Create |
| `test/controllers/pokemon_groups_controller_test.rb` | update/destroy hooks fire | Modify |

---

## Task 1: REFRESH button + dead-state components on the embed

**Files:**
- Modify: `app/services/soul_link/catch_message.rb`
- Test: `test/services/soul_link/catch_message_test.rb`

- [ ] **Step 1: Write the failing tests**

Append inside the `CatchMessageTest` class (before the final `end` on line 154), after the last existing test:

```ruby
    test "caught embed carries both add and refresh buttons" do
      with_stubbed_discord { SoulLink::CatchMessage.post_or_update(@group) }

      buttons = @posts.first[:components].first[:components]
      custom_ids = buttons.map { |b| b[:custom_id] }
      assert_includes custom_ids, "soul_link:catch_add:#{@group.id}"
      assert_includes custom_ids, "soul_link:catch_refresh:#{@group.id}"
    end

    test "dead group renders a red death embed with no buttons" do
      @group.update!(discord_catch_message_id: 4242, status: "dead")
      with_stubbed_discord { SoulLink::CatchMessage.post_or_update(@group) }

      embed = @edits.first[:embeds].first
      assert_includes embed[:title], "💀"
      assert_equal SoulLink::CatchMessage::DEAD_EMBED_COLOR, embed[:color]
      assert_empty @edits.first[:components]
    end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/soul_link/catch_message_test.rb -n "/refresh|dead group/"`
Expected: FAIL — `catch_refresh` custom_id missing; `DEAD_EMBED_COLOR` undefined / components not empty.

- [ ] **Step 3: Implement status-aware embed + components**

In `app/services/soul_link/catch_message.rb`, add the dead color constant next to `EMBED_COLOR` (line 17):

```ruby
    EMBED_COLOR      = 0x57F287  # green — matches the "caught" status colour
    DEAD_EMBED_COLOR = 0xED4245  # red — matches the "dead" status colour
    NOT_CAUGHT       = "— not caught yet —".freeze
```

Replace `embed` (lines 45-51):

```ruby
      def embed(group)
        dead = group.dead?
        {
          title: dead ? "💀 #{location_label(group)}" : "🎯 NEW CATCH — #{location_label(group)}",
          description: player_lines(group).join("\n"),
          color: dead ? DEAD_EMBED_COLOR : EMBED_COLOR
        }
      end
```

Replace `components` (lines 53-63). A dead group freezes as history — no buttons:

```ruby
      def components(group)
        return [] if group.dead?

        [ {
          type: 1,
          components: [
            {
              type: 2,
              style: 1,
              label: "ADD MY POKEMON",
              custom_id: "soul_link:catch_add:#{group.id}"
            },
            {
              type: 2,
              style: 2,
              label: "🔄 REFRESH",
              custom_id: "soul_link:catch_refresh:#{group.id}"
            }
          ]
        } ]
      end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/soul_link/catch_message_test.rb`
Expected: PASS (all tests, including the existing `catch_add` button test).

- [ ] **Step 5: Commit**

```bash
git add app/services/soul_link/catch_message.rb test/services/soul_link/catch_message_test.rb
git commit -m "feat(catch): add REFRESH button and dead-state embed rendering"
```

---

## Task 2: `CatchMessage.delete`

**Files:**
- Modify: `app/services/soul_link/catch_message.rb`
- Test: `test/services/soul_link/catch_message_test.rb`

- [ ] **Step 1: Write the failing tests**

First extend the `with_stubbed_discord` helper to capture deletes. Add a `@deletes = []` line in `setup` (after `@edits = []` on line 10), and add a delete stub inside `with_stubbed_discord`. Replace the stub-nesting block (lines 31-35) with:

```ruby
      delete_stub = lambda do |_token, channel_id, message_id, *_rest|
        @deletes << { channel_id: channel_id, message_id: message_id }
        { "id" => message_id.to_s }.to_json
      end

      Discordrb::API::Channel.stub(:create_message, post_stub) do
        Discordrb::API::Channel.stub(:edit_message, edit_stub) do
          Discordrb::API::Channel.stub(:delete_message, delete_stub) do
            SoulLink::CatchMessage.stub(:resolve_token, "Bot test", &block)
          end
        end
      end
```

Then append these tests before the class's final `end`:

```ruby
    test "delete removes the discord message and clears the id" do
      @group.update!(discord_catch_message_id: 7777)
      with_stubbed_discord { SoulLink::CatchMessage.delete(@group) }

      assert_equal 1, @deletes.length
      assert_equal 7777, @deletes.first[:message_id]
      assert_nil @group.reload.discord_catch_message_id
    end

    test "delete is a no-op when the group never posted" do
      with_stubbed_discord { SoulLink::CatchMessage.delete(@group) }
      assert_empty @deletes
    end

    test "delete is a no-op when the group is nil" do
      with_stubbed_discord { SoulLink::CatchMessage.delete(nil) }
      assert_empty @deletes
    end

    test "delete never raises when Discord is unreachable" do
      @group.update!(discord_catch_message_id: 7777)
      boom = ->(*_args) { raise SocketError, "no network" }

      Discordrb::API::Channel.stub(:delete_message, boom) do
        SoulLink::CatchMessage.stub(:resolve_token, "Bot test") do
          assert_nothing_raised { SoulLink::CatchMessage.delete(@group) }
        end
      end
    end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/soul_link/catch_message_test.rb -n "/delete/"`
Expected: FAIL — `NoMethodError: undefined method 'delete' for SoulLink::CatchMessage`.

- [ ] **Step 3: Implement `delete`**

In `app/services/soul_link/catch_message.rb`, add as a public class method right after `post_or_update` (after line 38, before the `# ── embed construction ─` comment):

```ruby
      # Remove the catch message from Discord and forget its id. Callers must
      # invoke this BEFORE destroying the group row — the id lives on the group.
      # Fire-and-forget, matching post_or_update: every failure is swallowed.
      def delete(group)
        return if group.nil? || group.discord_catch_message_id.blank?

        run = group.soul_link_run
        return if run.nil? || run.catches_channel_id.blank?

        token = resolve_token
        return if token.blank?

        Discordrb::API::Channel.delete_message(
          token,
          run.catches_channel_id,
          group.discord_catch_message_id
        )
        group.update_columns(discord_catch_message_id: nil)
      rescue StandardError => e
        log_failure(e, group)
        nil
      end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/soul_link/catch_message_test.rb`
Expected: PASS (all).

- [ ] **Step 5: Commit**

```bash
git add app/services/soul_link/catch_message.rb test/services/soul_link/catch_message_test.rb
git commit -m "feat(catch): add CatchMessage.delete for removing catch embeds"
```

---

## Task 3: `DiscordBot.apply_catch_refresh` + button handler

**Files:**
- Modify: `app/services/soul_link/discord_bot.rb`
- Test: `test/services/soul_link/catch_refresh_test.rb` (create)

- [ ] **Step 1: Write the failing test**

Create `test/services/soul_link/catch_refresh_test.rb`:

```ruby
require "test_helper"

module SoulLink
  class CatchRefreshTest < ActiveSupport::TestCase
    setup do
      @run = create(:soul_link_run, catches_channel_id: 1111)
      @group = create(:soul_link_pokemon_group, soul_link_run: @run)
    end

    test "refreshing an existing group re-syncs the embed" do
      calls = []
      SoulLink::CatchMessage.stub(:post_or_update, ->(g) { calls << g.id }) do
        result = SoulLink::DiscordBot.apply_catch_refresh(run: @run, group_id: @group.id)
        assert result[:ok], result[:error]
      end
      assert_equal [ @group.id ], calls
    end

    test "refreshing a missing group returns a not-found error" do
      result = SoulLink::DiscordBot.apply_catch_refresh(run: @run, group_id: 999_999)
      refute result[:ok]
      assert_match(/no longer exists/i, result[:error])
    end

    test "refreshing with a nil run returns a not-found error" do
      result = SoulLink::DiscordBot.apply_catch_refresh(run: nil, group_id: @group.id)
      refute result[:ok]
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/soul_link/catch_refresh_test.rb`
Expected: FAIL — `undefined method 'apply_catch_refresh'`.

- [ ] **Step 3: Implement the class method**

In `app/services/soul_link/discord_bot.rb`, add after `apply_catch_quick_add` ends (after line 51, before `def self.species_error`):

```ruby
    # Pure core of the catch REFRESH button: re-render the embed from current
    # DB state. Read-only, so no ownership/registration gate. Run-scoped for
    # the same reason quick-add is — a stale post must not touch a live run.
    #
    # Returns { ok: true } or { ok: false, error: "<player-facing message>" }.
    def self.apply_catch_refresh(run:, group_id:)
      group = run&.soul_link_pokemon_groups&.find_by(id: group_id)
      return { ok: false, error: "That catch group no longer exists." } if group.nil?

      SoulLink::CatchMessage.post_or_update(group)
      { ok: true }
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/soul_link/catch_refresh_test.rb`
Expected: PASS.

- [ ] **Step 5: Register the button handler**

In `app/services/soul_link/discord_bot.rb`, add after the `catch_add` button block (after line 324, before the `catch_quick_add_modal` block):

```ruby
      # Button: refresh a catch post from current website/DB state
      bot.button(custom_id: /^soul_link:catch_refresh:/) do |event|
        group_id = event.interaction.data['custom_id'].split(':').last
        handle_catch_refresh(event, group_id)
      end
```

Add the instance handler right after `handle_catch_quick_add` ends (after line 918, before `def open_uncaught_death_modal`):

```ruby
    def handle_catch_refresh(event, group_id)
      run = current_run(event)
      unless run
        respond_ephemeral(event, "❌ No active run found!")
        return
      end

      result = self.class.apply_catch_refresh(run: run, group_id: group_id)
      unless result[:ok]
        respond_ephemeral(event, "❌ #{result[:error]}")
        return
      end

      respond_ephemeral(event, "🔄 Refreshed.")
    rescue => e
      respond_ephemeral(event, "❌ Error: #{e.message}")
    end
```

- [ ] **Step 6: Run the full service suite to confirm no regressions**

Run: `bin/rails test test/services/soul_link/catch_refresh_test.rb test/services/soul_link/catch_quick_add_test.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/services/soul_link/discord_bot.rb test/services/soul_link/catch_refresh_test.rb
git commit -m "feat(catch): wire REFRESH button to apply_catch_refresh handler"
```

---

## Task 4: Self-healing hooks — controller update/destroy + bot eulogy path

**Files:**
- Modify: `app/controllers/pokemon_groups_controller.rb`
- Modify: `app/services/soul_link/discord_bot.rb`
- Test: `test/controllers/pokemon_groups_controller_test.rb`

- [ ] **Step 1: Write the failing controller tests**

Append inside `PokemonGroupsControllerTest` (before the final `end` on line 71):

```ruby
  test "updating a group re-syncs the catch embed" do
    login_as(GREY)
    group = create(:soul_link_pokemon_group, :route206, soul_link_run: @run)
    calls = []

    SoulLink::CatchMessage.stub(:post_or_update, ->(g) { calls << g.id }) do
      patch pokemon_group_path(group), params: { nickname: "RENAMED" }, as: :json
    end

    assert_response :success
    assert_equal [ group.id ], calls
  end

  test "destroying a group deletes the catch embed before the row is gone" do
    login_as(GREY)
    group = create(:soul_link_pokemon_group, :route206, soul_link_run: @run)
    seen_ids = []

    SoulLink::CatchMessage.stub(:delete, ->(g) { seen_ids << g.id }) do
      delete pokemon_group_path(group), as: :json
    end

    assert_response :success
    assert_equal [ group.id ], seen_ids
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/pokemon_groups_controller_test.rb -n "/re-syncs|deletes the catch/"`
Expected: FAIL — `post_or_update`/`delete` never called (empty arrays).

- [ ] **Step 3: Add the `#update` hook**

In `app/controllers/pokemon_groups_controller.rb`, in `update`, insert before the success `render` on line 109:

```ruby
    # Re-sync the live catch embed after any edit (rename, relocate, dead,
    # revive). Fire-and-forget; a Discord failure never touches the response.
    SoulLink::CatchMessage.post_or_update(group)

    render json: { status: "updated", group_id: group.id, nickname: group.nickname }
```

- [ ] **Step 4: Add the `#destroy` hook**

In `destroy`, replace `group.destroy!` (line 145) with a delete-first ordering:

```ruby
    # Remove the catch embed BEFORE the row is gone — delete reads the
    # message id off the group.
    SoulLink::CatchMessage.delete(group)
    group.destroy!
```

- [ ] **Step 5: Run controller tests to verify they pass**

Run: `bin/rails test test/controllers/pokemon_groups_controller_test.rb`
Expected: PASS (all).

- [ ] **Step 6: Add the bot eulogy-death hook**

In `app/services/soul_link/discord_bot.rb`, in `handle_move_to_deaths_final`, add the re-sync after `mark_as_dead!` (line 1094), so Discord-driven deaths recolor the embed like website-driven ones:

```ruby
      death_location = location == 'original' ? nil : location
      group.mark_as_dead!(death_location: death_location, eulogy: eulogy)

      SoulLink::CatchMessage.post_or_update(group)

      update_catches_panel(run)
```

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`
Expected: PASS (0 failures, 0 errors).

- [ ] **Step 8: Lint**

Run: `bundle exec rubocop app/services/soul_link/catch_message.rb app/services/soul_link/discord_bot.rb app/controllers/pokemon_groups_controller.rb`
Expected: no offenses.

- [ ] **Step 9: Commit**

```bash
git add app/controllers/pokemon_groups_controller.rb app/services/soul_link/discord_bot.rb test/controllers/pokemon_groups_controller_test.rb
git commit -m "fix(catch): self-heal catch embed on group update, destroy, and eulogy death"
```

---

## Self-Review Notes

- **Spec coverage:** Part 1 (status-aware embed) → Task 1 + Task 2; Part 2 (button) → Task 3; Part 3 (hooks) → Task 4; Part 4 (tests) → distributed across all tasks. ✅
- **Type consistency:** `DEAD_EMBED_COLOR` defined Task 1, asserted Task 1. `delete` defined Task 2, used Task 4. `apply_catch_refresh` defined Task 3, no later refs. `handle_catch_refresh` defined + registered Task 3. ✅
- **Ordering:** `delete` before `destroy!` is explicit (Task 4 Step 4) because the message id lives on the group row.
- **No placeholders.** All code blocks are complete.
