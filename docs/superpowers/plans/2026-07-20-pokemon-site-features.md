# Pokemon Site Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship seven features — catch embeds with Discord quick-add, a single death message, click-outside modal close, an any-ability searchable select, party drag-and-drop, and on-demand ROM download — as one PR of independently revertable commits.

**Architecture:** Three independent subsystems. Discord work centers on a new `SoulLink::CatchMessage` service that owns a live-updating embed keyed by a new `discord_catch_message_id` column. Frontend work is three unrelated Stimulus changes. The ROM pipeline extracts a session-free path out of the existing `RomRandomizer` and drives it through a new job + polling controller.

**Tech Stack:** Ruby 3.4.5, Rails 8.1, MySQL 8, Minitest + FactoryBot, discordrb, Stimulus + Importmap, SortableJS, Tailwind.

**Spec:** `docs/superpowers/specs/2026-07-20-pokemon-site-features-design.md`

**Baseline (verified before work started):** `bin/rails test` → **848 runs, 0 failures, 0 errors**. Any deviation from this at the end of a task is a regression introduced by that task.

---

## Review Corrections Folded In

This plan was reviewed before execution. These findings are already incorporated
below — they are recorded here so an engineer who spots the "obvious" simpler
form knows why it was rejected.

| Finding | Resolution |
|---------|-----------|
| **`Discordrb::API::Channel` takes POSITIONAL args, not keywords.** Passing `embeds:`/`components:` collapses them into the `tts` parameter; Discord 400s, the blanket rescue swallows it, and the feature is a silent no-op — while `**kwargs` test stubs pass green. | Task 3 uses positional args. Test stubs are positional so they cannot mask a regression. |
| `GameState.pokedex_species` does not exist. | Task 2 uses `SoulLink::GameState.pokedex.keys` (the idiom already inlined in three controllers). |
| `login_as(id, guild_id:)` — `guild_id` is a **keyword**. | All tests call `login_as(GREY)` with one arg. |
| Tasks 4, 10, 12 tests never logged in → asserted against a 302. | `login_as` added to each. |
| Deleting `notify_death` breaks `test/integration/wipe_flow_test.rb` (stubs at :39 and :86). | Task 6 rewrites that file explicitly and runs the full suite. |
| `@all_abilities` would be nil on `/map` (the modal renders from two controllers) → `optionsValue.filter is not a function`. | Task 9 inlines `GameState.all_abilities.to_json` in the partial; no ivar. |
| `#populateAbilities` has **two** callers (`:343` and `:373`), not one; and `abilitiesData` is still the species-existence guard at `:371`. | Task 9 replaces the method body rather than deleting it, and keeps `abilitiesData`. |
| Mounting `team-builder` on the party panel throws `Missing target element "teamList"` in `connect()`, killing all dashboard JS. | Task 11 uses a dedicated `party-drag` controller. |
| The dragged clone is a `.box-cell`, not a `.team-slot` — the original `querySelectorAll(".team-slot")` swap logic was a silent no-op. | Task 11 reads `event.item.dataset.groupId` and removes the clone. |
| Party slots need all **seven** `data-group-*` attributes for `selectPokemon`, not just the id — with only the id, SAVE could write a blank nickname to a real group. | Task 11 mirrors the full attribute set. |
| `RomRandomizer.allocate` + `instance_variable_set` was gratuitous (`initialize` only assigns `@session`). | Task 12 uses `new(nil)` with a public instance method. |
| Three verification commands were vacuous (a grep that can never match, a line-count of a just-written file, a single-file test run after a cross-cutting deletion). | Replaced with real assertions. |
| `skip "requires configured players"` guards were dead code — `settings.yml` defines all four players in every env, with no test override. | All removed. They would have silently zeroed coverage if `settings.yml` ever changed. |
| `GameState.location_name` never returns blank (falls back to `titleize`), so `.presence \|\| group.location` was unreachable. | Dropped. |

---

## File Structure

**Created:**

| File | Responsibility |
|------|----------------|
| `db/migrate/*_add_discord_catch_message_id_to_soul_link_pokemon_groups.rb` | Idempotency/addressing column |
| `db/migrate/*_create_soul_link_rom_downloads.rb` | ROM download table |
| `app/services/soul_link/catch_message.rb` | Builds + posts/edits the catch embed |
| `app/services/soul_link/species_resolver.rb` | Three-tier species name resolution |
| `app/models/soul_link_rom_download.rb` | ROM download record |
| `app/jobs/soul_link/generate_rom_download_job.rb` | Async ROM generation |
| `app/controllers/runs/rom_downloads_controller.rb` | Create/poll/download |
| `app/javascript/controllers/searchable_select_controller.js` | Generic filtered combobox |
| `app/javascript/controllers/party_drag_controller.js` | PC box → party drag |
| `app/javascript/controllers/rom_download_controller.js` | Click → poll → download |
| `test/factories/soul_link_rom_downloads.rb` | Factory |

**Modified:** `discord_notifier.rb`, `discord_bot.rb`, `game_state.rb`, `rom_randomizer.rb`, `pokemon_groups_controller.rb`, `pokemon_controller.rb`, `teams_controller.rb`, `soul_link_run.rb`, six modal partials, `pixeldex_controller.js`, `dashboard_controller.js`, `confirm_modal_controller.js`, `quick_calc_controller.js`, `_party_panel.html.erb`, `_pc_box_content.html.erb`, `_runs_content.html.erb`, `routes.rb`, `emulator_cleanup.rake`, `pixeldex.css`, `wipe_flow_test.rb`.

---

## Task 1: Migration — catch message id

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_discord_catch_message_id_to_soul_link_pokemon_groups.rb`

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration AddDiscordCatchMessageIdToSoulLinkPokemonGroups discord_catch_message_id:bigint
```

- [ ] **Step 2: Verify the generated body**

Must be exactly:

```ruby
class AddDiscordCatchMessageIdToSoulLinkPokemonGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :soul_link_pokemon_groups, :discord_catch_message_id, :bigint
  end
end
```

No index — lookups are always by group id, never by message id.

- [ ] **Step 3: Migrate**

Run: `bin/rails db:migrate`
Expected: `== AddDiscordCatchMessageIdToSoulLinkPokemonGroups: migrated`

- [ ] **Step 4: Confirm schema**

Run: `grep discord_catch_message_id db/schema.rb`
Expected: `t.bigint "discord_catch_message_id"`

- [ ] **Step 5: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "feat(catches): add discord_catch_message_id to pokemon groups"
```

---

## Task 2: Species resolver

**Files:**
- Create: `app/services/soul_link/species_resolver.rb`
- Test: `test/services/soul_link/species_resolver_test.rb`

Verified against `config/soul_link/pokedex.yml`: exactly five species start with
"star" (Staryu, Starmie, Starly, Staravia, Staraptor), so `MAX_CANDIDATES = 5`
returns both Staravia and Starly; "staravi" is a unique prefix.

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

module SoulLink
  class SpeciesResolverTest < ActiveSupport::TestCase
    test "exact match is case-insensitive" do
      result = SoulLink::SpeciesResolver.call("staravia")
      assert result.resolved?
      assert_equal "Staravia", result.species
    end

    test "unique prefix resolves" do
      result = SoulLink::SpeciesResolver.call("staravi")
      assert result.resolved?
      assert_equal "Staravia", result.species
    end

    test "ambiguous prefix is rejected with candidates" do
      result = SoulLink::SpeciesResolver.call("star")
      refute result.resolved?
      assert_includes result.candidates, "Staravia"
      assert_includes result.candidates, "Starly"
      assert_operator result.candidates.length, :<=, 5
    end

    test "unknown input is rejected with no candidates" do
      result = SoulLink::SpeciesResolver.call("zzzzznotapokemon")
      refute result.resolved?
      assert_empty result.candidates
    end

    test "blank input is rejected" do
      refute SoulLink::SpeciesResolver.call("").resolved?
      refute SoulLink::SpeciesResolver.call(nil).resolved?
    end

    test "an exact name that is also a prefix of nothing still resolves" do
      result = SoulLink::SpeciesResolver.call("Starly")
      assert result.resolved?
      assert_equal "Starly", result.species
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/soul_link/species_resolver_test.rb`
Expected: FAIL — `NameError: uninitialized constant SoulLink::SpeciesResolver`

- [ ] **Step 3: Write the implementation**

```ruby
module SoulLink
  # Resolves free-text species input (from a Discord modal) to a canonical
  # species name from `pokedex.yml`.
  #
  # Three tiers, in order:
  #   1. Exact match (case-insensitive)
  #   2. Unique prefix match
  #   3. Reject — ambiguous (with candidates) or unknown (without)
  #
  # Never guesses. An ambiguous input returns candidates so the caller can
  # tell the player what they might have meant.
  class SpeciesResolver
    MAX_CANDIDATES = 5

    Result = Struct.new(:species, :candidates, keyword_init: true) do
      def resolved? = species.present?
    end

    def self.call(input) = new(input).call

    def initialize(input)
      @input = input.to_s.strip
    end

    def call
      return reject([]) if @input.blank?

      exact = all_species.find { |s| s.casecmp?(@input) }
      return Result.new(species: exact, candidates: []) if exact

      prefixed = all_species.select { |s| s.downcase.start_with?(@input.downcase) }
      return Result.new(species: prefixed.first, candidates: []) if prefixed.one?

      reject(prefixed.first(MAX_CANDIDATES))
    end

    private

    def reject(candidates) = Result.new(species: nil, candidates: candidates)

    # `GameState.pokedex` is a `species name => sprite id` Hash — its keys are
    # the canonical species list. Same idiom as dashboard_controller.rb:104.
    def all_species = SoulLink::GameState.pokedex.keys
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/soul_link/species_resolver_test.rb`
Expected: 6 runs, 0 failures, 0 errors

- [ ] **Step 5: Commit**

```bash
git add app/services/soul_link/species_resolver.rb test/services/soul_link/species_resolver_test.rb
git commit -m "feat(catches): add three-tier species name resolver"
```

---

## Task 3: CatchMessage service

**Files:**
- Create: `app/services/soul_link/catch_message.rb`
- Test: `test/services/soul_link/catch_message_test.rb`

**The single most important detail in this task:** `Discordrb::API::Channel`
methods take **positional** arguments. Real signatures:

