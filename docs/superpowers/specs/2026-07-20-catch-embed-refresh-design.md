# Catch Embed Refresh + Self-Healing Sync — Design

**Date:** 2026-07-20
**Branch:** `claude/new-catch-refresh-button-4ae73a`

## Problem

The live "NEW CATCH" Discord embed (`SoulLink::CatchMessage`) is edited from the
website whenever a catch changes — but only on three of five write paths. Group
edits and deletes never re-sync, so website changes silently drift from Discord.
There is also no manual recovery path when a fire-and-forget Discord call fails
silently.

Today `CatchMessage.post_or_update` fires on:

- `PokemonGroupsController#create` — new group
- `PokemonController#create` — a player adds their pokemon
- `PokemonController#update` — a player edits their pokemon

It does **not** fire on:

- `PokemonGroupsController#update` — rename, relocate, **mark dead**, revive
- `PokemonGroupsController#destroy` — embed lingers forever after the group is gone

## Goals

1. A **REFRESH button** on the catch embed as a manual re-sync escape hatch.
2. **Self-healing hooks** so website group edits/deletes update Discord automatically.
3. **Terminal-state rendering:** a marked-dead group's embed recolors to a death
   look and drops its buttons (frozen history); a deleted group's message is
   removed from Discord entirely.

## Non-goals

- No refresh button on the run-status panel or death embeds. Scoped to catch embeds.
- No change to the three paths that already sync.

## Design

### 1. `CatchMessage` becomes status-aware

`app/services/soul_link/catch_message.rb`.

- `embed(group)` — branches on `group.dead?`:
  - caught → `🎯 NEW CATCH — <location> • "<nick>"`, green `0x57F287` (unchanged)
  - dead → `💀 <location> • "<nick>"`, red `0xED4245` (new `DEAD_EMBED_COLOR`)
  - description (`player_lines`) is unchanged in both cases.
- `components(group)` — returns `[]` when `group.dead?` (both buttons stripped so
  the embed freezes as history); otherwise the `ADD MY POKEMON` button **plus** a
  new `REFRESH` button.
- **New** `CatchMessage.delete(group)` — deletes the Discord message via
  `Discordrb::API::Channel.delete_message` and nils `discord_catch_message_id`
  through `update_columns`. No-op when the group is nil or has no message id.
  Same fire-and-forget rescue contract (`rescue StandardError` → warn log → nil)
  as `post_or_update`. **The message id must be read before the group row is
  destroyed** — callers order the delete before `group.destroy!`.

`post_or_update` is unchanged in shape: dead groups still route through `edit`
(they have a message id), which now renders the recolored, button-less embed.

### 2. REFRESH button + bot handler

- **Button:** second entry in the existing action row. Style `2` (secondary),
  label `🔄 REFRESH`, custom_id `soul_link:catch_refresh:<group.id>` — matches the
  `soul_link:action:context:value` convention.
- **Registration:** a `bot.button(custom_id: /^soul_link:catch_refresh:/)`
  handler beside the `catch_add` handler at `discord_bot.rb:321`.
- **Split:** mirror the existing `handle_catch_quick_add` →
  `self.class.apply_catch_quick_add` seam. Logic lives in a testable class method
  `CatchMessage`-driven `apply_catch_refresh(run:, group_id:)`; the instance
  handler just acks ephemerally. `apply_catch_refresh` is a class method on the
  bot service (like `apply_catch_quick_add`) that delegates to
  `CatchMessage.post_or_update`.
  - group found → `post_or_update(group)`, ephemeral `🔄 Refreshed.`
  - group missing (deleted on the website) → nothing to re-render; ephemeral
    `❌ That catch group no longer exists.`
- **No ownership gate** — a read-only re-render, any run member may click.

### 3. Missing self-healing hooks

- `PokemonGroupsController#update` (`:59`): one `CatchMessage.post_or_update(group)`
  before `render`, covering all three branches (dead / revive / metadata).
- `PokemonGroupsController#destroy` (`:145`): `CatchMessage.delete(group)`
  immediately **before** `group.destroy!` (id must still exist).
- `discord_bot.rb:1094` (bot's eulogy death path, which also calls
  `mark_as_dead!`): add `CatchMessage.post_or_update(group)` so Discord-driven
  deaths recolor the embed too, not just website-driven ones.

### 4. Tests

- `catch_message_test.rb`:
  - dead group → embed title starts `💀`, color is red, `components` is `[]`.
  - caught group → `components` includes both `catch_add` and `catch_refresh`
    custom_ids.
  - `delete` with a message id → issues `delete_message`, nils the column.
  - `delete` with nil id / nil group → no HTTP call, no raise.
- `pokemon_groups_controller` tests: `#update` triggers `post_or_update`;
  `#destroy` triggers `delete` before the row is gone.
- Bot logic: test `apply_catch_refresh` directly (found → post_or_update called;
  missing → returns the not-found result), per existing convention.

## Trade-offs

- **Stripping buttons on death** means a dead group's embed can't be manually
  refreshed. Reviving from the website still recolors it automatically via the
  `#update` hook, so the only loss is the manual escape hatch on already-dead
  groups. Accepted (user-confirmed).
- **Delete-on-destroy is fire-and-forget:** if the Discord delete fails, the
  embed lingers, but the group row is still removed locally. The REFRESH button
  on a since-deleted group self-cleans by reporting "no longer exists" — though
  once the row is gone there is no button to click. Acceptable; deletion is rare
  and the death channel carries the authoritative record.
