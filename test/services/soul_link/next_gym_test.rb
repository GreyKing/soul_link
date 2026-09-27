require "test_helper"

module SoulLink
  # Pure core of the `!next_gym` text command. Tested as a class method
  # because the bot instance can't be booted in tests.
  class NextGymTest < ActiveSupport::TestCase
    test "returns the gym after the ones the run has beaten" do
      run = create(:soul_link_run, gyms_defeated: 3)

      assert_equal SoulLink::GameState.gym_info_by_number(4),
                   SoulLink::DiscordBot.next_gym_for(run)
    end

    test "returns nil once all eight gyms are beaten" do
      run = create(:soul_link_run, gyms_defeated: 8)

      assert_nil SoulLink::DiscordBot.next_gym_for(run)
    end
  end
end
