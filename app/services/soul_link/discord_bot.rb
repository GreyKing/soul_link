# app/services/soul_link/discord_bot.rb
require 'discordrb'
require 'yaml'

module SoulLink
  class DiscordBot
    DISCORD_GUILD_ID = 404132250385383433
    INITIAL_GENERAL_CHANNEL_ID = 1467925828577923214

    def initialize
      creds = Rails.application.credentials.discord
      @client_id = creds[:client_id]
      @bot_token = creds[:token]
      @guild_id = DISCORD_GUILD_ID
      @channel_id = INITIAL_GENERAL_CHANNEL_ID

      @bot = Discordrb::Bot.new(
        token: @bot_token,
        intents: [:server_messages, :servers]
      )

      register_commands
      register_interactions
    end

    def run
      @bot.run
    end

    private

    attr_reader :bot, :guild_id

    # ------------------------
    # Commands Registration
    # ------------------------
    def register_commands
      # /start_new_run - Creates a new Soul Link run
      bot.register_application_command(
        :start_new_run,
        'Start a new Soul Link run',
        server_id: guild_id
      )

      bot.application_command(:start_new_run) do |event|
        event.defer(ephemeral: true)

        begin
          run = create_new_run(event)
          event.edit_response(content: "✅ Started **Run ##{run.run_number}**!\n" \
            "Created category and channels. Good luck!")
        rescue => e
          Rails.logger.error "Failed to start new run: #{e.message}"
          event.edit_response(content: "❌ Failed to start new run: #{e.message}")
        end
      end

      # Text command for !next_gym
      bot.message(content: '!next_gym') do |event|
        next unless event.channel.id == SoulLinkRun.current&.general_channel_id

        gym = GameState.next_gym_info
        event.respond embed: build_gym_embed(gym)
      end
    end

    # ------------------------
    # Button & Modal Handlers
    # ------------------------
    def register_interactions
      # Button: Add catch
      bot.button(custom_id: /^soul_link:add_catch/) do |event|
        open_catch_modal(event)
      end

      # Button: Mark caught pokemon as dead
      bot.button(custom_id: /^soul_link:move_to_deaths/) do |event|
        open_move_to_deaths_modal(event)
      end

      # Button: Add uncaught death
      bot.button(custom_id: /^soul_link:add_uncaught_death/) do |event|
        open_uncaught_death_modal(event)
      end

      # Modal: New catch submission
      bot.modal_submit(custom_id: 'soul_link:catch_modal') do |event|
        handle_catch_submission(event)
      end

      # Modal: Move to deaths submission
      bot.modal_submit(custom_id: 'soul_link:move_deaths_modal') do |event|
        handle_move_to_deaths_submission(event)
      end

      # Modal: Uncaught death submission
      bot.modal_submit(custom_id: 'soul_link:uncaught_death_modal') do |event|
        handle_uncaught_death_submission(event)
      end
    end

    # ------------------------
    # Run Creation
    # ------------------------
    def create_new_run(event)
      server = bot.servers[guild_id]

      # Deactivate current run if exists
      SoulLinkRun.current&.deactivate!

      # Determine next run number
      last_run = SoulLinkRun.order(run_number: :desc).first
      next_number = last_run ? last_run.run_number + 1 : 1

      # Create category
      category = server.create_channel(
        "Run ##{next_number}",
        4 # 4 = category type
      )

      # Move or find general channel
      general_channel = if SoulLinkRun.current
                          server.channels.find { |c| c.id == SoulLinkRun.current.general_channel_id }
                        else
                          server.channels.find { |c| c.id == INITIAL_GENERAL_CHANNEL_ID }
                        end

      if general_channel
        general_channel.parent = category
      else
        general_channel = server.create_channel(
          'general',
          0, # 0 = text channel
          parent: category
        )
      end

      # Create catches channel
      catches_channel = server.create_channel(
        'catches',
        0,
        parent: category
      )

      # Create deaths channel
      deaths_channel = server.create_channel(
        'deaths',
        0,
        parent: category
      )

      # Create database record
      run = SoulLinkRun.create!(
        run_number: next_number,
        category_id: category.id,
        general_channel_id: general_channel.id,
        catches_channel_id: catches_channel.id,
        deaths_channel_id: deaths_channel.id
      )

      # Post initial panels
      post_catches_panel(catches_channel, run)
      post_deaths_panel(deaths_channel, run)

      run
    end

    # ------------------------
    # Panel Creation & Updates
    # ------------------------
    def post_catches_panel(channel, run)
      message = channel.send_message(
        '',
        false,
        build_catches_embed(run),
        nil, nil, nil,
        build_catches_buttons
      )

      run.update!(catches_panel_message_id: message.id)
    end

    def post_deaths_panel(channel, run)
      message = channel.send_message(
        '',
        false,
        build_deaths_embed(run),
        nil, nil, nil,
        build_deaths_buttons
      )

      run.update!(deaths_panel_message_id: message.id)
    end

    def update_catches_panel(run)
      return unless run.catches_panel_message_id

      channel = bot.channel(run.catches_channel_id)
      message = channel.load_message(run.catches_panel_message_id)

      message.edit('', build_catches_embed(run), build_catches_buttons)
    rescue => e
      Rails.logger.error "Failed to update catches panel: #{e.message}"
    end

    def update_deaths_panel(run)
      return unless run.deaths_panel_message_id

      channel = bot.channel(run.deaths_channel_id)
      message = channel.load_message(run.deaths_panel_message_id)

      message.edit('', build_deaths_embed(run), build_deaths_buttons)
    rescue => e
      Rails.logger.error "Failed to update deaths panel: #{e.message}"
    end

    # ------------------------
    # Embeds
    # ------------------------
    def build_catches_embed(run)
      catches = run.catches

      description = if catches.empty?
                      "*No Pokemon caught yet. Click the + button to add your first catch!*"
                    else
                      catches.map.with_index(1) do |pokemon, idx|
                        "**#{idx}.** #{pokemon.name} *(#{GameState.location_name(pokemon.location)})*"
                      end.join("\n")
                    end

      Discordrb::Webhooks::Embed.new(
        title: "🎯 Caught Pokemon",
        description: description,
        color: 0x00ff00,
        footer: { text: "Run ##{run.run_number} | Total: #{catches.count}" },
        timestamp: Time.now
      )
    end

    def build_deaths_embed(run)
      deaths = run.deaths

      description = if deaths.empty?
                      "*No deaths yet. Stay safe out there!*"
                    else
                      deaths.map.with_index(1) do |pokemon, idx|
                        "**#{idx}.** #{pokemon.name} *(#{GameState.location_name(pokemon.location)})*"
                      end.join("\n")
                    end

      Discordrb::Webhooks::Embed.new(
        title: "💀 Fallen Pokemon",
        description: description,
        color: 0xff0000,
        footer: { text: "Run ##{run.run_number} | Total: #{deaths.count}" },
        timestamp: Time.now
      )
    end

    def build_gym_embed(gym)
      Discordrb::Webhooks::Embed.new(
        title: "🏆 Next Gym",
        fields: [
          { name: "Gym", value: gym['name'] || 'Unknown', inline: true },
          { name: "Recommended Level", value: gym['recommended_level']&.to_s || gym['max_level']&.to_s || 'N/A', inline: true }
        ],
        color: 0xffd700,
        timestamp: Time.now
      )
    end

    # ------------------------
    # Buttons
    # ------------------------
    def build_catches_buttons
      [
        {
          type: 1, # Action Row
          components: [
            {
              type: 2, # Button
              style: 3, # Success (green)
              label: '➕ Add Catch',
              custom_id: 'soul_link:add_catch'
            }
          ]
        }
      ]
    end

    def build_deaths_buttons
      [
        {
          type: 1, # Action Row
          components: [
            {
              type: 2, # Button
              style: 4, # Danger (red)
              label: '💀 Move Caught to Deaths',
              custom_id: 'soul_link:move_to_deaths'
            },
            {
              type: 2, # Button
              style: 2, # Secondary (gray)
              label: '➕ Add Uncaught Death',
              custom_id: 'soul_link:add_uncaught_death'
            }
          ]
        }
      ]
    end

    # ------------------------
    # Modals
    # ------------------------
    def open_catch_modal(event)
      location_options = GameState.location_choices.first(25) # Discord limit

      components = [
        {
          type: 1,
          components: [
            {
              type: 4, # text input
              custom_id: 'pokemon_name',
              label: 'Pokemon Name',
              style: 1, # short
              required: true,
              min_length: 1,
              max_length: 50,
              placeholder: 'e.g., Pikachu'
            }
          ]
        },
        {
          type: 1,
          components: [
            {
              type: 4,
              custom_id: 'location',
              label: 'Location (route key)',
              style: 1,
              required: true,
              min_length: 1,
              max_length: 50,
              placeholder: 'e.g., route_201'
            }
          ]
        }
      ]

      Discordrb::API::Interaction.create_interaction_modal_response(
        event.token,
        event.id,
        'soul_link:catch_modal',
        'Add New Catch',
        components
      )
    end

    def open_move_to_deaths_modal(event)
      components = [
        {
          type: 1,
          components: [
            {
              type: 4,
              custom_id: 'pokemon_name',
              label: 'Pokemon Name (from catches)',
              style: 1,
              required: true,
              placeholder: 'Exact name from catches list'
            }
          ]
        },
        {
          type: 1,
          components: [
            {
              type: 4,
              custom_id: 'death_location',
              label: 'Death Location (route key)',
              style: 1,
              required: false,
              placeholder: 'Leave blank to use catch location'
            }
          ]
        }
      ]

      Discordrb::API::Interaction.create_interaction_modal_response(
        event.token,
        event.id,
        'soul_link:move_deaths_modal',
        'Move Pokemon to Deaths',
        components
      )
    end

    def open_uncaught_death_modal(event)
      components = [
        {
          type: 1,
          components: [
            {
              type: 4,
              custom_id: 'pokemon_name',
              label: 'Pokemon Name',
              style: 1,
              required: true,
              placeholder: 'e.g., Starly'
            }
          ]
        },
        {
          type: 1,
          components: [
            {
              type: 4,
              custom_id: 'location',
              label: 'Location (route key)',
              style: 1,
              required: true,
              placeholder: 'e.g., route_202'
            }
          ]
        }
      ]

      Discordrb::API::Interaction.create_interaction_modal_response(
        event.token,
        event.id,
        'soul_link:uncaught_death_modal',
        'Add Uncaught Death',
        components
      )
    end

    # ------------------------
    # Modal Handlers
    # ------------------------
    def handle_catch_submission(event)
      run = SoulLinkRun.current
      unless run
        respond_ephemeral(event, "❌ No active run found!")
        return
      end

      values = extract_modal_values(event)

      pokemon = run.soul_link_pokemon.create!(
        name: values['pokemon_name'],
        location: values['location'],
        status: 'caught',
        discord_user_id: event.user.id
      )

      update_catches_panel(run)
      respond_ephemeral(event, "✅ Added **#{pokemon.name}** to catches!")
    rescue => e
      respond_ephemeral(event, "❌ Error: #{e.message}")
    end

    def handle_move_to_deaths_submission(event)
      run = SoulLinkRun.current
      unless run
        respond_ephemeral(event, "❌ No active run found!")
        return
      end

      values = extract_modal_values(event)
      pokemon_name = values['pokemon_name']
      death_location = values['death_location'].presence

      pokemon = run.catches.find_by("LOWER(name) = ?", pokemon_name.downcase)
      unless pokemon
        respond_ephemeral(event, "❌ Could not find **#{pokemon_name}** in catches!")
        return
      end

      pokemon.mark_as_dead!(location: death_location)

      update_catches_panel(run)
      update_deaths_panel(run)

      respond_ephemeral(event, "💀 Moved **#{pokemon.name}** to deaths. RIP.")
    rescue => e
      respond_ephemeral(event, "❌ Error: #{e.message}")
    end

    def handle_uncaught_death_submission(event)
      run = SoulLinkRun.current
      unless run
        respond_ephemeral(event, "❌ No active run found!")
        return
      end

      values = extract_modal_values(event)

      pokemon = run.soul_link_pokemon.create!(
        name: values['pokemon_name'],
        location: values['location'],
        status: 'dead',
        discord_user_id: event.user.id,
        died_at: Time.current
      )

      update_deaths_panel(run)
      respond_ephemeral(event, "💀 Added **#{pokemon.name}** to deaths!")
    rescue => e
      respond_ephemeral(event, "❌ Error: #{e.message}")
    end

    # ------------------------
    # Helpers
    # ------------------------
    def extract_modal_values(event)
      values = {}
      event.data['components'].each do |row|
        row['components'].each do |component|
          values[component['custom_id']] = component['value']
        end
      end
      values
    end

    def respond_ephemeral(event, content)
      Discordrb::API::Interaction.create_interaction_response(
        event.token,
        event.id,
        4, # CHANNEL_MESSAGE_WITH_SOURCE
        content,
        nil, nil, nil,
        1 << 6 # EPHEMERAL flag
      )
    end
  end
end