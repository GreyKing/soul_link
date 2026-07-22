# Death Embed Parity — Live-updating Death Message + Refresh — Design

**Date:** 2026-07-22
**Branch:** `claude/deaths-discord-integration-8e64d7`

## Problem

The catch system recently gained `SoulLink::CatchMessage`: a stateless, per-group
live embed in the catches channel that both the website and bot keep in sync, with
a `🔄 REFRESH` button as a manual re-sync escape hatch. Deaths never got the same
treatment. Today the death side has two artifacts, and both are stale-prone:

1. **The "RIP" announcement** (`DiscordNotifier.notify_group_death`) — a one-shot
   plain-text message. No stored id, no buttons, never edited.
2. **The "💀 Fallen Pokemon" panel** (`DiscordBot#build_deaths_embed` /
   `update_deaths_panel`) — a per-run roster embed. But `update_deaths_panel` uses
   the running bot's `channel.load_message(...).edit(...)`, so **only the bot
   process can update it.** When a death happens via the website
   (`PokemonGroupsController#update`), the panel is never touched — which is why the
   screenshot shows "No deaths yet · Groups: 0" even after a group died.

## Goals

Full parity with the catch system, mirroring its two-artifact shape:

1. **Per-group live death embed** — a new `SoulLink::DeathMessage` (clone of
   `CatchMessage`) posts one rich red embed per dead group to the deaths channel,
   updates in place, and carries a `🔄 REFRESH` button. Replaces the plain-text RIP.
2. **Web-updatable Fallen Pokemon panel** — a new stateless `SoulLink::DeathsPanel`
   re-renders the roster panel via `Discordrb::API::Channel.edit_message`, callable
   from the web process, plus a `🔄 REFRESH` button on the panel itself.
3. **Every death path posts/updates both** — website Mark-Dead, bot Move-to-Deaths,
   and bot Add-Uncaught-Death.

## Non-goals

- No `🔄 REFRESH` button on the *catches* panel — scoped to deaths.
- No change to how uncaught deaths or auto-parsed catches are created.
- The Fallen Pokemon panel is still **created** only via the bot's `/post_panels`
  command; the web path edits an existing panel but never spawns one.

## Design

### 1. `discord_death_message_id` column

Add `discord_death_message_id` (bigint) to `soul_link_pokemon_groups`, mirroring
`discord_catch_message_id`. Doubles as idempotency key and edit address for the
per-group death embed.

### 2. `SoulLink::DeathMessage` — per-group live embed

`app/services/soul_link/death_message.rb`. A near-exact clone of `CatchMessage`,
targeting `run.deaths_channel_id`:

- `post_or_update(group)` — edits if `discord_death_message_id` present, else posts
  and stores the id. Fire-and-forget (swallow + warn).
- `delete(group)` — deletes the message and nils the id. For revive / group destroy.
  Callers invoke it **before** destroying the row.
- `edit` — same stale-id recovery (`RestClient::NotFound` /
  `Discordrb::Errors::UnknownMessage` → clear id, re-post once).
- `embed(group)` — red (`0xED4245`): title `💀 RIP "<nick>" — <location>`,
  description one line per fallen player + species, plus a `📝 <eulogy>` line when
  present. Same content the plain-text RIP carried, now a rich embed.
- `components(group)` — a single `🔄 REFRESH` button,
  `custom_id: "soul_link:death_refresh:<group.id>"`. **Unlike the catch embed** —
  which strips buttons on death to freeze as history — a death embed is *always*
  dead, so it **keeps** its refresh button.

### 3. `SoulLink::DeathsPanel` — web-updatable roster panel

`app/services/soul_link/deaths_panel.rb`. Stateless renderer owning the panel's
embed + buttons, so there is one source of truth:

- `embed(run)` — the `💀 Fallen Pokemon` roster (moved verbatim from the bot's
  `build_deaths_embed`), as a plain hash.
- `components` — the panel action row: `💀 Move Caught to Deaths`
  (`soul_link:move_to_deaths`), `➕ Add Uncaught Death`
  (`soul_link:add_uncaught_death`), and the **new** `🔄 REFRESH`
  (`soul_link:deaths_refresh`).
