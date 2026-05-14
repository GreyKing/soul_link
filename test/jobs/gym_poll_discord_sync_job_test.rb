require "test_helper"

class GymPollDiscordSyncJobTest < ActiveJob::TestCase
  PLAYERS = [
    { "discord_user_id" => 111, "display_name" => "A" },
    { "discord_user_id" => 222, "display_name" => "B" },
    { "discord_user_id" => 333, "display_name" => "C" },
    { "discord_user_id" => 444, "display_name" => "D" }
  ].freeze

  setup do
    @poll = create(:gym_poll, discord_channel_id: 999, discord_message_id: 12345)
  end

  def with_credentials_and_players(&block)
    Rails.application.credentials.stub(:discord, { token: "test-token" }) do
      SoulLink::GameState.stub(:players, PLAYERS) do
        SoulLink::GameState.stub(:player_ids, PLAYERS.map { |p| p["discord_user_id"] }, &block)
      end
    end
  end

  test "noop when discord_message_id is nil" do
    @poll.update!(discord_message_id: nil)
    with_credentials_and_players { GymPollDiscordSyncJob.perform_now(@poll.id) }
    # No WebMock stub set; if a request fires, the test fails.
  end

  test "PATCHes the message embed" do
    stub = stub_request(:patch, "https://discord.com/api/v10/channels/999/messages/12345")
      .with(headers: { "Authorization" => "Bot test-token" })
      .to_return(status: 200, body: "{}")
    with_credentials_and_players { GymPollDiscordSyncJob.perform_now(@poll.id) }
    assert_requested stub
  end

  test "embed body contains slot fields and tally text" do
    body_captured = nil
    stub_request(:patch, /discord.com/).with { |req| body_captured = req.body }.to_return(status: 200, body: "{}")
    with_credentials_and_players do
      @poll.vote!(111, 0, "yes")
      GymPollDiscordSyncJob.perform_now(@poll.id)
    end
    assert_includes body_captured, "Gym Poll"
    assert_includes body_captured, "yes"
  end

  test "logs error on 5xx but does not raise" do
    stub_request(:patch, /discord.com/).to_return(status: 502, body: "bad gateway")
    with_credentials_and_players do
      assert_nothing_raised { GymPollDiscordSyncJob.perform_now(@poll.id) }
    end
  end
end
