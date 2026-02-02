# lib/tasks/soul_link.rake
namespace :soul_link do
  desc "Import existing run data from YAML"
  task import_data: :environment do
    require 'yaml'

    file_path = Rails.root.join('config', 'soul_link', 'import_data.yml')
    unless File.exist?(file_path)
      puts "❌ File not found: #{file_path}"
      puts "   Create this file with your existing run data."
      exit
    end

    data = YAML.load_file(file_path)

    puts "═══════════════════════════════════════"
    puts "  Importing Soul Link Run Data"
    puts "═══════════════════════════════════════"
    puts ""

    # Deactivate any current runs
    if SoulLinkRun.current
      puts "⚠️  Deactivating current active run..."
      SoulLinkRun.current.deactivate!
    end

    # Create the run
    run = SoulLinkRun.create!(
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
      data['dead_pokemon'].each do |poke|
        pokemon = run.soul_link_pokemon.create!(
          name: poke['name'],
          location: poke['location'],
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
    puts "⚠️  IMPORTANT: After starting the bot, run these commands in Discord:"
    puts "     1. Go to the #catches channel"
    puts "     2. Manually post a message (the bot will use this as the panel)"
    puts "     3. Note the message ID (right-click > Copy Message ID)"
    puts "     4. Run in Rails console:"
    puts "        run = SoulLinkRun.find(#{run.id})"
    puts "        run.update!(catches_panel_message_id: YOUR_MESSAGE_ID)"
    puts ""
    puts "     Repeat for #deaths channel with deaths_panel_message_id"
    puts ""
    puts "  OR just use /start_new_run to create fresh panels"
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

  desc "Create a new Soul Link run manually (for testing)"
  task test_run: :environment do
    last_run = SoulLinkRun.order(run_number: :desc).first
    next_number = last_run ? last_run.run_number + 1 : 1

    # Deactivate current run
    SoulLinkRun.current&.deactivate!

    puts "Creating test run ##{next_number}..."

    run = SoulLinkRun.create!(
      run_number: next_number,
      category_id: 999999999999999999, # Fake ID for testing
      general_channel_id: 999999999999999999,
      catches_channel_id: 999999999999999999,
      deaths_channel_id: 999999999999999999
    )

    puts "✅ Created Run ##{run.run_number}"
  end

  desc "Add test Pokemon data"
  task test_data: :environment do
    run = SoulLinkRun.current

    unless run
      puts "❌ No active run found. Create one first with: rake soul_link:test_run"
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

  desc "Show current run status"
  task status: :environment do
    run = SoulLinkRun.current

    unless run
      puts "❌ No active run found"
      exit
    end

    puts "═══════════════════════════════════════"
    puts "  Soul Link Run ##{run.run_number}"
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
  end

  desc "Reload YAML configuration files"
  task reload_config: :environment do
    SoulLink::GameState.reload!
    puts "✅ Reloaded gym_info.yml and locations.yml"

    puts "\nGyms loaded:"
    SoulLink::GameState.gym_info.each do |key, data|
      puts "  • #{data['name']}"
    end

    puts "\nLocations loaded: #{SoulLink::GameState.locations.count}"
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
