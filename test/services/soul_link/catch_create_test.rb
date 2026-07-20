require "test_helper"

module SoulLink
  # Pure core of the bot's "new catch" modal (handle_catch_submission). Tested
  # as a class method for the same reason apply_catch_quick_add is — the bot
  # instance can't be booted in tests (it opens a Discord connection).
  class CatchCreateTest < ActiveSupport::TestCase
    setup do
      @run = create(:soul_link_run, catches_channel_id: 1111)
      @uid = SoulLink::GameState.players.first["discord_user_id"]
    end

    test "creates the group and the submitter's pokemon" do
      result = SoulLink::DiscordBot.apply_catch_create(
        run: @run, nickname: "TOMMY", location: "route_205",
        species: "Staravia", discord_user_id: @uid
      )

      assert result[:ok], result[:error]
      group = result[:group]
      assert_equal "TOMMY", group.nickname
      assert_equal "Staravia",
                   group.soul_link_pokemon.find_by(discord_user_id: @uid).species
    end

    # The whole point of this change: bot-created catches must get the same
    # live embed website-created catches get (PokemonGroupsController#create).
    test "posts the live catch embed on creation" do
      calls = []
      SoulLink::CatchMessage.stub(:post_or_update, ->(g) { calls << g.id }) do
        result = SoulLink::DiscordBot.apply_catch_create(
          run: @run, nickname: "TOMMY", location: "route_205",
          species: "Staravia", discord_user_id: @uid
        )
        assert result[:ok]
        assert_equal [ result[:group].id ], calls
      end
    end

    # Atomic: a blank species must leave no orphan group behind (the pre-
    # extraction code created the group before the pokemon and left it).
    test "rolls back the group when the pokemon is invalid" do
      assert_no_difference "SoulLinkPokemonGroup.count" do
        result = SoulLink::DiscordBot.apply_catch_create(
          run: @run, nickname: "TOMMY", location: "route_205",
          species: "", discord_user_id: @uid
        )
        refute result[:ok]
      end
    end
  end
end