- `refresh(run)` — **edit-only.** No-op when `run.deaths_panel_message_id` is blank
  (the panel is created by `/post_panels`, not here). Edits via
  `Discordrb::API::Channel.edit_message`; on unknown-message clears the stale id so a
  later `/post_panels` re-creates cleanly. Fire-and-forget.

The bot's `update_deaths_panel(run)` delegates to `DeathsPanel.refresh(run)`; its
`post_deaths_panel` renders from `DeathsPanel.embed`/`components` so freshly-posted
panels gain the refresh button. The bot's `build_deaths_embed` / `build_deaths_buttons`
are removed (logic now lives in `DeathsPanel`).

### 4. Bot button handlers

Mirror the `apply_catch_refresh` / `handle_catch_refresh` seam:

- `bot.button(custom_id: /^soul_link:death_refresh:/)` → `handle_death_refresh` →
  `DiscordBot.apply_death_refresh(run:, group_id:)` → `DeathMessage.post_or_update`.
  Found → ephemeral `🔄 Refreshed.`; missing group → `❌ That death no longer exists.`
- `bot.button(custom_id: /^soul_link:deaths_refresh$/)` → `handle_deaths_panel_refresh`
  → `DiscordBot.apply_deaths_panel_refresh(run:)` → `DeathsPanel.refresh`. Ephemeral
  `🔄 Refreshed.` No ownership gate on either — read-only re-renders.

Both new panel/embed custom_ids must register **before** the existing broader
`move_to_deaths` / `add_uncaught_death` matchers so a stricter route isn't shadowed
(the existing ones use loose `/^soul_link:move_to_deaths/` regexes).

### 5. Wiring — post/update on every death path

`PokemonGroupsController#update`:
- **Mark-Dead branch:** replace `DiscordNotifier.notify_group_death(run, group)` with
  `DeathMessage.post_or_update(group)` + `DeathsPanel.refresh(run)`.
- **Revive branch:** `DeathMessage.delete(group)` + `DeathsPanel.refresh(run)`.
- **Metadata-edit branch (dead group):** re-sync the death embed when
  `discord_death_message_id` present (mirrors the catch guard) + `DeathsPanel.refresh`.

`PokemonGroupsController#destroy`: `DeathMessage.delete(group)` before `group.destroy!`
(alongside the existing `CatchMessage.delete`), then `DeathsPanel.refresh(run)` after.

`DiscordBot#handle_move_to_deaths_final`: add `DeathMessage.post_or_update(group)`
after `mark_as_dead!` (the panel already updates via `update_deaths_panel`).

`DiscordBot#handle_uncaught_death_submission`: add `DeathMessage.post_or_update(group)`.

### 6. Cleanup

Remove `DiscordNotifier.notify_group_death` and its tests — fully superseded by
`DeathMessage`. It has exactly one caller (the web Mark-Dead path), replaced above.

### 7. Tests

- `death_message_test.rb` — clone of `catch_message_test.rb`: posts+persists id,
  edits on second call, red embed, refresh button present, `delete`, stale-id re-post,
  never-raises, blank-channel / nil-group no-ops.
- `death_refresh_test.rb` — `apply_death_refresh` (found → post_or_update; missing →
  not-found; nil run) and `apply_deaths_panel_refresh` (calls `DeathsPanel.refresh`;
  nil run → error).
- `deaths_panel_test.rb` — `refresh` edits the stored id, is a no-op with no panel id,
  embed lists dead groups, components include all three buttons, never raises.
- `pokemon_groups_controller_test.rb` — Mark-Dead posts the death embed + refreshes the
  panel; revive deletes the embed; destroy deletes the embed; dead-group edit re-syncs.
- `discord_notifier_test.rb` — remove all `notify_group_death` cases.

## Trade-offs

- **The RIP becomes a boxed embed** rather than plain text. Required for buttons +
  in-place editing; matches the "NEW CATCH" look. Accepted (user-confirmed).
- **Panel refresh is edit-only.** If the panel message was deleted in Discord, the web
  path can't recreate it — an admin re-runs `/post_panels`. Consistent with today's
  `update_deaths_panel` no-op-when-missing behavior.
- **Both a per-group death embed and a roster panel now live in the deaths channel** —
  symmetric with the catches channel (per-group catch embeds + catches panel).
