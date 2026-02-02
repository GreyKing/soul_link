# Soul Link Discord Bot - Setup Guide

This Discord bot manages Pokemon Pearl Soul Link runs with automatic channel management, catch/death tracking, and gym information.

## Features

- **Automatic Run Management**: Creates categorized Discord channels for each run
- **Catch Tracking**: Interactive panel to log caught Pokemon with location data
- **Death Tracking**: Track fallen Pokemon (both caught and uncaught)
- **Live Updates**: Panels auto-update with each new entry
- **Gym Info**: Quick command to see next gym details

## Setup Instructions

### 1. Database Migration

Run the migration to create the required tables:

```bash
rails db:migrate
```

### 2. YAML Configuration Files

Place these files in your Rails app:

- `config/soul_link/gym_info.yml` - Gym data
- `config/soul_link/locations.yml` - Location data

### 3. Rails Credentials

Add your Discord bot credentials to `config/credentials.yml.enc`:

```bash
rails credentials:edit
```

Add:

```yaml
discord:
  client_id: YOUR_CLIENT_ID
  token: YOUR_BOT_TOKEN
```

### 4. Update Channel ID

In `discord_bot.rb`, update this constant with your initial general channel ID:

```ruby
INITIAL_GENERAL_CHANNEL_ID = 713775445635760206  # Your actual channel ID
```

### 5. Bot Permissions

Your Discord bot needs these permissions:
- Manage Channels
- Send Messages
- Embed Links
- Read Message History
- Use Slash Commands

Bot invite URL format:
```
https://discord.com/api/oauth2/authorize?client_id=YOUR_CLIENT_ID&permissions=268454928&scope=bot%20applications.commands
```

### 6. Run the Bot

Create a rake task or initializer to run the bot:

```ruby
# lib/tasks/soul_link.rake
namespace :soul_link do
  desc "Run the Soul Link Discord bot"
  task bot: :environment do
    bot = SoulLink::DiscordBot.new
    bot.run
  end
end
```

Then run:
```bash
rake soul_link:bot
```

## Usage

### Starting a New Run

1. In Discord, use the slash command: `/start_new_run`
2. The bot will:
    - Create a new category: "Run #X"
    - Move the general channel to this category
    - Create #catches and #deaths channels
    - Post interactive panels in both channels

### Adding Catches

1. In the #catches channel, click "➕ Add Catch"
2. Fill in the modal:
    - Pokemon Name (e.g., "Pikachu")
    - Location (route key, e.g., "route_201")
3. The panel updates automatically

### Recording Deaths

**Option 1: Move Caught Pokemon to Deaths**
1. In #deaths, click "💀 Move Caught to Deaths"
2. Enter the exact Pokemon name from catches
3. Optionally specify a different death location

**Option 2: Add Uncaught Death**
1. In #deaths, click "➕ Add Uncaught Death"
2. Fill in Pokemon name and location
3. Used for Pokemon that died before being caught

### Checking Next Gym

In the #general channel, type:
```
!next_gym
```

The bot will display the next gym's information from the YAML file.

## File Structure

```
app/
├── models/
│   ├── soul_link_run.rb
│   └── soul_link_pokemon.rb
└── services/
    └── soul_link/
        ├── discord_bot.rb
        └── game_state.rb

config/
└── soul_link/
    ├── gym_info.yml
    └── locations.yml

db/
└── migrate/
    └── YYYYMMDDHHMMSS_create_soul_link_tables.rb
```

## Database Schema

### soul_link_runs
- `run_number` - Sequential run number
- `category_id` - Discord category ID
- `general_channel_id` - General channel ID
- `catches_channel_id` - Catches channel ID
- `deaths_channel_id` - Deaths channel ID
- `catches_panel_message_id` - ID of the catches panel message
- `deaths_panel_message_id` - ID of the deaths panel message
- `active` - Whether this is the current run

### soul_link_pokemon
- `soul_link_run_id` - Which run this Pokemon belongs to
- `name` - Pokemon nickname/species
- `location` - Where caught/died (route key)
- `status` - 'caught' or 'dead'
- `discord_user_id` - Who recorded this entry
- `caught_at` - Timestamp of catch
- `died_at` - Timestamp of death

## Customization

### Adding More Gyms

Edit `config/soul_link/gym_info.yml`:

```yaml
ninth_gym:
  name: "Elite Four"
  recommended_level: 55
```

### Adding More Locations

Edit `config/soul_link/locations.yml`:

```yaml
route_215:
  name: "Route 215"
victory_road:
  name: "Victory Road"
```

### Enhancing Gym Tracking

To automatically track which gym is next, you could:

1. Add a `gyms_defeated` field to `SoulLinkRun`
2. Create a command to mark gyms as completed
3. Update `GameState.next_gym_info` to use this field