```ruby
create_message(token, channel_id, message, tts = false, embeds = nil, nonce = nil,
               attachments = nil, allowed_mentions = nil, message_reference = nil,
               components = nil, flags = nil, enforce_nonce = false)

edit_message(token, channel_id, message_id, message, mentions = nil,
             embeds = nil, components = nil, flags = nil)
```

Passing `embeds:`/`components:` as keywords would collapse them into a Hash bound
to `tts`, Discord would 400, and the rescue would swallow it. The tests below use
positional stubs specifically so this class of bug cannot pass green.

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

module SoulLink
  class CatchMessageTest < ActiveSupport::TestCase
    setup do
      @run = create(:soul_link_run, catches_channel_id: 1111)
      @group = create(:soul_link_pokemon_group, soul_link_run: @run,
                      nickname: "TOMMY", location: "route_205")
      @posts = []
      @edits = []
    end

    # Positional stubs, matching the real discordrb signatures. If the service
    # ever regresses to keyword args these bind wrong and the tests fail —
    # which is the entire point of spelling them out.
    def with_stubbed_discord(&block)
      post_stub = lambda do |_token, channel_id, _message, _tts = false, embeds = nil,
                             _nonce = nil, _attachments = nil, _allowed = nil,
                             _reference = nil, components = nil, *_rest|
        @posts << { channel_id: channel_id, embeds: embeds, components: components }
        { "id" => "9001" }.to_json
      end

      edit_stub = lambda do |_token, channel_id, message_id, _message,
                             _mentions = nil, embeds = nil, components = nil, *_rest|
        @edits << { channel_id: channel_id, message_id: message_id,
                    embeds: embeds, components: components }
        { "id" => message_id.to_s }.to_json
      end

      Discordrb::API::Channel.stub(:create_message, post_stub) do
        Discordrb::API::Channel.stub(:edit_message, edit_stub) do
          SoulLink::CatchMessage.stub(:resolve_token, "Bot test", &block)
        end
      end
    end

    test "posts once and persists the message id" do
      with_stubbed_discord { SoulLink::CatchMessage.post_or_update(@group) }

      assert_equal 1, @posts.length
      assert_equal 1111, @posts.first[:channel_id]
      assert_equal 9001, @group.reload.discord_catch_message_id
    end

    test "the embed lands in the embeds parameter, not swallowed by tts" do
      with_stubbed_discord { SoulLink::CatchMessage.post_or_update(@group) }

      embeds = @posts.first[:embeds]
      assert_kind_of Array, embeds, "embeds must be positional arg 5, not a keyword"
      assert_includes embeds.first[:title], "NEW CATCH"
    end

    test "second call edits rather than posting again" do
      with_stubbed_discord do
        SoulLink::CatchMessage.post_or_update(@group)
        SoulLink::CatchMessage.post_or_update(@group)
      end

      assert_equal 1, @posts.length, "must not post a second message"
      assert_equal 1, @edits.length
      assert_equal 9001, @edits.first[:message_id]
      assert_kind_of Array, @edits.first[:embeds]
    end

    test "is a no-op when the run has no catches channel" do
      @run.update!(catches_channel_id: nil)
      with_stubbed_discord { SoulLink::CatchMessage.post_or_update(@group) }

      assert_empty @posts
      assert_empty @edits
      assert_nil @group.reload.discord_catch_message_id
    end

    test "is a no-op when group is nil" do
      with_stubbed_discord { SoulLink::CatchMessage.post_or_update(nil) }
      assert_empty @posts
    end

    test "re-posts exactly once when the stored message is gone" do
      @group.update!(discord_catch_message_id: 4242)

      edit_404 = ->(*_args) { raise RestClient::NotFound }
      post_stub = lambda do |_token, channel_id, _message, _tts = false, embeds = nil, *_rest|
        @posts << { channel_id: channel_id, embeds: embeds }
        { "id" => "5005" }.to_json
      end

      Discordrb::API::Channel.stub(:create_message, post_stub) do
        Discordrb::API::Channel.stub(:edit_message, edit_404) do
          SoulLink::CatchMessage.stub(:resolve_token, "Bot test") do
            SoulLink::CatchMessage.post_or_update(@group)
          end
        end
      end

      assert_equal 1, @posts.length
      assert_equal 5005, @group.reload.discord_catch_message_id
    end

    test "never raises when Discord is unreachable" do
      boom = ->(*_args) { raise SocketError, "no network" }

      Discordrb::API::Channel.stub(:create_message, boom) do
        SoulLink::CatchMessage.stub(:resolve_token, "Bot test") do
          assert_nothing_raised { SoulLink::CatchMessage.post_or_update(@group) }
        end
      end
      assert_nil @group.reload.discord_catch_message_id
    end

    test "embed lists every registered player, filled or not" do
      players = SoulLink::GameState.players
      uid = players.first["discord_user_id"]
      create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: @group,
             discord_user_id: uid, species: "Staravia", level: 12)

      with_stubbed_discord { SoulLink::CatchMessage.post_or_update(@group) }

      description = @posts.first[:embeds].first[:description]
      assert_includes description, "Staravia"
      players.each { |p| assert_includes description, p["display_name"] }
      assert_includes description, SoulLink::CatchMessage::NOT_CAUGHT
    end

    test "embed carries the add-species button addressed to the group" do
      with_stubbed_discord { SoulLink::CatchMessage.post_or_update(@group) }

      button = @posts.first[:components].first[:components].first
      assert_equal "soul_link:catch_add:#{@group.id}", button[:custom_id]
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/soul_link/catch_message_test.rb`
Expected: FAIL — `NameError: uninitialized constant SoulLink::CatchMessage`

- [ ] **Step 3: Write the implementation**

```ruby
require "discordrb"

module SoulLink
  # Owns the live-updating "new catch" message in the run's catches channel.
  #
  # One Discord message per catch group. The group's
  # `discord_catch_message_id` is both the idempotency key (non-nil means
  # already posted) and the address for subsequent edits — so calling
  # `post_or_update` any number of times produces exactly one message.
  #
  # Embed shape mirrors `GymPollMessage`: a plain hash built here, handed to
  # the REST layer positionally below.
  #
  # Fire-and-forget, matching the `DiscordNotifier` contract: every failure
  # mode is swallowed and logged at warn level. Callers need no rescue.
  class CatchMessage
    EMBED_COLOR = 0x57F287  # green — matches the "caught" status colour
    NOT_CAUGHT  = "— not caught yet —".freeze

    class << self
      def post_or_update(group)
        return if group.nil?

        run = group.soul_link_run
        return if run.nil? || run.catches_channel_id.blank?

        token = resolve_token
        return if token.blank?

        if group.discord_catch_message_id.present?
          edit(token, run, group)
        else
          post(token, run, group)
        end
      rescue StandardError => e
        log_failure(e, group)
        nil
      end

      # ── embed construction (public for testability) ──────────────────

      def embed(group)
        {
          title: "🎯 NEW CATCH — #{location_label(group)}",
          description: player_lines(group).join("\n"),
          color: EMBED_COLOR
        }
      end

      def components(group)
        [ {
          type: 1,
          components: [ {
            type: 2,
            style: 1,
            label: "ADD MY POKEMON",
            custom_id: "soul_link:catch_add:#{group.id}"
          } ]
        } ]
      end

      private

      # POSITIONAL args — discordrb's API methods accept no keywords. Passing
      # `embeds:`/`components:` would collapse into a Hash bound to `tts` and
      # Discord would reject the payload. Signature:
      #   create_message(token, channel_id, message, tts, embeds, nonce,
      #                  attachments, allowed_mentions, message_reference,
      #                  components, flags, enforce_nonce)
      def post(token, run, group)
        response = Discordrb::API::Channel.create_message(
          token,
          run.catches_channel_id,
          "",                    # message
          false,                 # tts
          [ embed(group) ],      # embeds
          nil,                   # nonce
          nil,                   # attachments
          nil,                   # allowed_mentions
          nil,                   # message_reference
          components(group)      # components
        )
        message_id = parse_message_id(response)
        return if message_id.nil?

        group.update_columns(discord_catch_message_id: message_id)
      end

      #   edit_message(token, channel_id, message_id, message, mentions,
      #                embeds, components, flags)
      def edit(token, run, group)
        Discordrb::API::Channel.edit_message(
          token,
          run.catches_channel_id,
          group.discord_catch_message_id,
          "",                    # message
          nil,                   # mentions
          [ embed(group) ],      # embeds
          components(group)      # components
        )
      rescue RestClient::NotFound
        # The message was deleted in Discord. Clear the stale id and post
        # once more. A failure on that re-post falls through to the outer
        # rescue in `post_or_update` — we never loop.
        group.update_columns(discord_catch_message_id: nil)
        post(token, run, group)
      end

      # One line per registered player: filled slots show species + level,
      # empty slots show the NOT_CAUGHT placeholder. Players come from
      # GameState so the roster stays the single source of truth.
      def player_lines(group)
        by_uid = group.soul_link_pokemon.index_by(&:discord_user_id)

        SoulLink::GameState.players.map do |player|
          uid = player["discord_user_id"]
          pokemon = by_uid[uid]
          name = player["display_name"] || uid.to_s
          "**#{name}** — #{pokemon ? describe(pokemon) : NOT_CAUGHT}"
        end
      end

      def describe(pokemon)
        level = pokemon.level.present? ? " Lv #{pokemon.level}" : ""
        "#{pokemon.species}#{level}"
      end

      # "Route 205 • \"TOMMY\"". `location_name` already falls back to
      # `titleize` for unknown keys, so no nil guard is needed here.
      def location_label(group)
        "#{SoulLink::GameState.location_name(group.location)} • \"#{group.nickname}\""
      end

      # discordrb returns a RestClient::Response, which subclasses String.
      def parse_message_id(response)
        body = response.is_a?(String) ? JSON.parse(response) : response
        id = body.is_a?(Hash) ? (body["id"] || body[:id]) : nil
        id.presence && id.to_i
      rescue JSON::ParserError
        nil
      end

      def log_failure(error, group)
        Rails.logger.warn(
          "CatchMessage failed: #{error.class} #{error.message} (group=#{group&.id})"
        )
      end

      # Mirrors DiscordNotifier#resolve_token.
      def resolve_token
        creds = Rails.application.credentials.discord
        return nil if creds.nil?
        token = creds.is_a?(Hash) ? creds[:token] : creds.try(:[], :token)
        return nil if token.blank?
        "Bot #{token}"
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/soul_link/catch_message_test.rb`
Expected: 9 runs, 0 failures, 0 errors

- [ ] **Step 5: Commit**

```bash
git add app/services/soul_link/catch_message.rb test/services/soul_link/catch_message_test.rb
git commit -m "feat(catches): add live-updating catch embed service"
```

---

## Task 4: Wire CatchMessage into the site catch flow

**Files:**
- Modify: `app/controllers/pokemon_groups_controller.rb`
- Modify: `app/controllers/pokemon_controller.rb`
- Test: `test/controllers/pokemon_groups_controller_test.rb`

- [ ] **Step 1: Write the failing test**

Append to `test/controllers/pokemon_groups_controller_test.rb`. `GREY` is already
defined at line 4 of that file and `setup` already provides `@run`.

```ruby
  test "creating a group posts the catch embed once" do
    login_as(GREY)
    calls = []

    SoulLink::CatchMessage.stub(:post_or_update, ->(group) { calls << group.id }) do
      post pokemon_groups_path, params: {
        nickname: "TOMMY", location: "route_205"
      }, as: :json
    end

    assert_response :success
    assert_equal 1, calls.length
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/pokemon_groups_controller_test.rb`
Expected: FAIL — `Expected: 1, Actual: 0`

- [ ] **Step 3: Add the call in `PokemonGroupsController#create`**

