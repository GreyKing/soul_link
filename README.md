# Soul Link Discord Bot

A Discord bot for managing Pokemon Platinum Soul Link Nuzlocke runs. Tracks catches, deaths, and gym progress with interactive panels that auto-update in real time.

## Features

- **Multi-Server Support**: Runs independently across multiple Discord servers, scoped by guild ID
- **Automatic Run Management**: Creates categorized Discord channels for each run (e.g., "Platinum Run 17")
- **Catch Tracking**: Interactive panel with dropdown location selector and modal input
- **Death Tracking**: Move caught Pokemon to deaths or record uncaught deaths, with location tracking
- **Live Panels**: Catches and deaths panels auto-update with each new entry
- **Mid-Run Import**: Import existing run data from YAML and post panels to existing channels
- **Gym Info**: Quick command to check next gym details
- **Auto-Deploy**: GitHub Actions workflow deploys to VPS on push to main

## Slash Commands

| Command | Description |
|---|---|
| `/start_new_run` | Create a new run with category, general, catches, and deaths channels |
| `/end_current_run` | Deactivate the current run (keeps all data) |
| `/run_status` | Show current run statistics (caught, dead, total) |
| `/post_panels` | Post catches & deaths panels to existing channels (used after data import) |

All commands are registered **globally** and work in any server the bot is invited to. New servers may take up to 1 hour for commands to appear.

### Text Commands

| Command | Channel | Description |
|---|---|---|
| `!next_gym` | #general | Display next gym info from YAML config |

## Setup

### 1. Database

```bash
rails db:migrate
```

### 2. Configuration Files

Place these in `config/soul_link/`:

| File | Purpose |
|---|---|
| `gym_info.yml` | Gym names and recommended levels |
| `locations.yml` | Catch/death location definitions (route keys and display names) |
| `settings.yml` | Bot settings (category naming prefix, etc.) |
| `import_data.yml` | Template for importing existing run data |

### 3. Settings

Edit `config/soul_link/settings.yml` to customize:

```yaml
# Controls how Discord categories are named for each run.
# The run number is appended automatically.
# Examples: "Platinum Run" -> "Platinum Run 1", "Run #" -> "Run #1"
category_prefix: "Platinum Run"
```

### 4. Rails Credentials

```bash
rails credentials:edit
```

Add your Discord bot credentials:

```yaml
discord:
  client_id: YOUR_CLIENT_ID
  token: YOUR_BOT_TOKEN
```

### 5. Bot Permissions

Your Discord bot needs these permissions:
- Manage Channels
- Send Messages
- Embed Links
- Read Message History
- Use Slash Commands

Invite URL format:
```
https://discord.com/api/oauth2/authorize?client_id=YOUR_CLIENT_ID&permissions=268454928&scope=bot%20applications.commands
```

### 6. Run the Bot (Local Development)

```bash
rake soul_link:bot
```

## Usage

### Starting a New Run

1. Use `/start_new_run` in any channel
2. The bot creates:
   - A new category (e.g., "Platinum Run 17")
   - A #general channel (or moves an existing one into the category)
   - A #catches channel with an interactive panel
   - A #deaths channel with an interactive panel

### Adding Catches

1. In the #catches panel, click **"Add Catch"**
2. Select a location from the dropdown
3. Enter the Pokemon name in the modal
4. The panel updates automatically with the new catch

### Recording Deaths

**Move a caught Pokemon to deaths:**
1. In the #deaths panel, click **"Move Caught to Deaths"**
2. Select which Pokemon died from the dropdown
3. Choose where it died (or keep original catch location)
4. Both panels update automatically

**Record an uncaught death:**
1. Click **"Add Uncaught Death"**
2. Select the location and enter the Pokemon name
3. Used for Pokemon that died before being caught

### Checking Next Gym

In the #general channel, type `!next_gym` to see the next gym's name and recommended level.

## Importing Existing Run Data

If you're mid-run and want to start using the bot with your existing data:

### Step 1: Find Your Discord IDs

```bash
rake soul_link:find_channel_ids
```

Enable Developer Mode in Discord (Settings > Advanced > Developer Mode), then right-click channels/categories to copy their IDs.

### Step 2: Fill In the Import File

Edit `config/soul_link/import_data.yml`:

```yaml
run_number: 16

# Discord channel IDs (right-click channel > Copy ID)
category_id: 1234567890123456789
general_channel_id: 1234567890123456789
catches_channel_id: 1234567890123456789
deaths_channel_id: 1234567890123456789

# Your Discord user ID
discord_user_id: 123456789012345678

# All currently caught Pokemon
caught_pokemon:
  - name: "Turtwig"
    location: "starter"
    caught_at: "2026-01-15 10:00:00"

  - name: "Starly"
    location: "route_201"
    caught_at: "2026-01-15 10:30:00"

# Dead Pokemon (location is derived automatically from caught_pokemon data)
dead_pokemon:
  - name: "Bidoof"
    caught_at: "2026-01-15 09:00:00"
    died_at: "2026-01-15 12:00:00"
```

