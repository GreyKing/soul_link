# Death Embed Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Give deaths the catch system's live-updating + refresh treatment: a per-group `DeathMessage` embed (clone of `CatchMessage`) and a web-updatable `DeathsPanel`, each with a `🔄 REFRESH` button, wired into every death path. Remove the superseded plain-text RIP.

**Tech stack:** Rails 8.1, Ruby 3.4.5, discordrb (positional REST API), Minitest + FactoryBot, `Object#stub`.

Design: `docs/superpowers/specs/2026-07-22-death-embed-parity-design.md`.

---

## File Structure

| File | Change |
|------|--------|
| `db/migrate/*_add_discord_death_message_id_to_soul_link_pokemon_groups.rb` | Create |
| `app/services/soul_link/death_message.rb` | Create |
| `app/services/soul_link/deaths_panel.rb` | Create |
| `app/services/soul_link/discord_bot.rb` | Modify (handlers, panel delegation, death-path hooks) |
| `app/controllers/pokemon_groups_controller.rb` | Modify (death/revive/edit/destroy hooks) |
| `app/services/soul_link/discord_notifier.rb` | Modify (remove `notify_group_death`) |
| `test/services/soul_link/death_message_test.rb` | Create |
| `test/services/soul_link/deaths_panel_test.rb` | Create |
| `test/services/soul_link/death_refresh_test.rb` | Create |
| `test/controllers/pokemon_groups_controller_test.rb` | Modify |
| `test/services/soul_link/discord_notifier_test.rb` | Modify (drop group_death cases) |

---

## Task 1: Migration + `DeathMessage` service

- [ ] **Migration:** `bin/rails g migration AddDiscordDeathMessageIdToSoulLinkPokemonGroups discord_death_message_id:bigint`, run `bin/rails db:migrate`, confirm `db/schema.rb` gains the column.

- [ ] **Test first** — `test/services/soul_link/death_message_test.rb`, cloned from `catch_message_test.rb` but for `SoulLink::DeathMessage`, `deaths_channel_id: 2222`, and `discord_death_message_id`. Cases: posts+persists id (channel 2222); embed lands in positional arg 5 with `💀` + `RIP` in the title; second call edits not posts; no-op when `deaths_channel_id` blank; no-op when group nil; stale-id re-post on `UnknownMessage` and bodyless `NotFound`; never raises on `SocketError`; embed lists every fallen player+species (create a `:route206`-style group with pokemon, mark dead); embed carries `soul_link:death_refresh:<id>` button; `delete` removes message + nils id; delete no-ops (never posted / nil group); delete never raises. Run → fail.

- [ ] **Implement** `app/services/soul_link/death_message.rb` — copy `catch_message.rb` and adapt:
  - `EMBED_COLOR = 0xED4245` (red).
  - Reads/writes `discord_death_message_id`; targets `run.deaths_channel_id`.
  - `embed(group)`: `title: "💀 RIP \"#{group.nickname}\" — #{location_name(group.location)}"`, `description: death_lines(group).join("\n")` (one `**<player>** — <species>` line per `group.soul_link_pokemon`, then `📝 <eulogy>` when present), `color: EMBED_COLOR`.
  - `components(group)`: always one row with the `🔄 REFRESH` button `soul_link:death_refresh:#{group.id}` (no dead-check — death embeds keep the button).
  - Keep `post`/`edit`/`delete`/`parse_message_id`/`log_failure`/`resolve_token` verbatim (rename `discord_catch_message_id` → `discord_death_message_id`, `catches_channel_id` → `deaths_channel_id`, log prefix `DeathMessage`).
  - Run → pass. **Commit.**

## Task 2: `DeathsPanel` service + bot delegation

- [ ] **Test first** — `test/services/soul_link/deaths_panel_test.rb`. Setup a run with `deaths_channel_id: 2222`, `deaths_panel_message_id: 8080`, and a dead group. Stub `edit_message`. Cases: `refresh(run)` edits message 8080 in channel 2222; no-op when `deaths_panel_message_id` blank; embed (arg 6) title includes `Fallen Pokemon`, lists the dead group's nickname; `components` first row has three buttons with custom_ids `soul_link:move_to_deaths`, `soul_link:add_uncaught_death`, `soul_link:deaths_refresh`; never raises on `SocketError`; clears stale id + logs on `UnknownMessage`. Run → fail.

- [ ] **Implement** `app/services/soul_link/deaths_panel.rb` (stateless, `class << self`):
  - `embed(run)` — plain hash moved from bot's `build_deaths_embed`: `title: "💀 Fallen Pokemon"`, roster `description` over `run.dead_groups.includes(:soul_link_pokemon)`, `color: 0xff0000`, `footer: { text: "Run ##{run.run_number} | Groups: #{groups.count}" }`, `timestamp: Time.now.utc.iso8601` (string — plain hashes can't hand the REST layer a `Time`).
  - `components` — plain hash array: Move-to-Deaths (style 4), Add-Uncaught-Death (style 2), 🔄 REFRESH `soul_link:deaths_refresh` (style 2).
  - `refresh(run)` — `return if run.nil? || run.deaths_panel_message_id.blank?`; resolve token; `Discordrb::API::Channel.edit_message(token, run.deaths_channel_id, run.deaths_panel_message_id, "", nil, [embed(run)], components)`; rescue `RestClient::NotFound`/`UnknownMessage` → `run.update_columns(deaths_panel_message_id: nil)` + warn; outer `rescue StandardError` → warn, nil.
  - `resolve_token`/`log_failure` mirror `DeathMessage`.

