# lib/tasks/soul_link.rake
namespace :soul_link do
  # Helper to extract guild_id from ENV, with optional default for convenience
  def self.require_guild_id!(default: nil)
    guild_id = ENV['GUILD_ID']&.to_i || default
    unless guild_id
      puts "❌ GUILD_ID is required. Usage: GUILD_ID=123456789 rake soul_link:#{ARGV.first&.split(':')&.last}"
      exit 1
    end
    guild_id
  end

  desc "Import existing run data from YAML (requires GUILD_ID env var)"
  task import_data: :environment do
    require 'yaml'

    file_path = Rails.root.join('config', 'soul_link', 'import_data.yml')
    unless File.exist?(file_path)
      puts "❌ File not found: #{file_path}"
      puts "   Create this file with your existing run data."
      exit
    end

    data = YAML.load_file(file_path)

    guild_id = require_guild_id!

    # Detect format: new format has 'nickname' + 'species' hash, legacy has 'name' + root 'discord_user_id'
    is_grouped_format = data['caught_pokemon']&.first&.key?('nickname') rescue false

    puts "═══════════════════════════════════════"
    puts "  Importing Soul Link Run Data"
    puts "  Guild: #{guild_id}"
    puts "  Format: #{is_grouped_format ? 'grouped (with species)' : 'legacy (flat)'}"
    puts "═══════════════════════════════════════"
    puts ""

    # Deactivate any current runs for this guild
    if SoulLinkRun.current(guild_id)
      puts "⚠️  Deactivating current active run..."
      SoulLinkRun.current(guild_id).deactivate!
    end

    # Create the run
    run = SoulLinkRun.create!(
      guild_id: guild_id,
      run_number: data['run_number'],
      category_id: data['category_id'],
      general_channel_id: data['general_channel_id'],
      catches_channel_id: data['catches_channel_id'],
      deaths_channel_id: data['deaths_channel_id'],
      active: true
    )

    puts "✅ Created Run ##{run.run_number}"
    puts ""

    if is_grouped_format
      import_grouped_format(run, data)
    else
      import_legacy_format(run, data)
    end

    # Import species pool (unassigned species per player for web drag-and-drop)
    if data['species_pool']
      import_species_pool(run, data['species_pool'])
    end

    puts "═══════════════════════════════════════"
    puts "  Import Complete!"
    puts "═══════════════════════════════════════"
    puts ""
    puts "Run ##{run.run_number} Summary:"
    puts "  🎯 Caught Groups: #{run.caught_groups.count}"
    puts "  💀 Dead Groups: #{run.dead_groups.count}"
    puts "  📊 Total Species Entries: #{run.soul_link_pokemon.count}"
    unassigned = run.soul_link_pokemon.unassigned.count
    puts "  🎴 Unassigned Species: #{unassigned}" if unassigned > 0
    puts ""
    puts "📋 Next step: Start (or restart) the bot, then use /post_panels"
    puts "   in any Discord channel to post interactive panels to your"
    puts "   #catches and #deaths channels."
    if unassigned > 0
      puts ""
      puts "🌐 Visit the Species page on the web UI to assign species to groups."
    end
  end

  # Import with grouped format (nickname + species hash per group)
  def self.import_grouped_format(run, data)
    # Import caught groups
    if data['caught_pokemon']
      puts "Importing caught groups..."
      data['caught_pokemon'].each do |group_data|
        group = run.soul_link_pokemon_groups.create!(
          nickname: group_data['nickname'],
          location: group_data['location'],
          status: 'caught',
          caught_at: group_data['caught_at'] ? Time.parse(group_data['caught_at']) : Time.current
        )

        species_count = 0
        group_data['species']&.each do |discord_user_id, species_name|
          group.soul_link_pokemon.create!(
            soul_link_run: run,
            species: species_name,
            name: group_data['nickname'],
            location: group_data['location'],
            discord_user_id: discord_user_id.to_i,
            status: 'caught',
            caught_at: group_data['caught_at'] ? Time.parse(group_data['caught_at']) : Time.current
          )
          species_count += 1
        end

        puts "  ✅ #{group.nickname} (#{group.location}) — #{species_count} species"
      end
      puts ""
    end

    # Import dead groups
    if data['dead_pokemon']
      puts "Importing dead groups..."

      # Build location lookup from caught groups
      caught_lookup = {}
      (data['caught_pokemon'] || []).each do |cp|
        key = [cp['nickname'], cp['caught_at']]
        caught_lookup[key] = cp['location']
      end

      data['dead_pokemon'].each do |group_data|
        location = group_data['location'] ||
                   caught_lookup[[group_data['nickname'], group_data['caught_at']]] ||
                   'unknown'

        group = run.soul_link_pokemon_groups.create!(
          nickname: group_data['nickname'],
          location: location,
          status: 'dead',
          caught_at: group_data['caught_at'] ? Time.parse(group_data['caught_at']) : nil,
          died_at: group_data['died_at'] ? Time.parse(group_data['died_at']) : Time.current
        )

        species_count = 0
        group_data['species']&.each do |discord_user_id, species_name|
          group.soul_link_pokemon.create!(
            soul_link_run: run,
            species: species_name,
            name: group_data['nickname'],
            location: location,
            discord_user_id: discord_user_id.to_i,
            status: 'dead',
            caught_at: group_data['caught_at'] ? Time.parse(group_data['caught_at']) : nil,
            died_at: group_data['died_at'] ? Time.parse(group_data['died_at']) : Time.current
          )
          species_count += 1
        end

        puts "  💀 #{group.nickname} (#{location}) — #{species_count} species"
      end
      puts ""
    end
  end

  # Import with legacy flat format (single discord_user_id, no species)
  def self.import_legacy_format(run, data)
    if data['caught_pokemon']
      puts "Importing caught Pokemon (legacy format)..."
      data['caught_pokemon'].each do |poke|
        group = run.soul_link_pokemon_groups.create!(
          nickname: poke['name'],
          location: poke['location'],
          status: 'caught',
          caught_at: poke['caught_at'] ? Time.parse(poke['caught_at']) : Time.current
        )

        group.soul_link_pokemon.create!(
          soul_link_run: run,
          species: 'Unknown',
          name: poke['name'],
          location: poke['location'],
          discord_user_id: data['discord_user_id'],
          status: 'caught',
          caught_at: poke['caught_at'] ? Time.parse(poke['caught_at']) : Time.current
        )

        puts "  ✅ #{group.nickname} (#{group.location})"
      end
      puts ""
    end

    if data['dead_pokemon']
      puts "Importing dead Pokemon (legacy format)..."

      caught_lookup = {}
      (data['caught_pokemon'] || []).each do |cp|
        key = [cp['name'], cp['caught_at']]
        caught_lookup[key] = cp['location']
      end

      data['dead_pokemon'].each do |poke|
        location = poke['location'] ||
                   caught_lookup[[poke['name'], poke['caught_at']]] ||
                   'unknown'

        group = run.soul_link_pokemon_groups.create!(
          nickname: poke['name'],
          location: location,
          status: 'dead',
          caught_at: poke['caught_at'] ? Time.parse(poke['caught_at']) : nil,
          died_at: poke['died_at'] ? Time.parse(poke['died_at']) : Time.current
        )

        group.soul_link_pokemon.create!(
          soul_link_run: run,
          species: 'Unknown',
          name: poke['name'],
          location: location,
          discord_user_id: data['discord_user_id'],
          status: 'dead',
          caught_at: poke['caught_at'] ? Time.parse(poke['caught_at']) : nil,
          died_at: poke['died_at'] ? Time.parse(poke['died_at']) : Time.current
        )

        puts "  💀 #{group.nickname} (#{location})"
      end
      puts ""
    end
  end

  # Import species pool — unassigned species per player for web-based assignment
  def self.import_species_pool(run, species_pool)
    puts "Importing species pool..."
    total = 0

    species_pool.each do |discord_user_id, species_list|
      player_name = SoulLink::GameState.player_name(discord_user_id.to_i)
      count = 0

      species_list.each do |species_name|
        run.soul_link_pokemon.create!(
          species: species_name,
          name: species_name,
          location: 'pool',
          discord_user_id: discord_user_id.to_i,
          status: 'caught'
        )
        count += 1
      end

      puts "  🎴 #{player_name}: #{count} species"
      total += count
    end

    puts "  Total: #{total} unassigned species"
    puts ""
  end

  desc "Run the Soul Link Discord bot"
  task bot: :environment do
    puts "Starting Soul Link Discord Bot..."
    puts "Press Ctrl+C to stop"

    bot = SoulLink::DiscordBot.new

    # Graceful shutdown
    trap('INT') do
      puts "\nShutting down bot..."
      exit
    end

    bot.run
  end

  desc "Create a new Soul Link run manually (for testing). Accepts GUILD_ID env var (defaults to 0 for testing)"
  task test_run: :environment do
    guild_id = require_guild_id!(default: 0)

    last_run = SoulLinkRun.for_guild(guild_id).order(run_number: :desc).first
    next_number = last_run ? last_run.run_number + 1 : 1

    # Deactivate current run for this guild
    SoulLinkRun.current(guild_id)&.deactivate!

    puts "Creating test run ##{next_number} for guild #{guild_id}..."

    run = SoulLinkRun.create!(
      guild_id: guild_id,
      run_number: next_number,
      category_id: 999999999999999999, # Fake ID for testing
      general_channel_id: 999999999999999999,
      catches_channel_id: 999999999999999999,
      deaths_channel_id: 999999999999999999
    )

    puts "✅ Created Run ##{run.run_number}"
  end

  desc "Add test Pokemon data with groups. Accepts GUILD_ID env var (defaults to 0 for testing)"
  task test_data: :environment do
    guild_id = require_guild_id!(default: 0)
    run = SoulLinkRun.current(guild_id)

    unless run
      puts "❌ No active run found for guild #{guild_id}. Create one first with: GUILD_ID=#{guild_id} rake soul_link:test_run"
      exit
    end

    puts "Adding test Pokemon groups to Run ##{run.run_number}..."

    # Add some catch groups
    [
      { nickname: "ROSS", location: "starter", species: { 111 => "Turtwig", 222 => "Chimchar", 333 => "Piplup", 444 => "Starly" } },
      { nickname: "RACHEL", location: "route_201", species: { 111 => "Shinx", 222 => "Bidoof", 333 => "Kricketot", 444 => "Starly" } }
    ].each do |attrs|
      group = run.soul_link_pokemon_groups.create!(
        nickname: attrs[:nickname],
        location: attrs[:location],
        status: 'caught'
      )

      attrs[:species].each do |user_id, species|
        group.soul_link_pokemon.create!(
          soul_link_run: run,
          species: species,
          name: attrs[:nickname],
          location: attrs[:location],
          discord_user_id: user_id,
          status: 'caught',
          caught_at: Time.current
        )
      end

      puts "  ✅ #{group.nickname} (#{group.location}) — #{attrs[:species].count} species"
    end

    # Add a dead group
    dead_group = run.soul_link_pokemon_groups.create!(
      nickname: "Chandler",
      location: "route_218",
      status: 'dead',
      died_at: Time.current
    )
    { 111 => "Machop", 222 => "Meditite", 333 => "Tentacool", 444 => "Shellos" }.each do |user_id, species|
      dead_group.soul_link_pokemon.create!(
        soul_link_run: run,
        species: species,
        name: "Chandler",
        location: "route_218",
        discord_user_id: user_id,
        status: 'dead',
        died_at: Time.current
      )
    end
    puts "  💀 Chandler (route_218) — 4 species"

    puts "\n✅ Test data added!"
    puts "   Caught Groups: #{run.caught_groups.count}"
    puts "   Dead Groups: #{run.dead_groups.count}"
  end

  desc "Show current run status. Accepts optional GUILD_ID env var (shows all guilds if omitted)"
  task status: :environment do
    guild_id = ENV['GUILD_ID']&.to_i

    runs = if guild_id
             run = SoulLinkRun.current(guild_id)
             run ? [run] : []
           else
             SoulLinkRun.active.order(:guild_id, run_number: :desc)
           end

    if runs.empty?
      puts guild_id ? "❌ No active run found for guild #{guild_id}" : "❌ No active runs found"
      exit
    end

    runs.each do |run|
      puts "═══════════════════════════════════════"
      puts "  Soul Link Run ##{run.run_number}"
      puts "  Guild: #{run.guild_id}"
      puts "═══════════════════════════════════════"
      puts ""
      puts "Channels:"
      puts "  Category ID: #{run.category_id}"
      puts "  General: #{run.general_channel_id}"
      puts "  Catches: #{run.catches_channel_id}"
      puts "  Deaths: #{run.deaths_channel_id}"
      puts ""
      puts "Groups:"
      puts "  🎯 Caught: #{run.caught_groups.count}"
      puts "  💀 Dead: #{run.dead_groups.count}"
      puts ""

      if run.caught_groups.any?
        puts "Caught Groups:"
        run.caught_groups.includes(:soul_link_pokemon).last(5).each do |group|
          species_list = group.soul_link_pokemon.map { |p|
            "#{SoulLink::GameState.player_name(p.discord_user_id)}: #{p.species}"
          }.join(', ')
          puts "  • #{group.nickname} (#{SoulLink::GameState.location_name(group.location)}) — #{species_list}"
        end
        puts ""
      end

      if run.dead_groups.any?
        puts "Dead Groups:"
        run.dead_groups.includes(:soul_link_pokemon).last(5).each do |group|
          species_list = group.soul_link_pokemon.map { |p|
            "#{SoulLink::GameState.player_name(p.discord_user_id)}: #{p.species}"
          }.join(', ')
          puts "  • #{group.nickname} (#{SoulLink::GameState.location_name(group.location)}) — #{species_list}"
        end
      end

      puts "═══════════════════════════════════════"
      puts ""
    end
  end

  desc "Reload YAML configuration files"
  task reload_config: :environment do
    SoulLink::GameState.reload!
    puts "✅ Reloaded gym_info.yml, locations.yml, and settings.yml"

    puts "\nGyms loaded:"
    SoulLink::GameState.gym_info.each do |key, data|
      puts "  • #{data['name']}"
    end

    puts "\nLocations loaded: #{SoulLink::GameState.locations.count}"

    puts "\nSettings:"
    puts "  Category prefix: #{SoulLink::GameState.settings['category_prefix'] || 'Platinum Run'}"

    puts "\nPlayers:"
    if SoulLink::GameState.players.any?
      SoulLink::GameState.players.each do |player|
        puts "  • #{player['display_name']} (#{player['discord_user_id']})"
      end
    else
      puts "  ⚠️  No players configured. Add them to config/soul_link/settings.yml"
    end
  end

  desc "Helper: Find your Discord channel IDs"
  task find_channel_ids: :environment do
    puts "═══════════════════════════════════════"
    puts "  How to Find Discord Channel IDs"
    puts "═══════════════════════════════════════"
    puts ""
    puts "1. Enable Developer Mode in Discord:"
    puts "   • Click User Settings (gear icon)"
    puts "   • Go to 'Advanced'"
    puts "   • Enable 'Developer Mode'"
    puts ""
    puts "2. Find Channel IDs:"
    puts "   • Right-click any channel"
    puts "   • Click 'Copy Channel ID'"
    puts "   • Paste into import_data.yml"
    puts ""
    puts "3. Find Category ID:"
    puts "   • Right-click the category name (e.g., 'Platinum Run 16')"
    puts "   • Click 'Copy Channel ID' (yes, categories are channels too!)"
    puts ""
    puts "4. Find Your User ID:"
    puts "   • Right-click your username"
    puts "   • Click 'Copy User ID'"
    puts ""
    puts "═══════════════════════════════════════"
  end
end