**Notes:**
- Use location keys from `locations.yml` (e.g., `route_201`, not `Route 201`)
- Dead Pokemon don't need a `location` field — it's derived from their matching `caught_pokemon` entry using `name` + `caught_at`
- Dates use `YYYY-MM-DD HH:MM:SS` format

### Step 3: Run the Import

```bash
GUILD_ID=YOUR_GUILD_ID rake soul_link:import_data
```

### Step 4: Post Panels

Start (or restart) the bot, then use `/post_panels` in any channel in your Discord server. The bot will post interactive panels to the #catches and #deaths channels with all your imported data.

### Step 5: Verify

```bash
GUILD_ID=YOUR_GUILD_ID rake soul_link:status
```

## Multi-Guild Support

The bot supports multiple Discord servers simultaneously. Each server gets independent runs, catches, and deaths scoped by `guild_id`.

### Inviting to a New Server

1. Use the invite URL from the [Bot Permissions](#5-bot-permissions) section
2. You must have **Manage Server** permission on the target server
3. Slash commands will appear within ~1 hour of the bot joining
4. Use `/start_new_run` to begin — no additional setup needed

### Rake Tasks with Guild ID

Most rake tasks accept a `GUILD_ID` environment variable:

```bash
# Import data for a specific guild
GUILD_ID=404132250385383433 rake soul_link:import_data

# Show status for a specific guild
GUILD_ID=404132250385383433 rake soul_link:status

# Show status for ALL guilds
rake soul_link:status

# Create a test run (defaults to guild 0 if omitted)
GUILD_ID=404132250385383433 rake soul_link:test_run

# Add test data (defaults to guild 0 if omitted)
GUILD_ID=404132250385383433 rake soul_link:test_data
```

## Production Deployment (Vultr VPS)

The bot runs on a small VPS (1 CPU, 1GB RAM). Auto-deploys via GitHub Actions on push to main.

### Server Setup

1. **Install dependencies:**
   ```bash
   apt update && apt upgrade -y
   apt install -y build-essential git curl libssl-dev libreadline-dev zlib1g-dev libffi-dev libyaml-dev mysql-server libmysqlclient-dev
   ```

2. **Add swap space** (recommended for 1GB servers):
   ```bash
   fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
   echo '/swapfile none swap sw 0 0' >> /etc/fstab
   ```

3. **Install Ruby via rbenv:**
   ```bash
   git clone https://github.com/rbenv/rbenv.git ~/.rbenv
   git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
   echo 'eval "$(~/.rbenv/bin/rbenv init - bash)"' >> ~/.bashrc
   source ~/.bashrc
   rbenv install 3.4.5
   rbenv global 3.4.5
   ```

4. **Set up MySQL:**
   ```bash
   DB_PASS=$(openssl rand -base64 24) && echo "Your DB password: $DB_PASS"
   mysql -u root -e "CREATE DATABASE soul_link_production; CREATE USER 'soul_link'@'localhost' IDENTIFIED BY '$DB_PASS'; GRANT ALL PRIVILEGES ON soul_link_production.* TO 'soul_link'@'localhost'; FLUSH PRIVILEGES;"
   ```
   Save the generated password!

5. **Clone and install:**
   ```bash
   git clone https://github.com/GreyKing/soul_link.git /opt/soul_link
   cd /opt/soul_link
   gem install bundler && bundle install
   ```

6. **Run migrations:**
   ```bash
   RAILS_ENV=production RAILS_MASTER_KEY=your_key DATABASE_USERNAME=soul_link DATABASE_PASSWORD=your_pass bin/rails db:migrate
   ```

### Systemd Service

Create `/etc/systemd/system/soul-link-bot.service`:

```ini
[Unit]
Description=Soul Link Discord Bot
After=mysql.service

[Service]
WorkingDirectory=/opt/soul_link
ExecStart=/root/.rbenv/shims/ruby bin/rails soul_link:bot
Restart=always
RestartSec=5
Environment=RAILS_ENV=production
Environment=RAILS_MASTER_KEY=your_master_key_here
Environment=DATABASE_USERNAME=soul_link
Environment=DATABASE_PASSWORD=your_db_password_here

[Install]
WantedBy=multi-user.target
```

Then enable and start:

```bash
systemctl daemon-reload
systemctl enable soul-link-bot
systemctl start soul-link-bot
```

### Server Management

| Command | Description |
|---|---|
| `systemctl status soul-link-bot` | Check if the bot is running |
| `journalctl -u soul-link-bot -f` | Tail live logs |
| `systemctl restart soul-link-bot` | Restart the bot |
| `systemctl stop soul-link-bot` | Stop the bot |

### Auto-Deploy (GitHub Actions)

Pushes to `main` automatically deploy via `.github/workflows/deploy.yml`. The workflow SSHs into the VPS, pulls the latest code, installs dependencies, runs migrations, and restarts the bot.

Required GitHub Secrets:

| Secret | Description |
|---|---|
| `VPS_HOST` | Vultr server IP address |
| `VPS_SSH_KEY` | SSH private key for root access |
| `RAILS_MASTER_KEY` | Rails master key for encrypted credentials |
| `DATABASE_USERNAME` | MySQL username (e.g., `soul_link`) |
| `DATABASE_PASSWORD` | MySQL password |

### Manual Deploy

```bash
cd /opt/soul_link && git pull && bundle install && \
RAILS_ENV=production RAILS_MASTER_KEY=your_key DATABASE_USERNAME=soul_link DATABASE_PASSWORD=your_pass bin/rails db:migrate && \
systemctl restart soul-link-bot
```

## Available Rake Tasks

| Task | Description |
|---|---|
| `rake soul_link:bot` | Start the Discord bot |
| `rake soul_link:status` | Show current run status (all guilds, or `GUILD_ID=X` for one) |
| `rake soul_link:import_data` | Import run data from YAML (requires `GUILD_ID`) |
| `rake soul_link:test_run` | Create a test run (optional `GUILD_ID`, defaults to 0) |
| `rake soul_link:test_data` | Add sample Pokemon to test run (optional `GUILD_ID`) |
| `rake soul_link:reload_config` | Reload gym, location, and settings YAML files |
| `rake soul_link:find_channel_ids` | Show how to find Discord channel IDs |

## File Structure

```
app/
├── models/
│   ├── soul_link_run.rb          # Run model (guild-scoped, tracks channels/panels)
│   └── soul_link_pokemon.rb      # Pokemon model (caught/dead status, location)
└── services/
    └── soul_link/
        ├── discord_bot.rb         # Bot logic (commands, interactions, panels)
        └── game_state.rb          # YAML config loader (gyms, locations, settings)

config/
└── soul_link/
    ├── gym_info.yml               # Gym names and recommended levels
    ├── locations.yml              # Location keys and display names
    ├── settings.yml               # Bot settings (category prefix, etc.)
    └── import_data.yml            # Template for importing existing run data

db/
└── migrate/
    ├── 20260202164130_create_soul_link_tables.rb
    └── 20260221200000_add_guild_id_to_soul_link_runs.rb

.github/
└── workflows/
    └── deploy.yml                 # Auto-deploy to Vultr on push to main
```

## Database Schema

### soul_link_runs
| Column | Type | Description |
|---|---|---|
| `guild_id` | bigint | Discord server (guild) ID |
| `run_number` | integer | Sequential run number (unique per guild) |
| `category_id` | bigint | Discord category channel ID |
| `general_channel_id` | bigint | General text channel ID |
| `catches_channel_id` | bigint | Catches text channel ID |
| `deaths_channel_id` | bigint | Deaths text channel ID |
| `catches_panel_message_id` | bigint | Message ID of the catches panel |
| `deaths_panel_message_id` | bigint | Message ID of the deaths panel |
| `active` | boolean | Whether this is the current active run |

### soul_link_pokemon
| Column | Type | Description |
|---|---|---|
| `soul_link_run_id` | bigint | Foreign key to the run |
| `name` | string | Pokemon nickname |
| `location` | string | Location key (from locations.yml) |
| `status` | string | `caught` or `dead` |
| `discord_user_id` | bigint | Who recorded this entry |
| `caught_at` | datetime | When caught |
| `died_at` | datetime | When died (null if still alive) |

## Customization

### Category Naming

Edit `config/soul_link/settings.yml`:

```yaml
category_prefix: "Platinum Run"   # -> "Platinum Run 1", "Platinum Run 2"
# category_prefix: "Nuzlocke Run"  # -> "Nuzlocke Run 1", etc.
```

### Adding Locations

Edit `config/soul_link/locations.yml`:

```yaml
victory_road:
  name: "Victory Road"
route_228:
  name: "Route 228"
```

### Adding Gyms

Edit `config/soul_link/gym_info.yml`:

```yaml
ninth_gym:
  name: "Elite Four"
  recommended_level: 55
```

After editing any YAML file, reload with:
```bash
rake soul_link:reload_config
```

## Troubleshooting

**Bot not responding to commands:**
- Check the bot is running: `systemctl status soul-link-bot`
- Check logs: `journalctl -u soul-link-bot -f`
- Slash commands may take up to 1 hour to sync with new servers
- Verify bot has proper permissions in the server

**Panels not updating:**
- Ensure `catches_panel_message_id` and `deaths_panel_message_id` are set
- Use `/post_panels` to post fresh panels
- Check logs for errors

**`/post_panels` says "No active run found":**
- Verify the import succeeded: `GUILD_ID=X rake soul_link:status`
- Ensure only one run has `active: true` per guild

**Location not found:**
- Use route keys from `locations.yml` (e.g., `route_201` not `Route 201`)
- Keys are lowercase with underscores

**Import errors:**
- YAML requires 2-space indentation (not tabs)
- Wrap strings with special characters in quotes
- Dead Pokemon locations are derived from `caught_pokemon` by matching `name` + `caught_at`

## Support

- discordrb: https://github.com/shardlab/discordrb
- Discord API: https://discord.com/developers/docs
- Rails logs: `journalctl -u soul-link-bot -f` (production) or check `log/development.log` (local)
