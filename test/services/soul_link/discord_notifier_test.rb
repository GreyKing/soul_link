require "test_helper"

module SoulLink
  # Step 19 — DiscordNotifier contract tests. Every test stubs
  # `Discordrb::API::Channel.create_message` so no real HTTP fires. Token
  # resolution is also stubbed (test env has no Discord credentials);
  # the notifier's `send_message` short-circuits on a blank token before
  # ever reaching the API stub, so we patch `resolve_token` to return a
  # static "Bot test" string.
  class DiscordNotifierTest < ActiveSupport::TestCase
    GREY = 153665622641737728

    setup do
      @run = create(:soul_link_run,
                    catches_channel_id: 1111,
                    deaths_channel_id: 2222,
                    general_channel_id: 3333)
      @captured = []
    end

    # Run a block with `Discordrb::API::Channel.create_message` and
    # `resolve_token` both stubbed. Captures every message payload into
    # `@captured` so tests can assert on channel + content.
    def with_stubbed_notifier(&block)
      stub = ->(token, channel_id, content, *_rest) { @captured << { token: token, channel_id: channel_id, content: content } }
      Discordrb::API::Channel.stub(:create_message, stub) do
        SoulLink::DiscordNotifier.stub(:resolve_token, "Bot test", &block)
      end
    end

    # ── nil-run guard (defense in depth) ─────────────────────────────────

    test "every notifier method is a silent no-op when run is nil" do
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_catch(nil, GREY, "Starly", "Route 201", 5)
        SoulLink::DiscordNotifier.notify_group_death(nil, nil)
        SoulLink::DiscordNotifier.notify_gym_player_progress(nil, 1, GREY)
        SoulLink::DiscordNotifier.notify_gym_team_beaten(nil, 1)
        SoulLink::DiscordNotifier.notify_wipe(nil, GREY, "Route 201")
        SoulLink::DiscordNotifier.notify_run_complete(nil)
      end
      assert_equal [], @captured
    end

    # ── nil-channel guard ─────────────────────────────────────────────────

    test "notify_catch is a no-op when run.catches_channel_id is blank" do
      @run.update!(catches_channel_id: nil)
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_catch(@run, GREY, "Starly", "Route 201", 5)
      end
      assert_equal [], @captured
    end

    test "notify_group_death is a no-op when run.deaths_channel_id is blank" do
      @run.update!(deaths_channel_id: nil)
      group = create(:soul_link_pokemon_group, soul_link_run: @run)
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_group_death(@run, group)
      end
      assert_equal [], @captured
    end

    test "notify_gym_player_progress is a no-op when general_channel_id is blank" do
      @run.update!(general_channel_id: nil)
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_gym_player_progress(@run, 1, GREY)
      end
      assert_equal [], @captured
    end

    test "notify_gym_team_beaten is a no-op when general_channel_id is blank" do
      @run.update!(general_channel_id: nil)
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_gym_team_beaten(@run, 1)
      end
      assert_equal [], @captured
    end

    test "notify_wipe is a no-op when general_channel_id is blank" do
      @run.update!(general_channel_id: nil)
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_wipe(@run, GREY, "Route 201")
      end
      assert_equal [], @captured
    end

    test "notify_run_complete is a no-op when general_channel_id is blank" do
      @run.update!(general_channel_id: nil)
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_run_complete(@run)
      end
      assert_equal [], @captured
    end

    # ── channel routing ──────────────────────────────────────────────────

    test "notify_catch routes to catches_channel_id" do
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_catch(@run, GREY, "Starly", "Route 201", 5)
      end
      assert_equal 1, @captured.size
      assert_equal 1111, @captured.first[:channel_id]
    end

    test "notify_gym_player_progress routes to general_channel_id" do
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_gym_player_progress(@run, 1, GREY)
      end
      assert_equal 1, @captured.size
      assert_equal 3333, @captured.first[:channel_id]
    end

    test "notify_gym_team_beaten routes to general_channel_id" do
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_gym_team_beaten(@run, 1)
      end
      assert_equal 3333, @captured.first[:channel_id]
    end

    test "notify_wipe routes to general_channel_id" do
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_wipe(@run, GREY, "Route 201")
      end
      assert_equal 3333, @captured.first[:channel_id]
    end

    test "notify_run_complete routes to general_channel_id" do
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_run_complete(@run)
      end
      assert_equal 3333, @captured.first[:channel_id]
    end

    # ── message formatting (happy path) ──────────────────────────────────

    test "notify_catch formats with player + species + route + level" do
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_catch(@run, GREY, "Starly", "Route 201", 5)
      end
      assert_equal "Grey just caught a Starly on Route 201 (Lv 5)", @captured.first[:content]
    end

    test "notify_catch appends ' [off-feed]' when off_feed: true" do
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_catch(@run, GREY, "Starly", "Route 201", 5, off_feed: true)
      end
      assert_equal "Grey just caught a Starly on Route 201 (Lv 5) [off-feed]", @captured.first[:content]
    end

    test "notify_group_death sends exactly one message for a four-pokemon group" do
      group = create(:soul_link_pokemon_group, soul_link_run: @run,
                     nickname: "TOMMY", location: "route_205")
      SoulLink::GameState.players.first(4).each_with_index do |player, i|
        create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: group,
               discord_user_id: player["discord_user_id"],
               species: %w[Staravia Shinx Bidoof Kricketot][i])
      end

      with_stubbed_notifier { SoulLink::DiscordNotifier.notify_group_death(@run, group) }

      assert_equal 1, @captured.length
      assert_equal 2222, @captured.first[:channel_id]
    end

    test "notify_group_death names every fallen pokemon" do
      group = create(:soul_link_pokemon_group, soul_link_run: @run, nickname: "TOMMY")
      uid = SoulLink::GameState.players.first["discord_user_id"]
      create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: group,
             discord_user_id: uid, species: "Staravia")

      with_stubbed_notifier { SoulLink::DiscordNotifier.notify_group_death(@run, group) }

      content = @captured.first[:content]
      assert_includes content, "Staravia"
      assert_includes content, "TOMMY"
      assert_includes content, SoulLink::GameState.location_name(group.location)
      assert_includes content, SoulLink::GameState.player_name(uid)
    end

    test "notify_group_death is a no-op with a nil run or nil group" do
      group = create(:soul_link_pokemon_group, soul_link_run: @run)
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_group_death(nil, group)
        SoulLink::DiscordNotifier.notify_group_death(@run, nil)
      end
      assert_empty @captured
    end

    test "notify_gym_player_progress formats with player + gym number + leader + town" do
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_gym_player_progress(@run, 1, GREY)
      end
      # Gym 1 = Roark (Oreburgh City) per gym_info.yml
      assert_match(/^Grey earned the badge from Gym 1 \(Roark, .+\)$/, @captured.first[:content])
    end

    test "notify_gym_team_beaten formats with badge marker + gym number + leader + town" do
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_gym_team_beaten(@run, 1)
      end
      assert_match(/^🏅 Gym 1 \(Roark, .+\) beaten by the team!$/, @captured.first[:content])
    end

    test "notify_wipe formats with skull markers + player + route" do
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_wipe(@run, GREY, "Route 201")
      end
      assert_equal "💀💀💀 RUN ENDED — Grey wiped on Route 201", @captured.first[:content]
    end

    test "notify_run_complete formats with trophy marker + run number" do
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_run_complete(@run)
      end
      assert_equal "🏆 HALL OF FAME — Run ##{@run.run_number} complete!", @captured.first[:content]
    end

    # ── exception swallow + logger.warn ──────────────────────────────────

    test "REST exceptions from create_message are swallowed and logged at warn level" do
      log = StringIO.new
      original_logger = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(log)

      raising_stub = ->(*) { raise SocketError, "stubbed network failure" }
      Discordrb::API::Channel.stub(:create_message, raising_stub) do
        SoulLink::DiscordNotifier.stub(:resolve_token, "Bot test") do
          assert_nothing_raised do
            SoulLink::DiscordNotifier.notify_catch(@run, GREY, "Starly", "Route 201", 5)
          end
        end
      end

      assert_match(/DiscordNotifier failed: SocketError stubbed network failure/, log.string)
      assert_match(/run=#{@run.id} method=notify_catch/, log.string)
    ensure
      Rails.logger = original_logger if original_logger
    end

    test "unexpected StandardError is also swallowed (belt-and-suspenders rescue)" do
      raising_stub = ->(*) { raise RuntimeError, "out of left field" }
      Discordrb::API::Channel.stub(:create_message, raising_stub) do
        SoulLink::DiscordNotifier.stub(:resolve_token, "Bot test") do
          assert_nothing_raised do
            SoulLink::DiscordNotifier.notify_run_complete(@run)
          end
        end
      end
    end

    # ── token resolution fallback ────────────────────────────────────────

    test "when resolve_token returns blank, send_message short-circuits without calling create_message" do
      called = false
      stub = ->(*) { called = true }
      # Stub resolve_token to return nil explicitly. We previously relied on
      # the real path (no `RAILS_MASTER_KEY` in test env -> credentials.discord
      # is nil -> resolve_token is nil), but other parallel tests that stub
      # `Rails.application.credentials.discord` can leave behind a
      # singleton-class method on the shared credentials object — making this
      # test flaky depending on parallel-worker scheduling. Stubbing
      # `resolve_token` directly removes that environmental dependency while
      # preserving the contract under test: blank token -> no API call.
      Discordrb::API::Channel.stub(:create_message, stub) do
        SoulLink::DiscordNotifier.stub(:resolve_token, nil) do
          SoulLink::DiscordNotifier.notify_run_complete(@run)
        end
      end
      assert_not called, "create_message should not be invoked when token is blank"
    end
  end
end
