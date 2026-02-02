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

      # /end_current_run - Ends the current active run
      bot.register_application_command(
        :end_current_run,
        'End the current Soul Link run',
        server_id: guild_id
      )

      bot.application_command(:end_current_run) do |event|
        event.defer(ephemeral: true)

        run = SoulLinkRun.current
        unless run
          event.edit_response(content: "❌ No active run found!")
          next
        end

        # Show confirmation with stats
        stats = "**Run ##{run.run_number} Summary:**\n" \
          "🎯 Caught: #{run.catches.count}\n" \
          "💀 Dead: #{run.deaths.count}\n\n" \
          "This will deactivate the run but keep all data. " \
          "Use `/start_new_run` to begin Run ##{run.run_number + 1}."

        run.deactivate!

        event.edit_response(content: "✅ Ended Run ##{run.run_number}\n\n#{stats}")
      end

      # /run_status - Show current run statistics
      bot.register_application_command(
        :run_status,
        'Show current run statistics',
        server_id: guild_id
      )

      bot.application_command(:run_status) do |event|
        run = SoulLinkRun.current
        unless run
          event.respond(content: "❌ No active run found!", ephemeral: true)
          next
        end

        embed = Discordrb::Webhooks::Embed.new(
          title: "📊 Run ##{run.run_number} Statistics",
          color: 0x5865F2,
          fields: [
            { name: "🎯 Currently Caught", value: run.catches.count.to_s, inline: true },
            { name: "💀 Deaths", value: run.deaths.count.to_s, inline: true },
            { name: "📈 Total Caught", value: run.soul_link_pokemon.count.to_s, inline: true }
          ],
          footer: { text: "Use /end_current_run to end this run" },
          timestamp: Time.now
        )

        event.respond(embed: embed, ephemeral: true)
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
      # Button: Add catch - show location selector
      bot.button(custom_id: /^soul_link:add_catch/) do |event|
        show_location_selector(event, 'catch')
      end

      # Select menu: Location selected for catch
      bot.select_menu(custom_id: /^soul_link:location_select:catch:/) do |event|
        location = event.values.first
        open_catch_modal(event, location)
      end

      # Button: Mark caught pokemon as dead - show pokemon selector
      bot.button(custom_id: /^soul_link:move_to_deaths/) do |event|
        show_caught_pokemon_selector(event)
      end

      # Select menu: Pokemon selected to move to deaths
      bot.select_menu(custom_id: /^soul_link:pokemon_select:move_deaths:/) do |event|
        pokemon_id = event.values.first
        show_death_location_selector(event, pokemon_id)
      end

      # Select menu: Death location selected
      bot.select_menu(custom_id: /^soul_link:death_location_select:/) do |event|
        # Extract pokemon_id from custom_id
        pokemon_id = event.interaction.data['custom_id'].split(':').last
        location = event.values.first
        handle_move_to_deaths_final(event, pokemon_id, location)
      end

      # Button: Add uncaught death - show location selector
      bot.button(custom_id: /^soul_link:add_uncaught_death/) do |event|
        show_location_selector(event, 'uncaught_death')
      end

      # Select menu: Location selected for uncaught death
      bot.select_menu(custom_id: /^soul_link:location_select:uncaught_death:/) do |event|
        location = event.values.first
        open_uncaught_death_modal(event, location)
      end

      # Modal: New catch submission
      bot.modal_submit(custom_id: 'soul_link:catch_modal') do |event|
        handle_catch_submission(event)
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
    # Location Selector
    # ------------------------
    def show_location_selector(event, action_type)
      locations = GameState.location_choices.first(25) # Discord limit

      components = [
        {
          type: 1, # Action Row
          components: [
            {
              type: 3, # Select Menu
              custom_id: "soul_link:location_select:#{action_type}:",
              placeholder: 'Choose a location',
              options: locations
            }
          ]
        }
      ]

      event.respond(
        content: 'Select the location:',
        components: components,
        ephemeral: true
      )
    end

    def show_caught_pokemon_selector(event)
      run = SoulLinkRun.current
      unless run
        event.respond(content: "❌ No active run found!", ephemeral: true)
        return
      end

      caught = run.catches
      if caught.empty?
        event.respond(content: "❌ No caught Pokemon to move to deaths!", ephemeral: true)
        return
      end

      options = caught.first(25).map do |pokemon|
        {
          label: "#{pokemon.name} (#{GameState.location_name(pokemon.location)})",
          value: pokemon.id.to_s,
          description: "Caught at #{GameState.location_name(pokemon.location)}"
        }
      end

      components = [
        {
          type: 1,
          components: [
            {
              type: 3,
              custom_id: 'soul_link:pokemon_select:move_deaths:',
              placeholder: 'Choose a Pokemon to mark as dead',
              options: options
            }
          ]
        }
      ]

      event.respond(
        content: 'Select which Pokemon died:',
        components: components,
        ephemeral: true
      )
    end

    def show_death_location_selector(event, pokemon_id)
      locations = GameState.location_choices.first(25)

      components = [
        {
          type: 1,
          components: [
            {
              type: 3,
              custom_id: "soul_link:death_location_select:#{pokemon_id}",
              placeholder: 'Where did it die? (or skip to use catch location)',
              options: [
                { label: 'Use original catch location', value: 'original', description: 'Keep the catch location' }
              ] + locations
            }
          ]
        }
      ]

      event.respond(
        content: 'Select the death location:',
        components: components,
        ephemeral: true
      )
    end

    # ------------------------
    # Modals
    # ------------------------
    def open_catch_modal(event, location)
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
              label: 'Location',
              style: 1,
              required: true,
              value: location, # Pre-fill with selected location
              min_length: 1,
              max_length: 50
            }
          ]
        }
      ]

      event.show_modal(
        title: 'Add New Catch',
        custom_id: 'soul_link:catch_modal',
        components: components
      )
    end


    def open_uncaught_death_modal(event, location)
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
              label: 'Location',
              style: 1,
              required: true,
              value: location, # Pre-fill with selected location
              min_length: 1,
              max_length: 50
            }
          ]
        }
      ]

      event.show_modal(
        title: 'Add Uncaught Death',
        custom_id: 'soul_link:uncaught_death_modal',
        components: components
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

    def handle_move_to_deaths_final(event, pokemon_id, location)
      run = SoulLinkRun.current
      unless run
        event.respond(content: "❌ No active run found!", ephemeral: true)
        return
      end

      pokemon = run.catches.find_by(id: pokemon_id)
      unless pokemon
        event.respond(content: "❌ Could not find that Pokemon!", ephemeral: true)
        return
      end

      # Use original location if 'original' was selected
      death_location = location == 'original' ? nil : location
      pokemon.mark_as_dead!(location: death_location)

      update_catches_panel(run)
      update_deaths_panel(run)

      event.respond(content: "💀 Moved **#{pokemon.name}** to deaths. RIP.", ephemeral: true)
    rescue => e
      event.respond(content: "❌ Error: #{e.message}", ephemeral: true)
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

      # Try different ways discordrb might structure this
      if event.respond_to?(:values)
        # If there's a direct values method
        return event.values
      elsif event.respond_to?(:components) && event.components
        # If components exist
        event.components.each do |row|
          next unless row.respond_to?(:components)
          row.components.each do |component|
            values[component.custom_id] = component.value
          end
        end
      elsif event.respond_to?(:interaction) && event.interaction
        # Try via interaction object
        data = event.interaction.data
        if data && data['components']
          data['components'].each do |row|
            row['components'].each do |component|
              values[component['custom_id']] = component['value']
            end
          end
        end
      end

      values
    rescue => e
      Rails.logger.error "Failed to extract modal values: #{e.message}"
      Rails.logger.error "Event class: #{event.class}"
      Rails.logger.error "Event methods: #{event.methods.grep(/component|value|data/).join(', ')}"
      {}
    end

    def respond_ephemeral(event, content)
      event.respond(content: content, ephemeral: true)
    end
  end
end