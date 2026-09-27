require "test_helper"

# The bot and the jobs worker are separate processes. Only a database-backed
# adapter lets their broadcasts reach browsers connected to Puma.
class CableConfigTest < ActiveSupport::TestCase
  def cable_config(env)
    ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/cable.yml")).fetch(env)
  end

  %w[development production].each do |env|
    test "#{env} broadcasts through Solid Cable in the primary database" do
      config = cable_config(env)

      assert_equal "solid_cable", config["adapter"]
      assert_not config.key?("connects_to"), "Solid Cable must share the primary database"
      assert_equal "0.1.seconds", config["polling_interval"]
      assert_equal "1.day", config["message_retention"]
      assert_equal [ 1, 2, 3, 5, 10, 15, 30, 60, 60, 60 ], config["reconnect_attempts"], "listener must survive a MySQL restart"
    end
  end

  test "test keeps the in-memory test adapter" do
    assert_equal({ "adapter" => "test" }, cable_config("test"))
  end
end
