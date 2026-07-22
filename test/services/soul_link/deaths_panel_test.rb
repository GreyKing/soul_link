require "test_helper"

module SoulLink
  # The Fallen Pokemon roster panel, made editable from the web process via the
  # stateless REST layer (the bot's old load_message/edit path only worked
  # inside the bot process).
  class DeathsPanelTest < ActiveSupport::TestCase
    setup do
      @run = create(:soul_link_run, deaths_channel_id: 2222,
                    deaths_panel_message_id: 8080)
      @group = create(:soul_link_pokemon_group, soul_link_run: @run,
                      nickname: "TOMMY", location: "route_205", status: "dead")
      @edits = []
    end

    def with_stubbed_discord(&block)
      edit_stub = lambda do |_token, channel_id, message_id, _message,
                             _mentions = nil, embeds = nil, components = nil, *_rest|
        @edits << { channel_id: channel_id, message_id: message_id,
                    embeds: embeds, components: components }
        { "id" => message_id.to_s }.to_json
      end

      Discordrb::API::Channel.stub(:edit_message, edit_stub) do
        SoulLink::DeathsPanel.stub(:resolve_token, "Bot test", &block)
      end
    end

    test "refresh edits the stored panel message in the deaths channel" do
      with_stubbed_discord { SoulLink::DeathsPanel.refresh(@run) }

      assert_equal 1, @edits.length
      assert_equal 2222, @edits.first[:channel_id]
      assert_equal 8080, @edits.first[:message_id]
    end

    test "refresh is a no-op when the run has no panel message id" do
      @run.update!(deaths_panel_message_id: nil)
      with_stubbed_discord { SoulLink::DeathsPanel.refresh(@run) }
      assert_empty @edits
    end

    test "the roster embed lands in the embeds parameter and lists dead groups" do
      with_stubbed_discord { SoulLink::DeathsPanel.refresh(@run) }

      embed = @edits.first[:embeds].first
      assert_includes embed[:title], "Fallen Pokemon"
      assert_includes embed[:description], "TOMMY"
    end

    test "the panel carries all three action buttons including refresh" do
      with_stubbed_discord { SoulLink::DeathsPanel.refresh(@run) }

      custom_ids = @edits.first[:components].first[:components].map { |b| b[:custom_id] }
      assert_includes custom_ids, "soul_link:move_to_deaths"
      assert_includes custom_ids, "soul_link:add_uncaught_death"
      assert_includes custom_ids, "soul_link:deaths_refresh"
    end

    test "refresh never raises when Discord is unreachable" do
      boom = ->(*_args) { raise SocketError, "no network" }

      Discordrb::API::Channel.stub(:edit_message, boom) do
        SoulLink::DeathsPanel.stub(:resolve_token, "Bot test") do
          assert_nothing_raised { SoulLink::DeathsPanel.refresh(@run) }
        end
      end
    end

    test "refresh clears the stale panel id when Discord reports it unknown" do
      unknown = ->(*_args) { raise Discordrb::Errors::UnknownMessage.new("Unknown Message") }

      Discordrb::API::Channel.stub(:edit_message, unknown) do
        SoulLink::DeathsPanel.stub(:resolve_token, "Bot test") do
          SoulLink::DeathsPanel.refresh(@run)
        end
      end

      assert_nil @run.reload.deaths_panel_message_id
    end
  end
end
