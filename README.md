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