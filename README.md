# Soul Link Discord Bot

A Rails-powered Discord bot for managing Soul Link runs.
Features slash commands, buttons, and modals for logging catches and deaths.

### current invite link within the credentials

⸻

## Setup

### 1. Install gem
See: https://github.com/shardlab/discordrb

``gem 'discordrb', '~> 3.5'``


``bundle install``

### 2. Add credentials

Accessed via: ``rails credentials:edit``

```
discord:
  client_id: "YOUR_CLIENT_ID"
  bot_token: "YOUR_BOT_TOKEN"
  client_secret: "YOUR_CLIENT_SECRET"
```

### 3. Set guild + channel IDs

Edit in app/services/soul_link/discord_bot.rb:

```
DISCORD_GUILD_ID   = 123456789012345678
DISCORD_CHANNEL_ID = 123456789012345678
```

### 4. Invite the bot

Use the Developer Portal → OAuth2 → URL Generator:

* Scopes:
    * bot
    * applications.commands

* Bot Permissions:
    * View Channels
    * Send Messages
    * Manage Channels

Re-invite the bot to apply scopes.

### 5. Running

Via bin script
``bin/discord_bot``

Via Rails runner
``rails runner "SoulLink::DiscordBot.new.run"``

### 6. Commands

/panel

Posts the Soul Link control panel with:

* New Catch → modal for name + location
* New Death → modal for name + location

/status

Shows current boss info (from YAML or Rails data).

## Flow

Flow

1. Run bot
2. In configured channel, type /panel
3. Use buttons:
   * New Catch
   * New Death
4. Submit modal → bot logs entry (handled by SoulLink::Events)

## Structure

```
app/services/soul_link/
  discord_bot.rb   # main bot
  game_state.rb    # YAML-backed info
  events.rb        # handle catches/deaths
bin/
  discord_bot      # start bot
```

## Troubleshooting

* Slash commands missing → re-invite with applications.commands
* Bot can’t post → give it View Channel + Send Messages
* /panel fails → confirm channel ID + bot permissions