Immediately before the `if errors.any?` block (after the player loop):

```ruby
    # Live catch embed. Last statement before render so a Discord failure
    # can never roll back the group/pokemon writes. The service is
    # fire-and-forget and swallows its own errors.
    SoulLink::CatchMessage.post_or_update(group)
```

- [ ] **Step 4: Add the refresh calls in `PokemonController`**

In `create`, replace `render json: { status: "created", pokemon_id: pokemon.id }` with:

```ruby
    SoulLink::CatchMessage.post_or_update(group)
    render json: { status: "created", pokemon_id: pokemon.id }
```

In `update`, replace the two-line update+render with:

```ruby
    pokemon.update!(pokemon_params)
    SoulLink::CatchMessage.post_or_update(pokemon.soul_link_pokemon_group)
    render json: { status: "updated", pokemon_id: pokemon.id }
```

`post_or_update` returns early on a nil group, so an unpaired Pokemon (group id
nil, as created by `CatchCoordinator`) is safely a no-op. Both insertion points
are outside any transaction.

- [ ] **Step 5: Run the full suite**

Run: `bin/rails test`
Expected: 849+ runs, 0 failures, 0 errors

- [ ] **Step 6: Commit**

```bash
git add app/controllers/pokemon_groups_controller.rb app/controllers/pokemon_controller.rb test/controllers/pokemon_groups_controller_test.rb
git commit -m "feat(catches): post catch embed from the site catch flow"
```

---

## Task 5: Discord quick-add interaction

**Files:**
- Modify: `app/services/soul_link/discord_bot.rb`
- Test: `test/services/soul_link/catch_quick_add_test.rb`

The bot's event loop is not bootable in tests, so the handler body is extracted
into a testable public class method and the `bot.button` / `bot.modal_submit`
blocks are thin delegations.

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

module SoulLink
  class CatchQuickAddTest < ActiveSupport::TestCase
    setup do
      @run = create(:soul_link_run, catches_channel_id: 1111)
      @group = create(:soul_link_pokemon_group, soul_link_run: @run)
      @uid = SoulLink::GameState.players.first["discord_user_id"]
    end

    # `post_or_update` is a real call in most of these tests. It is safe —
    # the test env has no discord credentials, so `resolve_token` returns nil
    # and the service early-returns before any HTTP. Stubbed explicitly in the
    # one test that asserts on it.
    test "creates the pokemon for the clicking user" do
      result = SoulLink::DiscordBot.apply_catch_quick_add(
        group_id: @group.id, discord_user_id: @uid, species_input: "staravia"
      )

      assert result[:ok], result[:error]
      assert_equal "Staravia", @group.soul_link_pokemon.find_by(discord_user_id: @uid).species
    end

    test "rejects an ambiguous species without writing" do
      result = SoulLink::DiscordBot.apply_catch_quick_add(
        group_id: @group.id, discord_user_id: @uid, species_input: "star"
      )

      refute result[:ok]
      assert_match(/did you mean/i, result[:error])
      assert_equal 0, @group.soul_link_pokemon.count
    end

    test "rejects an unknown species without writing" do
      result = SoulLink::DiscordBot.apply_catch_quick_add(
        group_id: @group.id, discord_user_id: @uid, species_input: "zzzz"
      )

      refute result[:ok]
      assert_equal 0, @group.soul_link_pokemon.count
    end

    test "rejects a player who already has a pokemon in the group" do
      create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: @group,
             discord_user_id: @uid, species: "Shinx")

      result = SoulLink::DiscordBot.apply_catch_quick_add(
        group_id: @group.id, discord_user_id: @uid, species_input: "Staravia"
      )

      refute result[:ok]
      assert_equal "Shinx", @group.soul_link_pokemon.find_by(discord_user_id: @uid).species
    end

    test "rejects an unregistered user" do
      result = SoulLink::DiscordBot.apply_catch_quick_add(
        group_id: @group.id, discord_user_id: 999_999_999, species_input: "Staravia"
      )

      refute result[:ok]
      assert_equal 0, @group.soul_link_pokemon.count
    end

    test "rejects a missing group" do
      result = SoulLink::DiscordBot.apply_catch_quick_add(
        group_id: 0, discord_user_id: @uid, species_input: "Staravia"
      )
      refute result[:ok]
    end

    test "refreshes the embed on success" do
      refreshed = []
      SoulLink::CatchMessage.stub(:post_or_update, ->(g) { refreshed << g.id }) do
        SoulLink::DiscordBot.apply_catch_quick_add(
          group_id: @group.id, discord_user_id: @uid, species_input: "Staravia"
        )
      end
      assert_equal [ @group.id ], refreshed
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/soul_link/catch_quick_add_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'apply_catch_quick_add'`

- [ ] **Step 3: Add the class methods to `SoulLink::DiscordBot`**

`private` at `discord_bot.rb:25` affects instance methods only, so `def self.`
methods are public wherever they sit in the class body. Place them near the top:

```ruby
    # Pure, testable core of the catch quick-add interaction. Kept separate
    # from the `bot.modal_submit` block so it can be tested without booting
    # the bot's event loop.
    #
    # Returns { ok: true } or { ok: false, error: "<player-facing message>" }.
    def self.apply_catch_quick_add(group_id:, discord_user_id:, species_input:)
      group = SoulLinkPokemonGroup.find_by(id: group_id)
      return { ok: false, error: "That catch no longer exists." } if group.nil?

      unless SoulLink::GameState.player_ids.include?(discord_user_id)
        return { ok: false, error: "You're not a registered player in this run." }
      end

      if group.soul_link_pokemon.exists?(discord_user_id: discord_user_id)
        return { ok: false, error: "You already have a Pokemon in this catch." }
      end

      resolution = SoulLink::SpeciesResolver.call(species_input)
      unless resolution.resolved?
        return { ok: false, error: species_error(species_input, resolution) }
      end

      group.soul_link_run.soul_link_pokemon.create!(
        soul_link_pokemon_group: group,
        discord_user_id: discord_user_id,
        species: resolution.species,
        name: group.nickname,
        location: group.location,
        status: group.status
      )

      SoulLink::CatchMessage.post_or_update(group)
      { ok: true }
    rescue ActiveRecord::RecordNotUnique
      { ok: false, error: "You already have a Pokemon in this catch." }
    rescue ActiveRecord::RecordInvalid => e
      { ok: false, error: e.record.errors.full_messages.join(", ") }
    end

    def self.species_error(input, resolution)
      if resolution.candidates.any?
        "Did you mean: #{resolution.candidates.join(', ')}?"
      else
        "No species matches \"#{input}\"."
      end
    end
```

- [ ] **Step 4: Register the interactions**

In `register_interactions`, after the existing `soul_link:species_modal` block:

```ruby
      # Button: quick-add your species straight from a catch post
      bot.button(custom_id: /^soul_link:catch_add:/) do |event|
        group_id = event.interaction.data['custom_id'].split(':').last
        open_catch_quick_add_modal(event, group_id)
      end

      # Modal: quick-add species submission
      bot.modal_submit(custom_id: /^soul_link:catch_quick_add_modal:/) do |event|
        handle_catch_quick_add(event)
      end
```

- [ ] **Step 5: Add the two instance handlers**

Place next to `open_species_modal` (~line 774). Note this matches the house
idiom: `extract_modal_values(event)` (used at `discord_bot.rb:930` and `:1023`)
and `respond_ephemeral(event, msg)` (`:1093`) rather than raw `event.value` /
`event.respond`.

```ruby
    def open_catch_quick_add_modal(event, group_id)
      components = [
        {
          type: 1,
          components: [
            {
              type: 4,
              custom_id: 'species',
              label: 'Your Species',
              style: 1,
              required: true,
              min_length: 1,
              max_length: 50,
              placeholder: 'e.g., Staravia'
            }
          ]
        }
      ]

      event.show_modal(
        title: 'Add Your Pokemon',
        custom_id: "soul_link:catch_quick_add_modal:#{group_id}",
        components: components
      )
    end

    def handle_catch_quick_add(event)
      group_id = event.interaction.data['custom_id'].split(':').last
      species  = extract_modal_values(event)['species']

      result = self.class.apply_catch_quick_add(
        group_id: group_id,
        discord_user_id: event.user.id,
        species_input: species
      )

      if result[:ok]
        respond_ephemeral(event, "✅ Added your #{species}.")
      else
        respond_ephemeral(event, "⚠️ #{result[:error]}")
      end
    end
```

Before writing, confirm both helper signatures:
Run: `grep -n "def extract_modal_values\|def respond_ephemeral" app/services/soul_link/discord_bot.rb`
Expected: both present. If either differs, match the real signature.

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test`
Expected: 856+ runs, 0 failures, 0 errors

- [ ] **Step 7: Commit**

```bash
git add app/services/soul_link/discord_bot.rb test/services/soul_link/catch_quick_add_test.rb
git commit -m "feat(catches): add Discord quick-add species button to catch posts"
```

