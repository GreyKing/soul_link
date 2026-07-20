# app/services/soul_link/discord_bot.rb
require 'discordrb'
require 'yaml'

module SoulLink
  class DiscordBot
    # Pure, testable core of the catch quick-add interaction. Kept separate
    # from the `bot.modal_submit` block so it can be tested without booting
    # the bot's event loop.
    #
    # Scoped to `run` for the same reason every sibling handler is: catch
    # posts from an inactive run keep live buttons in Discord forever, so an
    # unscoped lookup would let a click on an old post write into that old
    # run's group.
    #
    # Returns { ok: true, species: "<canonical>" } or
    # { ok: false, error: "<player-facing message>" }.
    def self.apply_catch_quick_add(run:, group_id:, discord_user_id:, species_input:)
      group = run&.soul_link_pokemon_groups&.find_by(id: group_id)
      return { ok: false, error: "That catch no longer exists." } if group.nil?
      return { ok: false, error: "That catch is already marked dead." } if group.dead?

      unless SoulLink::GameState.player_ids.include?(discord_user_id)
        return { ok: false, error: "You're not a registered player in this run." }
      end

      if group.soul_link_pokemon.exists?(discord_user_id: discord_user_id)
        return { ok: false, error: "You already have a Pokemon in this catch." }
      end

      resolution = SoulLink::SpeciesResolver.call(species_input)
      unless resolution.resolved?
        return { ok: false, error: species_error(species_input, resolution) }
      end

      run.soul_link_pokemon.create!(
        soul_link_pokemon_group: group,
        discord_user_id: discord_user_id,
        species: resolution.species,
        name: group.nickname,
        location: group.location,
        status: group.status
      )

      SoulLink::CatchMessage.post_or_update(group)
      { ok: true, species: resolution.species }
    rescue ActiveRecord::RecordNotUnique
      { ok: false, error: "You already have a Pokemon in this catch." }
    rescue ActiveRecord::RecordInvalid => e
      { ok: false, error: e.record.errors.full_messages.join(", ") }
    end

    # Pure core of the catch REFRESH button: re-render the embed from current
    # DB state. Read-only, so no ownership/registration gate. Run-scoped for
    # the same reason quick-add is — a stale post must not touch a live run.
    #
    # Returns { ok: true } or { ok: false, error: "<player-facing message>" }.
    def self.apply_catch_refresh(run:, group_id:)
      group = run&.soul_link_pokemon_groups&.find_by(id: group_id)
      return { ok: false, error: "That catch group no longer exists." } if group.nil?

      SoulLink::CatchMessage.post_or_update(group)
      { ok: true }
    end

    def self.species_error(input, resolution)
      if resolution.candidates.any?
        "Did you mean: #{resolution.candidates.join(', ')}?"
      else
        "No species matches \"#{input}\"."
      end
    end
    private_class_method :species_error

    def initialize
      creds = Rails.application.credentials.discord
      @client_id = creds[:client_id]
      @bot_token = creds[:token]

      @bot = Discordrb::Bot.new(
        token: @bot_token,
        intents: [ :server_messages, :servers ]
      )

      register_commands
      register_interactions
    end

    def run
      @bot.run
    end

    private

    attr_reader :bot

    # ------------------------
    # Commands Registration
    # ------------------------
    def register_commands
      # /start_new_run - Creates a new Soul Link run
      bot.register_application_command(
        :start_new_run,
        'Start a new Soul Link run'
      )

      bot.application_command(:start_new_run) do |event|
        event.defer(ephemeral: true)

        begin
          run = create_new_run(event)
          broadcast_run_state(run.guild_id)
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
        'End the current Soul Link run'
      )

      bot.application_command(:end_current_run) do |event|
        event.defer(ephemeral: true)

        run = current_run(event)
        unless run
          event.edit_response(content: "❌ No active run found!")
          next
        end

        stats = "**Run ##{run.run_number} Summary:**\n" \
          "🎯 Caught Groups: #{run.caught_groups.count}\n" \
          "💀 Dead Groups: #{run.dead_groups.count}\n\n" \
          "This will deactivate the run but keep all data. " \
          "Use `/start_new_run` to begin Run ##{run.run_number + 1}."

        run.deactivate!
        broadcast_run_state(run.guild_id)

        event.edit_response(content: "✅ Ended Run ##{run.run_number}\n\n#{stats}")
      end

      # /run_status - Show current run statistics
      bot.register_application_command(
        :run_status,
        'Show current run statistics'
      )

      bot.application_command(:run_status) do |event|
        run = current_run(event)
        unless run
          event.respond(content: "❌ No active run found!", ephemeral: true)
          next
        end

        embed = Discordrb::Webhooks::Embed.new(
          title: "📊 Run ##{run.run_number} Statistics",
          color: 0x5865F2,
          fields: [
            { name: "🎯 Caught Groups", value: run.caught_groups.count.to_s, inline: true },
            { name: "💀 Dead Groups", value: run.dead_groups.count.to_s, inline: true },
            { name: "📈 Total Species", value: run.soul_link_pokemon.count.to_s, inline: true }
          ],
          footer: { text: "Use /end_current_run to end this run" },
          timestamp: Time.now
        )

        event.respond(embed: embed, ephemeral: true)
      end

      # /post_panels - Post catches/deaths panels to existing channels
      bot.register_application_command(
        :post_panels,
        'Post catches & deaths panels to the current run channels'
      )

      bot.application_command(:post_panels) do |event|
        event.defer(ephemeral: true)

        begin
          run = current_run(event)
          unless run
            event.edit_response(content: "❌ No active run found! Use `/start_new_run` first or import data via rake.")
            next
          end

          catches_channel = bot.channel(run.catches_channel_id)
          deaths_channel = bot.channel(run.deaths_channel_id)

          unless catches_channel && deaths_channel
            event.edit_response(content: "❌ Could not find the catches/deaths channels. " \
              "Make sure the channel IDs are correct in the database.")
            next
          end

          post_catches_panel(catches_channel, run)
          post_deaths_panel(deaths_channel, run)

          event.edit_response(content: "✅ Posted panels to ##{catches_channel.name} and ##{deaths_channel.name}!\n" \
            "Panels will auto-update as you add catches and deaths.")
        rescue => e
          Rails.logger.error "Failed to post panels: #{e.message}"
          event.edit_response(content: "❌ Failed to post panels: #{e.message}")
        end
      end

      # /new_gym_poll - Create a new weekly gym poll from the template
      bot.register_application_command(
        :new_gym_poll,
        'Start a new weekly gym poll from your schedule template'
      )

      bot.application_command(:new_gym_poll) do |event|
        event.defer(ephemeral: true)

        run = current_run(event)
        unless run
          event.edit_response(content: "❌ No active run found! Use `/start_new_run` first.")
          next
        end

        if run.schedule_template.blank?
          event.edit_response(content: "❌ No schedule template set. Configure it on the dashboard Schedule tab first.")
          next
        end

        if run.gym_polls.where(status: %w[open locked]).exists?
          event.edit_response(content: "❌ An open poll already exists. Click the Reset button on it (or run `/reset_gym_poll`) first.")
          next
        end

        unless run.discord_channels_configured?
          event.edit_response(content: "❌ This run has no Discord channels yet. " \
            "Click **SETUP DISCORD** on the dashboard, then try again.")
          next
        end

        channel = bot.channel(run.general_channel_id)
        unless channel
          event.edit_response(content: "❌ Couldn't reach the run's general channel (#{run.general_channel_id}). " \
            "It may have been deleted, or the bot may have lost access.")
          next
        end

        begin
          slots = GymPoll.materialize_slots(run)
          poll = run.gym_polls.create!(state_data: { "slots" => slots, "votes" => {} })

          message = post_initial_poll_message(channel, poll)
          poll.update!(
            discord_channel_id: run.general_channel_id,
            discord_message_id: message.id
          )

          event.edit_response(content: "✅ Posted gym poll to ##{channel.name}!")
        rescue GymPoll::EmptyTemplateError => e
          event.edit_response(content: "❌ #{e.message}")
        rescue => e
          Rails.logger.error "Failed to create gym poll: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          event.edit_response(content: "❌ Failed to create gym poll: #{e.message}")
        end
      end

      # /reset_gym_poll - Destroy the current poll
      bot.register_application_command(
        :reset_gym_poll,
        'Reset the current gym poll'
      )

      bot.application_command(:reset_gym_poll) do |event|
        event.defer(ephemeral: true)
        run = current_run(event)
        unless run
          event.edit_response(content: "❌ No active run found!")
          next
        end

        poll = run.gym_polls.where(status: %w[open locked]).first
        unless poll
          event.edit_response(content: "❌ No active poll to reset.")
          next
        end

        poll.destroy
        event.edit_response(content: "✅ Poll reset. Run `/new_gym_poll` to start the next one.")
      end

      # Text command for !next_gym
      bot.message(content: '!next_gym') do |event|
        next unless event.channel.id == current_run(event)&.general_channel_id

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

      # Button: Add species to existing group
      bot.button(custom_id: /^soul_link:add_species/) do |event|
        show_group_selector_for_species(event)
      end

      # Select menu: Group selected for adding species
      bot.select_menu(custom_id: /^soul_link:group_select:add_species:/) do |event|
        group_id = event.values.first
        open_species_modal(event, group_id)
      end

      # Modal: Species submission for existing group
      bot.modal_submit(custom_id: /^soul_link:species_modal:/) do |event|
        handle_species_submission(event)
      end

      # Button: quick-add your species straight from a catch post
      bot.button(custom_id: /^soul_link:catch_add:/) do |event|
        group_id = event.interaction.data['custom_id'].split(':').last
        open_catch_quick_add_modal(event, group_id)
      end

      # Button: refresh a catch post from current website/DB state
      bot.button(custom_id: /^soul_link:catch_refresh:/) do |event|
        group_id = event.interaction.data['custom_id'].split(':').last
        handle_catch_refresh(event, group_id)
      end

      # Modal: quick-add species submission
      bot.modal_submit(custom_id: /^soul_link:catch_quick_add_modal:/) do |event|
        handle_catch_quick_add(event)
      end

      # Button: Mark caught group as dead - show group selector
      bot.button(custom_id: /^soul_link:move_to_deaths/) do |event|
        show_caught_group_selector(event)
      end

      # Select menu: Group selected to move to deaths
      bot.select_menu(custom_id: /^soul_link:group_select:move_deaths:/) do |event|
        group_id = event.values.first
        show_death_location_selector(event, group_id)
      end

      # Select menu: Death location selected - show eulogy modal
      bot.select_menu(custom_id: /^soul_link:death_location_select:/) do |event|
        group_id = event.interaction.data['custom_id'].split(':').last
        location = event.values.first
        open_eulogy_modal(event, group_id, location)
      end

      # Modal: Eulogy submission for caught death
      bot.modal_submit(custom_id: /^soul_link:eulogy_modal:/) do |event|
        handle_eulogy_submission(event)
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

      # Button: Gym poll vote
      bot.button(custom_id: /^soul_link:gym_poll_vote:/) do |event|
        handle_gym_poll_vote(event)
      end

      # Button: Gym poll reset
      bot.button(custom_id: /^soul_link:gym_poll_reset:/) do |event|
        handle_gym_poll_reset(event)
      end
    end

    # ------------------------
    # Run Creation
    # ------------------------
    def create_new_run(event)
      guild_id = event.server.id
      server = event.server

      # Deactivate current run if exists
      SoulLinkRun.current(guild_id)&.deactivate!

      # Determine next run number
      last_run = SoulLinkRun.for_guild(guild_id).order(run_number: :desc).first
      next_number = last_run ? last_run.run_number + 1 : 1

      # Create category
      category = server.create_channel(
        GameState.category_name(next_number),
        4 # 4 = category type
      )

      # Look for an existing "general" channel inside the current run's category,
      # or create a new one under the new category
      existing_run = SoulLinkRun.current(guild_id)
      general_channel = if existing_run
                          server.channels.find { |c| c.id == existing_run.general_channel_id }
      else
                          server.channels.find { |c| c.name == 'general' && c.parent_id == category.id }
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
        guild_id: guild_id,
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
    # Embeds (Group-Based)
    # ------------------------
    def build_catches_embed(run)
      groups = run.caught_groups.includes(:soul_link_pokemon)

      description = if groups.empty?
                      "*No Pokemon caught yet. Click 'Add Catch' to start a new group!*"
      else
                      groups.map.with_index(1) do |group, idx|
                        lines = [ "**#{idx}.** #{group.nickname} *(#{GameState.location_name(group.location)})*" ]

                        group.soul_link_pokemon.each do |pokemon|
                          lines << "   #{GameState.player_name(pokemon.discord_user_id)}: #{pokemon.species}"
                        end

                        group.missing_players.each do |user_id|
                          lines << "   #{GameState.player_name(user_id)}: *pending*"
                        end

                        lines.join("\n")
                      end.join("\n\n")
      end

      Discordrb::Webhooks::Embed.new(
        title: "🎯 Caught Pokemon",
        description: description,
        color: 0x00ff00,
        footer: { text: "Run ##{run.run_number} | Groups: #{groups.count}" },
        timestamp: Time.now
      )
    end

    def build_deaths_embed(run)
      groups = run.dead_groups.includes(:soul_link_pokemon)

      description = if groups.empty?
                      "*No deaths yet. Stay safe out there!*"
      else
                      groups.map.with_index(1) do |group, idx|
                        lines = [ "**#{idx}.** #{group.nickname} *(#{GameState.location_name(group.location)})*" ]

                        group.soul_link_pokemon.each do |pokemon|
                          lines << "   #{GameState.player_name(pokemon.discord_user_id)}: #{pokemon.species}"
                        end

                        if group.eulogy.present?
                          lines << "   📝 *#{group.eulogy}*"
                        end

                        lines.join("\n")
                      end.join("\n\n")
      end

      Discordrb::Webhooks::Embed.new(
        title: "💀 Fallen Pokemon",
        description: description,
        color: 0xff0000,
        footer: { text: "Run ##{run.run_number} | Groups: #{groups.count}" },
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
            },
            {
              type: 2, # Button
              style: 1, # Primary (blue)
              label: '🔗 Add My Species',
              custom_id: 'soul_link:add_species'
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

    # ------------------------
    # Group Selectors
    # ------------------------
    def show_group_selector_for_species(event)
      run = current_run(event)
      unless run
        event.respond(content: "❌ No active run found!", ephemeral: true)
        return
      end

      user_id = event.user.id

      # Find groups where this player hasn't added their species yet
      incomplete_groups = run.caught_groups.includes(:soul_link_pokemon).select do |group|
        group.species_for(user_id).nil?
      end

      if incomplete_groups.empty?
        event.respond(content: "✅ You've already added your species to all caught groups!", ephemeral: true)
        return
      end

      options = incomplete_groups.first(25).map do |group|
        existing = group.soul_link_pokemon.map { |p|
          "#{GameState.player_name(p.discord_user_id)}: #{p.species}"
        }.join(', ')

        {
          label: "#{group.nickname} (#{GameState.location_name(group.location)})",
          value: group.id.to_s,
          description: existing.truncate(100)
        }
      end

      components = [
        {
          type: 1,
          components: [
            {
              type: 3,
              custom_id: 'soul_link:group_select:add_species:',
              placeholder: 'Choose a group to add your species to',
              options: options
            }
          ]
        }
      ]

      event.respond(
        content: 'Select the group to add your species to:',
        components: components,
        ephemeral: true
      )
    end

    def show_caught_group_selector(event)
      run = current_run(event)
      unless run
        event.respond(content: "❌ No active run found!", ephemeral: true)
        return
      end

      groups = run.caught_groups.includes(:soul_link_pokemon)
      if groups.empty?
        event.respond(content: "❌ No caught groups to move to deaths!", ephemeral: true)
        return
      end

      options = groups.first(25).map do |group|
        species_list = group.soul_link_pokemon.map { |p|
          "#{GameState.player_name(p.discord_user_id)}: #{p.species}"
        }.join(', ')

        {
          label: "#{group.nickname} (#{GameState.location_name(group.location)})",
          value: group.id.to_s,
          description: species_list.truncate(100)
        }
      end

      components = [
        {
          type: 1,
          components: [
            {
              type: 3,
              custom_id: 'soul_link:group_select:move_deaths:',
              placeholder: 'Choose a group to mark as dead',
              options: options
            }
          ]
        }
      ]

      event.respond(
        content: 'Select which group died (ALL species will be marked dead):',
        components: components,
        ephemeral: true
      )
    end

    def show_death_location_selector(event, group_id)
      locations = GameState.location_choices.first(25)

      components = [
        {
          type: 1,
          components: [
            {
              type: 3,
              custom_id: "soul_link:death_location_select:#{group_id}",
              placeholder: 'Where did it die? (or keep catch location)',
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
              custom_id: 'nickname',
              label: 'Group Nickname',
              style: 1, # short
              required: true,
              min_length: 1,
              max_length: 50,
              placeholder: 'e.g., ROSS'
            }
          ]
        },
        {
          type: 1,
          components: [
            {
              type: 4,
              custom_id: 'species',
              label: 'Your Species',
              style: 1,
              required: true,
              min_length: 1,
              max_length: 50,
              placeholder: 'e.g., Turtwig'
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
              value: location,
              min_length: 1,
              max_length: 50
            }
          ]
        }
      ]

      event.show_modal(
        title: 'Add New Catch Group',
        custom_id: 'soul_link:catch_modal',
        components: components
      )
    end

    def open_species_modal(event, group_id)
      components = [
        {
          type: 1,
          components: [
            {
              type: 4,
              custom_id: 'species',
              label: 'Your Species',
              style: 1,
              required: true,
              min_length: 1,
              max_length: 50,
              placeholder: 'e.g., Chimchar'
            }
          ]
        }
      ]

      event.show_modal(
        title: 'Add Your Species',
        custom_id: "soul_link:species_modal:#{group_id}",
        components: components
      )
    end

    def open_catch_quick_add_modal(event, group_id)
      components = [
        {
          type: 1,
          components: [
            {
              type: 4,
              custom_id: 'species',
              label: 'Your Species',
              style: 1,
              required: true,
              min_length: 1,
              max_length: 50,
              placeholder: 'e.g., Staravia'
            }
          ]
        }
      ]

      event.show_modal(
        title: 'Add Your Pokemon',
        custom_id: "soul_link:catch_quick_add_modal:#{group_id}",
        components: components
      )
    end

    def handle_catch_quick_add(event)
      run = current_run(event)
      unless run
        respond_ephemeral(event, "❌ No active run found!")
        return
      end

      group_id = event.interaction.data['custom_id'].split(':').last
      species  = extract_modal_values(event)['species']

      result = self.class.apply_catch_quick_add(
        run: run,
        group_id: group_id,
        discord_user_id: event.user.id,
        species_input: species
      )

      unless result[:ok]
        respond_ephemeral(event, "❌ #{result[:error]}")
        return
      end

      update_catches_panel(run)
      respond_ephemeral(event, "✅ Added your **#{result[:species]}**.")
    rescue => e
      respond_ephemeral(event, "❌ Error: #{e.message}")
    end

    def handle_catch_refresh(event, group_id)
      run = current_run(event)
      unless run
        respond_ephemeral(event, "❌ No active run found!")
        return
      end

      result = self.class.apply_catch_refresh(run: run, group_id: group_id)
      unless result[:ok]
        respond_ephemeral(event, "❌ #{result[:error]}")
        return
      end

      respond_ephemeral(event, "🔄 Refreshed.")
    rescue => e
      respond_ephemeral(event, "❌ Error: #{e.message}")
    end

    def open_uncaught_death_modal(event, location)
      components = [
        {
          type: 1,
          components: [
            {
              type: 4,
              custom_id: 'nickname',
              label: 'Group Nickname',
              style: 1,
              required: true,
              placeholder: 'e.g., Chandler'
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
              value: location,
              min_length: 1,
              max_length: 50
            }
          ]
        },
        {
          type: 1,
          components: [
            {
              type: 4,
              custom_id: 'eulogy',
              label: 'Eulogy (optional)',
              style: 2, # paragraph
              required: false,
              max_length: 500,
              placeholder: 'How did they die? Write a short eulogy...'
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

    def open_eulogy_modal(event, group_id, location)
      components = [
        {
          type: 1,
          components: [
            {
              type: 4, # text input
              custom_id: 'eulogy',
              label: 'Eulogy (optional)',
              style: 2, # paragraph (multi-line)
              required: false,
              max_length: 500,
              placeholder: 'How did they die? Write a short eulogy...'
            }
          ]
        }
      ]

      event.show_modal(
        title: 'Write a Eulogy',
        custom_id: "soul_link:eulogy_modal:#{group_id}:#{location}",
        components: components
      )
    end

    # ------------------------
    # Modal Handlers
    # ------------------------
    def handle_catch_submission(event)
      run = current_run(event)
      unless run
        respond_ephemeral(event, "❌ No active run found!")
        return
      end

      values = extract_modal_values(event)

      group = run.soul_link_pokemon_groups.create!(
        nickname: values['nickname'],
        location: values['location'],
        status: 'caught'
      )

      group.soul_link_pokemon.create!(
        soul_link_run: run,
        species: values['species'],
        name: values['nickname'],
        location: values['location'],
        discord_user_id: event.user.id,
        status: 'caught'
      )

      update_catches_panel(run)
      respond_ephemeral(event, "✅ Added group **#{group.nickname}** with your species **#{values['species']}**!\n" \
        "Other players: use **Add My Species** to add yours.")
    rescue => e
      respond_ephemeral(event, "❌ Error: #{e.message}")
    end

    def handle_species_submission(event)
      run = current_run(event)
      unless run
        respond_ephemeral(event, "❌ No active run found!")
        return
      end

      group_id = event.interaction.data['custom_id'].split(':').last
      group = run.soul_link_pokemon_groups.find_by(id: group_id)
      unless group
        respond_ephemeral(event, "❌ Could not find that group!")
        return
      end

      if group.species_for(event.user.id)
        respond_ephemeral(event, "❌ You've already added your species to **#{group.nickname}**!")
        return
      end

      values = extract_modal_values(event)

      group.soul_link_pokemon.create!(
        soul_link_run: run,
        species: values['species'],
        name: group.nickname,
        location: group.location,
        discord_user_id: event.user.id,
        status: 'caught'
      )

      update_catches_panel(run)
      respond_ephemeral(event, "✅ Added **#{values['species']}** to group **#{group.nickname}**!")
    rescue => e
      respond_ephemeral(event, "❌ Error: #{e.message}")
    end

    def handle_eulogy_submission(event)
      # custom_id format: soul_link:eulogy_modal:GROUP_ID:LOCATION
      parts = event.interaction.data['custom_id'].split(':')
      group_id = parts[2]
      location = parts[3..].join(':') # rejoin in case location has colons

      values = extract_modal_values(event)
      eulogy = values['eulogy']

      handle_move_to_deaths_final(event, group_id, location, eulogy: eulogy)
    end

    def handle_move_to_deaths_final(event, group_id, location, eulogy: nil)
      run = current_run(event)
      unless run
        respond_ephemeral(event, "❌ No active run found!")
        return
      end

      group = run.caught_groups.find_by(id: group_id)
      unless group
        respond_ephemeral(event, "❌ Could not find that group!")
        return
      end

      death_location = location == 'original' ? nil : location
      group.mark_as_dead!(death_location: death_location, eulogy: eulogy)

      # Recolor the catch embed to its dead state, same as the website path.
      SoulLink::CatchMessage.post_or_update(group)

      update_catches_panel(run)
      update_deaths_panel(run)

      species_count = group.soul_link_pokemon.count
      response = "💀 Moved **#{group.nickname}** (#{species_count} species) to deaths. RIP."
      response += "\n📝 *#{eulogy}*" if eulogy.present?
      respond_ephemeral(event, response)
    rescue => e
      respond_ephemeral(event, "❌ Error: #{e.message}")
    end

    def handle_uncaught_death_submission(event)
      run = current_run(event)
      unless run
        respond_ephemeral(event, "❌ No active run found!")
        return
      end

      values = extract_modal_values(event)

      group = run.soul_link_pokemon_groups.create!(
        nickname: values['nickname'],
        location: values['location'],
        status: 'dead',
        died_at: Time.current,
        eulogy: values['eulogy'].presence
      )

      update_deaths_panel(run)
      response = "💀 Added **#{group.nickname}** to deaths!"
      response += "\n📝 *#{values['eulogy']}*" if values['eulogy'].present?
      respond_ephemeral(event, response)
    rescue => e
      respond_ephemeral(event, "❌ Error: #{e.message}")
    end

    # ------------------------
    # Gym Poll Helpers
    # ------------------------
    def post_initial_poll_message(channel, poll)
      embed = Discordrb::Webhooks::Embed.new(**SoulLink::GymPollMessage.embed(poll), timestamp: Time.now)
      channel.send_message('', false, embed, nil, nil, nil, SoulLink::GymPollMessage.components(poll))
    end

    # ------------------------
    # Helpers
    # ------------------------
    def extract_modal_values(event)
      values = {}

      # Try different ways discordrb might structure this
      if event.respond_to?(:values)
        return event.values
      elsif event.respond_to?(:components) && event.components
        event.components.each do |row|
          next unless row.respond_to?(:components)
          row.components.each do |component|
            values[component.custom_id] = component.value
          end
        end
      elsif event.respond_to?(:interaction) && event.interaction
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

    def handle_gym_poll_vote(event)
      _, _, poll_id, slot_index, response = event.interaction.data["custom_id"].split(":")
      poll = GymPoll.find_by(id: poll_id)
      return respond_ephemeral(event, "❌ Poll not found.") unless poll

      discord_user_id = event.user.id
      unless SoulLink::GameState.registered_player?(discord_user_id)
        respond_ephemeral(event, "❌ You aren't a player in this run.")
        return
      end

      begin
        poll.vote!(discord_user_id, slot_index.to_i, response)
        at = Time.iso8601(poll.slots[slot_index.to_i]["scheduled_at"]).in_time_zone(poll.soul_link_run.timezone)
        confirmation = "Got it — #{at.strftime('%a %-l%P').sub(':00', '')} #{response_emoji(response)}"
        respond_ephemeral(event, confirmation)
      rescue GymPoll::LockedError, GymPoll::InvalidSlotError, GymPoll::PastSlotError, GymPoll::InvalidResponseError => e
        respond_ephemeral(event, "❌ #{e.message}")
      end
    end

    def handle_gym_poll_reset(event)
      _, _, poll_id = event.interaction.data["custom_id"].split(":")
      poll = GymPoll.find_by(id: poll_id)
      return respond_ephemeral(event, "❌ Poll not found.") unless poll

      poll.destroy
      respond_ephemeral(event, "✅ Poll reset.")
    end

    def response_emoji(response)
      case response
      when "yes"   then "✅"
      when "maybe" then "❓"
      when "no"    then "❌"
      end
    end

    def respond_ephemeral(event, content)
      event.respond(content: content, ephemeral: true)
    end

    def broadcast_run_state(guild_id)
      RunChannel.broadcast_run_state(guild_id)
    rescue => e
      Rails.logger.error "Failed to broadcast run state: #{e.message}"
    end

    def current_run(event)
      guild_id = if event.respond_to?(:server_id)
                   event.server_id
      elsif event.respond_to?(:server) && event.server
                   event.server.id
      elsif event.respond_to?(:interaction) && event.interaction
                   event.interaction.server_id
      end

      SoulLinkRun.current(guild_id)
    end
  end
end
