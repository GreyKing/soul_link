require "test_helper"

class GymPollChannelTest < ActionCable::Channel::TestCase
  tests GymPollChannel

  PLAYERS = [
    { "discord_user_id" => 111, "display_name" => "A" },
    { "discord_user_id" => 222, "display_name" => "B" },
    { "discord_user_id" => 333, "display_name" => "C" },
    { "discord_user_id" => 444, "display_name" => "D" }
  ].freeze
  PLAYER_IDS = PLAYERS.map { |p| p["discord_user_id"] }.freeze

  setup do
    @poll = create(:gym_poll)
    stub_connection current_user_id: 111
  end

  def with_player_data(&block)
    SoulLink::GameState.stub(:players, PLAYERS) do
      SoulLink::GameState.stub(:player_ids, PLAYER_IDS, &block)
    end
  end

  test "subscribes to the poll's stream and broadcasts initial state" do
    with_player_data do
      subscribe(id: @poll.id)
      assert subscription.confirmed?
      assert_has_stream_for @poll
    end
  end

  test "vote action records and broadcasts state" do
    with_player_data do
      subscribe(id: @poll.id)
      perform :vote, { "slot_index" => 0, "response" => "yes" }
    end
    assert_equal "yes", @poll.reload.votes["111"]["0"]
  end

  test "vote action transmits error on locked poll" do
    @poll.update!(status: "locked", locked_slot_index: 0, locked_at: Time.current)
    with_player_data do
      subscribe(id: @poll.id)
      perform :vote, { "slot_index" => 0, "response" => "yes" }
    end
    err = transmissions.find { |t| t["type"] == "error" }
    assert err
    assert_match(/locked/i, err["message"])
  end

  test "reset action destroys the poll and broadcasts poll_reset before destroy" do
    with_player_data do
      subscribe(id: @poll.id)
      assert_difference -> { GymPoll.count }, -1 do
        perform :reset, {}
      end
    end
  end

  test "vote action rejects unregistered users" do
    with_player_data do
      stub_connection current_user_id: 99999  # not in PLAYER_IDS
      subscribe(id: @poll.id)
      perform :vote, { "slot_index" => 0, "response" => "yes" }
    end
    err = transmissions.find { |t| t["type"] == "error" }
    assert err
    assert_match(/aren't a player/i, err["message"])
  end
end
