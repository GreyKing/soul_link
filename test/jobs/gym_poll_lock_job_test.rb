require "test_helper"

class GymPollLockJobTest < ActiveJob::TestCase
  PLAYERS = [
    { "discord_user_id" => 111, "display_name" => "A" },
    { "discord_user_id" => 222, "display_name" => "B" },
    { "discord_user_id" => 333, "display_name" => "C" },
    { "discord_user_id" => 444, "display_name" => "D" }
  ].freeze

  setup do
    @poll = create(:gym_poll, :locked,
                   discord_channel_id: 999,
                   discord_message_id: 12345,
                   pinged_at: nil)
  end

  def with_creds_and_players(&block)
    Rails.application.credentials.stub(:discord, { token: "test-token" }) do
      SoulLink::GameState.stub(:players, PLAYERS) do
        SoulLink::GameState.stub(:player_ids, PLAYERS.map { |p| p["discord_user_id"] }, &block)
      end
    end
  end

  test "POSTs ping message with all 4 mentions" do
    body_captured = nil
    stub_request(:patch, /messages\/12345/).to_return(status: 200, body: "{}")
    post_stub = stub_request(:post, "https://discord.com/api/v10/channels/999/messages")
      .with { |req| body_captured = req.body; true }
      .to_return(status: 200, body: "{}")
    with_creds_and_players { GymPollLockJob.perform_now(@poll.id) }
    assert_requested post_stub
    # Ruby's `to_json` escapes `<` and `>` as `<`/`>` (HTML-safe default),
    # so parse the body and assert on the decoded `content` field rather than the raw bytes.
    content = JSON.parse(body_captured).fetch("content")
    assert_includes content, "<@111>"
    assert_includes content, "<@222>"
    assert_includes content, "<@333>"
    assert_includes content, "<@444>"
  end

  test "PATCHes the poll embed to a locked state" do
    patch_stub = stub_request(:patch, /messages\/12345/).to_return(status: 200, body: "{}")
    stub_request(:post, /channels\/999\/messages/).to_return(status: 200, body: "{}")
    with_creds_and_players { GymPollLockJob.perform_now(@poll.id) }
    assert_requested patch_stub
  end

  test "sets pinged_at on success" do
    stub_request(:patch, /discord/).to_return(status: 200, body: "{}")
    stub_request(:post, /discord/).to_return(status: 200, body: "{}")
    assert_nil @poll.pinged_at
    with_creds_and_players { GymPollLockJob.perform_now(@poll.id) }
    assert_not_nil @poll.reload.pinged_at
  end

  test "is idempotent — second run does not re-POST the ping" do
    stub_request(:patch, /discord/).to_return(status: 200, body: "{}")
    post_stub = stub_request(:post, /messages\b/).to_return(status: 200, body: "{}")
    with_creds_and_players do
      GymPollLockJob.perform_now(@poll.id)
      GymPollLockJob.perform_now(@poll.id)
    end
    assert_requested post_stub, times: 1
  end

  test "noop when poll is not locked" do
    @poll.update!(status: "open", locked_slot_index: nil, locked_at: nil)
    # No WebMock stubs: an outbound request would raise (WebMock blocks net traffic),
    # which `assert_nothing_raised` would catch. Doubles as the assertion that silences
    # minitest's "Test is missing assertions" warning.
    with_creds_and_players do
      assert_nothing_raised { GymPollLockJob.perform_now(@poll.id) }
    end
  end
end
