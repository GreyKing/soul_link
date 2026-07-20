require "test_helper"

module SoulLink
  class CatchQuickAddTest < ActiveSupport::TestCase
    setup do
      @run = create(:soul_link_run, catches_channel_id: 1111)
      @group = create(:soul_link_pokemon_group, soul_link_run: @run)
      @uid = SoulLink::GameState.players.first["discord_user_id"]
    end

    # `post_or_update` is a real call in most of these tests. It is safe —
    # the test env has no discord credentials, so `resolve_token` returns nil
    # and the service early-returns before any HTTP. Stubbed explicitly in the
    # one test that asserts on it.
    test "creates the pokemon for the clicking user" do
      result = SoulLink::DiscordBot.apply_catch_quick_add(
        group_id: @group.id, discord_user_id: @uid, species_input: "staravia"
      )

      assert result[:ok], result[:error]
      assert_equal "Staravia", @group.soul_link_pokemon.find_by(discord_user_id: @uid).species
    end

    test "rejects an ambiguous species without writing" do
      result = SoulLink::DiscordBot.apply_catch_quick_add(
        group_id: @group.id, discord_user_id: @uid, species_input: "star"
      )

      refute result[:ok]
      assert_match(/did you mean/i, result[:error])
      assert_equal 0, @group.soul_link_pokemon.count
    end

    test "rejects an unknown species without writing" do
      result = SoulLink::DiscordBot.apply_catch_quick_add(
        group_id: @group.id, discord_user_id: @uid, species_input: "zzzz"
      )

      refute result[:ok]
      assert_equal 0, @group.soul_link_pokemon.count
    end

    test "rejects a player who already has a pokemon in the group" do
      create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: @group,
             discord_user_id: @uid, species: "Shinx")

      result = SoulLink::DiscordBot.apply_catch_quick_add(
        group_id: @group.id, discord_user_id: @uid, species_input: "Staravia"
      )

      refute result[:ok]
      assert_equal "Shinx", @group.soul_link_pokemon.find_by(discord_user_id: @uid).species
    end

    test "rejects an unregistered user" do
      result = SoulLink::DiscordBot.apply_catch_quick_add(
        group_id: @group.id, discord_user_id: 999_999_999, species_input: "Staravia"
      )

      refute result[:ok]
      assert_equal 0, @group.soul_link_pokemon.count
    end

    test "rejects a missing group" do
      result = SoulLink::DiscordBot.apply_catch_quick_add(
        group_id: 0, discord_user_id: @uid, species_input: "Staravia"
      )
      refute result[:ok]
    end

    test "refreshes the embed on success" do
      refreshed = []
      SoulLink::CatchMessage.stub(:post_or_update, ->(g) { refreshed << g.id }) do
        SoulLink::DiscordBot.apply_catch_quick_add(
          group_id: @group.id, discord_user_id: @uid, species_input: "Staravia"
        )
      end
      assert_equal [ @group.id ], refreshed
    end
  end
end
