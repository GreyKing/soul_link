require 'discordrb'
require 'yaml'

module SoulLink
  class DiscordBot
    DISCORD_GUILD_ID = 404132250385383433
    DISCORD_CHANNEL_ID = 713775445635760206
    PANEL_MESSAGE_CONTENT = "🎮 **Pokemon: Soul Link Panel**\n" \
      "Use the buttons below to record a new catch or a death.\n" \
      "To start a new run, click Start New Run."

    def initialize
      creds = Rails.application.credentials.discord
      @client_id = creds[:client_id]
      @bot_token = creds[:token]
      @guild_id = DISCORD_GUILD_ID
      @channel_id = DISCORD_CHANNEL_ID

      @bot = Discordrb::Bot.new(
        token: @bot_token,
        intents: :unprivileged
      )

      register_slash_commands
      register_interactions
    end

    def run
      @bot.run
    end

    private

    attr_reader :bot, :channel_id, :guild_id

    # ------------------------
    # Slash Commands
    # ------------------------
    def register_slash_commands
      # Register a guild-scoped `/panel` command (updates each time the bot boots)
      bot.register_application_command(
        :panel,
        'Post the Soul Link control panel',
        server_id: guild_id
      )

      # Handler for when `/panel` is used
      bot.application_command(:panel) do |event|
        # Only allow it in the designated Soul Link channel
        if event.channel.id != channel_id
          event.respond content: "Please use this command in the Soul Link channel."
          next
        end

        post_panel(event.channel)
        event.respond content: "Panel posted."
      end

      # Example `/status` command using your YAML state
      bot.register_application_command(
        :status,
        'Show the current boss info',
        server_id: guild_id
      )

      bot.application_command(:status) do |event|
        info = SoulLink::GameState.current_boss_info

        event.respond content: [
          "**Next Boss:** #{info[:name]}",
          "**Recommended Level:** #{info[:recommended_level]}",
          "**Notes:** #{info[:notes]}"
        ].join("\n")
      end
    end

    # ------------------------
    # Button & Modal handlers
    # ------------------------
    def register_interactions
      # Button: "New Catch"
      bot.button(custom_id: 'soul_link:new_catch') do |event|
        open_catch_modal(event)
      end

      # Button: "New Death"
      bot.button(custom_id: 'soul_link:new_death') do |event|
        open_death_modal(event)
      end

      # Modal submission for "New Catch"
      bot.modal_submit(custom_id: 'soul_link:catch_modal') do |event|
        payload = extract_modal_values(event)
        SoulLink::Events.record_catch(
          user_id: event.user.id,
          name: payload['catch_name'],
          location: payload['catch_location']
        )

        respond_ephemeral(event, "✅ Logged catch: **#{payload['catch_name']}** at **#{payload['catch_location']}**")
      end

      # Modal submission for "New Death"
      bot.modal_submit(custom_id: 'soul_link:death_modal') do |event|
        payload = extract_modal_values(event)
        SoulLink::Events.record_death(
          user_id: event.user.id,
          name: payload['death_name'],
          location: payload['death_location']
        )

        respond_ephemeral(event, "🩸 Logged death: **#{payload['death_name']}** at **#{payload['death_location']}**")
      end
    end

    # ------------------------
    # Panel message + buttons
    # ------------------------
    def post_panel(channel)
      components = [
        {
          type: 1, # Action Row
          components: [
            {
              type: 2, # Button
              style: 1, # Primary
              label: 'New Catch',
              custom_id: 'soul_link:new_catch'
            },
            {
              type: 2, # Button
              style: 4, # Danger
              label: 'New Death',
              custom_id: 'soul_link:new_death'
            }
          ]
        }
      ]

      # send_message(channel_id, content, tts = false, embed = nil, file = nil, allowed_mentions = nil, reply_to = nil, components = nil)
      channel.send_message(PANEL_MESSAGE_CONTENT, false, nil, nil, nil, nil, components)
    end

    # ------------------------
    # Modals
    # ------------------------
    def open_catch_modal(event)
      components = [
        {
          type: 1, # action row
          components: [
            {
              type: 4, # text input
              custom_id: 'catch_name',
              label: 'Pokemon Name',
              style: 1, # short
              required: true,
              min_length: 1,
              max_length: 100
            }
          ]
        },
        {
          type: 1,
          components: [
            {
              type: 4, # text input
              custom_id: 'catch_location',
              label: 'Location',
              style: 1, # short
              required: true,
              min_length: 1,
              max_length: 100
            }
          ]
        }
      ]

      Discordrb::API::Interaction.create_interaction_modal_response(
        event.token, # interaction_token
        event.id, # interaction_id
        'soul_link:catch_modal', # modal custom_id
        'New Catch', # title
        components
      )
    end

    def open_death_modal(event)
      components = [
        {
          type: 1,
          components: [
            {
              type: 4,
              custom_id: 'death_name',
              label: 'Pokemon Name',
              style: 1,
              required: true,
              min_length: 1,
              max_length: 100
            }
          ]
        },
        {
          type: 1,
          components: [
            {
              type: 4,
              custom_id: 'death_location',
              label: 'Location',
              style: 1,
              required: true,
              min_length: 1,
              max_length: 100
            }
          ]
        }
      ]

      Discordrb::API::Interaction.create_interaction_modal_response(
        event.token,
        event.id,
        'soul_link:death_modal',
        'New Death',
        components
      )
    end

    # ------------------------
    # Helpers
    # ------------------------

    # modal components come back nested; this flattens to a { custom_id => value } hash
    def extract_modal_values(event)
      values = {}

      # Shape is roughly: data["components"] => [ { "components" => [ { "custom_id", "value", ... } ] }, ... ]
      event.data['components'].each do |row|
        row['components'].each do |component|
          values[component['custom_id']] = component['value']
        end
      end

      values
    end

    # simple convenience for ephemeral "got it" style responses
    def respond_ephemeral(event, content)
      Discordrb::API::Interaction.create_interaction_response(
        event.token,
        event.id,
        4, # CHANNEL_MESSAGE_WITH_SOURCE
        content,
        nil,
        nil,
        nil,
        1 << 6 # EPHEMERAL flag
      )
    end
  end
end