---

## Task 6: Single death message

**Files:**
- Modify: `app/services/soul_link/discord_notifier.rb` (replace `notify_death`)
- Modify: `app/controllers/pokemon_groups_controller.rb` (replace the loop)
- Modify: `test/services/soul_link/discord_notifier_test.rb`
- Modify: `test/integration/wipe_flow_test.rb` — **stubs `notify_death` at lines 39 and 86.** Minitest's `stub` calls `undef_method`; stubbing a deleted method raises `NameError`. This file MUST be updated in the same commit.

- [ ] **Step 1: Write the failing tests**

Add to `test/services/soul_link/discord_notifier_test.rb`:

```ruby
    test "notify_group_death sends exactly one message for a four-pokemon group" do
      group = create(:soul_link_pokemon_group, soul_link_run: @run,
                     nickname: "TOMMY", location: "route_205")
      SoulLink::GameState.players.first(4).each_with_index do |player, i|
        create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: group,
               discord_user_id: player["discord_user_id"],
               species: %w[Staravia Shinx Bidoof Kricketot][i])
      end

      with_stubbed_notifier { SoulLink::DiscordNotifier.notify_group_death(@run, group) }

      assert_equal 1, @captured.length
      assert_equal 2222, @captured.first[:channel_id]
    end

    test "notify_group_death names every fallen pokemon" do
      group = create(:soul_link_pokemon_group, soul_link_run: @run, nickname: "TOMMY")
      uid = SoulLink::GameState.players.first["discord_user_id"]
      create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: group,
             discord_user_id: uid, species: "Staravia")

      with_stubbed_notifier { SoulLink::DiscordNotifier.notify_group_death(@run, group) }

      assert_includes @captured.first[:content], "Staravia"
      assert_includes @captured.first[:content], "TOMMY"
    end

    test "notify_group_death is a no-op with a nil run or nil group" do
      group = create(:soul_link_pokemon_group, soul_link_run: @run)
      with_stubbed_notifier do
        SoulLink::DiscordNotifier.notify_group_death(nil, group)
        SoulLink::DiscordNotifier.notify_group_death(@run, nil)
      end
      assert_empty @captured
    end
```

In the existing `"every notifier method is a silent no-op when run is nil"` test,
replace the `notify_death(nil, GREY, "Starly", "Route 201")` line with:

```ruby
        SoulLink::DiscordNotifier.notify_group_death(nil, nil)
```

Delete any other test referencing `notify_death`.

- [ ] **Step 2: Update `test/integration/wipe_flow_test.rb`**

At **line 39**, change the stub target and recorder arity:

```ruby
      death_recorder = ->(_run, _group) { death_calls << :hit }
      SoulLink::DiscordNotifier.stub(:notify_group_death, death_recorder) do
```

At **line 53**, update the assertion message (the count still holds — one group,
one message — but the semantics changed from per-Pokemon to per-group):

```ruby
      assert_equal 1, death_calls.size, "one death notification per group"
```

At **line 86**, change:

```ruby
      SoulLink::DiscordNotifier.stub(:notify_group_death, ->(*) { }) do
```

Read the surrounding context before editing — match the real variable names in
that file rather than assuming they are `death_recorder` / `death_calls`.

- [ ] **Step 3: Run tests to verify they fail**

Run: `bin/rails test test/services/soul_link/discord_notifier_test.rb test/integration/wipe_flow_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'notify_group_death'`

- [ ] **Step 4: Replace `notify_death` in the notifier**

Delete the entire `notify_death` method (lines 38-50, including its comment) and
put in its place:

```ruby
      # Death-event surface (PokemonGroupsController#update — Mark Dead).
      # ONE message per group listing every fallen linked Pokemon — not one
      # message per Pokemon, which spammed the channel four times per death.
      def notify_group_death(run, group)
        return if run.nil? || group.nil?

        channel_id = run.deaths_channel_id
        return if channel_id.blank?

        lines = group.soul_link_pokemon.map do |pokemon|
          "#{SoulLink::GameState.player_name(pokemon.discord_user_id)} — #{pokemon.species}"
        end

        route = SoulLink::GameState.location_name(group.location)
        content = "💀 RIP \"#{group.nickname}\" — #{route}\n#{lines.join("\n")}"

        send_message(channel_id, content, run: run, method_name: __method__)
      end
```

- [ ] **Step 5: Replace the loop in the controller**

In `app/controllers/pokemon_groups_controller.rb`, replace:

```ruby
      group.soul_link_pokemon.reload.each do |p|
        SoulLink::DiscordNotifier.notify_death(run, p.discord_user_id, p.species, p.location)
      end
```

with:

```ruby
      # One message for the whole group. `reload` so the cascaded dead
      # status is visible; the notifier rescues every failure internally.
      group.soul_link_pokemon.reload
      SoulLink::DiscordNotifier.notify_group_death(run, group)
```

- [ ] **Step 6: Verify no `notify_death` callers remain**

Run: `grep -rn "notify_death" app test`
Expected: no output.

- [ ] **Step 7: Run the FULL suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors. A single-file run is NOT sufficient here — this
task deletes public surface area with off-task consumers.

- [ ] **Step 8: Commit**

```bash
git add app/services/soul_link/discord_notifier.rb app/controllers/pokemon_groups_controller.rb test/services/soul_link/discord_notifier_test.rb test/integration/wipe_flow_test.rb
git commit -m "fix(deaths): send one grouped death message instead of one per player"
```

---

## Task 7: Modal click-outside close

Diagnosis verified: all six partials have a `position: absolute; inset: 0`
backdrop followed by a **sibling** `position: relative; min-height: 100vh`
wrapper inside a `position: fixed` parent. Both have `z-index: auto`, so they
paint in tree order — the wrapper paints last, covers the viewport, and
hit-testing never reaches the backdrop.

| Partial | backdrop line | wrapper line |
|---|---|---|
| `dashboard/_pokemon_modal.html.erb` | 5–6 | 8 |
| `dashboard/_catch_modal.html.erb` | 5–6 | 8 |
| `dashboard/_mark_dead_modal.html.erb` | 16–17 | 19 |
| `dashboard/_reset_draft_modal.html.erb` | 16–17 | 19 |
| `shared/_confirm_modal.html.erb` | 15–16 | 18 |
| `teams/_quick_calc_modal.html.erb` | 7–8 | 10 |

No automated test — browser z-order behavior with no unit-test surface in this
stack. Verified manually in Task 13.

- [ ] **Step 1: Add the backdrop guard methods**

In `dashboard_controller.js`, next to the existing close methods:

```js
  // The dimming backdrop sits *behind* the centering wrapper (both z-index
  // auto, wrapper paints later), so clicks in the empty area never reach it.
  // The wrapper carries the close action instead; this guard ignores clicks
  // that bubbled up from the modal card.
  closeCatchModalOnBackdrop(event) {
    if (event.target !== event.currentTarget) return
    this.closeCatchModal()
  }

  closeMarkDeadModalOnBackdrop(event) {
    if (event.target !== event.currentTarget) return
    this.closeMarkDeadModal()
  }

  closeResetDraftModalOnBackdrop(event) {
    if (event.target !== event.currentTarget) return
    this.closeResetDraftModal()
  }
```

In `pixeldex_controller.js`, next to `closePokemonModal` (line 364):

```js
  closePokemonModalOnBackdrop(event) {
    if (event.target !== event.currentTarget) return
    this.closePokemonModal()
  }
```

In `confirm_modal_controller.js` (its `close()` is at line 61):

```js
  closeOnBackdrop(event) {
    if (event.target !== event.currentTarget) return
    this.close()
  }
```

In `quick_calc_controller.js` (its `close()` is at line 52):

```js
  closeOnBackdrop(event) {
    if (event.target !== event.currentTarget) return
    this.close()
  }
```

- [ ] **Step 2: Move the action onto the centering wrapper in each partial**

For each partial: **remove** the `data-action` from the backdrop div (it is
unreachable; keeping a dead handler is misleading) and **add** the matching
action to the `position: relative` wrapper. Preserve each wrapper's existing
inline `style` attribute exactly.

`_pokemon_modal.html.erb` — line 5 becomes:

```erb
  <div style="position: absolute; inset: 0; background: rgba(15, 56, 15, 0.75);"></div>
```

line 8 becomes:

```erb
  <div data-action="click->pixeldex#closePokemonModalOnBackdrop"
       style="position: relative; display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: 16px;">
```

Apply the same two-part edit to the other five:

| Partial | Wrapper action |
|---------|----------------|
| `_catch_modal.html.erb` | `click->dashboard#closeCatchModalOnBackdrop` |
| `_mark_dead_modal.html.erb` | `click->dashboard#closeMarkDeadModalOnBackdrop` |
| `_reset_draft_modal.html.erb` | `click->dashboard#closeResetDraftModalOnBackdrop` |
| `shared/_confirm_modal.html.erb` | `click->confirm-modal#closeOnBackdrop` |
| `teams/_quick_calc_modal.html.erb` | `click->quick-calc#closeOnBackdrop` |

- [ ] **Step 3: Verify every modal was covered**

Run: `grep -rn "OnBackdrop" app/views | wc -l`
Expected: `6`

Run: `grep -c "gb-modal-close" app/views/dashboard/_pokemon_modal.html.erb`
Expected: `1` — the close **button** handler must survive untouched.

- [ ] **Step 4: Run the full suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors

- [ ] **Step 5: Commit**

```bash
git add app/views app/javascript/controllers
git commit -m "fix(modals): close on backdrop click across all six modals

The backdrop div was covered by its position:relative sibling wrapper, so
its click handler was unreachable. Move the action to the wrapper with a
target===currentTarget guard."
```

---

## Task 8: `GameState.all_abilities`

**Files:**
- Modify: `app/services/soul_link/game_state.rb`
- Test: `test/services/soul_link/game_state_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
    test "all_abilities returns the sorted unique union" do
      abilities = SoulLink::GameState.all_abilities

      assert_equal 123, abilities.length
      assert_equal abilities.uniq, abilities, "must be deduplicated"
      assert_equal abilities.sort, abilities, "must be sorted"
      assert_includes abilities, "Overgrow"
      assert_includes abilities, "Blaze"
    end

    test "all_abilities is a superset of any single species' abilities" do
      SoulLink::GameState.abilities_for("Bulbasaur").each do |ability|
        assert_includes SoulLink::GameState.all_abilities, ability
      end
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/soul_link/game_state_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'all_abilities'`

