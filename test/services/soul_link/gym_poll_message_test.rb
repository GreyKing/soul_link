require "test_helper"

class SoulLink::GymPollMessageTest < ActiveSupport::TestCase
  PLAYERS = [
    { "discord_user_id" => 111, "display_name" => "Alice" },
    { "discord_user_id" => 222, "display_name" => "Bob" },
    { "discord_user_id" => 333, "display_name" => "Carol" },
    { "discord_user_id" => 444, "display_name" => "Dave" }
  ].freeze

  setup do
    @poll = create(:gym_poll)
  end

  def with_players(&block)
    SoulLink::GameState.stub(:players, PLAYERS) do
      SoulLink::GameState.stub(:player_ids, PLAYERS.map { |p| p["discord_user_id"] }, &block)
    end
  end

  test "embed lists every player as pending before anyone votes" do
    with_players do
      desc = SoulLink::GymPollMessage.embed(@poll)[:description]
      assert_includes desc, "⏳ Alice, Bob, Carol, Dave"
    end
  end

  test "embed groups voters by response using their display names" do
    with_players do
      @poll.vote!(111, 0, "yes")
      @poll.vote!(222, 0, "yes")
      @poll.vote!(333, 0, "no")

      desc = SoulLink::GymPollMessage.embed(@poll)[:description]

      assert_includes desc, "✅ Alice, Bob"
      assert_includes desc, "❌ Carol"
      assert_includes desc, "⏳ Dave"
    end
  end

  test "embed omits response buckets that have no voters" do
    with_players do
      @poll.vote!(111, 0, "yes")

      desc = SoulLink::GymPollMessage.embed(@poll)[:description]

      refute_includes desc, "❓"
      refute_includes desc, "❌"
    end
  end

  test "embed title shows LOCKED for a locked poll" do
    poll = create(:gym_poll, :locked, soul_link_run: @poll.soul_link_run)
    with_players do
      assert_includes SoulLink::GymPollMessage.embed(poll)[:title], "LOCKED"
    end
  end

  test "components return a vote row per upcoming slot plus a reset row" do
    with_players do
      rows = SoulLink::GymPollMessage.components(@poll)

      assert_equal 3, rows.length # two future slots + reset
      reset_button = rows.last[:components].first
      assert_equal "soul_link:gym_poll_reset:#{@poll.id}", reset_button[:custom_id]
    end
  end

  test "components hide vote buttons but keep reset when locked" do
    poll = create(:gym_poll, :locked, soul_link_run: @poll.soul_link_run)
    with_players do
      rows = SoulLink::GymPollMessage.components(poll)

      assert_equal 1, rows.length
      assert_equal "soul_link:gym_poll_reset:#{poll.id}", rows.first[:components].first[:custom_id]
    end
  end
end