## Troubleshooting

**Bot not responding to commands:**
- Ensure the bot is online in your server
- Check that slash commands are synced (may take up to 1 hour)
- Verify bot has proper permissions

**Panels not updating:**
- Check Rails logs for errors
- Ensure message IDs are being saved correctly
- Verify bot can edit its own messages

**Location not found:**
- Ensure you're using the route key (e.g., "route_201") not the display name
- Check `locations.yml` for valid keys
- Add custom locations as needed

## Future Enhancements

Potential features to add:
- Dropdown select menus for locations instead of text input
- Team composition view showing current party
- Statistics dashboard (catch rate, survival rate, etc.)
- Level tracking for each Pokemon
- Auto-linking caught Pokemon when moved to deaths
- Export run data to CSV/JSON
- Multi-run comparison statistics

## Support

For issues or questions, check:
- discordrb documentation: https://github.com/shardlab/discordrb
- Discord API docs: https://discord.com/developers/docs
- Rails logs for detailed error messages




# Importing Existing Run Data

If you're already mid-run and want to start using the bot, follow these steps:

## Step 1: Find Your Discord IDs

```bash
rake soul_link:find_channel_ids
```

This will show you how to enable Developer Mode and find the IDs you need.

## Step 2: Create Your Import File

Copy `config/soul_link/import_data.yml` template and fill it in:

```yaml
run_number: 3  # Current run number

# Channel IDs (right-click channel > Copy Channel ID)
category_id: 1234567890123456789
general_channel_id: 1234567890123456789
catches_channel_id: 1234567890123456789
deaths_channel_id: 1234567890123456789

# Your Discord User ID
discord_user_id: 123456789012345678

# Currently caught Pokemon
caught_pokemon:
  - name: "Turtwig"
    location: "starter"
    caught_at: "2026-01-15 10:00:00"
  
  - name: "Starly"
    location: "route_201"
    caught_at: "2026-01-15 10:30:00"

# Dead Pokemon
dead_pokemon:
  - name: "Bidoof"
    location: "route_202"
    caught_at: "2026-01-15 09:00:00"
    died_at: "2026-01-15 12:00:00"
```

## Step 3: Run the Import

```bash
rake soul_link:import_data
```

This will:
- Create the run in the database
- Import all your Pokemon
- Show you a summary

## Step 4: Set Up Panels (Two Options)

### Option A: Create Fresh Panels (Easiest)

1. Start the bot: `./bin/discord_bot`
2. In Discord, run `/start_new_run`
3. This will create new panels with your imported data

**Note:** This will create NEW channels. If you want to keep your existing channels, use Option B.

### Option B: Use Existing Channels

If you want to keep your existing #catches and #deaths channels:

1. Start the bot: `./bin/discord_bot`
2. In #catches channel, type `/panel` to post the panel
3. Right-click the new panel message > Copy Message ID
4. Run in Rails console:
   ```ruby
   run = SoulLinkRun.current
   run.update!(catches_panel_message_id: PASTE_MESSAGE_ID_HERE)
   ```
5. Repeat for #deaths channel:
   ```ruby
   run.update!(deaths_panel_message_id: PASTE_MESSAGE_ID_HERE)
   ```

**Note:** You'll need to add a `/panel` command to the bot, or you can manually create a message and use that ID.

## Step 5: Verify

```bash
rake soul_link:status
```

Should show your imported data!

## Tips

### Location Keys

Make sure you use the exact keys from `locations.yml`:
- ✅ `route_201`, `starter`, `eterna_forest`
- ❌ `Route 201`, `Starter`, `Eterna Forest`

### Dates

Use ISO 8601 format: `YYYY-MM-DD HH:MM:SS`
- Example: `2026-01-15 10:30:00`
- Leave out `caught_at` for Pokemon that died before being caught

### Multiple Runs

To import multiple past runs:

1. Set the first run as `active: false` in the database after import
2. Run import again with next run's data
3. Only the latest should be `active: true`

```ruby
# In Rails console
SoulLinkRun.find_by(run_number: 1).update!(active: false)
SoulLinkRun.find_by(run_number: 2).update!(active: false)
# Run 3 stays active
```

## Troubleshooting

**"No active run found" in bot:**
- Make sure import succeeded
- Check `rake soul_link:status`
- Verify only one run has `active: true`

**Panel not updating:**
- Make sure `catches_panel_message_id` and `deaths_panel_message_id` are set
- Check that message IDs are correct (18-19 digit numbers)
- Try restarting the bot

**Location not found:**
- Check spelling matches `locations.yml` exactly
- Keys are lowercase with underscores: `route_201` not `Route 201`

**Import errors:**
- YAML syntax is very picky about spacing
- Use 2 spaces for indentation (not tabs)
- Quotes around strings with special characters