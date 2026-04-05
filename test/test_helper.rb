ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

# OmniAuth test mode — prevents real OAuth calls
OmniAuth.config.test_mode = true

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

# Helper for integration tests that need a logged-in session
module LoginHelper
  GUILD_ID = 999999999999999999

  def login_as(discord_user_id, guild_id: GUILD_ID)
    OmniAuth.config.mock_auth[:discord] = OmniAuth::AuthHash.new(
      provider: "discord",
      uid: discord_user_id.to_s,
      info: { name: "TestUser", image: nil },
      credentials: { token: "fake_token" }
    )

    # Stub the Faraday guild API call made by SessionsController#create.
    # Use a lambda so Minitest calls it (handling the block Faraday.get yields)
    # instead of trying to return a static value that ignores the block.
    fake_response = Struct.new(:body).new([{ "id" => guild_id.to_s }].to_json)
    stub_get = lambda { |_url, &_block| fake_response }
    Faraday.stub(:get, stub_get) do
      get "/auth/discord/callback"
    end
  end
end

class ActionDispatch::IntegrationTest
  include LoginHelper
end
