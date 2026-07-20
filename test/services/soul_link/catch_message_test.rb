require "test_helper"

module SoulLink
  class CatchMessageTest < ActiveSupport::TestCase
    setup do
      @run = create(:soul_link_run, catches_channel_id: 1111)
      @group = create(:soul_link_pokemon_group, soul_link_run: @run,
                      nickname: "TOMMY", location: "route_205")
      @posts = []
      @edits = []
    end

    # Positional stubs, matching the real discordrb signatures. If the service
    # ever regresses to keyword args these bind wrong and the tests fail —
    # which is the entire point of spelling them out.
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

      Discordrb::API::Channel.stub(:create_message, post_stub) do
        Discordrb::API::Channel.stub(:edit_message, edit_stub) do
          SoulLink::CatchMessage.stub(:resolve_token, "Bot test", &block)
        end
      end
    end

    test "posts once and persists the message id" do
      with_stubbed_discord { SoulLink::CatchMessage.post_or_update(@group) }

      assert_equal 1, @posts.length
      assert_equal 1111, @posts.first[:channel_id]
      assert_equal 9001, @group.reload.discord_catch_message_id
    end

    test "the embed lands in the embeds parameter, not swallowed by tts" do
      with_stubbed_discord { SoulLink::CatchMessage.post_or_update(@group) }

      embeds = @posts.first[:embeds]
      assert_kind_of Array, embeds, "embeds must be positional arg 5, not a keyword"
      assert_includes embeds.first[:title], "NEW CATCH"
    end

    test "second call edits rather than posting again" do
      with_stubbed_discord do
        SoulLink::CatchMessage.post_or_update(@group)
        SoulLink::CatchMessage.post_or_update(@group)
      end

      assert_equal 1, @posts.length, "must not post a second message"
      assert_equal 1, @edits.length
      assert_equal 9001, @edits.first[:message_id]
      assert_kind_of Array, @edits.first[:embeds]
    end

    test "is a no-op when the run has no catches channel" do
      @run.update!(catches_channel_id: nil)
      with_stubbed_discord { SoulLink::CatchMessage.post_or_update(@group) }

      assert_empty @posts
      assert_empty @edits
      assert_nil @group.reload.discord_catch_message_id
    end

    test "is a no-op when group is nil" do
      with_stubbed_discord { SoulLink::CatchMessage.post_or_update(nil) }
      assert_empty @posts
    end

    # Drives post_or_update against a group whose stored message is gone,
    # with `edit_message` raising `error`. Asserts the stale id is replaced
    # by exactly one re-post.
    def assert_reposts_after(error)
      @group.update!(discord_catch_message_id: 4242)

      failing_edit = ->(*_args) { raise error }
      post_stub = lambda do |_token, channel_id, _message, _tts = false, embeds = nil, *_rest|
        @posts << { channel_id: channel_id, embeds: embeds }
        { "id" => "5005" }.to_json
      end

      Discordrb::API::Channel.stub(:create_message, post_stub) do
        Discordrb::API::Channel.stub(:edit_message, failing_edit) do
          SoulLink::CatchMessage.stub(:resolve_token, "Bot test") do
            SoulLink::CatchMessage.post_or_update(@group)
          end
        end
      end

      assert_equal 1, @posts.length
      assert_equal 5005, @group.reload.discord_catch_message_id
    end

    # This is what a deleted message ACTUALLY raises. `Discordrb::API.request`
    # intercepts the RestClient::NotFound, parses the body, and re-raises
    # `Errors.error_class_for(10008)` — an UnknownMessage, which does not
    # inherit from RestClient::NotFound. A rescue on RestClient::NotFound
    # alone is dead code in production.
    #
    # UnknownMessage is a CodeError whose constructor is
    # `initialize(message, errors = nil)`, so it must be instantiated with a
    # message — bare `raise UnknownMessage` raises ArgumentError instead.
    test "re-posts exactly once when Discord reports the message unknown" do
      assert_reposts_after(Discordrb::Errors::UnknownMessage.new("Unknown Message"))
    end

    # Reachable when the 404 response has no body: API.request skips the
    # conversion and re-raises the original RestClient exception.
    test "re-posts exactly once when the edit 404s without a body" do
      assert_reposts_after(RestClient::NotFound.new)
    end

    test "never raises when Discord is unreachable" do
      boom = ->(*_args) { raise SocketError, "no network" }

      Discordrb::API::Channel.stub(:create_message, boom) do
        SoulLink::CatchMessage.stub(:resolve_token, "Bot test") do
          assert_nothing_raised { SoulLink::CatchMessage.post_or_update(@group) }
        end
      end
      assert_nil @group.reload.discord_catch_message_id
    end

    test "embed lists every registered player, filled or not" do
      players = SoulLink::GameState.players
      uid = players.first["discord_user_id"]
      create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: @group,
             discord_user_id: uid, species: "Staravia", level: 12)

      with_stubbed_discord { SoulLink::CatchMessage.post_or_update(@group) }

      description = @posts.first[:embeds].first[:description]
      assert_includes description, "Staravia"
      players.each { |p| assert_includes description, p["display_name"] }
      assert_includes description, SoulLink::CatchMessage::NOT_CAUGHT
    end

    test "embed carries the add-species button addressed to the group" do
      with_stubbed_discord { SoulLink::CatchMessage.post_or_update(@group) }

      button = @posts.first[:components].first[:components].first
      assert_equal "soul_link:catch_add:#{@group.id}", button[:custom_id]
    end

    test "caught embed carries both add and refresh buttons" do
      with_stubbed_discord { SoulLink::CatchMessage.post_or_update(@group) }

      buttons = @posts.first[:components].first[:components]
      custom_ids = buttons.map { |b| b[:custom_id] }
      assert_includes custom_ids, "soul_link:catch_add:#{@group.id}"
      assert_includes custom_ids, "soul_link:catch_refresh:#{@group.id}"
    end

    test "dead group renders a red death embed with no buttons" do
      @group.update!(discord_catch_message_id: 4242, status: "dead")
      with_stubbed_discord { SoulLink::CatchMessage.post_or_update(@group) }

      embed = @edits.first[:embeds].first
      assert_includes embed[:title], "💀"
      assert_equal SoulLink::CatchMessage::DEAD_EMBED_COLOR, embed[:color]
      assert_empty @edits.first[:components]
    end
  end
end