- [ ] **Step 3: Add the method**

Directly after `abilities_for` (line ~186):

```ruby
      # Every ability in the game, sorted and deduplicated (123 of them).
      # Any Pokemon may now have any ability, so the detail-page selector
      # offers the whole list rather than a species-restricted subset.
      def all_abilities
        @all_abilities ||= pokemon_abilities.values.flatten.uniq.sort
      end
```

- [ ] **Step 4: Add it to the cache reset**

Find the reset method containing `@pokemon_abilities = nil` (line ~218) and add:

```ruby
        @all_abilities = nil
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/services/soul_link/game_state_test.rb`
Expected: 0 failures, 0 errors

- [ ] **Step 6: Commit**

```bash
git add app/services/soul_link/game_state.rb test/services/soul_link/game_state_test.rb
git commit -m "feat(abilities): add GameState.all_abilities"
```

---

## Task 9: Searchable ability select

**Files:**
- Create: `app/javascript/controllers/searchable_select_controller.js`
- Modify: `app/assets/stylesheets/pixeldex.css`
- Modify: `app/views/dashboard/_pokemon_modal.html.erb` (lines 61-66)
- Modify: `app/javascript/controllers/pixeldex_controller.js` (`#populateAbilities`, lines 513-524)

**Two traps, both confirmed:**
1. `_pokemon_modal.html.erb` renders from **two** controllers —
   `dashboard/show.html.erb:92` and `map/show.html.erb:364`. An `@all_abilities`
   ivar would be nil on `/map`, giving `optionsValue = null` and a `TypeError`
   on first filter. So the partial reads `GameState` directly, matching how both
   `show.html.erb` files already inline `GameState.pokemon_abilities.to_json`.
2. `#populateAbilities` has **two** callers — `:343` (modal open) and `:373`
   (`searchSpecies`). It is *replaced*, not deleted, so both keep working.
   `abilitiesData` must **stay** — line 371 uses it as the species-existence
   guard for the entire species-selection path.

`app/javascript/controllers/index.js` uses `eagerLoadControllersFrom`, so the new
file auto-registers as `searchable-select`. No manual registration needed.

- [ ] **Step 1: Write the controller**

```js
import { Controller } from "@hotwired/stimulus"

// Generic filtered combobox. Written option-agnostic so the species field
// can adopt it later without a rewrite.
//
// The full option list ships inline — for abilities that is 123 strings,
// roughly 3KB, far cheaper than an endpoint round-trip per keystroke.
export default class extends Controller {
  static targets = ["input", "list", "hidden"]
  static values = {
    options: Array,
    visibleCount: { type: Number, default: 5 }
  }

  connect() {
    this._activeIndex = -1
    this._filtered = []
    this._open = false
    // Unique per instance — a second searchable-select on the page would
    // otherwise emit duplicate option ids and break aria-activedescendant.
    this._uid = `ss-${Math.random().toString(36).slice(2, 9)}`
    this.listTarget.id = `${this._uid}-list`
    this.inputTarget.setAttribute("aria-controls", this.listTarget.id)
    this.listTarget.style.setProperty("--visible-count", String(this.visibleCountValue))
    this.close()
  }

  // Set the value programmatically (used when a modal opens with a stored
  // ability). Updates both the visible input and the hidden field.
  setValue(value) {
    this.inputTarget.value = value || ""
    this.hiddenTarget.value = value || ""
  }

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase()
    this._filtered = query
      ? this.optionsValue.filter((o) => o.toLowerCase().includes(query))
      : [...this.optionsValue]
    this._activeIndex = this._filtered.length > 0 ? 0 : -1
    this.#render()
    this.open()
  }

  open() {
    this._open = true
    this.listTarget.classList.remove("hidden")
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this._open = false
    this.listTarget.classList.add("hidden")
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
  }

  // Delay so a click on an option lands before the list is hidden.
  closeSoon() {
    this._blurTimer = setTimeout(() => this.close(), 150)
  }

  cancelClose() {
    if (this._blurTimer) clearTimeout(this._blurTimer)
  }

  selectOption(event) {
    this.#commit(event.currentTarget.dataset.value)
  }

  keydown(event) {
    if (!this._open && ["ArrowDown", "ArrowUp"].includes(event.key)) {
      this.filter()
      return
    }
    if (!this._open) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.#move(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.#move(-1)
        break
      case "Enter":
        if (this._activeIndex >= 0) {
          event.preventDefault()
          this.#commit(this._filtered[this._activeIndex])
        }
        break
      case "Escape":
        // Swallow so the global escape-close controller does not also tear
        // down the surrounding modal — one Escape closes one thing.
        event.preventDefault()
        event.stopPropagation()
        this.close()
        break
    }
  }

  #commit(value) {
    if (value === undefined || value === null) return
    this.inputTarget.value = value
    this.hiddenTarget.value = value
    this.hiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.close()
  }

  #move(delta) {
    if (this._filtered.length === 0) return
    this._activeIndex =
      (this._activeIndex + delta + this._filtered.length) % this._filtered.length
    this.#render()
    this.listTarget.children[this._activeIndex]?.scrollIntoView({ block: "nearest" })
  }

  #render() {
    this.listTarget.replaceChildren()

    if (this._filtered.length === 0) {
      const empty = document.createElement("li")
      empty.textContent = "No matches"
      empty.className = "searchable-select-empty"
      this.listTarget.appendChild(empty)
      return
    }

    this._filtered.forEach((option, index) => {
      const li = document.createElement("li")
      li.textContent = option
      li.dataset.value = option
      li.id = `${this._uid}-opt-${index}`
      li.setAttribute("role", "option")
      li.setAttribute("aria-selected", String(index === this._activeIndex))
      li.className =
        "searchable-select-option" + (index === this._activeIndex ? " is-active" : "")
      li.setAttribute("data-action", "mousedown->searchable-select#selectOption")
      this.listTarget.appendChild(li)
    })

    const active = this.listTarget.children[this._activeIndex]
    if (active) this.inputTarget.setAttribute("aria-activedescendant", active.id)
  }
}
```

- [ ] **Step 2: Add the stylesheet rules**

Append to `app/assets/stylesheets/pixeldex.css`:

```css
/* Searchable select (abilities) — 5 rows visible, scroll for the rest. */
.searchable-select { position: relative; }

.searchable-select-list {
  position: absolute;
  z-index: 70;              /* above the modal card (z-index 50/60) */
  left: 0; right: 0;
  margin: 0; padding: 0;
  list-style: none;
  max-height: calc(var(--visible-count, 5) * 22px);
  overflow-y: auto;
  background: var(--l2);
  border: var(--border-thin);
}

.searchable-select-option {
  padding: 3px 6px;
  font-size: 11px;
  line-height: 16px;
  cursor: pointer;
}

.searchable-select-option:hover,
.searchable-select-option.is-active {
  background: var(--d2);
  color: var(--l2);
}

.searchable-select-empty {
  padding: 3px 6px;
  font-size: 11px;
  color: var(--d2);
}
```

- [ ] **Step 3: Replace the ability select in the modal**

In `_pokemon_modal.html.erb`, replace lines 61-66 (the ABILITY block):

```erb
        <div>
          <label class="gb-label">ABILITY</label>
          <select data-pixeldex-target="modalAbility" class="gb-select">
            <option value="">Select...</option>
          </select>
        </div>
```

with:

```erb
        <%# Options read from GameState directly, not an ivar — this partial
            renders from BOTH dashboard#show and map#show, and an ivar set in
            only one controller would be nil on the other. %>
        <div class="searchable-select"
             data-controller="searchable-select"
             data-searchable-select-options-value="<%= SoulLink::GameState.all_abilities.to_json %>"
             data-searchable-select-visible-count-value="5">
          <label class="gb-label" for="modal-ability-input">ABILITY</label>
          <input type="text"
                 id="modal-ability-input"
                 class="gb-input"
                 role="combobox"
                 aria-expanded="false"
                 aria-autocomplete="list"
                 autocomplete="off"
                 placeholder="Search abilities..."
                 data-searchable-select-target="input"
                 data-action="input->searchable-select#filter
                              focus->searchable-select#filter
                              blur->searchable-select#closeSoon
                              keydown->searchable-select#keydown">
          <ul class="searchable-select-list hidden"
              role="listbox"
              data-searchable-select-target="list"
              data-action="mousedown->searchable-select#cancelClose"></ul>
          <input type="hidden"
                 data-searchable-select-target="hidden"
                 data-pixeldex-target="modalAbility">
        </div>
```

The hidden input keeps `data-pixeldex-target="modalAbility"`, so
`pixeldex_controller.js:394`'s `this.modalAbilityTarget.value` read is unchanged
(`.value` works on `type="hidden"`).

- [ ] **Step 4: Replace `#populateAbilities` — do NOT delete it**

In `pixeldex_controller.js`, replace the whole method body at lines **513-524**
(keeping the name and arity, because `:343` and `:373` both call it):

```js
  // Any Pokemon may now have any ability, so this no longer filters by
  // species — it just seeds the searchable select's current value. Kept
  // under the original name/arity because both callers (#openModal and
  // searchSpecies) still invoke it.
  #populateAbilities(_species, currentAbility) {
    this.modalAbilityTarget.value = currentAbility || ""

    const wrapper = this.modalAbilityTarget.closest(".searchable-select")
    const input = wrapper?.querySelector("[data-searchable-select-target='input']")
    if (input) input.value = currentAbility || ""
  }
```

Leave lines 343 and 373 untouched. **Leave `abilitiesData` in `static values`** —
line 371 still uses `this.abilitiesDataValue[input]` as the species-existence
guard, and removing it would break species search.

- [ ] **Step 5: Verify both callers still resolve**

