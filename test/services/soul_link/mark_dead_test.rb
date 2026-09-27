require "test_helper"

module SoulLink
  # Pure core of the bot's Mark Dead flow (eulogy modal). Tested as a class
  # method because the bot instance can't be booted in tests.
  class MarkDeadTest < ActiveSupport::TestCase
    GREY = 153665622641737728

    setup do
      @run = create(:soul_link_run)
      @group = create(:soul_link_pokemon_group, soul_link_run: @run)
      create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: @group, discord_user_id: GREY)
    end

    def apply(group_id: @group.id)
      SoulLink::CatchMessage.stub(:post_or_update, nil) do
        SoulLink::DeathMessage.stub(:post_or_update, nil) do
          SoulLink::DiscordNotifier.stub(:notify_wipe, nil) do
            SoulLink::DiscordBot.apply_mark_dead(run: @run, group_id: group_id, location: "original")
          end
        end
      end
    end

    test "marks the group dead" do
      result = apply

      assert result[:ok], result[:error]
      assert @group.reload.dead?
    end

    test "runs wipe detection, same as the website" do
      apply

      assert @run.reload.wiped_at.present?, "the player's only pokemon died, so the run should wipe"
    end

    test "refuses on a wiped run" do
      @run.update!(wiped_at: Time.current)

      result = apply

      assert_not result[:ok]
      assert_equal SoulLinkRun::READ_ONLY_MESSAGE, result[:error]
      assert @group.reload.caught?
    end

    test "reports an unknown group" do
      result = apply(group_id: 0)

      assert_not result[:ok]
      assert_equal "Could not find that group!", result[:error]
    end
  end
end
