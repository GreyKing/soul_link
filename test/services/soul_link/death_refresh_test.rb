require "test_helper"

module SoulLink
  # Pure cores of the death REFRESH buttons — mirrors CatchRefreshTest.
  class DeathRefreshTest < ActiveSupport::TestCase
    setup do
      @run = create(:soul_link_run, deaths_channel_id: 2222,
                    deaths_panel_message_id: 8080)
      @group = create(:soul_link_pokemon_group, soul_link_run: @run, status: "dead")
    end

    test "refreshing an existing death re-syncs the embed" do
      calls = []
      SoulLink::DeathMessage.stub(:post_or_update, ->(g) { calls << g.id }) do
        result = SoulLink::DiscordBot.apply_death_refresh(run: @run, group_id: @group.id)
        assert result[:ok], result[:error]
      end
      assert_equal [ @group.id ], calls
    end

    test "refreshing a missing death returns a not-found error" do
      result = SoulLink::DiscordBot.apply_death_refresh(run: @run, group_id: 999_999)
      refute result[:ok]
      assert_match(/no longer exists/i, result[:error])
    end

    test "refreshing a death with a nil run returns a not-found error" do
      result = SoulLink::DiscordBot.apply_death_refresh(run: nil, group_id: @group.id)
      refute result[:ok]
    end

    test "refreshing the panel re-renders it" do
      calls = []
      SoulLink::DeathsPanel.stub(:refresh, ->(run) { calls << run.id }) do
        result = SoulLink::DiscordBot.apply_deaths_panel_refresh(run: @run)
        assert result[:ok], result[:error]
      end
      assert_equal [ @run.id ], calls
    end

    test "refreshing the panel with a nil run is a not-found error and no-ops" do
      calls = []
      SoulLink::DeathsPanel.stub(:refresh, ->(run) { calls << run&.id }) do
        result = SoulLink::DiscordBot.apply_deaths_panel_refresh(run: nil)
        refute result[:ok]
      end
      assert_empty calls
    end
  end
end
