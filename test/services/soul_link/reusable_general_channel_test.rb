require "test_helper"

module SoulLink
  class ReusableGeneralChannelTest < ActiveSupport::TestCase
    Channel = Struct.new(:id, :name)
    Server = Struct.new(:channels)

    test "returns the previous run's general channel" do
      general = Channel.new(42, "general")
      server = Server.new([ Channel.new(7, "catches"), general ])
      previous = build(:soul_link_run, general_channel_id: 42)

      assert_equal general, SoulLink::DiscordBot.reusable_general_channel(server, previous)
    end

    test "returns nil with no previous run or when its channel is gone" do
      server = Server.new([ Channel.new(7, "general") ])

      assert_nil SoulLink::DiscordBot.reusable_general_channel(server, nil)
      assert_nil SoulLink::DiscordBot.reusable_general_channel(server, build(:soul_link_run, general_channel_id: 42))
    end
  end
end