Run: `grep -n "populateAbilities\|abilitiesDataValue" app/javascript/controllers/pixeldex_controller.js`
Expected: the definition plus calls at ~343 and ~373, and `abilitiesDataValue`
still referenced at ~371.

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/searchable_select_controller.js app/assets/stylesheets/pixeldex.css app/views/dashboard/_pokemon_modal.html.erb app/javascript/controllers/pixeldex_controller.js
git commit -m "feat(abilities): searchable any-ability select on the pokemon detail modal"
```

---

## Task 10: Party duplicate guard (server)

**Files:**
- Modify: `app/controllers/teams_controller.rb` (after line 24)
- Test: `test/controllers/teams_controller_test.rb`

`update_slots` already replaces the whole slot list, so a swap is expressible
client-side as a reordered id list. What it does **not** do is reject duplicates,
which a buggy swap could send. `GREY` is a class constant in this test file; the
setup provides `@run` only.

- [ ] **Step 1: Write the failing test**

```ruby
  test "update_slots rejects duplicate group ids" do
    login_as(GREY)
    group = create(:soul_link_pokemon_group, soul_link_run: @run)
    create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: group,
           discord_user_id: GREY, species: "Staravia")

    patch update_slots_team_path, params: { group_ids: [ group.id, group.id ] }, as: :json

    assert_response :unprocessable_entity
    assert_match(/duplicate/i, JSON.parse(response.body)["error"])
  end

  test "update_slots preserves the submitted order" do
    login_as(GREY)
    groups = 3.times.map do
      g = create(:soul_link_pokemon_group, soul_link_run: @run)
      create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: g,
             discord_user_id: GREY, species: "Staravia")
      g
    end
    ordered = [ groups[2].id, groups[0].id, groups[1].id ]

    patch update_slots_team_path, params: { group_ids: ordered }, as: :json

    assert_response :success
    team = @run.soul_link_teams.find_by(discord_user_id: GREY)
    assert_equal ordered,
                 team.soul_link_team_slots.order(:position).pluck(:soul_link_pokemon_group_id)
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/teams_controller_test.rb`
Expected: FAIL on the duplicate test — got 200, expected 422

- [ ] **Step 3: Add the duplicate guard**

In `update_slots`, immediately after `group_ids = params[:group_ids] || []` (line 24):

```ruby
    # A swap is expressed client-side as a reordered id list. A duplicate id
    # means the client built that list wrong — reject rather than silently
    # dropping a slot inside replace_slots!.
    if group_ids.length != group_ids.uniq.length
      render json: { error: "Duplicate group ids in team" }, status: :unprocessable_entity
      return
    end
```

- [ ] **Step 4: Run the full suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors

- [ ] **Step 5: Commit**

```bash
git add app/controllers/teams_controller.rb test/controllers/teams_controller_test.rb
git commit -m "feat(party): reject duplicate group ids in update_slots"
```

---

## Task 11: Party drag-and-drop and click-through

**Files:**
- Create: `app/javascript/controllers/party_drag_controller.js`
- Modify: `app/views/dashboard/_party_panel.html.erb`
- Modify: `app/views/dashboard/_pc_box_content.html.erb`
- Modify: `app/views/dashboard/show.html.erb`

**Four traps, all confirmed:**
1. **Do NOT mount `team-builder` here.** Its `connect()` unconditionally
   dereferences `this.teamListTarget` and `this.poolListTarget`, which exist only
   on `/team`. Stimulus would raise `Missing target element "teamList"`, aborting
   connect and breaking dashboard JS. A dedicated `party-drag` controller is used
   instead, mounted alongside `pixeldex` on the dashboard root.
2. **The dragged clone is a `.box-cell`, not a `.team-slot`.** Any logic that
   locates it via `querySelectorAll(".team-slot")` silently no-ops. We read
   `event.item.dataset.groupId` and remove the clone.
3. **Party slots need all seven `data-group-*` attributes**, not just the id.
   `selectPokemon` → `#openModal` reads `groupSpecies`, `groupNickname`,
   `groupLocation`, `groupStatus`, `groupId`, `groupPokemon`, `groupTypes`. With
   only the id, the modal opens blank and SAVE would write a blank nickname to a
   real group.
4. **Empty slots use `.team-slot-empty`**, a different class — so DOM-position
   arithmetic must count `.team-slot` nodes explicitly.

After a successful PATCH the page reloads. That is deliberate: the server-rendered
party slot markup carries seven data attributes, and rebuilding it client-side
would duplicate view logic and drift. Party edits are infrequent; correctness wins.

No automated test — drag-and-drop has no practical unit-test surface here.
Verified manually in Task 13.

- [ ] **Step 1: Add `data-alive` to PC box cells**

`_pc_box_content.html.erb:229` **already** has `data-group-id`. Add only the new
attribute to the `.box-cell` div (around line 229):

```erb
               data-alive="<%= group.caught? %>"
```

- [ ] **Step 2: Add the grid hook**

Find the `.box-grid` container:
Run: `grep -n "box-grid" app/views/dashboard/_pc_box_content.html.erb`

Add `data-party-drag-target="boxGrid"` to that element.

- [ ] **Step 3: Give party slots the full attribute set**

In `_party_panel.html.erb`, replace the `.team-slot` opening tag (line 10) with a
mirror of `_pc_box_content.html.erb:228-235`. Read those exact lines first and
copy the attribute list verbatim, substituting this partial's local variables:

```erb
        <div class="team-slot"
             data-action="click->pixeldex#selectPokemon"
             data-group-id="<%= group.id %>"
             data-group-nickname="<%= group.nickname %>"
             data-group-species="<%= my_pokemon&.species || '' %>"
             data-group-location="<%= group.location %>"
             data-group-status="<%= group.dead? ? 'dead' : 'caught' %>"
             data-group-types="<%= my_pokemon&.species.present? ? SoulLink::GameState.types_for(my_pokemon.species).join(',') : '' %>"
             data-group-pokemon="<%= pixeldex_group_pokemon_json(group, current_user_id) %>">
```

Add the drop-target hook to the `.panel-body` wrapper:

```erb
  <div class="panel-body" data-party-drag-target="partyList">
```

- [ ] **Step 4: Mount the controller**

In `app/views/dashboard/show.html.erb`, add `party-drag` to the existing root
`data-controller` attribute (line ~14, currently `data-controller="pixeldex ..."`)
and pass the two values:

```erb
     data-party-drag-update-url-value="<%= update_slots_team_path %>"
     data-party-drag-csrf-value="<%= form_authenticity_token %>"
```

Read line 14 first and append rather than replacing the existing controller list.

- [ ] **Step 5: Write the controller**

```js
import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Drag a living Pokemon from the PC box into the party sidebar.
//
// Dropping onto an occupied slot SWAPS: the resident leaves the party and
// the dragged group takes its position.
//
// The dragged node is a *clone of a .box-cell*, not a .team-slot, so we read
// its group id from the dataset and discard the node — then reload, because
// party slot markup carries seven data-group-* attributes that the detail
// modal depends on, and rebuilding that client-side would duplicate view
// logic. Party edits are infrequent; a reload is the honest trade.
export default class extends Controller {
  static targets = ["boxGrid", "partyList"]
  static values = { updateUrl: String, csrf: String }

  static MAX_SLOTS = 6

  connect() {
    if (!this.hasBoxGridTarget || !this.hasPartyListTarget) return

    this._boxSortable = new Sortable(this.boxGridTarget, {
      group: { name: "party", pull: "clone", put: false },
      sort: false,
      // Dead Pokemon never start a drag, so the gesture cannot appear to
      // succeed and then snap back.
      filter: "[data-alive='false']",
      onStart: () => document.body.classList.add("sortable-dragging"),
      onEnd: () => {
        setTimeout(() => document.body.classList.remove("sortable-dragging"), 0)
      }
    })

    this._partySortable = new Sortable(this.partyListTarget, {
      group: { name: "party", pull: false, put: true },
      draggable: ".team-slot",
      onAdd: (event) => this.#handleDrop(event)
    })
  }

  disconnect() {
    this._boxSortable?.destroy()
    this._partySortable?.destroy()
  }

  #handleDrop(event) {
    const item = event.item
    const groupId = item.dataset.groupId

    // Count real party slots preceding the drop point. Empty placeholders
    // use .team-slot-empty and must not be counted.
    let insertAt = 0
    for (let node = item.previousElementSibling; node; node = node.previousElementSibling) {
      if (node.classList.contains("team-slot")) insertAt++
    }

    item.remove() // discard the .box-cell clone; server render is the truth

    if (!groupId) return

    const current = Array.from(this.partyListTarget.querySelectorAll(".team-slot"))
      .map((el) => el.dataset.groupId)
      .filter(Boolean)

    if (current.includes(groupId)) return // already in the party

    const ids = [...current]
    const MAX = this.constructor.MAX_SLOTS

    if (ids.length >= MAX) {
      // Swap: the resident at the drop position is displaced.
      ids[Math.min(insertAt, MAX - 1)] = groupId
    } else {
      ids.splice(insertAt, 0, groupId)
    }

    this.#persist(ids)
  }

  #persist(ids) {
    fetch(this.updateUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfValue
      },
      body: JSON.stringify({ group_ids: ids })
    })
      .then((r) => r.json())
      .then((data) => {
        if (data.error) console.warn("Party update rejected:", data.error)
        window.location.reload()
      })
      .catch(() => window.location.reload())
  }
}
```

- [ ] **Step 6: Confirm the existing drag guard on `selectPokemon`**

`pixeldex_controller.js:253` **already** guards with
`if (event.currentTarget.classList.contains("sortable-chosen")) return`.

Add the body-class guard alongside it (the clone does not carry
`sortable-chosen`, so the existing guard alone is insufficient for this path):

```js
    // A drag ends with a click on the dragged element; ignore it so dropping
    // into the party does not also open the detail modal. Complements the
    // existing sortable-chosen check below.
    if (document.body.classList.contains("sortable-dragging")) return
```

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors

- [ ] **Step 8: Commit**

```bash
git add app/views/dashboard app/javascript/controllers
git commit -m "feat(party): drag PC box pokemon into the party, click party for details"
```

---

## Task 12: ROM download

**Files:**
- Create: migration, `app/models/soul_link_rom_download.rb`, `app/jobs/soul_link/generate_rom_download_job.rb`, `app/controllers/runs/rom_downloads_controller.rb`, `app/javascript/controllers/rom_download_controller.js`, `test/factories/soul_link_rom_downloads.rb`
- Modify: `app/services/soul_link/rom_randomizer.rb`, `app/models/soul_link_run.rb`, `config/routes.rb`, `app/views/dashboard/_runs_content.html.erb`, `lib/tasks/emulator_cleanup.rake`
- Test: `test/jobs/soul_link/generate_rom_download_job_test.rb`, `test/controllers/runs/rom_downloads_controller_test.rb`

