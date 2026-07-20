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
        run: @run, group_id: @group.id, discord_user_id: @uid, species_input: "staravia"
      )

      assert result[:ok], result[:error]
      assert_equal "Staravia", result[:species]
      assert_equal "Staravia", @group.soul_link_pokemon.find_by(discord_user_id: @uid).species
    end

    # Prefix resolution means the stored species can differ from what was
    # typed, so the caller needs the canonical name back to confirm with.
    test "returns the canonical species for a prefix match" do
      result = SoulLink::DiscordBot.apply_catch_quick_add(
        run: @run, group_id: @group.id, discord_user_id: @uid, species_input: "staravi"
      )

      assert result[:ok], result[:error]
      assert_equal "Staravia", result[:species]
    end

    test "rejects an ambiguous species without writing" do
      result = SoulLink::DiscordBot.apply_catch_quick_add(
        run: @run, group_id: @group.id, discord_user_id: @uid, species_input: "star"
      )

      refute result[:ok]
      assert_match(/did you mean/i, result[:error])
      assert_equal 0, @group.soul_link_pokemon.count
    end

    test "rejects an unknown species without writing" do
      result = SoulLink::DiscordBot.apply_catch_quick_add(
        run: @run, group_id: @group.id, discord_user_id: @uid, species_input: "zzzz"
      )

      refute result[:ok]
      assert_match(/no species matches/i, result[:error])
      assert_equal 0, @group.soul_link_pokemon.count
    end

    # Asserts the error string, not just the absence of a write: the DB
    # unique index and the model validation would also keep Shinx intact, so
    # without this the up-front guard could be deleted and the test stay green.
    test "rejects a player who already has a pokemon in the group" do
      create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: @group,
             discord_user_id: @uid, species: "Shinx")

      result = SoulLink::DiscordBot.apply_catch_quick_add(
        run: @run, group_id: @group.id, discord_user_id: @uid, species_input: "Staravia"
      )

      refute result[:ok]
      assert_equal "You already have a Pokemon in this catch.", result[:error]
      assert_equal "Shinx", @group.soul_link_pokemon.find_by(discord_user_id: @uid).species
    end

    test "rejects an unregistered user" do
      result = SoulLink::DiscordBot.apply_catch_quick_add(
        run: @run, group_id: @group.id, discord_user_id: 999_999_999, species_input: "Staravia"
      )

      refute result[:ok]
      assert_equal "You're not a registered player in this run.", result[:error]
      assert_equal 0, @group.soul_link_pokemon.count
    end

    test "rejects a missing group" do
      result = SoulLink::DiscordBot.apply_catch_quick_add(
        run: @run, group_id: 0, discord_user_id: @uid, species_input: "Staravia"
      )

      refute result[:ok]
      assert_equal "That catch no longer exists.", result[:error]
    end

    test "rejects a nil run" do
      result = SoulLink::DiscordBot.apply_catch_quick_add(
        run: nil, group_id: @group.id, discord_user_id: @uid, species_input: "Staravia"
      )

      refute result[:ok]
      assert_equal "That catch no longer exists.", result[:error]
      assert_equal 0, @group.soul_link_pokemon.count
    end

    # Catch posts from an inactive run keep their live ADD MY POKEMON button
    # in Discord forever. A click on one of those must not write into the old
    # run's group while a different run is current.
    test "rejects a group belonging to a different run" do
      other_run = create(:soul_link_run, active: false, catches_channel_id: 2222)
      other_group = create(:soul_link_pokemon_group, soul_link_run: other_run)

      result = SoulLink::DiscordBot.apply_catch_quick_add(
        run: @run, group_id: other_group.id, discord_user_id: @uid, species_input: "Staravia"
      )

      refute result[:ok]
      assert_equal "That catch no longer exists.", result[:error]
      assert_equal 0, other_group.soul_link_pokemon.count
    end

    test "rejects a group that is already marked dead" do
      @group.update!(status: "dead")

      result = SoulLink::DiscordBot.apply_catch_quick_add(
        run: @run, group_id: @group.id, discord_user_id: @uid, species_input: "Staravia"
      )

      refute result[:ok]
      assert_equal "That catch is already marked dead.", result[:error]
      assert_equal 0, @group.soul_link_pokemon.count
    end

    test "refreshes the embed on success" do
      refreshed = []
      SoulLink::CatchMessage.stub(:post_or_update, ->(g) { refreshed << g.id }) do
        SoulLink::DiscordBot.apply_catch_quick_add(
          run: @run, group_id: @group.id, discord_user_id: @uid, species_input: "Staravia"
        )
      end
      assert_equal [ @group.id ], refreshed
    end
  end
end
