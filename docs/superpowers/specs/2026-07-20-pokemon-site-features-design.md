# Pokemon Site Features — Design

**Date:** 2026-07-20
**Branch:** `claude/pokemon-site-features-a3b30e`
**Shape:** One spec, seven staged commits, one PR.

## Overview

Seven features spanning three subsystems: Discord notification/interaction, the
site frontend, and the ROM randomizer pipeline. They are grouped here because
they land as one PR, but each is an independently reviewable and revertable
commit.

| # | Feature | Subsystem |
|---|---------|-----------|
| 1 | Site catch pushes to the catches channel, once per route/name | Discord |
| 6 | Players add their mon to that catch from Discord | Discord |
| 5 | One death message per group, not four | Discord |
| 2 | Click-outside closes modals | Frontend |
| 3 | Any-ability searchable select | Frontend |
| 7 | Drag PC-box mon to party; click party mon for details | Frontend |
| 4 | On-demand randomized ROM download | ROM pipeline |

Features 1 and 6 are one subsystem and share a commit boundary; the rest are
independent.

## Schema change

One migration:

```ruby
add_column :soul_link_pokemon_groups, :discord_catch_message_id, :bigint
```

Nullable, no index needed (lookups are by group id, never by message id — the
bot resolves the group from the button's custom_id, not from the message).

This column does double duty: it is the idempotency key for feature 1 (non-nil
means "already posted") and the addressing mechanism for feature 6 (the message
to PATCH after a player adds their species).

---

## Feature 1 + 6 — Catch post as a live embed

### Rationale

The existing `DiscordNotifier.notify_catch` fires only from the emulator
save-diff path (`CatchCoordinator`). The site's catch flow —
`PokemonGroupsController#create`, driven by the 4-player catch modal — posts
nothing. Rather than bolt a second fire-and-forget notifier onto the site path,
the catch post becomes a **live embed** that reflects the group's current state.
This makes "only once per route/name" fall out of the stored message id rather
than requiring a separate dedup table, and gives feature 6 a message to attach
its button to.

### New service: `SoulLink::CatchMessage`

Mirrors the shape of the existing `SoulLink::GymPollMessage` (embed builder +
post/update, class methods, fire-and-forget error handling).

```ruby
SoulLink::CatchMessage.post_or_update(group)
```

- Returns silently if `group.soul_link_run.catches_channel_id` is blank.
- Builds an embed listing all four registered players from
  `SoulLink::GameState.players`, each showing either their species + level or
  `— not caught yet —`.
- If `group.discord_catch_message_id` is nil: POST, then persist the returned
  message id to the group.
- If non-nil: PATCH the existing message.
- On a 404 from the PATCH (message manually deleted in Discord), null the
  column and re-POST once. This is the only retry; a second failure logs and
  gives up.
- Swallows and logs every failure at warn level. Never raises. Callers need no
  rescue, matching the `DiscordNotifier` contract.

**Idempotency is the central property.** Calling `post_or_update` twice must
produce exactly one Discord message. This gets explicit test coverage.

### Embed shape

```
🎯 NEW CATCH — Route 205 • "Tommy"

Glenn     Staravia   Lv 12
Alex      Shinx      Lv 11
Sam       — not caught yet —
Jordan    — not caught yet —

[ADD MY POKEMON]
```

The button's custom_id is `soul_link:catch_add:<group_id>`, following the
existing `soul_link:action:context:value` convention documented in
`.claude/documents/discord-bot.md`.

### Call sites

| Call site | Trigger |
|-----------|---------|
| `PokemonGroupsController#create` | New group created from the site catch modal |
| `PokemonController#create` | A player fills in their species for an existing group |
| `PokemonController#update` | A player edits species/level on an existing group |

Called as the last statement of the successful path in each, so a notification
failure cannot roll back the write.

### Bot interaction flow (feature 6)

Follows the existing `soul_link:species_modal` pattern already in
`SoulLink::DiscordBot`:

1. `bot.button(custom_id: /^soul_link:catch_add:/)` — opens a Discord modal with
   a single species text field.
2. `bot.modal_submit(custom_id: /^soul_link:catch_species_modal:/)` — resolves
   the species, creates the `SoulLinkPokemon` for `event.user.id`, calls
   `CatchMessage.post_or_update(group)` to refresh the embed.

**Why a modal and not a select menu:** Discord string select menus cap at 25
options. There are 493 species. A select menu cannot represent the species list.
The modal + text field pattern has no such cap and is already used elsewhere in
this bot.

### Species resolution rules

Deterministic, three-tier, no guessing:

1. **Exact match** (case-insensitive) against `pokedex.yml` keys → accept.
2. **Unique prefix match** → accept. `"staravi"` → `Staravia`.
3. **Ambiguous or no match** → reject with an ephemeral message listing up to 5
   candidates. `"star"` → `Did you mean: Staravia, Staraptor, Starly, Starmie?`

No write occurs on rejection. The player can click the button again.

### Authorization

The species is always created for `event.user.id` — the clicking player. A
player cannot fill in someone else's slot from Discord. If that player already
has a Pokemon in the group, the modal submit returns an ephemeral error rather
than overwriting (matches `PokemonController#create`'s existing guard).

If the clicking user is not one of the four registered players in
`SoulLink::GameState.players`, reject with an ephemeral message.

---

## Feature 5 — Single death message

### Current behavior

`PokemonGroupsController#update` loops over the group's Pokemon and calls
`DiscordNotifier.notify_death` once per linked Pokemon — four messages for one
death event.

### Change

Replace the loop with a single call:

```ruby
SoulLink::DiscordNotifier.notify_group_death(run, group)
```

One embed listing all four players' mons:

```
💀 RIP "Tommy" — Route 205

Glenn     Staravia
Alex      Shinx
Sam       Bidoof
Jordan    Kricketot
```

The old per-Pokemon `notify_death` method is **deleted**, not left in place. It
has no other callers. Its existing test is rewritten against the new method
rather than deleted.

Wipe detection (`WipeCoordinator.process`) is unchanged and still runs on every
Mark Dead transition.

---

## Feature 2 — Click-outside closes modals

### Root cause

Every modal already has a working close action on its backdrop, e.g.
`_pokemon_modal.html.erb:5`:

```erb
<div data-action="click->pixeldex#closePokemonModal"
     style="position: absolute; inset: 0; background: rgba(15, 56, 15, 0.75);"></div>
```

The bug is z-order. The backdrop is `position: absolute; inset: 0`, and its
**sibling** content wrapper is `position: relative; min-height: 100vh`. The
positioned sibling paints above the backdrop and covers the entire viewport, so
every click in the visually-empty area around the modal card lands on the
wrapper, not the backdrop. The backdrop's handler is unreachable.

This affects all six modals identically. It is one bug, not six.

### Fix

Move the close action from the backdrop onto the content wrapper, guarded so
that only clicks on the wrapper itself — not clicks that bubbled up from the
modal card — trigger the close:

```erb
<div data-action="click->pixeldex#closePokemonModalOnBackdrop"
     style="position: relative; display: flex; ...">
```

```js
closePokemonModalOnBackdrop(event) {
  if (event.target !== event.currentTarget) return
  this.closePokemonModal()
}
```

The `event.target !== event.currentTarget` guard is what prevents clicks inside
the modal card from closing it. Keeping the backdrop element itself is still
correct — it provides the dimming — it just no longer carries the handler.

### Scope

Applied uniformly to all six modals:

| Modal | Controller method |
|-------|-------------------|
| `dashboard/_catch_modal.html.erb` | `dashboard#closeCatchModal` |
| `dashboard/_pokemon_modal.html.erb` | `pixeldex#closePokemonModal` |
| `dashboard/_mark_dead_modal.html.erb` | `dashboard#closeMarkDeadModal` |
| `dashboard/_reset_draft_modal.html.erb` | `dashboard#closeResetDraftModal` |
| `shared/_confirm_modal.html.erb` | `confirm-modal#close` |
| `teams/_quick_calc_modal.html.erb` | `quick-calc#close` |

Existing ESC-to-close (`escape_close_controller`) and focus trapping
(`modal_a11y_controller`) are untouched and continue to work.

---

## Feature 3 — Any-ability searchable select

### Rationale

The ability select is currently populated per-species from
`abilitiesDataValue[species]` (`pixeldex_controller.js:514`), which restricts a
Pokemon to its natural abilities. Since any Pokemon can now have any ability,
the select must offer the full list.

`config/soul_link/abilities.yml` contains **123 unique abilities** across all
species. That is roughly 3KB of JSON — smaller than a single sprite asset. An
AJAX-paginated endpoint with infinite scroll would add an endpoint, a loading
state, a failure mode, and per-keystroke latency to a dataset that fits
comfortably in the page. The list ships inline; filtering is client-side.

The UX is unchanged from the original request: search box, five visible at a
time, scroll for more.

### New controller: `searchable_select_controller.js`

Written generically (not ability-specific) so the species field can adopt it
later without a rewrite.

**Values:**
- `options: Array` — the selectable strings
- `placeholder: String`
- `visibleCount: Number` (default 5)

**Targets:** `input`, `list`, `hidden`

**Behavior:**
- Typing filters case-insensitively on substring match.
- Listbox shows `visibleCount` rows at a time; the rest reachable by scrolling.
- Keyboard: ↑/↓ move the active option, Enter selects, Escape closes the
  listbox (and does **not** close the parent modal — the handler stops
  propagation when the listbox is open).
- Clicking an option selects it and writes to the hidden input.
- Blur closes the listbox after a short delay so option clicks still register.

**ARIA:** `role="combobox"` on the input with `aria-expanded` and
`aria-activedescendant`; `role="listbox"` on the list; `role="option"` on rows.

### New helper

`SoulLink::GameState.all_abilities` — the sorted unique union of
`pokemon_abilities.values`, memoized alongside the existing `pokemon_abilities`
and cleared by the existing cache-reset method.

### Wiring

`_pokemon_modal.html.erb`'s `<select data-pixeldex-target="modalAbility">` is
replaced with the searchable-select markup. `pixeldex_controller.js`'s
`savePokemon` reads the hidden input instead of the select's value. The
per-species population logic at line 514 is removed.

Existing saved abilities that are not in the list (data drift) still display —
the input is seeded with the stored value on open regardless of list membership.

---

## Feature 7 — Party drag-and-drop and click-through

### Drag PC-box → party

SortableJS is already used in `team_builder_controller.js`. The PC box grid and
the party panel become a shared Sortable group.

- Only **living** (`status == 'caught'`) Pokemon are draggable. Dead cells get
  `filter` applied so the drag never starts.
- On drop, the client computes the resulting ordered group id list and PATCHes
  the existing `/team/update_slots` endpoint. No new endpoint.

### Full party — swap semantics

Dropping onto an occupied slot *n* **swaps**: the resident group leaves the
party, the dragged group takes position *n*. The displaced group returns to the
PC box view. Party order is otherwise preserved.

This is a deliberate choice over rejecting the drop — it makes party editing a
single gesture rather than remove-then-add.

### Ownership constraint

`TeamsController#update_slots` already rejects groups where the current user has
no Pokemon (`teams_controller.rb:32`). The client mirrors this check so an
ineligible drag is refused visually at drag-start, rather than appearing to
succeed and then silently reverting when the server response comes back.

The server-side check remains authoritative and is not weakened.

### Click party mon → details

Party slots gain `data-action="click->pixeldex#selectPokemon"` with the group id
in a data attribute, opening the same detail modal the PC box uses. No new
modal, no new controller method — the existing one is reused.

Because a slot is both draggable and clickable, the click handler ignores events
that follow a drag (SortableJS sets a flag during drag; the handler checks it).

---

## Feature 4 — On-demand randomized ROM download

### Rationale

`SoulLink::RomRandomizer` and `SoulLink::GenerateRunRomsJob` already exist, but
they are bound to `SoulLinkEmulatorSession` records — one ROM per player per
run, for the in-browser emulator. This feature wants a standalone ROM, not tied
to a session, downloadable from the runs page.

### Why async

`RomRandomizer` has a 30-second timeout on the Java subprocess. Holding an HTTP
request open for that long risks nginx and Puma timeouts and gives the user no
feedback while waiting. Generation is queued; the button reflects progress.

### Changes

**`RomRandomizer` gains a session-free path.** The class currently reads and
writes `session.status` / `session.error_message` / `session.rom_path`
throughout. Extract the subprocess invocation into a method that takes an
explicit output path and returns a result object, leaving the session-mutating
wrapper on top of it for existing callers. This keeps the emulator path
byte-for-byte unchanged while making the randomizer reusable.

**New model `SoulLinkRomDownload`:**

```ruby
create_table :soul_link_rom_downloads do |t|
  t.references :soul_link_run, null: false, foreign_key: true
  t.bigint  :discord_user_id, null: false
  t.string  :status, null: false, default: "pending"  # pending/generating/ready/failed
  t.string  :rom_path
  t.string  :error_message
  t.timestamps
end
```

**New job `SoulLink::GenerateRomDownloadJob`** — wraps the extracted randomizer
path, writes to `storage/roms/downloads/run_<id>/<download_id>.nds`.

**Routes:**

```ruby
resources :runs, only: %i[index edit update] do
  resources :rom_downloads, only: %i[create show], module: :runs do
    get :download, on: :member
  end
end
```

- `POST` queues the job, returns the download id.
- `GET show` returns `{ status: ... }` for polling.
- `GET download` streams the `.nds` with `send_file`, 404 unless status is ready
  and the requesting user owns the row.

**Frontend:** a `rom-download` Stimulus controller on the runs panel. Click →
POST → poll `show` every 2s → flip to a download link on ready, or an inline
error on failed. Polling stops on terminal status and on controller disconnect.

**Cleanup:** generated ROMs accumulate on disk. The existing
`lib/tasks/emulator_cleanup.rake` gains a task to prune download ROMs older than
7 days, following the pattern already established there.

### Blocked dependency

This feature is built against the **current**
`config/soul_link/randomizer_settings.rnqs`. The updated settings file has not
been supplied yet.

The settings file is pure data — swapping it is a drop-in replacement requiring
no code change. However, **the new settings cannot be verified to produce a
valid ROM until the file lands.** This is called out in the PR description.

---

## Testing

All tests use FactoryBot factories from `test/factories/`, minimum-viable per
`CLAUDE.md`. No fixtures.

**Discord paths** stub `Discordrb::API::Channel` (`create_message`,
`edit_message`), following the convention in
`test/services/soul_link/discord_notifier_test.rb`. No real HTTP.

| Area | Coverage |
|------|----------|
| `CatchMessage` | Posts once; second call PATCHes rather than posting; persists message id; blank channel is a no-op; 404-on-PATCH re-posts exactly once |
| Species resolution | Exact match; unique prefix; ambiguous rejects without writing; unknown rejects |
| Bot interaction | Creates for the clicking user only; duplicate-player guard; unregistered-user guard |
| Death message | Exactly one `create_message` call for a 4-Pokemon group |
| `GameState.all_abilities` | Returns sorted unique union; cache reset works |
| `update_slots` swap | Displaced group leaves; order preserved; ownership rejection still enforced |
| `RomDownload` | Job transitions status; download 404s when not ready; download 404s for a non-owner |

**Not covered by automated tests:** the modal z-order fix (feature 2) and the
drag-and-drop interaction (feature 7) are browser-behavior changes with no
practical unit-test surface in this stack. Both are verified manually in the
running app before the PR is opened, and that verification is stated explicitly
rather than implied.

## Out of scope

- Bot decomposition. `SoulLink::DiscordBot` is already a 1115-line god object;
  this work adds handlers following existing patterns rather than restructuring
  it. Refactoring it is a separate effort.
- Adopting `searchable_select` for the species field. The controller is built to
  allow it; the swap is not made here.
- Backfilling `discord_catch_message_id` for groups created before this change.
  They simply never got a post; there is nothing to reconcile.
