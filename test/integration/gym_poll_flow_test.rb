require "test_helper"

class GymPollFlowTest < ActionDispatch::IntegrationTest
  PLAYERS = [
    { "discord_user_id" => 111, "display_name" => "A" },
    { "discord_user_id" => 222, "display_name" => "B" },
    { "discord_user_id" => 333, "display_name" => "C" },
    { "discord_user_id" => 444, "display_name" => "D" }
  ].freeze
  PLAYER_IDS = PLAYERS.map { |p| p["discord_user_id"] }.freeze

  setup do
    @run = create(:soul_link_run, :with_schedule_template, guild_id: LoginHelper::GUILD_ID)
    login_as(PLAYER_IDS.first)
  end

  def with_player_data(&block)
    SoulLink::GameState.stub(:players, PLAYERS) do
      SoulLink::GameState.stub(:player_ids, PLAYER_IDS, &block)
    end
  end

  test "happy path: create -> vote -> lock -> reset" do
    with_player_data do
      # Freeze time to Monday 6am Phoenix — before the Mon 7pm slot materializes,
      # so votes on slot 0 never raise PastSlotError regardless of wall-clock day.
      travel_to Time.find_zone("America/Phoenix").local(2026, 5, 11, 6, 0) do
        # Create
        assert_difference -> { GymPoll.count }, 1 do
          post gym_poll_path
        end
        poll = GymPoll.last
        poll.update!(discord_channel_id: 999, discord_message_id: 555)

        # Vote (model-level — channel test covers the channel path)
        poll.vote!(111, 0, "yes")
        poll.vote!(222, 0, "yes")
        poll.vote!(333, 0, "yes")
        assert_enqueued_with(job: GymPollLockJob, args: [poll.id]) do
          poll.vote!(444, 0, "yes")
        end
        assert poll.reload.locked?

        # Verify additional votes are rejected on locked poll
        assert_raises(GymPoll::LockedError) { poll.vote!(111, 1, "yes") }

        # Reset
        assert_difference -> { GymPoll.count }, -1 do
          delete gym_poll_path
        end
      end
    end
  end
end
