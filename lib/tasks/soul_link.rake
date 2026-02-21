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

    puts "═══════════════════════════════════════"
    puts "  Importing Soul Link Run Data"
    puts "  Guild: #{guild_id}"
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

    # Import caught Pokemon
    if data['caught_pokemon']
      puts "Importing caught Pokemon..."
      data['caught_pokemon'].each do |poke|
        pokemon = run.soul_link_pokemon.create!(
          name: poke['name'],
          location: poke['location'],
          status: 'caught',
          discord_user_id: data['discord_user_id'],
          caught_at: poke['caught_at'] ? Time.parse(poke['caught_at']) : Time.current
        )
        puts "  ✅ #{pokemon.name} (#{pokemon.location})"
      end
      puts ""
    end

    # Import dead Pokemon
    if data['dead_pokemon']
      puts "Importing dead Pokemon..."

      # Build a lookup from caught_pokemon to derive location for dead pokemon.
      # Dead pokemon don't have their own location — they use the location where
      # they were originally caught. Match on name + caught_at for precision
      # (handles duplicates like RACHEL who was caught twice).
      caught_lookup = {}
      (data['caught_pokemon'] || []).each do |cp|
        key = [cp['name'], cp['caught_at']]
        caught_lookup[key] = cp['location']
      end

      data['dead_pokemon'].each do |poke|
        # Try to find location: explicit > matched from caught data > "unknown"
        location = poke['location'] ||
                   caught_lookup[[poke['name'], poke['caught_at']]] ||
                   'unknown'

        pokemon = run.soul_link_pokemon.create!(
          name: poke['name'],
          location: location,
          status: 'dead',
          discord_user_id: data['discord_user_id'],
          caught_at: poke['caught_at'] ? Time.parse(poke['caught_at']) : nil,
          died_at: poke['died_at'] ? Time.parse(poke['died_at']) : Time.current
        )
        puts "  💀 #{pokemon.name} (#{pokemon.location})"
      end
      puts ""
    end

    puts "═══════════════════════════════════════"
    puts "  Import Complete!"
    puts "═══════════════════════════════════════"
    puts ""
    puts "Run ##{run.run_number} Summary:"
    puts "  🎯 Caught: #{run.catches.count}"
    puts "  💀 Dead: #{run.deaths.count}"
    puts ""
    puts "📋 Next step: Start (or restart) the bot, then use /post_panels"
    puts "   in any Discord channel to post interactive panels to your"
    puts "   #catches and #deaths channels."
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

  desc "Add test Pokemon data. Accepts GUILD_ID env var (defaults to 0 for testing)"
  task test_data: :environment do
    guild_id = require_guild_id!(default: 0)
    run = SoulLinkRun.current(guild_id)

    unless run
      puts "❌ No active run found for guild #{guild_id}. Create one first with: GUILD_ID=#{guild_id} rake soul_link:test_run"
      exit
    end

    puts "Adding test Pokemon to Run ##{run.run_number}..."

    # Add some catches
    [
      { name: "Turtwig", location: "starter" },
      { name: "Starly", location: "route_201" },
      { name: "Bidoof", location: "route_202" },
      { name: "Shinx", location: "route_202" }
    ].each do |attrs|
      run.soul_link_pokemon.create!(
        **attrs,
        status: 'caught',
        discord_user_id: 123456789,
        caught_at: Time.current
      )
      puts "  ✅ Caught #{attrs[:name]}"
    end

    # Add a death
    run.soul_link_pokemon.create!(
      name: "Zubat",
      location: "ravaged_path",
      status: 'dead',
      discord_user_id: 123456789,
      died_at: Time.current
    )
    puts "  💀 Died: Zubat"

    puts "\n✅ Test data added!"
    puts "   Catches: #{run.catches.count}"
    puts "   Deaths: #{run.deaths.count}"
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
      puts "Pokemon:"
      puts "  🎯 Caught: #{run.catches.count}"
      puts "  💀 Dead: #{run.deaths.count}"
      puts ""

      if run.catches.any?
        puts "Recent Catches:"
        run.catches.last(5).each do |p|
          puts "  • #{p.name} (#{SoulLink::GameState.location_name(p.location)})"
        end
        puts ""
      end

      if run.deaths.any?
        puts "Recent Deaths:"
        run.deaths.last(5).each do |p|
          puts "  • #{p.name} (#{SoulLink::GameState.location_name(p.location)})"
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
    puts "   • Right-click the category name (e.g., 'Run #3')"
    puts "   • Click 'Copy Channel ID' (yes, categories are channels too!)"
    puts ""
    puts "4. Find Your User ID:"
    puts "   • Right-click your username"
    puts "   • Click 'Copy User ID'"
    puts ""
    puts "═══════════════════════════════════════"
  end
end
