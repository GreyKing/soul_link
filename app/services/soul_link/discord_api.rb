require "discordrb"

module SoulLink
  class DiscordApi
    def initialize
      @token = "Bot #{Rails.application.credentials.discord[:token]}"
    end

    def create_run_channels(guild_id, run)
      server_id = guild_id.to_s

      # Create category
      category = Discordrb::API::Server.create_channel(
        @token, server_id,
        GameState.category_name(run.run_number),
        4, # category type
        nil, nil, nil, nil, nil, nil, nil
      )
      category_data = JSON.parse(category.body)
      category_id = category_data["id"]

      # Create text channels under category
      general = create_text_channel(server_id, "general", category_id)
      catches = create_text_channel(server_id, "catches", category_id)
      deaths = create_text_channel(server_id, "deaths", category_id)

      run.update!(
        category_id: category_id,
        general_channel_id: general["id"],
        catches_channel_id: catches["id"],
        deaths_channel_id: deaths["id"]
      )

      run
    end

    private

    def create_text_channel(server_id, name, parent_id)
      response = Discordrb::API::Server.create_channel(
        @token, server_id,
        name,
        0, # text channel type
        nil, nil, nil, nil, nil, parent_id, nil
      )
      JSON.parse(response.body)
    end
  end
end