- [ ] **Redirect the bot** in `discord_bot.rb`:
  - `update_deaths_panel(run)` body → `SoulLink::DeathsPanel.refresh(run)` (drop the `bot.channel.load_message` path).
  - `post_deaths_panel(channel, run)` → pass `SoulLink::DeathsPanel.embed(run)` and `SoulLink::DeathsPanel.components` into `channel.send_message` (hash embed is fine — `send_message` calls `.to_hash`).
  - Delete `build_deaths_embed` and `build_deaths_buttons` (now unused — confirmed no other callers).
  - Run panel test + full bot-touching suite → pass. **Commit.**

## Task 3: Bot refresh handlers (`death_refresh`, `deaths_refresh`)

- [ ] **Test first** — `test/services/soul_link/death_refresh_test.rb`:
  - `apply_death_refresh(run:, group_id:)`: existing dead group → `DeathMessage.post_or_update` called, `{ok: true}`; missing group → `{ok:false, error:/no longer exists/i}`; nil run → not ok.
  - `apply_deaths_panel_refresh(run:)`: calls `DeathsPanel.refresh` (stub-capture) and returns ok; nil run → not ok, no call. Run → fail.

- [ ] **Implement** in `discord_bot.rb`:
  - Class methods beside `apply_catch_refresh`:
    ```ruby
    def self.apply_death_refresh(run:, group_id:)
      group = run&.soul_link_pokemon_groups&.find_by(id: group_id)
      return { ok: false, error: "That death no longer exists." } if group.nil?
      SoulLink::DeathMessage.post_or_update(group)
      { ok: true }
    end

    def self.apply_deaths_panel_refresh(run:)
      return { ok: false, error: "No active run found." } if run.nil?
      SoulLink::DeathsPanel.refresh(run)
      { ok: true }
    end
    ```
  - Button registrations — add **before** the loose `move_to_deaths` matcher (line ~384) so the stricter `deaths_refresh` route isn't shadowed:
    ```ruby
    bot.button(custom_id: /^soul_link:death_refresh:/) do |event|
      handle_death_refresh(event, event.interaction.data['custom_id'].split(':').last)
    end
    bot.button(custom_id: /^soul_link:deaths_refresh$/) do |event|
      handle_deaths_panel_refresh(event)
    end
    ```
  - Instance handlers beside `handle_catch_refresh`, each acking ephemerally (`🔄 Refreshed.` / `❌ #{error}`), mirroring its rescue shape.
  - Run → pass. **Commit.**

## Task 4: Wire the death paths + remove the plain-text RIP

- [ ] **Controller tests first** — append to `pokemon_groups_controller_test.rb`: Mark-Dead posts the death embed (`DeathMessage.post_or_update` called with the group) and refreshes the panel (`DeathsPanel.refresh` called); revive deletes the embed (`DeathMessage.delete`); destroy deletes the embed before the row is gone; editing a dead group with a live `discord_death_message_id` re-syncs. Run → fail.

- [ ] **Implement `PokemonGroupsController#update`:**
  - Mark-Dead branch: replace `SoulLink::DiscordNotifier.notify_group_death(run, group)` with `SoulLink::DeathMessage.post_or_update(group)`; add `SoulLink::DeathsPanel.refresh(run)`.
  - Revive branch: after the transaction, `SoulLink::DeathMessage.delete(group)` + `SoulLink::DeathsPanel.refresh(run)`.
  - Metadata-edit branch: after the catch re-sync guard, add `SoulLink::DeathMessage.post_or_update(group) if group.discord_death_message_id.present?` + `SoulLink::DeathsPanel.refresh(run) if group.dead?`.

- [ ] **Implement `PokemonGroupsController#destroy`:** add `SoulLink::DeathMessage.delete(group)` beside the existing `CatchMessage.delete(group)` (before `group.destroy!`), then `SoulLink::DeathsPanel.refresh(run)` after `group.destroy!`.

- [ ] **Bot death-final hooks:** in `handle_move_to_deaths_final` add `SoulLink::DeathMessage.post_or_update(group)` after `mark_as_dead!` (before/after the panel update); in `handle_uncaught_death_submission` add `SoulLink::DeathMessage.post_or_update(group)` after create.

- [ ] **Remove the RIP:** delete `DiscordNotifier.notify_group_death` (lines 38-55) and every `notify_group_death` case from `discord_notifier_test.rb` (the line in the nil-run test, the blank-channel test, and the three formatting/no-op tests).
  - Run controller + notifier suites → pass. **Commit.**

## Task 5: Full suite, lint, PR

- [ ] `bin/rails test` → 0 failures, 0 errors.
- [ ] `bundle exec rubocop app/services/soul_link/death_message.rb app/services/soul_link/deaths_panel.rb app/services/soul_link/discord_bot.rb app/controllers/pokemon_groups_controller.rb app/services/soul_link/discord_notifier.rb` → no offenses.
- [ ] Push branch, open PR against `main` with a summary + test evidence.

---

## Self-Review Notes

- **Symmetry:** `DeathMessage` mirrors `CatchMessage` method-for-method; only difference is `components` never strips buttons (death embeds are terminal but stay refreshable).
- **DRY:** panel rendering lives once in `DeathsPanel`; bot create + web edit both consume it.
- **Ordering:** `DeathMessage.delete` before `group.destroy!` (id lives on the row); custom_id `deaths_refresh` registered before the loose `move_to_deaths` matcher.
- **No orphan refs:** `notify_group_death` has one caller (removed) + its tests (removed).
