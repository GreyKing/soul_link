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