Route helpers verified: `module: :runs` scopes only the controller lookup, so the
helpers are `run_rom_downloads_path(@run)`, `run_rom_download_path(@run, dl)`, and
`download_run_rom_download_path(@run, dl)`. No Zeitwerk collision —
`RunsController` and `Runs::RomDownloadsController` are distinct constants.

- [ ] **Step 1: Create the migration, model, and factory**

```bash
bin/rails generate migration CreateSoulLinkRomDownloads
```

Body:

```ruby
class CreateSoulLinkRomDownloads < ActiveRecord::Migration[8.1]
  def change
    create_table :soul_link_rom_downloads do |t|
      t.references :soul_link_run, null: false, foreign_key: true
      t.bigint  :discord_user_id, null: false
      t.string  :status, null: false, default: "pending"
      t.string  :rom_path
      t.string  :error_message
      t.timestamps
    end

    add_index :soul_link_rom_downloads, [ :soul_link_run_id, :discord_user_id ]
  end
end
```

`app/models/soul_link_rom_download.rb`:

```ruby
class SoulLinkRomDownload < ApplicationRecord
  belongs_to :soul_link_run

  STATUSES = %w[pending generating ready failed].freeze

  validates :discord_user_id, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :ready, -> { where(status: "ready") }

  def ready?  = status == "ready"
  def failed? = status == "failed"

  # Absolute path on disk, or nil when the ROM is not there — guards against
  # a rom_path pointing at a file the cleanup task already pruned.
  def absolute_rom_path
    return nil if rom_path.blank?
    path = Rails.root.join(rom_path)
    File.exist?(path) ? path : nil
  end
end
```

`test/factories/soul_link_rom_downloads.rb`:

```ruby
FactoryBot.define do
  factory :soul_link_rom_download do
    association :soul_link_run
    # Must be a REGISTERED player (GameState.players.first) — the controller
    # scopes downloads to current_user_id, and the controller tests log in as
    # that player. A sequence here would break them.
    discord_user_id { SoulLink::GameState.players.first["discord_user_id"] }
    status { "pending" }
  end
end
```

Add to `app/models/soul_link_run.rb`:

```ruby
  has_many :soul_link_rom_downloads, dependent: :destroy
```

Run: `bin/rails db:migrate`

- [ ] **Step 2: Extract the session-free randomizer path**

`initialize` only assigns `@session`, so `new(nil)` is sufficient — no `allocate`
hack. Verified: `precondition_error` (:58-65), `java_available?` (:69-71), and
`run_subprocess` (:85-148) contain zero `@session` references.

Add to `app/services/soul_link/rom_randomizer.rb`:

```ruby
    class << self
      # Session-free generation for callers with no session to mutate (the
      # on-demand download). Returns [ok, error_message].
      def generate_to(output_path) = new(nil).generate_to(output_path)
    end

    # Public instance entry point. The session-mutating `call` wraps the same
    # subprocess machinery; this exposes it without the session bookkeeping.
    def generate_to(output_path)
      reason = precondition_error
      return [ false, reason ] if reason

      path = Pathname.new(output_path.to_s)
      FileUtils.mkdir_p(path.dirname)

      _stdout, stderr, status = run_subprocess(path)
      return [ true, nil ] if status&.success?

      [ false, stderr.to_s.strip.presence || "Randomizer exited non-zero" ]
    rescue Timeout::Error
      [ false, "Generation timed out after #{GENERATION_TIMEOUT}s" ]
    end
```

Place `generate_to` above the `private` keyword so it is public.

- [ ] **Step 3: Verify the nil session is safe**

Run: `sed -n '58,72p;85,148p' app/services/soul_link/rom_randomizer.rb | grep -n "session"`
Expected: **no output** — neither the precondition checks nor the subprocess
runner touch the session.

Run: `bin/rails runner 'p SoulLink::RomRandomizer.new(nil).send(:precondition_error)'`
Expected: prints a precondition string or `nil` — must NOT raise `NoMethodError`.

- [ ] **Step 4: Write the job test**

```ruby
require "test_helper"

module SoulLink
  class GenerateRomDownloadJobTest < ActiveSupport::TestCase
    setup do
      @run = create(:soul_link_run)
      @download = create(:soul_link_rom_download, soul_link_run: @run)
    end

    test "marks the download ready on success" do
      SoulLink::RomRandomizer.stub(:generate_to, ->(_path) { [ true, nil ] }) do
        SoulLink::GenerateRomDownloadJob.perform_now(@download.id)
      end

      @download.reload
      assert_equal "ready", @download.status
      assert @download.rom_path.present?
      assert_nil @download.error_message
    end

    test "marks the download failed with the reason" do
      SoulLink::RomRandomizer.stub(:generate_to, ->(_path) { [ false, "Java is not installed" ] }) do
        SoulLink::GenerateRomDownloadJob.perform_now(@download.id)
      end

      @download.reload
      assert_equal "failed", @download.status
      assert_equal "Java is not installed", @download.error_message
    end

    test "is a no-op for a missing download id" do
      assert_nothing_raised { SoulLink::GenerateRomDownloadJob.perform_now(0) }
    end

    test "truncates an overlong error to the column limit" do
      SoulLink::RomRandomizer.stub(:generate_to, ->(_path) { [ false, "x" * 500 ] }) do
        SoulLink::GenerateRomDownloadJob.perform_now(@download.id)
      end

      assert_operator @download.reload.error_message.length, :<=, 255
    end
  end
end
```

- [ ] **Step 5: Run the job test to verify it fails**

Run: `bin/rails test test/jobs/soul_link/generate_rom_download_job_test.rb`
Expected: FAIL — uninitialized constant `GenerateRomDownloadJob`

- [ ] **Step 6: Write the job**

```ruby
module SoulLink
  # Generates a standalone randomized ROM for the on-demand download button.
  # Unlike GenerateRunRomsJob this is not tied to an emulator session — the
  # output is a one-off file the player downloads and runs elsewhere.
  class GenerateRomDownloadJob < ApplicationJob
    queue_as :default

    OUTPUT_DIR  = Rails.root.join("storage", "roms", "downloads")
    ERROR_LIMIT = 255  # error_message is varchar(255)

    def perform(download_id)
      download = SoulLinkRomDownload.find_by(id: download_id)
      return if download.nil?

      download.update!(status: "generating", error_message: nil)

      output_path = OUTPUT_DIR.join("run_#{download.soul_link_run_id}", "#{download.id}.nds")
      ok, error = SoulLink::RomRandomizer.generate_to(output_path)

      if ok
        download.update!(
          status: "ready",
          rom_path: output_path.relative_path_from(Rails.root).to_s,
          error_message: nil
        )
      else
        download.update!(status: "failed", error_message: error.to_s[0, ERROR_LIMIT])
      end
    rescue StandardError => e
      Rails.logger.error("GenerateRomDownloadJob failed: #{e.class} #{e.message}")
      download&.update(status: "failed", error_message: e.message.to_s[0, ERROR_LIMIT])
    end
  end
end
```

- [ ] **Step 7: Run the job test to verify it passes**

Run: `bin/rails test test/jobs/soul_link/generate_rom_download_job_test.rb`
Expected: 4 runs, 0 failures, 0 errors

- [ ] **Step 8: Add routes**

Replace `resources :runs, only: %i[index edit update]` (routes.rb:41) with:

```ruby
  resources :runs, only: %i[index edit update] do
    resources :rom_downloads, only: %i[create show], module: :runs do
      get :download, on: :member
    end
  end
```

- [ ] **Step 9: Write the controller test**

`login_as` takes `guild_id` as a **keyword** with default `GUILD_ID`
(999999999999999999), which is exactly what the run factory sets — so one
positional arg is correct.

```ruby
require "test_helper"

module Runs
  class RomDownloadsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @run = create(:soul_link_run)
      @user_id = SoulLink::GameState.players.first["discord_user_id"]
      login_as(@user_id)
    end

    test "create queues a job and returns the download id" do
      assert_enqueued_with(job: SoulLink::GenerateRomDownloadJob) do
        post run_rom_downloads_path(@run), as: :json
      end

      assert_response :success
      assert JSON.parse(response.body)["id"].present?
    end

    test "show reports status for polling" do
      download = create(:soul_link_rom_download, soul_link_run: @run,
                        discord_user_id: @user_id, status: "generating")

      get run_rom_download_path(@run, download), as: :json

      assert_response :success
      assert_equal "generating", JSON.parse(response.body)["status"]
    end

    test "download 404s when the rom is not ready" do
      download = create(:soul_link_rom_download, soul_link_run: @run,
                        discord_user_id: @user_id, status: "generating")

      get download_run_rom_download_path(@run, download)
      assert_response :not_found
    end

    test "download 404s for a different user's rom" do
      download = create(:soul_link_rom_download, soul_link_run: @run,
                        discord_user_id: @user_id + 1, status: "ready",
                        rom_path: "storage/roms/downloads/nope.nds")

      get download_run_rom_download_path(@run, download)
      assert_response :not_found
    end

    test "download 404s when the file is gone from disk" do
      download = create(:soul_link_rom_download, soul_link_run: @run,
                        discord_user_id: @user_id, status: "ready",
                        rom_path: "storage/roms/downloads/pruned.nds")

      get download_run_rom_download_path(@run, download)
      assert_response :not_found
    end
  end
end
```

- [ ] **Step 10: Run the controller test to verify it fails**

Run: `bin/rails test test/controllers/runs/rom_downloads_controller_test.rb`
Expected: FAIL — uninitialized constant `Runs::RomDownloadsController`

- [ ] **Step 11: Write the controller**

