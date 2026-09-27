require "test_helper"

# Broadcasts must go through the primary database so a broadcast from any
# process (the Discord bot, the jobs worker, a console) reaches browsers
# connected to Puma.
class SolidCableAdapterTest < ActiveSupport::TestCase
  CHANNEL = "phase2:probe".freeze

  test "Solid Cable uses the primary database" do
    assert_equal ActiveRecord::Base.connection_db_config, SolidCable::Record.connection_db_config
  end

  test "a broadcast is written to solid_cable_messages" do
    adapter = ActionCable::SubscriptionAdapter::SolidCable.new(ActionCable.server)
    messages = -> { SolidCable::Message.where(channel_hash: SolidCable::Message.channel_hash_for(CHANNEL)) }

    begin
      assert_difference -> { messages.call.count }, 1 do
        adapter.broadcast(CHANNEL, { hello: "world" }.to_json)
        # solid_cable 4.1 writes from a background thread. shutdown closes the
        # queue and joins the writer, so the insert has happened afterwards.
        # The writer thread uses the test's pinned transactional connection
        # (lock_threads), so the insert is rolled back with the test.
        adapter.shutdown
      end
    ensure
      adapter.shutdown
    end

    assert_equal({ "hello" => "world" }, JSON.parse(messages.call.last.payload))
  end
end
