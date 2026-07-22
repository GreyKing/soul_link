require "test_helper"

module SoulLink
  # Mirrors CatchMessageTest — the death embed is the same stateless REST
  # service targeting the deaths channel and the `discord_death_message_id`
  # column. Positional stubs match the real discordrb signatures so a regression
  # to keyword args binds wrong and fails loudly.
  class DeathMessageTest < ActiveSupport::TestCase
    setup do
      @run = create(:soul_link_run, deaths_channel_id: 2222)
      @group = create(:soul_link_pokemon_group, soul_link_run: @run,
                      nickname: "TOMMY", location: "route_205", status: "dead")
      @posts = []
      @edits = []
      @deletes = []
    end

    def with_stubbed_discord(&block)
      post_stub = lambda do |_token, channel_id, _message, _tts = false, embeds = nil,
                             _nonce = nil, _attachments = nil, _allowed = nil,
                             _reference = nil, components = nil, *_rest|
        @posts << { channel_id: channel_id, embeds: embeds, components: components }
        { "id" => "9001" }.to_json
      end

      edit_stub = lambda do |_token, channel_id, message_id, _message,
                             _mentions = nil, embeds = nil, components = nil, *_rest|
        @edits << { channel_id: channel_id, message_id: message_id,
                    embeds: embeds, components: components }
        { "id" => message_id.to_s }.to_json
      end

      delete_stub = lambda do |_token, channel_id, message_id, *_rest|
        @deletes << { channel_id: channel_id, message_id: message_id }
        { "id" => message_id.to_s }.to_json
      end

      Discordrb::API::Channel.stub(:create_message, post_stub) do
        Discordrb::API::Channel.stub(:edit_message, edit_stub) do
          Discordrb::API::Channel.stub(:delete_message, delete_stub) do
            SoulLink::DeathMessage.stub(:resolve_token, "Bot test", &block)
          end
        end
      end
    end

    test "posts once to the deaths channel and persists the message id" do
      with_stubbed_discord { SoulLink::DeathMessage.post_or_update(@group) }

      assert_equal 1, @posts.length
      assert_equal 2222, @posts.first[:channel_id]
      assert_equal 9001, @group.reload.discord_death_message_id
    end

    test "the embed lands in the embeds parameter, not swallowed by tts" do
      with_stubbed_discord { SoulLink::DeathMessage.post_or_update(@group) }

      embeds = @posts.first[:embeds]
      assert_kind_of Array, embeds, "embeds must be positional arg 5, not a keyword"
      assert_includes embeds.first[:title], "💀"
      assert_includes embeds.first[:title], "RIP"
    end

    test "the embed is red" do
      with_stubbed_discord { SoulLink::DeathMessage.post_or_update(@group) }
      assert_equal SoulLink::DeathMessage::EMBED_COLOR, @posts.first[:embeds].first[:color]
    end

    test "second call edits rather than posting again" do
      with_stubbed_discord do
        SoulLink::DeathMessage.post_or_update(@group)
        SoulLink::DeathMessage.post_or_update(@group)
      end

      assert_equal 1, @posts.length, "must not post a second message"
      assert_equal 1, @edits.length
      assert_equal 9001, @edits.first[:message_id]
    end

    test "is a no-op when the run has no deaths channel" do
      @run.update!(deaths_channel_id: nil)
      with_stubbed_discord { SoulLink::DeathMessage.post_or_update(@group) }

      assert_empty @posts
      assert_empty @edits
      assert_nil @group.reload.discord_death_message_id
    end

    test "is a no-op when group is nil" do
      with_stubbed_discord { SoulLink::DeathMessage.post_or_update(nil) }
      assert_empty @posts
    end

    def assert_reposts_after(error)
      @group.update!(discord_death_message_id: 4242)

      failing_edit = ->(*_args) { raise error }
      post_stub = lambda do |_token, channel_id, _message, _tts = false, embeds = nil, *_rest|
        @posts << { channel_id: channel_id, embeds: embeds }
        { "id" => "5005" }.to_json
      end

      Discordrb::API::Channel.stub(:create_message, post_stub) do
        Discordrb::API::Channel.stub(:edit_message, failing_edit) do
          SoulLink::DeathMessage.stub(:resolve_token, "Bot test") do
            SoulLink::DeathMessage.post_or_update(@group)
          end
        end
      end

      assert_equal 1, @posts.length
      assert_equal 5005, @group.reload.discord_death_message_id
    end

    test "re-posts exactly once when Discord reports the message unknown" do
      assert_reposts_after(Discordrb::Errors::UnknownMessage.new("Unknown Message"))
    end

    test "re-posts exactly once when the edit 404s without a body" do
      assert_reposts_after(RestClient::NotFound.new)
    end

    test "never raises when Discord is unreachable" do
      boom = ->(*_args) { raise SocketError, "no network" }

      Discordrb::API::Channel.stub(:create_message, boom) do
        SoulLink::DeathMessage.stub(:resolve_token, "Bot test") do
          assert_nothing_raised { SoulLink::DeathMessage.post_or_update(@group) }
        end
      end
      assert_nil @group.reload.discord_death_message_id
    end

    test "embed names every fallen pokemon in the group" do
      players = SoulLink::GameState.players.first(2)
      players.each_with_index do |player, i|
        create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: @group,
               discord_user_id: player["discord_user_id"],
               species: %w[Staravia Shinx][i], status: "dead")
      end

      with_stubbed_discord { SoulLink::DeathMessage.post_or_update(@group) }

      description = @posts.first[:embeds].first[:description]
      assert_includes description, "Staravia"
      assert_includes description, "Shinx"
      players.each { |p| assert_includes description, p["display_name"] }
    end

    test "embed surfaces the eulogy when present" do
      @group.update!(eulogy: "Gone but not forgotten")
      with_stubbed_discord { SoulLink::DeathMessage.post_or_update(@group) }

      assert_includes @posts.first[:embeds].first[:description], "Gone but not forgotten"
    end

    test "embed carries the refresh button addressed to the group" do
      with_stubbed_discord { SoulLink::DeathMessage.post_or_update(@group) }

      button = @posts.first[:components].first[:components].first
      assert_equal "soul_link:death_refresh:#{@group.id}", button[:custom_id]
    end

    test "delete removes the discord message and clears the id" do
      @group.update!(discord_death_message_id: 7777)
      with_stubbed_discord { SoulLink::DeathMessage.delete(@group) }

      assert_equal 1, @deletes.length
      assert_equal 7777, @deletes.first[:message_id]
      assert_nil @group.reload.discord_death_message_id
    end

    test "delete is a no-op when the group never posted" do
      with_stubbed_discord { SoulLink::DeathMessage.delete(@group) }
      assert_empty @deletes
    end

    test "delete is a no-op when the group is nil" do
      with_stubbed_discord { SoulLink::DeathMessage.delete(nil) }
      assert_empty @deletes
    end

    test "delete never raises when Discord is unreachable" do
      @group.update!(discord_death_message_id: 7777)
      boom = ->(*_args) { raise SocketError, "no network" }

      Discordrb::API::Channel.stub(:delete_message, boom) do
        SoulLink::DeathMessage.stub(:resolve_token, "Bot test") do
          assert_nothing_raised { SoulLink::DeathMessage.delete(@group) }
        end
      end
    end
  end
end