```ruby
module Runs
  class RomDownloadsController < ApplicationController
    before_action :require_login

    def create
      run = find_run
      head :not_found and return unless run

      download = run.soul_link_rom_downloads.create!(
        discord_user_id: current_user_id,
        status: "pending"
      )
      SoulLink::GenerateRomDownloadJob.perform_later(download.id)

      render json: { id: download.id, status: download.status }
    end

    def show
      download = find_download
      head :not_found and return unless download

      render json: { id: download.id, status: download.status, error: download.error_message }
    end

    def download
      record = find_download
      head :not_found and return unless record&.ready?

      path = record.absolute_rom_path
      head :not_found and return if path.nil?

      send_file path,
                filename: "soul_link_run_#{record.soul_link_run_id}_#{record.id}.nds",
                type: "application/octet-stream"
    end

    private

    # Scoped to the requesting player — a download belongs to whoever
    # generated it.
    def find_download
      run = find_run
      return nil unless run
      run.soul_link_rom_downloads.find_by(id: params[:id], discord_user_id: current_user_id)
    end

    def find_run
      guild_id = session[:guild_id]
      return nil unless guild_id
      SoulLinkRun.for_guild(guild_id).find_by(id: params[:run_id])
    end
  end
end
```

- [ ] **Step 12: Run the controller test to verify it passes**

Run: `bin/rails test test/controllers/runs/rom_downloads_controller_test.rb`
Expected: 5 runs, 0 failures, 0 errors

- [ ] **Step 13: Add the Stimulus controller**

`app/javascript/controllers/rom_download_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// Click → POST → poll → download link. Generation takes up to 30s (Java
// subprocess), far too long to hold an HTTP request open, so the work is
// queued and this polls for the result.
export default class extends Controller {
  static targets = ["button", "status", "link"]
  static values = { runId: Number, pollInterval: { type: Number, default: 2000 } }

  disconnect() {
    this.#stopPolling()
  }

  generate() {
    this.buttonTarget.disabled = true
    this.#setStatus("Generating ROM…")
    this.linkTarget.classList.add("hidden")

    fetch(`/runs/${this.runIdValue}/rom_downloads`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      }
    })
      .then((r) => r.json())
      .then((data) => {
        if (!data.id) throw new Error("no download id")
        this._downloadId = data.id
        this.#startPolling()
      })
      .catch(() => this.#fail("Could not start generation."))
  }

  #startPolling() {
    this.#stopPolling()
    this._timer = setInterval(() => this.#poll(), this.pollIntervalValue)
  }

  #stopPolling() {
    if (this._timer) clearInterval(this._timer)
    this._timer = null
  }

  #poll() {
    fetch(`/runs/${this.runIdValue}/rom_downloads/${this._downloadId}`)
      .then((r) => r.json())
      .then((data) => {
        if (data.status === "ready") {
          this.#stopPolling()
          this.#succeed()
        } else if (data.status === "failed") {
          this.#stopPolling()
          this.#fail(data.error || "Generation failed.")
        }
      })
      .catch(() => {
        this.#stopPolling()
        this.#fail("Lost contact with the server.")
      })
  }

  #succeed() {
    this.#setStatus("")
    this.buttonTarget.disabled = false
    this.linkTarget.href = `/runs/${this.runIdValue}/rom_downloads/${this._downloadId}/download`
    this.linkTarget.classList.remove("hidden")
  }

  #fail(message) {
    this.buttonTarget.disabled = false
    this.#setStatus(`⚠️ ${message}`)
  }

  #setStatus(text) {
    this.statusTarget.textContent = text
    this.statusTarget.classList.toggle("hidden", text === "")
  }
}
```

- [ ] **Step 14: Add the button to the runs panel**

In `_runs_content.html.erb`, inside the existing button row (the flex div holding
`END RUN` / `SETUP DISCORD`), add:

```erb
          <span data-controller="rom-download"
                data-rom-download-run-id-value="<%= active_run&.id %>"
                style="display: inline-flex; align-items: center; gap: 6px;">
            <button data-action="click->rom-download#generate"
                    data-rom-download-target="button"
                    class="gb-btn-primary gb-btn-sm">
              Download Randomized ROM
            </button>
            <span data-rom-download-target="status"
                  class="hidden"
                  style="font-size: 11px; color: var(--l1);"></span>
            <a data-rom-download-target="link"
               class="gb-btn gb-btn-sm hidden"
               style="text-decoration: none;"
               download>SAVE .NDS</a>
          </span>
```

- [ ] **Step 15: Add the cleanup task**

Append inside the existing `namespace :soul_link` block in
`lib/tasks/emulator_cleanup.rake`, matching the style of the tasks already there:

```ruby
  desc "Prune downloaded ROMs older than 7 days"
  task prune_rom_downloads: :environment do
    cutoff = 7.days.ago
    pruned = 0

    SoulLinkRomDownload.where("created_at < ?", cutoff).find_each do |download|
      path = download.absolute_rom_path
      File.delete(path) if path
      download.destroy!
      pruned += 1
    end

    puts "Pruned #{pruned} ROM download(s) older than #{cutoff.to_date}"
  end
```

- [ ] **Step 16: Run the full suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors

- [ ] **Step 17: Commit**

```bash
git add db app/models app/jobs app/controllers app/javascript app/views config/routes.rb lib/tasks test
git commit -m "feat(roms): on-demand randomized ROM generation and download"
```

---

## Task 13: Verification and PR

- [ ] **Step 1: Full suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors, run count ≥ 848 (the pre-work baseline).
**Read the actual output.** Do not claim success without it.

- [ ] **Step 2: Lint**

Run: `bundle exec rubocop`
Expected: no offenses. Fix them; do not disable cops to pass.

- [ ] **Step 3: Security scan**

Run: `bundle exec brakeman -q`
Expected: 0 warnings. `send_file` with a DB-sourced path is the likely flag —
the path is confined to `storage/roms/downloads` and the record is scoped to the
requesting user. If Brakeman flags it, verify that reasoning still holds before
annotating.

- [ ] **Step 4: Update the spec's custom_id**

The spec says `soul_link:catch_species_modal:`; the implementation uses
`soul_link:catch_quick_add_modal:`. Update the spec so the two agree.

- [ ] **Step 5: Manual browser verification**

Start with `bin/dev` and confirm each by hand — none of these have automated
coverage. Record the result of every line.

1. PC box → click a Pokemon → click the dimmed area → modal closes.
2. Same for catch, mark-dead, reset-draft, confirm, and quick-calc modals.
3. Click *inside* a modal card → does **not** close.
4. Escape in each modal → still closes (no regression).
5. Ability box: typing filters, 5 rows visible, scrolls, arrows + Enter select.
6. Escape with the ability list open closes the list but **not** the modal.
7. Open the same modal from `/map` → ability list populated (not empty/broken).
8. Species search in the modal still works (the `abilitiesData` guard path).
9. Drag a living Pokemon from PC box → party → it lands.
10. Drag onto an occupied slot in a full party → resident displaced, still 6.
11. Drag a dead Pokemon → refused.
12. Click a party member → detail modal opens, populated (not blank).
13. Dropping does **not** also open the modal.

- [ ] **Step 6: Push and open the PR**

```bash
git push -u origin claude/pokemon-site-features-a3b30e
gh pr create --title "Seven site + Discord features" --body "$(cat <<'EOF'
Implements seven requested features as independently revertable commits.

## Discord
- **Catch embeds** — creating a catch on the site now posts a live-updating
  embed to the run's catches channel, one per group, listing all four players.
  Idempotency comes from a new `discord_catch_message_id` column, so repeated
  saves edit the existing message rather than reposting.
- **Quick-add from Discord** — the catch post carries an ADD MY POKEMON button
  that opens a modal for the clicking player's species. *Discord string selects
  cap at 25 options and there are 493 species, so a dropdown was not possible;
  this uses the same modal pattern the bot already uses elsewhere.* Species
  input resolves exact → unique-prefix → reject-with-candidates, never guessing.
- **One death message** — Mark Dead sent four messages (one per player's
  Pokemon). Now sends one listing all four.

## Frontend
- **Modal click-outside** — every modal already had a backdrop handler, but the
  backdrop was covered by its `position: relative` sibling, making it
  unreachable. Moved the action to the wrapper with a target/currentTarget
  guard. Fixed across all six modals.
- **Any-ability select** — new `searchable-select` Stimulus controller with
  search, 5 visible rows, keyboard nav, ARIA combobox roles. *Built with the
  123-ability list inline rather than an AJAX endpoint — the whole dataset is
  ~3KB, so pagination would have added latency and failure modes for no gain.*
- **Party drag-and-drop** — living Pokemon drag from the PC box into the party;
  dropping onto an occupied slot swaps. Party members are now clickable and open
  the detail modal.

## ROM pipeline
- **On-demand ROM download** — new button generates a standalone randomized ROM
  via a background job and hands back a download link. *Async because generation
  takes up to 30s and would otherwise risk proxy timeouts.*

## Notes for reviewers
`Discordrb::API::Channel` methods take **positional** arguments — passing
`embeds:`/`components:` as keywords silently binds them to `tts`, and the
fire-and-forget rescue would hide the resulting 400. `CatchMessage` passes them
positionally and its tests use positional stubs so a regression cannot pass green.

## Testing
Full suite green (baseline was 848 runs, 0 failures), rubocop clean, brakeman
clean. The modal fix and the drag-and-drop are browser behaviors with no
unit-test surface in this stack — both verified manually against the checklist
in the plan doc.

## ⚠️ Outstanding
Feature 4 is built against the **current** `randomizer_settings.rnqs`. The
updated settings file has not been supplied. Swapping it is a drop-in data
change requiring no code edit, but **the new settings have not been verified to
produce a valid ROM.**

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review

**Spec coverage:** Feature 1 → Tasks 1, 3, 4. Feature 2 → Task 7. Feature 3 →
Tasks 8, 9. Feature 4 → Task 12. Feature 5 → Task 6. Feature 6 → Tasks 2, 5.
Feature 7 → Tasks 10, 11. Verification → Task 13. No gaps.

**Placeholders:** None. Every code step carries complete code.

**Type consistency:** `SpeciesResolver.call` → `Result#species`/`#candidates`/
`#resolved?` (Tasks 2, 5). `CatchMessage.post_or_update(group)` takes a group
everywhere (Tasks 3, 4, 5). `RomRandomizer.generate_to(path)` → `[ok, error]`
(Task 12 Steps 2, 6). `notify_group_death(run, group)` consistent across Task 6
Steps 1, 2, 4, 5. `modalAbility` stays the pixeldex target name (Task 9 Steps 3, 4).
`#populateAbilities(species, currentAbility)` keeps its original arity so both
existing callers resolve.

**Cross-task deletion safety:** Tasks 6 and 9 both remove or replace public
surface with off-task consumers; both now run the full suite, and Task 6 names
`wipe_flow_test.rb` explicitly.
