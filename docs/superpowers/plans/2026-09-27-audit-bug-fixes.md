# Audit Bug Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the bugs found in the 2026-09-27 audit (spec: `docs/superpowers/specs/2026-09-27-audit-bug-fixes-design.md`) and ship them as one production deploy.

**Architecture:** Minimal, test-first fixes in place. No restructuring; later cleanup phases do that. Shared pieces introduced here: `SoulLinkRun#ensure_writable!` + `SoulLinkRun::ReadOnlyError`, a `RunWriteGuard` controller concern, `for_guild` scopes on `GymDraft`/`GymPoll`, and a `stub_connection_with_session` test helper.

**Tech Stack:** Rails 8.1, Ruby 3.4.5, MySQL 8, Minitest + FactoryBot, ActionCable, Stimulus (Importmap, no Node build).

---

## Ground rules for every task

- Work in the worktree `/Users/gferm/personal/projects/soul_link/.claude/worktrees/gym-draft-completion-save-a6e161` on branch `claude/project-refactor-rails-1a347c`. Never `cd` elsewhere.
- Run tests with `bin/rails test <path>`. For the full suite, redirect to a file and grep it (terminal output is compressed and unreliable):
  `bin/rails test > tmp/test_full.txt 2>&1; grep -E "runs, .*assertions" tmp/test_full.txt`
- Baseline before this plan: **964 runs, 0 failures, 0 errors**.
- Code style is rubocop-rails-omakase: double-quoted strings, spaces inside array brackets (`[ a, b ]`).
- Commit after each task. Do not push until Task 17.

## File map

| File | Change |
|---|---|
| `app/controllers/dashboard_controller.rb` | Fall back to latest run; no-runs page |
| `app/views/dashboard/no_runs.html.erb` | New |
| `app/controllers/{teams,map,gym_ready,species_assignments,gym_polls,gym_drafts,runs}_controller.rb` | No-run redirects go to `/` |
| `app/services/soul_link/catch_coordinator.rb` | Species lookup constant; read-only guard |
| `lib/tasks/species_name_backfill.rake` | New |
| `app/services/soul_link/discord_bot.rb` | `next_gym_for`, `apply_mark_dead`, `reusable_general_channel`, guild-scoped poll lookup, read-only guards |
| `app/models/gym_draft.rb`, `app/models/gym_poll.rb` | `for_guild` scope; `with_lock`; read-only check |
| `app/channels/application_cable/channel.rb` | `session_guild_id` helper |
| `app/channels/gym_draft_channel.rb`, `gym_poll_channel.rb` | Guild-scoped subscribe; read-only on reset |
| `app/controllers/save_slots_controller.rb` | Remove CSRF override |
| `app/models/soul_link_run.rb` | `READ_ONLY_MESSAGE`, `ReadOnlyError`, `ensure_writable!` |
| `app/controllers/concerns/run_write_guard.rb` | New |
| `app/controllers/application_controller.rb` | Include `RunWriteGuard` |
| `app/services/soul_link/wipe_coordinator.rb` | `reconsider` |
| `app/services/soul_link/gym_beaten_coordinator.rb`, `hall_of_fame_coordinator.rb` | Read-only guard |
| `app/views/dashboard/_pokemon_modal.html.erb`, `app/javascript/controllers/pixeldex_controller.js` | REVIVE button |
| `app/jobs/soul_link/generate_run_roms_job.rb` | Lock |
| `app/jobs/soul_link/parse_save_data_job.rb`, `app/models/soul_link_emulator_save_slot.rb` | Explicit roster broadcast |
| `app/jobs/application_job.rb`, `gym_poll_lock_job.rb`, `gym_poll_discord_sync_job.rb` | Robustness |
| `app/javascript/controllers/species_assignment_controller.js` | Safe DOM build |
| `test/test_helper.rb` | `CableSessionHelper` |

---

# Batch 1: user-facing

### Task 1: Break the no-active-run redirect loop

**Files:**
- Modify: `app/controllers/dashboard_controller.rb:5-23`
- Create: `app/views/dashboard/no_runs.html.erb`
- Modify: `app/controllers/teams_controller.rb:7,55`, `app/controllers/map_controller.rb:7`, `app/controllers/gym_ready_controller.rb:7`, `app/controllers/species_assignments_controller.rb:7`, `app/controllers/gym_polls_controller.rb:39`, `app/controllers/gym_drafts_controller.rb:6,71`, `app/controllers/runs_controller.rb:33`
- Create: `test/controllers/dashboard_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/controllers/dashboard_controller_test.rb`:

```ruby
require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  test "shows the latest run with the no-run panel when the guild has no active run" do
    create(:soul_link_run, active: false)
    latest = create(:soul_link_run, active: false)
    login_as(GREY)

    get root_path

    assert_response :success
    assert_select "[data-run-management-target=noRunPanel]:not(.hidden)"
    assert_select "a[href='/?run_id=#{latest.id}']", text: /VIEWING/
  end

  test "an unknown run_id falls back to a run instead of redirecting to login" do
    create(:soul_link_run)
    login_as(GREY)

    get root_path(run_id: 0)

    assert_response :success
  end

  test "renders the no-runs page when the guild has no runs at all" do
    run = create(:soul_link_run)
    login_as(GREY)
    run.destroy!

    get root_path

    assert_response :success
    assert_match "No runs yet", response.body
  end

  test "pages that need an active run send a logged-in user to the dashboard" do
    create(:soul_link_run, active: false)
    login_as(GREY)

    [ team_path, teams_path, map_path, gym_ready_path, species_path, gym_poll_path ].each do |path|
      get path
      assert_redirected_to root_path, "GET #{path}"
    end

    post gym_drafts_path
    assert_redirected_to root_path, "POST #{gym_drafts_path}"
  end

  test "the login page chain ends on the dashboard, not back at login" do
    create(:soul_link_run, active: false)
    login_as(GREY)

    get login_path
    assert_redirected_to team_path
    follow_redirect!
    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/dashboard_controller_test.rb`
Expected: 5 failures (redirects to `/login` instead of 200 / `root_path`).

- [ ] **Step 3: Fix the dashboard lookup**

In `app/controllers/dashboard_controller.rb`, replace lines 12-23:

```ruby
    @all_runs = SoulLinkRun.for_guild(guild_id).order(run_number: :desc)

    run = if params[:run_id].present?
            @all_runs.find_by(id: params[:run_id])
    else
            @all_runs.active.first
    end

    unless run
      redirect_to login_path, alert: "No active Soul Link run found."
      return
    end
```

with:

```ruby
    @all_runs = SoulLinkRun.for_guild(guild_id).order(run_number: :desc)

    # With no active run (after END RUN) show the latest run; its RUNS tab
    # carries the START NEW RUN panel. Redirecting to login here looped,
    # because login sends a signed-in user straight back.
    run = (params[:run_id].present? && @all_runs.find_by(id: params[:run_id])) ||
          @all_runs.active.first ||
          @all_runs.first
    return render :no_runs unless run
```

- [ ] **Step 4: Create the no-runs page**

Create `app/views/dashboard/no_runs.html.erb`:

```erb
<div class="dash-r1">
  <div class="panel" style="max-width: 480px; margin: 40px auto;">
    <div class="panel-header"><span>NO RUNS YET</span></div>
    <div class="panel-body" style="text-align: center;">
      <p style="font-size: 11px; margin-bottom: 12px;">
        No runs yet for this server. Start one in Discord with <code>/start_new_run</code>.
      </p>
      <%= button_to "SIGN OUT", logout_path, method: :delete, class: "gb-btn gb-btn-sm" %>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Point the other no-run redirects at the dashboard**

Replace `login_path` with `root_path` on exactly these lines (the alert text stays):

| File | Line | Before | After |
|---|---|---|---|
| `teams_controller.rb` | 7 | `redirect_to login_path, alert: "No active Soul Link run found."` | `redirect_to root_path, alert: "No active Soul Link run found."` |
| `teams_controller.rb` | 55 | same | same |
| `map_controller.rb` | 7 | same | same |
| `gym_ready_controller.rb` | 7 | same | same |
| `species_assignments_controller.rb` | 7 | same | same |
| `gym_polls_controller.rb` | 39 | `redirect_to login_path, alert: "No active run found." unless @run` | `redirect_to root_path, alert: "No active run found." unless @run` |
| `gym_drafts_controller.rb` | 6 | `redirect_to login_path, alert: "No active run found." and return unless run` | `redirect_to root_path, alert: "No active run found." and return unless run` |
| `gym_drafts_controller.rb` | 71 | same | same |
| `runs_controller.rb` | 33 | `redirect_to login_path, alert: "Run not found in this guild."` | `redirect_to root_path, alert: "Run not found in this guild."` |

Do not touch `sessions_controller.rb` or `concerns/discord_authentication.rb`; logged-out users still go to login.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/dashboard_controller_test.rb test/controllers test/integration`
Expected: 0 failures, 0 errors.

- [ ] **Step 7: Commit**

```bash
git add app/controllers app/views/dashboard/no_runs.html.erb test/controllers/dashboard_controller_test.rb
git commit -m "fix: show the latest run instead of looping to login when no run is active"
```

---

### Task 2: Resolve species names for auto-detected catches

**Files:**
- Modify: `app/services/soul_link/catch_coordinator.rb:172-187`
- Create: `lib/tasks/species_name_backfill.rake`
- Test: `test/services/soul_link/catch_coordinator_test.rb`, create `test/lib/tasks/species_name_backfill_test.rb`

- [ ] **Step 1: Write the failing coordinator test**

Add to `test/services/soul_link/catch_coordinator_test.rb`, after the `caught_event` helper:

```ruby
    test "stores the species name from pokemon_base_stats" do
      Pokemon::BaseStat.create!(species: "Turtwig", national_dex_number: 387, type1: "grass",
                                hp: 55, atk: 68, def_stat: 64, spa: 45, spd: 55, spe: 31)
      SoulLink::CatchCoordinator.reset_species_cache!

      SoulLink::CatchCoordinator.process(@slot, [ caught_event ])

      row = SoulLinkPokemon.find_by!(pid: 0xDEADBEEF)
      assert_equal "Turtwig", row.species
      assert_equal "Turtwig", row.name
    end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/services/soul_link/catch_coordinator_test.rb -n "/species name/"`
Expected: FAIL, `Expected: "Turtwig" Actual: "Species #387"`.

- [ ] **Step 3: Fix the lookup**

In `app/services/soul_link/catch_coordinator.rb`, replace:

```ruby
    def self.species_name_by_id
      @species_name_by_id ||= begin
        if defined?(PokemonBaseStat) && PokemonBaseStat.table_exists?
          PokemonBaseStat.pluck(:national_dex_number, :species).to_h
        else
          {}
        end
      rescue StandardError
        {}
      end
    end
```

with:

```ruby
    def self.species_name_by_id
      @species_name_by_id ||= Pokemon::BaseStat.pluck(:national_dex_number, :species).to_h
    end
```

(The old guard named a constant that does not exist, so the lookup was always empty, and the rescue hid that.)

- [ ] **Step 4: Run the coordinator and job tests**

Run: `bin/rails test test/services/soul_link/catch_coordinator_test.rb test/jobs/soul_link/parse_save_data_job_test.rb`
Expected: 0 failures.

- [ ] **Step 5: Write the failing backfill task test**

Create `test/lib/tasks/species_name_backfill_test.rb`:

```ruby
require "test_helper"
require "rake"

class SpeciesNameBackfillTaskTest < ActiveSupport::TestCase
  TASK_NAME = "soul_link:backfill_species_names".freeze

  @loaded = false
  class << self
    attr_accessor :loaded
  end

  setup do
    unless self.class.loaded
      Rails.application.load_tasks
      self.class.loaded = true
    end
    Rake::Task[TASK_NAME].reenable

    Pokemon::BaseStat.create!(species: "Turtwig", national_dex_number: 387, type1: "grass",
                              hp: 55, atk: 68, def_stat: 64, spa: 45, spd: 55, spe: 31)
    @run = create(:soul_link_run)
  end

  def catch_row(species, name: species)
    create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: nil,
           species: species, name: name)
  end

  def invoke
    capture_io { Rake::Task[TASK_NAME].invoke }
  end

  test "replaces placeholder species and a matching placeholder name" do
    row = catch_row("Species #387")

    invoke

    row.reload
    assert_equal "Turtwig", row.species
    assert_equal "Turtwig", row.name
  end

  test "keeps a name the player changed" do
    row = catch_row("Species #387", name: "SHELLY")

    invoke

    assert_equal "Turtwig", row.reload.species
    assert_equal "SHELLY", row.name
  end

  test "leaves real names and unknown dex numbers alone" do
    real = catch_row("Bidoof")
    unknown = catch_row("Species #999")

    invoke

    assert_equal "Bidoof", real.reload.species
    assert_equal "Species #999", unknown.reload.species
  end

  test "DRY_RUN makes no changes" do
    row = catch_row("Species #387")

    ENV["DRY_RUN"] = "1"
    invoke
    ENV.delete("DRY_RUN")

    assert_equal "Species #387", row.reload.species
  end
end
```

- [ ] **Step 6: Run it to verify it fails**

Run: `bin/rails test test/lib/tasks/species_name_backfill_test.rb`
Expected: errors, `Don't know how to build task 'soul_link:backfill_species_names'`.

- [ ] **Step 7: Write the task**

Create `lib/tasks/species_name_backfill.rake`:

```ruby
namespace :soul_link do
  desc "Replace 'Species #N' placeholders on auto-detected catches with real species names (DRY_RUN=1 to preview)"
  task backfill_species_names: :environment do
    dry_run = ENV["DRY_RUN"].present?
    names = Pokemon::BaseStat.pluck(:national_dex_number, :species).to_h

    SoulLinkPokemon.where("species LIKE ?", "Species #%").find_each do |pokemon|
      dex_number = pokemon.species[/\ASpecies #(\d+)\z/, 1]&.to_i
      species = names[dex_number]
      if species.nil?
        puts "pokemon=#{pokemon.id}: #{pokemon.species} has no match, skipped"
        next
      end

      attrs = { species: species }
      attrs[:name] = species if pokemon.name == pokemon.species
      puts "pokemon=#{pokemon.id}: #{pokemon.species} -> #{species}"
      pokemon.update!(attrs) unless dry_run
    end
  end
end
```

- [ ] **Step 8: Run it to verify it passes**

Run: `bin/rails test test/lib/tasks/species_name_backfill_test.rb`
Expected: 4 runs, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add app/services/soul_link/catch_coordinator.rb lib/tasks/species_name_backfill.rake test/services/soul_link/catch_coordinator_test.rb test/lib/tasks/species_name_backfill_test.rb
git commit -m "fix: resolve species names for auto-detected catches and add a backfill task"
```

---

### Task 3: `!next_gym` shows the run's next gym

**Files:**
- Modify: `app/services/soul_link/discord_bot.rb:119-126` (add method), `:346-352` (handler)
- Create: `test/services/soul_link/next_gym_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/services/soul_link/next_gym_test.rb`:

```ruby
require "test_helper"

module SoulLink
  # Pure core of the `!next_gym` text command. Tested as a class method
  # because the bot instance can't be booted in tests.
  class NextGymTest < ActiveSupport::TestCase
    test "returns the gym after the ones the run has beaten" do
      run = create(:soul_link_run, gyms_defeated: 3)

      assert_equal SoulLink::GameState.gym_info_by_number(4),
                   SoulLink::DiscordBot.next_gym_for(run)
    end

    test "returns nil once all eight gyms are beaten" do
      run = create(:soul_link_run, gyms_defeated: 8)

      assert_nil SoulLink::DiscordBot.next_gym_for(run)
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/services/soul_link/next_gym_test.rb`
Expected: errors, `NoMethodError: undefined method 'next_gym_for'`.

- [ ] **Step 3: Add the method and use it**

In `app/services/soul_link/discord_bot.rb`, add directly above `def self.species_error(input, resolution)`:

```ruby
    # Gym info for the `!next_gym` text command. nil once every gym is beaten.
    def self.next_gym_for(run)
      GameState.next_gym_info(run.gyms_defeated)
    end

```

Replace the `!next_gym` handler:

```ruby
      bot.message(content: '!next_gym') do |event|
        next unless event.channel.id == current_run(event)&.general_channel_id

        gym = GameState.next_gym_info
        event.respond embed: build_gym_embed(gym)
      end
```

with:

```ruby
      bot.message(content: "!next_gym") do |event|
        run = current_run(event)
        next unless run && event.channel.id == run.general_channel_id

        gym = self.class.next_gym_for(run)
        if gym
          event.respond embed: build_gym_embed(gym)
        else
          event.respond "🏆 All gyms beaten!"
        end
      end
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bin/rails test test/services/soul_link/next_gym_test.rb`
Expected: 2 runs, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/soul_link/discord_bot.rb test/services/soul_link/next_gym_test.rb
git commit -m "fix: !next_gym shows the run's next gym instead of always gym 1"
```

---

### Task 4: Deaths marked from Discord run wipe detection

**Files:**
- Modify: `app/services/soul_link/discord_bot.rb` (add `self.apply_mark_dead` after `self.apply_catch_create`; rewrite `handle_move_to_deaths_final` at ~line 1157)
- Create: `test/services/soul_link/mark_dead_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/services/soul_link/mark_dead_test.rb`:

```ruby
require "test_helper"

module SoulLink
  # Pure core of the bot's Mark Dead flow (eulogy modal). Tested as a class
  # method because the bot instance can't be booted in tests.
  class MarkDeadTest < ActiveSupport::TestCase
    GREY = 153665622641737728

    setup do
      @run = create(:soul_link_run)
      @group = create(:soul_link_pokemon_group, soul_link_run: @run)
      create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: @group, discord_user_id: GREY)
    end

    def apply(group_id: @group.id)
      SoulLink::CatchMessage.stub(:post_or_update, nil) do
        SoulLink::DeathMessage.stub(:post_or_update, nil) do
          SoulLink::DiscordNotifier.stub(:notify_wipe, nil) do
            SoulLink::DiscordBot.apply_mark_dead(run: @run, group_id: group_id, location: "original")
          end
        end
      end
    end

    test "marks the group dead" do
      result = apply

      assert result[:ok], result[:error]
      assert @group.reload.dead?
    end

    test "runs wipe detection, same as the website" do
      apply

      assert @run.reload.wiped_at.present?, "the player's only pokemon died, so the run should wipe"
    end

    test "reports an unknown group" do
      result = apply(group_id: 0)

      assert_not result[:ok]
      assert_equal "Could not find that group!", result[:error]
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/services/soul_link/mark_dead_test.rb`
Expected: errors, `NoMethodError: undefined method 'apply_mark_dead'`.

- [ ] **Step 3: Add `apply_mark_dead`**

In `app/services/soul_link/discord_bot.rb`, add after the `self.apply_catch_create` method (before `self.next_gym_for`):

```ruby
    # Pure core of the bot's Mark Dead flow. Marks the group dead, syncs its
    # catch and RIP embeds, and runs wipe detection, same as
    # PokemonGroupsController#update. `location` is "original" to keep the
    # catch location.
    #
    # Returns { ok: true, group: <group> } or { ok: false, error: "<msg>" }.
    def self.apply_mark_dead(run:, group_id:, location:, eulogy: nil)
      group = run&.caught_groups&.find_by(id: group_id)
      return { ok: false, error: "Could not find that group!" } if group.nil?

      death_location = location == "original" ? nil : location
      group.mark_as_dead!(death_location: death_location, eulogy: eulogy)

      SoulLink::CatchMessage.post_or_update(group)
      SoulLink::DeathMessage.post_or_update(group)
      SoulLink::WipeCoordinator.process(run)
      { ok: true, group: group }
    end

```

- [ ] **Step 4: Call it from the handler**

Replace the body of `handle_move_to_deaths_final` (from `group = run.caught_groups.find_by(id: group_id)` down to `update_deaths_panel(run)`):

```ruby
      group = run.caught_groups.find_by(id: group_id)
      unless group
        respond_ephemeral(event, "❌ Could not find that group!")
        return
      end

      death_location = location == 'original' ? nil : location
      group.mark_as_dead!(death_location: death_location, eulogy: eulogy)

      # Recolor the catch embed to its dead state, same as the website path.
      SoulLink::CatchMessage.post_or_update(group)
      # Post/refresh the live RIP embed, same as the website Mark-Dead path.
      SoulLink::DeathMessage.post_or_update(group)

      update_catches_panel(run)
      update_deaths_panel(run)
```

with:

```ruby
      result = self.class.apply_mark_dead(run: run, group_id: group_id, location: location, eulogy: eulogy)
      unless result[:ok]
        respond_ephemeral(event, "❌ #{result[:error]}")
        return
      end
      group = result[:group]

      update_catches_panel(run)
      update_deaths_panel(run)
```

The lines after it (`species_count = ...` through the `rescue`) stay.

- [ ] **Step 5: Run it to verify it passes**

Run: `bin/rails test test/services/soul_link/mark_dead_test.rb test/services/soul_link/wipe_coordinator_test.rb`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/services/soul_link/discord_bot.rb test/services/soul_link/mark_dead_test.rb
git commit -m "fix: run wipe detection when a death is marked from Discord"
```

- [ ] **Step 7: Batch 1 checkpoint**

Run: `bin/rails test > tmp/test_full.txt 2>&1; grep -E "runs, .*assertions" tmp/test_full.txt`
Expected: `0 failures, 0 errors`, run count above 964.

---

# Batch 2: access control and state integrity

### Task 5: Scope draft and poll access to the session's guild

**Files:**
- Modify: `app/models/gym_draft.rb` (scope), `app/models/gym_poll.rb` (scope)
- Modify: `app/channels/application_cable/channel.rb`, `app/channels/gym_draft_channel.rb:2-6`, `app/channels/gym_poll_channel.rb:2-6`
- Modify: `app/controllers/gym_drafts_controller.rb:20`
- Modify: `app/services/soul_link/discord_bot.rb` (`handle_gym_poll_vote`, `handle_gym_poll_reset`, `current_run`)
- Modify: `test/test_helper.rb`, `test/channels/run_channel_test.rb:13-23`, `test/channels/gym_draft_channel_test.rb:18,84`, `test/channels/gym_poll_channel_test.rb:16,63`
- Test: `test/models/gym_draft_test.rb`, `test/models/gym_poll_test.rb`, the two channel tests, `test/controllers/gym_drafts_controller_test.rb`

- [ ] **Step 1: Share the cable session stub**

In `test/test_helper.rb`, append after the `ActionDispatch::IntegrationTest` block:

```ruby
# ActionCable's ConnectionStub only knows `identified_by` attributes. Channels
# that authorize against the logged-in guild read `connection.session`, so the
# stub has to fake one.
module CableSessionHelper
  def stub_connection_with_session(current_user_id:, guild_id: LoginHelper::GUILD_ID)
    stub_connection(current_user_id: current_user_id)
    fake_session = { guild_id: guild_id }
    connection.define_singleton_method(:session) { fake_session }
  end
end

class ActionCable::Channel::TestCase
  include CableSessionHelper
end
```

In `test/channels/run_channel_test.rb`, delete the local `stub_connection_with_session` method and the comment above it (lines 13-23 in the current file, from `# \`ConnectionStub\` from ActionCable's TestCase` through the method's `end`). Its call site already passes `guild_id:`.

In the draft and poll channel tests, switch every `stub_connection` to the helper:

- `test/channels/gym_draft_channel_test.rb:18`: `stub_connection(current_user_id: GREY)` → `stub_connection_with_session(current_user_id: GREY)`
- `test/channels/gym_draft_channel_test.rb:84`: `stub_connection(current_user_id: next_nominator)` → `stub_connection_with_session(current_user_id: next_nominator)`
- `test/channels/gym_poll_channel_test.rb:16`: `stub_connection current_user_id: 111` → `stub_connection_with_session(current_user_id: 111)`
- `test/channels/gym_poll_channel_test.rb:63`: `stub_connection current_user_id: 99999  # not in PLAYER_IDS` → `stub_connection_with_session(current_user_id: 99999)  # not in PLAYER_IDS`

Run: `bin/rails test test/channels`
Expected: 0 failures (behaviour unchanged so far).

- [ ] **Step 2: Write the failing tests**

Add to `test/models/gym_draft_test.rb` (inside `GymDraftTest`):

```ruby
  test "for_guild only returns drafts from that guild's runs" do
    other = create(:gym_draft, soul_link_run: create(:soul_link_run, guild_id: 1))

    drafts = GymDraft.for_guild(@run.guild_id)

    assert_includes drafts, @draft
    assert_not_includes drafts, other
  end
```

Add to `test/models/gym_poll_test.rb` (inside `GymPollVoteTest`):

```ruby
  test "for_guild only returns polls from that guild's runs" do
    poll = open_poll
    other = create(:gym_poll, soul_link_run: create(:soul_link_run, guild_id: 1))

    polls = GymPoll.for_guild(poll.soul_link_run.guild_id)

    assert_includes polls, poll
    assert_not_includes polls, other
  end
```

Add to `test/channels/gym_draft_channel_test.rb`:

```ruby
  test "rejects a subscription to another guild's draft" do
    other = create(:gym_draft, soul_link_run: create(:soul_link_run, guild_id: 1))

    subscribe(draft_id: other.id)

    assert subscription.rejected?
  end
```

Add to `test/channels/gym_poll_channel_test.rb`:

```ruby
  test "rejects a subscription to another guild's poll" do
    other = create(:gym_poll, soul_link_run: create(:soul_link_run, guild_id: 1))

    with_player_data { subscribe(id: other.id) }

    assert subscription.rejected?
  end
```

Add to `test/controllers/gym_drafts_controller_test.rb`:

```ruby
  test "show returns 404 for another guild's draft" do
    other = create(:gym_draft, soul_link_run: create(:soul_link_run, guild_id: 1))
    login_as(GREY)

    get gym_draft_path(other)

    assert_response :not_found
  end
```

- [ ] **Step 3: Run them to verify they fail**

Run: `bin/rails test test/models/gym_draft_test.rb test/models/gym_poll_test.rb test/channels test/controllers/gym_drafts_controller_test.rb`
Expected: 2 errors (`undefined method 'for_guild'`) and 3 failures (subscriptions confirmed, show returns 200).

- [ ] **Step 4: Add the scopes**

In `app/models/gym_draft.rb`, after `after_initialize :set_defaults, if: :new_record?`:

```ruby

  scope :for_guild, ->(guild_id) { joins(:soul_link_run).where(soul_link_runs: { guild_id: guild_id }) }
```

In `app/models/gym_poll.rb`, after `after_initialize :set_defaults, if: :new_record?`:

```ruby

  scope :for_guild, ->(guild_id) { joins(:soul_link_run).where(soul_link_runs: { guild_id: guild_id }) }
```

- [ ] **Step 5: Scope the channels**

Replace `app/channels/application_cable/channel.rb` with:

```ruby
module ApplicationCable
  class Channel < ActionCable::Channel::Base
    private

    # The guild the connection logged in with. Channels scope every record
    # lookup to it, so a client can't reach another server's data by id.
    def session_guild_id
      connection.session && connection.session[:guild_id]
    end
  end
end
```

In `app/channels/gym_draft_channel.rb`, replace:

```ruby
  def subscribed
    @draft = GymDraft.find(params[:draft_id])
    stream_for @draft
```

with:

```ruby
  def subscribed
    @draft = GymDraft.for_guild(session_guild_id).find_by(id: params[:draft_id])
    return reject unless @draft

    stream_for @draft
```

In `app/channels/gym_poll_channel.rb`, replace:

```ruby
  def subscribed
    @poll = GymPoll.find(params[:id])
    stream_for @poll
```

with:

```ruby
  def subscribed
    @poll = GymPoll.for_guild(session_guild_id).find_by(id: params[:id])
    return reject unless @poll

    stream_for @poll
```

- [ ] **Step 6: Scope the controller**

In `app/controllers/gym_drafts_controller.rb#show`, replace `@draft = GymDraft.find(params[:id])` with:

```ruby
    @draft = GymDraft.for_guild(session[:guild_id]).find(params[:id])
```

- [ ] **Step 7: Scope the bot's poll buttons**

In `app/services/soul_link/discord_bot.rb`, replace `current_run`:

```ruby
    def current_run(event)
      guild_id = if event.respond_to?(:server_id)
                   event.server_id
      elsif event.respond_to?(:server) && event.server
                   event.server.id
      elsif event.respond_to?(:interaction) && event.interaction
                   event.interaction.server_id
      end

      SoulLinkRun.current(guild_id)
    end
```

with:

```ruby
    def current_run(event)
      SoulLinkRun.current(event_guild_id(event))
    end

    def event_guild_id(event)
      if event.respond_to?(:server_id)
        event.server_id
      elsif event.respond_to?(:server) && event.server
        event.server.id
      elsif event.respond_to?(:interaction) && event.interaction
        event.interaction.server_id
      end
    end
```

In both `handle_gym_poll_vote` and `handle_gym_poll_reset`, replace `poll = GymPoll.find_by(id: poll_id)` with:

```ruby
      poll = GymPoll.for_guild(event_guild_id(event)).find_by(id: poll_id)
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `bin/rails test test/models/gym_draft_test.rb test/models/gym_poll_test.rb test/channels test/controllers/gym_drafts_controller_test.rb test/integration/gym_poll_flow_test.rb`
Expected: 0 failures, 0 errors.

- [ ] **Step 9: Commit**

```bash
git add app/models/gym_draft.rb app/models/gym_poll.rb app/channels app/controllers/gym_drafts_controller.rb app/services/soul_link/discord_bot.rb test
git commit -m "fix: scope gym draft and poll access to the session's guild"
```

---

### Task 6: Restore CSRF verification on save slots

**Files:**
- Modify: `app/controllers/save_slots_controller.rb:20-27`
- Modify: `test/controllers/save_slots_controller_test.rb:162-172`

- [ ] **Step 1: Replace the bypass test with failing tests**

In `test/controllers/save_slots_controller_test.rb`, replace the whole test `"create succeeds without CSRF token (null_session bypass)"` with:

```ruby
  test "writes without a CSRF token are rejected when forgery protection is on" do
    login_as(GREY)

    with_forgery_protection do
      post emulator_save_slots_path, params: "BYTES".b,
           headers: { "Content-Type" => "application/octet-stream" }
      assert_response :unprocessable_entity, "create"

      patch emulator_save_slot_path(slot_number: 1), params: "BYTES".b,
            headers: { "Content-Type" => "application/octet-stream" }
      assert_response :unprocessable_entity, "update"

      delete emulator_save_slot_path(slot_number: 1)
      assert_response :unprocessable_entity, "destroy"

      post restore_emulator_save_slot_path(slot_number: 1)
      assert_response :unprocessable_entity, "restore"
    end
  end

  test "create with the page's CSRF token succeeds when forgery protection is on" do
    login_as(GREY)

    with_forgery_protection do
      get emulator_path
      token = css_select("meta[name=csrf-token]").first["content"]

      post emulator_save_slots_path, params: "BYTES_WITH_CSRF".b,
           headers: { "Content-Type" => "application/octet-stream", "X-CSRF-Token" => token }
    end

    assert_response :created
  end
```

- [ ] **Step 2: Run them to verify the first fails**

Run: `bin/rails test test/controllers/save_slots_controller_test.rb -n "/forgery protection/"`
Expected: the "rejected" test fails (`Expected response to be a <422>, but was a <201>`); the "succeeds" test passes.

- [ ] **Step 3: Remove the override**

In `app/controllers/save_slots_controller.rb`, delete these lines (and the blank line after them):

```ruby
  # The binary upload endpoints (POST create, PATCH update) carry an
  # octet-stream body that can't ride the standard form-CSRF token. The
  # Stimulus controllers send `X-CSRF-Token` for belt-and-suspenders, but we
  # accept the request even without one. DELETE / restore go through the
  # standard CSRF path.
  protect_from_forgery with: :null_session,
                       only: [ :create, :update ],
                       if: -> { request.post? || request.patch? }
```

The inherited protection from `ApplicationController` now applies. All client call sites (`save_slots_controller.js`, `emulator_controller.js`) already send `X-CSRF-Token`.

- [ ] **Step 4: Run the controller tests**

Run: `bin/rails test test/controllers/save_slots_controller_test.rb test/controllers/emulator_controller_test.rb`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/save_slots_controller.rb test/controllers/save_slots_controller_test.rb
git commit -m "fix: verify CSRF tokens on every save slot write"
```

---

### Task 7: Lock gym draft and poll state changes

Implements spec 3.1. It comes before the read-only tasks because the read-only check goes inside these locks.

**Files:**
- Modify: `app/models/gym_draft.rb` (`mark_ready!`, `cast_vote!`, `make_pick!`, `nominate!`, `skip_turn!`)
- Modify: `app/models/gym_poll.rb` (`vote!`)
- Test: `test/models/gym_draft_test.rb`, `test/models/gym_poll_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/models/gym_draft_test.rb`:

```ruby
  test "mark_ready! from a stale instance keeps the other player's ready mark" do
    stale = GymDraft.find(@draft.id)

    @draft.mark_ready!(GREY)
    stale.mark_ready!(ARATY)

    assert_equal [ GREY, ARATY ], @draft.reload.ready_players
  end
```

Add to `test/models/gym_poll_test.rb` (inside `GymPollVoteTest`):

```ruby
  test "vote! from a stale instance keeps the other player's vote" do
    poll = open_poll
    stale = GymPoll.find(poll.id)

    with_player_ids do
      poll.vote!(111, 0, "yes")
      stale.vote!(222, 0, "maybe")
    end

    votes = poll.reload.votes
    assert_equal "yes", votes["111"]["0"]
    assert_equal "maybe", votes["222"]["0"]
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bin/rails test test/models/gym_draft_test.rb test/models/gym_poll_test.rb -n "/stale instance/"`
Expected: 2 failures; the first player's write is lost.

- [ ] **Step 3: Lock the draft actions**

In `app/models/gym_draft.rb`, wrap the body of each of these five methods in `with_lock do ... end`: `mark_ready!`, `cast_vote!`, `make_pick!`, `nominate!`, `skip_turn!`. `with_lock` reloads the row under `SELECT ... FOR UPDATE` inside a transaction, so the phase checks and the JSON read-modify-write see the latest state. Also add this comment above `# ── Actions ──`:

```ruby
  # Every action runs inside `with_lock`: it reloads the row under
  # SELECT ... FOR UPDATE, so two players acting at once can't overwrite each
  # other's changes to the JSON state.
```

`mark_ready!` becomes:

```ruby
  def mark_ready!(uid)
    with_lock do
      raise "Not in lobby" unless lobby?
      rp = ready_players
      rp << uid.to_i unless rp.include?(uid.to_i)
      update_data!("ready_players" => rp)

      if all_players_ready?
        update!(status: "voting")
      end
    end
  end
```

`cast_vote!` becomes:

```ruby
  def cast_vote!(voter_uid, voted_for_uid)
    with_lock do
      raise "Not in voting phase" unless voting?
      votes = first_pick_votes
      votes[voter_uid.to_s] = voted_for_uid.to_i
      update_data!("first_pick_votes" => votes)

      if all_voted?
        resolve_votes!
      end
    end
  end
```

For `make_pick!`, `nominate!` and `skip_turn!`, insert `with_lock do` as the first line of the method body and a matching `end` before the method's closing `end`, then re-indent the body two spaces. No other lines change (the `reload` inside `nominate!` stays; it runs under the lock).

- [ ] **Step 4: Lock the poll vote**

In `app/models/gym_poll.rb`, `vote!` becomes:

```ruby
  def vote!(user_id, slot_index, response)
    with_lock do
      raise LockedError, "Poll is locked — reset to vote again" if locked?
      raise InvalidResponseError, "Response must be yes, maybe, or no" unless VALID_RESPONSES.include?(response)

      slot = slots.find { |s| s["index"].to_i == slot_index.to_i }
      raise InvalidSlotError, "Slot #{slot_index} does not exist on this poll" unless slot
      raise PastSlotError, "Slot has already passed" if Time.iso8601(slot["scheduled_at"]) < Time.current

      user_key  = user_id.to_s
      slot_key  = slot_index.to_s
      next_data = data.deep_dup
      next_data["votes"][user_key] ||= {}
      next_data["votes"][user_key][slot_key] = response

      if all_yes_on_slot?(next_data, slot_index)
        update!(
          state_data:        next_data.as_json,
          status:            "locked",
          locked_slot_index: slot_index.to_i,
          locked_at:         Time.current
        )
      else
        update!(state_data: next_data.as_json)
      end
    end
    true
  end
```

- [ ] **Step 5: Run the draft and poll tests**

Run: `bin/rails test test/models/gym_draft_test.rb test/models/gym_poll_test.rb test/channels test/integration/gym_poll_flow_test.rb test/jobs`
Expected: 0 failures, 0 errors.

If a test errors with `Locking a record with unpersisted changes is not supported`, that test assigned attributes without saving before calling an action; save them in the test (`update!` instead of `=`) rather than changing the model.

- [ ] **Step 6: Commit**

```bash
git add app/models/gym_draft.rb app/models/gym_poll.rb test/models/gym_draft_test.rb test/models/gym_poll_test.rb
git commit -m "fix: lock gym draft and poll rows so concurrent actions do not lose writes"
```

---

### Task 8: Read-only runs: model contract and web endpoints

**Files:**
- Modify: `app/models/soul_link_run.rb` (after `TIME_OF_DAY_FORMAT`, and after `read_only?`)
- Create: `app/controllers/concerns/run_write_guard.rb`
- Modify: `app/controllers/application_controller.rb`
- Modify: `pokemon_groups_controller.rb`, `pokemon_controller.rb`, `species_assignments_controller.rb`, `teams_controller.rb`, `gym_progress_controller.rb`, `gym_drafts_controller.rb`, `gym_results_controller.rb`, `gym_polls_controller.rb`
- Test: `test/models/soul_link_run_test.rb`, create `test/integration/read_only_run_test.rb`, `test/channels/run_channel_test.rb`

- [ ] **Step 1: Write the failing model test**

Add to `test/models/soul_link_run_test.rb` (inside the main test class):

```ruby
  test "ensure_writable! refuses a wiped run unless it also completed" do
    run = create(:soul_link_run)
    assert_nothing_raised { run.ensure_writable! }

    run.update!(wiped_at: Time.current)
    error = assert_raises(SoulLinkRun::ReadOnlyError) { run.ensure_writable! }
    assert_equal SoulLinkRun::READ_ONLY_MESSAGE, error.message

    run.update!(completed_at: Time.current)
    assert_nothing_raised { run.ensure_writable! }
  end
```

- [ ] **Step 2: Write the failing endpoint tests**

Create `test/integration/read_only_run_test.rb`:

```ruby
require "test_helper"

# Server-side read-only mode: once a run has wiped (and not completed), every
# write to its data is refused. Reviving is the exception; see the revive
# tests at the bottom.
class ReadOnlyRunTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  setup do
    @run = create(:soul_link_run, wiped_at: 1.day.ago)
    @group = create(:soul_link_pokemon_group, soul_link_run: @run)
    @pokemon = create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: @group,
                      discord_user_id: GREY)
    login_as(GREY)
  end

  test "JSON writes to a wiped run are refused with 403" do
    requests = {
      "create group"   => -> { post pokemon_groups_path, params: { nickname: "X", location: "route_201" }, as: :json },
      "edit group"     => -> { patch pokemon_group_path(@group), params: { nickname: "Y" }, as: :json },
      "reorder groups" => -> { patch reorder_pokemon_groups_path, params: { group_ids: [ @group.id ] }, as: :json },
      "delete group"   => -> { delete pokemon_group_path(@group), as: :json },
      "add pokemon"    => -> { post pokemon_index_path, params: { group_id: @group.id, species: "Bidoof" }, as: :json },
      "edit pokemon"   => -> { patch pokemon_path(@pokemon), params: { level: 9 }, as: :json },
      "assign species" => -> { patch assign_species_path, params: {}, as: :json },
      "team slots"     => -> { patch update_slots_team_path, params: { group_ids: [] }, as: :json },
      "gym progress"   => -> { patch gym_progress_path, params: { gym_number: 1 }, as: :json },
      "gym result"     => -> { patch gym_result_path(1), params: { group_ids: [ @group.id ] }, as: :json }
    }

    requests.each do |label, request|
      request.call
      assert_response :forbidden, label
      assert_equal SoulLinkRun::READ_ONLY_MESSAGE, response.parsed_body["error"], label
    end
    assert SoulLinkPokemonGroup.exists?(@group.id)
    assert_equal @group.nickname, @group.reload.nickname
  end

  test "form writes to a wiped run redirect to the dashboard with the alert" do
    draft = create(:gym_draft, soul_link_run: @run)
    requests = {
      "start draft"  => -> { post gym_drafts_path },
      "delete draft" => -> { delete gym_draft_path(draft) },
      "mark beaten"  => -> { post mark_beaten_gym_draft_path(draft) },
      "start poll"   => -> { post gym_poll_path },
      "reset poll"   => -> { delete gym_poll_path }
    }

    requests.each do |label, request|
      request.call
      assert_redirected_to root_path, label
      assert_equal SoulLinkRun::READ_ONLY_MESSAGE, flash[:alert], label
    end
    assert GymDraft.exists?(draft.id)
  end

  test "a run that wiped after completing stays editable" do
    @run.update!(completed_at: Time.current)

    patch pokemon_group_path(@group), params: { nickname: "Y" }, as: :json

    assert_response :success
    assert_equal "Y", @group.reload.nickname
  end

  test "a live run is unaffected" do
    @run.update!(wiped_at: nil)

    patch pokemon_group_path(@group), params: { nickname: "Y" }, as: :json

    assert_response :success
  end
end
```

Add to `test/channels/run_channel_test.rb`:

```ruby
  test "end_run still works on a wiped run" do
    @run.update!(wiped_at: Time.current)
    subscribe(guild_id: GUILD_ID)

    perform :end_run

    assert_not @run.reload.active?
  end
```

- [ ] **Step 3: Run them to verify they fail**

Run: `bin/rails test test/models/soul_link_run_test.rb test/integration/read_only_run_test.rb test/channels/run_channel_test.rb`
Expected: the model test errors (`uninitialized constant SoulLinkRun::ReadOnlyError`); the two refusal tests fail (writes succeed); the other tests pass.

- [ ] **Step 4: Add the model contract**

In `app/models/soul_link_run.rb`, after `TIME_OF_DAY_FORMAT = ...`:

```ruby

  READ_ONLY_MESSAGE = "This run has wiped and is read-only.".freeze

  # Raised by `ensure_writable!`. Callers that report errors to players use
  # its message as-is.
  class ReadOnlyError < StandardError
    def initialize(message = READ_ONLY_MESSAGE)
      super
    end
  end
```

Replace the comment above `read_only?` (the `# Step 19 — read-only mode ...` block) with:

```ruby
  # Read-only mode: true when the run is wiped AND not yet completed (HoF
  # wins — a run that wipes after HoF is "complete" first). Enforced on the
  # server by `ensure_writable!`; the dashboard also hides write controls via
  # `dashboard_read_only?`.
```

and add after the `read_only?` method:

```ruby

  # Called before any write to run data from the website, the bot, live
  # channels or save parsing. Ending or starting a run, emulator saves and
  # ROM downloads are not run data and stay allowed.
  def ensure_writable!
    raise ReadOnlyError if read_only?
  end
```

- [ ] **Step 5: Add the controller guard**

Create `app/controllers/concerns/run_write_guard.rb`:

```ruby
# Refuses writes to the current run while it is read-only (wiped). Controllers
# opt in per action:
#
#   before_action :require_writable_run!, only: %i[create update]
#
# JSON requests get a 403 with the message; form submissions are redirected
# to the dashboard with it as the alert.
module RunWriteGuard
  extend ActiveSupport::Concern

  private

  def require_writable_run!
    return unless SoulLinkRun.current(session[:guild_id])&.read_only?

    if request.format.json? || request.content_mime_type&.json?
      render json: { error: SoulLinkRun::READ_ONLY_MESSAGE }, status: :forbidden
    else
      redirect_to root_path, alert: SoulLinkRun::READ_ONLY_MESSAGE
    end
  end
end
```

In `app/controllers/application_controller.rb`, add `include RunWriteGuard` below `include DiscordAuthentication`.

- [ ] **Step 6: Apply it to the write actions**

Add the line directly below each controller's `before_action :require_login`:

| Controller | Line to add |
|---|---|
| `pokemon_groups_controller.rb` | `before_action :require_writable_run!` |
| `pokemon_controller.rb` | `before_action :require_writable_run!` |
| `species_assignments_controller.rb` | `before_action :require_writable_run!, except: :show` |
| `teams_controller.rb` | `before_action :require_writable_run!, only: :update_slots` |
| `gym_progress_controller.rb` | `before_action :require_writable_run!` |
| `gym_drafts_controller.rb` | `before_action :require_writable_run!, only: %i[create destroy mark_beaten]` |
| `gym_results_controller.rb` | `before_action :require_writable_run!` |
| `gym_polls_controller.rb` | `before_action :require_writable_run!, only: %i[create destroy]` |

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bin/rails test test/models/soul_link_run_test.rb test/integration test/controllers test/channels/run_channel_test.rb`
Expected: 0 failures, 0 errors.

- [ ] **Step 8: Commit**

```bash
git add app/models/soul_link_run.rb app/controllers test/models/soul_link_run_test.rb test/integration/read_only_run_test.rb test/channels/run_channel_test.rb
git commit -m "fix: refuse web writes to a wiped run on the server"
```

---

### Task 9: Read-only runs: live channels, bot and save parsing

**Files:**
- Modify: `app/models/gym_draft.rb` (five actions), `app/models/gym_poll.rb` (`vote!`)
- Modify: `app/channels/gym_poll_channel.rb` (`reset`)
- Modify: `app/services/soul_link/discord_bot.rb` (`apply_catch_quick_add`, `apply_catch_create`, `apply_mark_dead`, `handle_species_submission`, `handle_uncaught_death_submission`, `/new_gym_poll`, `/reset_gym_poll`, `handle_gym_poll_vote`, `handle_gym_poll_reset`)
- Modify: `app/services/soul_link/catch_coordinator.rb:58`, `gym_beaten_coordinator.rb:30`, `hall_of_fame_coordinator.rb:21`
- Test: `test/models/gym_draft_test.rb`, `test/models/gym_poll_test.rb`, `test/channels/gym_draft_channel_test.rb`, `test/channels/gym_poll_channel_test.rb`, `test/services/soul_link/catch_quick_add_test.rb`, `catch_create_test.rb`, `mark_dead_test.rb`, `catch_coordinator_test.rb`, `gym_beaten_coordinator_test.rb`, `hall_of_fame_coordinator_test.rb`

- [ ] **Step 1: Write the failing tests**

`test/models/gym_draft_test.rb`:

```ruby
  test "actions on a wiped run raise ReadOnlyError and change nothing" do
    @run.update!(wiped_at: Time.current)

    assert_raises(SoulLinkRun::ReadOnlyError) { @draft.mark_ready!(GREY) }
    assert_empty @draft.reload.ready_players
  end
```

`test/models/gym_poll_test.rb` (inside `GymPollVoteTest`):

```ruby
  test "vote! on a wiped run raises ReadOnlyError" do
    poll = open_poll
    poll.soul_link_run.update!(wiped_at: Time.current)

    with_player_ids do
      assert_raises(SoulLinkRun::ReadOnlyError) { poll.vote!(111, 0, "yes") }
    end
    assert_empty poll.reload.votes
  end
```

`test/channels/gym_draft_channel_test.rb`:

```ruby
  test "actions on a wiped run transmit the read-only error" do
    subscribe(draft_id: @draft.id)
    @run.update!(wiped_at: Time.current)

    perform :ready

    assert_equal SoulLinkRun::READ_ONLY_MESSAGE, transmissions.last["error"]
    assert_empty @draft.reload.ready_players
  end
```

`test/channels/gym_poll_channel_test.rb`:

```ruby
  test "vote and reset on a wiped run transmit the read-only error" do
    @poll.soul_link_run.update!(wiped_at: Time.current)

    with_player_data do
      subscribe(id: @poll.id)
      perform :vote, { "slot_index" => 0, "response" => "yes" }
      perform :reset, {}
    end

    errors = transmissions.select { |t| t["type"] == "error" }.map { |t| t["message"] }
    assert_equal [ SoulLinkRun::READ_ONLY_MESSAGE ] * 2, errors
    assert GymPoll.exists?(@poll.id)
  end
```

`test/services/soul_link/catch_create_test.rb`:

```ruby
    test "refuses to create a catch on a wiped run" do
      @run.update!(wiped_at: Time.current)

      result = SoulLink::DiscordBot.apply_catch_create(
        run: @run, nickname: "TOMMY", location: "route_205",
        species: "Staravia", discord_user_id: @uid
      )

      assert_not result[:ok]
      assert_equal SoulLinkRun::READ_ONLY_MESSAGE, result[:error]
      assert_equal 0, @run.soul_link_pokemon_groups.count
    end
```

`test/services/soul_link/catch_quick_add_test.rb` (its `setup` defines `@run`, `@group` and `@uid`):

```ruby
    test "refuses to add a species on a wiped run" do
      @run.update!(wiped_at: Time.current)

      result = SoulLink::DiscordBot.apply_catch_quick_add(
        run: @run, group_id: @group.id, discord_user_id: @uid, species_input: "Bidoof"
      )

      assert_not result[:ok]
      assert_equal SoulLinkRun::READ_ONLY_MESSAGE, result[:error]
    end
```

`test/services/soul_link/mark_dead_test.rb`:

```ruby
    test "refuses on a wiped run" do
      @run.update!(wiped_at: Time.current)

      result = apply

      assert_not result[:ok]
      assert_equal SoulLinkRun::READ_ONLY_MESSAGE, result[:error]
      assert @group.reload.caught?
    end
```

`test/services/soul_link/catch_coordinator_test.rb`:

```ruby
    test "no-op on a wiped run" do
      @run.update!(wiped_at: Time.current)

      assert_no_difference "SoulLinkPokemon.count" do
        SoulLink::CatchCoordinator.process(@slot, [ caught_event ])
      end
    end
```

`test/services/soul_link/gym_beaten_coordinator_test.rb`:

```ruby
    test "BadgeGained on a wiped run → no gym_results created" do
      @slots.each { |slot| slot.update_columns(parsed_badges: 4) }
      @run.update!(wiped_at: Time.current)

      assert_no_difference "@run.gym_results.count" do
        SoulLink::GymBeatenCoordinator.process(@slots.first, [ event(SoulLink::SaveDiff::BadgeGained, 4) ])
      end
    end
```

`test/services/soul_link/hall_of_fame_coordinator_test.rb`:

```ruby
    test "wiped run → no-op even when 4/4 satisfy" do
      @slots.each { |slot| slot.update_columns(parsed_hof_count: 1) }
      @run.update!(wiped_at: Time.current)

      SoulLink::HallOfFameCoordinator.process(@slots.first, [ event ])

      assert_nil @run.reload.completed_at
    end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bin/rails test test/models/gym_draft_test.rb test/models/gym_poll_test.rb test/channels test/services/soul_link`
Expected: the 11 new tests fail; everything else passes.

- [ ] **Step 3: Guard the draft and poll models**

In `app/models/gym_draft.rb`, add `soul_link_run.ensure_writable!` as the first line inside `with_lock do` in each of the five actions. For example:

```ruby
  def mark_ready!(uid)
    with_lock do
      soul_link_run.ensure_writable!
      raise "Not in lobby" unless lobby?
```

In `app/models/gym_poll.rb#vote!`, likewise:

```ruby
    with_lock do
      soul_link_run.ensure_writable!
      raise LockedError, "Poll is locked — reset to vote again" if locked?
```

Update the comment added in Task 7 above `# ── Actions ──` to:

```ruby
  # Every action runs inside `with_lock`: it reloads the row under
  # SELECT ... FOR UPDATE, so two players acting at once can't overwrite each
  # other's changes to the JSON state. Actions are refused once the run is
  # read-only (wiped).
```

`GymDraftChannel` needs no change: its `rescue => e` already transmits `e.message`.

- [ ] **Step 4: Guard the poll channel's reset**

In `app/channels/gym_poll_channel.rb#reset`, after `@poll.reload`:

```ruby
    @poll.soul_link_run.ensure_writable!
```

- [ ] **Step 5: Guard the bot's pure cores**

In `app/services/soul_link/discord_bot.rb`, add as the first line of `self.apply_catch_quick_add`, `self.apply_catch_create` and `self.apply_mark_dead`:

```ruby
      return { ok: false, error: SoulLinkRun::READ_ONLY_MESSAGE } if run&.read_only?
```

(In `apply_catch_create` it goes before the existing `return { ok: false, error: "No active run found." } if run.nil?`.)

- [ ] **Step 6: Guard the bot handlers that write directly**

These handlers have no pure core and no tests; each gets the same guard right after its existing "no active run" check.

In `handle_species_submission` and `handle_uncaught_death_submission`, after the `unless run ... end` block:

```ruby
      if run.read_only?
        respond_ephemeral(event, "❌ #{SoulLinkRun::READ_ONLY_MESSAGE}")
        return
      end
```

In the `/new_gym_poll` and `/reset_gym_poll` command blocks, after the `unless run ... next end` block:

```ruby
        if run.read_only?
          event.edit_response(content: "❌ #{SoulLinkRun::READ_ONLY_MESSAGE}")
          next
        end
```

In `handle_gym_poll_vote`, add `SoulLinkRun::ReadOnlyError` to the rescue list:

```ruby
      rescue GymPoll::LockedError, GymPoll::InvalidSlotError, GymPoll::PastSlotError,
             GymPoll::InvalidResponseError, SoulLinkRun::ReadOnlyError => e
```

In `handle_gym_poll_reset`, after the `return respond_ephemeral(event, "❌ Poll not found.") unless poll` line:

```ruby
      return respond_ephemeral(event, "❌ #{SoulLinkRun::READ_ONLY_MESSAGE}") if poll.soul_link_run.read_only?
```

- [ ] **Step 7: Guard save parsing**

- `app/services/soul_link/catch_coordinator.rb` in `self.process`: `return if run.nil?` → `return if run.nil? || run.read_only?`
- `app/services/soul_link/gym_beaten_coordinator.rb` in `self.process`: `return if run.nil? || !run.active?` → `return if run.nil? || !run.active? || run.read_only?`
- `app/services/soul_link/hall_of_fame_coordinator.rb` in `self.process`: `return if run.nil? || !run.active? || run.completed_at.present?` → `return if run.nil? || !run.active? || run.completed_at.present? || run.read_only?`

- [ ] **Step 8: Run the tests to verify they pass**

Run: `bin/rails test test/models test/channels test/services/soul_link test/jobs`
Expected: 0 failures, 0 errors.

- [ ] **Step 9: Commit**

```bash
git add app/models app/channels app/services test
git commit -m "fix: refuse bot, live channel and save-parse writes to a wiped run"
```

---

### Task 10: Revive undoes a wipe

**Files:**
- Modify: `app/services/soul_link/wipe_coordinator.rb` (add `self.reconsider`)
- Modify: `app/controllers/pokemon_groups_controller.rb` (guard exemption, revive branch)
- Modify: `app/views/dashboard/_pokemon_modal.html.erb:137-154`
- Modify: `app/javascript/controllers/pixeldex_controller.js` (targets, `#openModal`, new `revivePokemon`)
- Test: `test/services/soul_link/wipe_coordinator_test.rb`, `test/integration/read_only_run_test.rb`

- [ ] **Step 1: Write the failing coordinator tests**

Add to `test/services/soul_link/wipe_coordinator_test.rb`:

```ruby
    test "reconsider clears the wipe once no player is wiped" do
      pokemon(PLAYERS[0], status: "caught")
      @run.update!(wiped_at: Time.current)

      SoulLink::WipeCoordinator.reconsider(@run)

      assert_nil @run.reload.wiped_at
    end

    test "reconsider keeps the wipe while another player is still wiped" do
      pokemon(PLAYERS[0], status: "caught")
      pokemon(PLAYERS[1], status: "dead", died_at: 1.day.ago)
      @run.update!(wiped_at: Time.current)

      SoulLink::WipeCoordinator.reconsider(@run)

      assert @run.reload.wiped_at.present?
    end

    test "reconsider leaves a run that is not wiped alone" do
      pokemon(PLAYERS[0], status: "dead", died_at: 1.day.ago)

      SoulLink::WipeCoordinator.reconsider(@run)

      assert_nil @run.reload.wiped_at
    end
```

- [ ] **Step 2: Write the failing revive request tests**

Add to `test/integration/read_only_run_test.rb`:

```ruby
  test "reviving a dead group on a wiped run is allowed and lifts the wipe" do
    @group.mark_as_dead!

    SoulLink::DeathMessage.stub(:delete, nil) do
      SoulLink::DeathsPanel.stub(:refresh, nil) do
        patch pokemon_group_path(@group), params: { status: "caught" }, as: :json
      end
    end

    assert_response :success
    assert @group.reload.caught?
    assert_nil @run.reload.wiped_at
  end

  test "editing a dead group on a wiped run is still refused" do
    @group.mark_as_dead!

    patch pokemon_group_path(@group), params: { nickname: "Z" }, as: :json

    assert_response :forbidden
  end

  test "the pokemon modal offers REVIVE but not MARK DEAD on a wiped run" do
    get root_path

    assert_select "[data-pixeldex-target=modalReviveBtn]", 1
    assert_select "[data-pixeldex-target=modalDeadBtn]", 0
  end
```

- [ ] **Step 3: Run them to verify they fail**

Run: `bin/rails test test/services/soul_link/wipe_coordinator_test.rb test/integration/read_only_run_test.rb`
Expected: the reconsider tests error (`undefined method 'reconsider'`); the revive test gets 403; the modal test finds no REVIVE button. The "still refused" test passes already.

- [ ] **Step 4: Add `reconsider`**

In `app/services/soul_link/wipe_coordinator.rb`, add after `self.process`:

```ruby

    # Clears a wipe once no player meets the wipe rule any more. Called after
    # a revive so a mistaken Mark Dead can be undone. Sends no Discord
    # message; the original wipe announcement stays in the channel.
    def self.reconsider(run)
      return if run.nil? || run.wiped_at.nil?

      run.with_lock do
        return if run.wiped_at.nil?

        uid, _route = wiping_player_and_route(run)
        run.update!(wiped_at: nil) if uid.nil?
      end
      nil
    end
```

- [ ] **Step 5: Exempt revive in the controller and reconsider after it**

In `app/controllers/pokemon_groups_controller.rb`, change the guard added in Task 8:

```ruby
  before_action :require_writable_run!, unless: :revive_request?
```

In `update`'s revive branch, after `SoulLink::DeathsPanel.refresh(run)`:

```ruby

      # A revive may be undoing the Mark Dead that wiped the run.
      SoulLink::WipeCoordinator.reconsider(run)
```

In the `private` section, add:

```ruby

  # Reviving a dead group stays allowed on a wiped run, so a mistaken Mark
  # Dead can be undone (see WipeCoordinator.reconsider).
  def revive_request?
    action_name == "update" && params[:status] == "caught" &&
      current_run&.soul_link_pokemon_groups&.dead&.exists?(id: params[:id])
  end
```

- [ ] **Step 6: Add the REVIVE button**

In `app/views/dashboard/_pokemon_modal.html.erb`, inside `<div style="display: flex; gap: 6px;">`, add before the `<%# Step 19 — hide the Mark Dead trigger ... %>` comment:

```erb
          <%# Shown by pixeldex#openModal for dead groups, including on a
              wiped run, where reviving can lift the wipe. %>
          <button type="button"
                  data-pixeldex-target="modalReviveBtn"
                  data-action="click->pixeldex#revivePokemon"
                  class="gb-btn gb-btn-sm hidden">
            REVIVE
          </button>
```

and change that comment's text to:

```erb
          <%# Step 19 — hide the Mark Dead trigger when the run is in
              read-only mode (already wiped). The server refuses it too. %>
```

In `app/javascript/controllers/pixeldex_controller.js`:

1. Add `"modalReviveBtn"` to `static targets`, after `"modalDeadBtn"`.
2. In `#openModal`, replace:

```js
    if (status === "dead") {
      this.modalDeadBtnTarget.classList.add("hidden")
    } else {
      this.modalDeadBtnTarget.classList.remove("hidden")
      this.modalDeadBtnTarget.dataset.groupId = groupId
      this.modalDeadBtnTarget.dataset.groupNickname = nickname
    }
```

with:

```js
    // MARK DEAD isn't rendered on a read-only run, so guard the target.
    if (this.hasModalDeadBtnTarget) {
      this.modalDeadBtnTarget.classList.toggle("hidden", status === "dead")
      this.modalDeadBtnTarget.dataset.groupId = groupId
      this.modalDeadBtnTarget.dataset.groupNickname = nickname
    }
    if (this.hasModalReviveBtnTarget) {
      this.modalReviveBtnTarget.classList.toggle("hidden", status !== "dead")
    }
```

3. Add after `savePokemon`:

```js
  async revivePokemon(event) {
    const groupId = this.modalGroupIdTarget.value
    if (!groupId) return

    const reviveBtn = event.currentTarget
    reviveBtn.disabled = true
    this.modalStatusTarget.textContent = "REVIVING..."

    try {
      await this.#updateGroupStatus(groupId, "caught")
      window.location.reload()
    } catch (error) {
      this.modalStatusTarget.textContent = error.message || "REVIVE FAILED"
      reviveBtn.disabled = false
    }
  }
```

(`#updateGroupStatus` already exists; it throws with the server's error message on a non-2xx response.)

- [ ] **Step 7: Syntax-check the JS and run the tests**

Run:

```bash
cp app/javascript/controllers/pixeldex_controller.js tmp/pixeldex_check.mjs && node --check tmp/pixeldex_check.mjs && rm tmp/pixeldex_check.mjs
bin/rails test test/services/soul_link/wipe_coordinator_test.rb test/integration test/controllers/pokemon_groups_controller_test.rb
```

Expected: `node --check` prints nothing; 0 failures, 0 errors.

- [ ] **Step 8: Commit**

```bash
git add app/services/soul_link/wipe_coordinator.rb app/controllers/pokemon_groups_controller.rb app/views/dashboard/_pokemon_modal.html.erb app/javascript/controllers/pixeldex_controller.js test
git commit -m "feat: revive a dead group to undo a mistaken wipe"
```

- [ ] **Step 9: Batch 2 checkpoint**

Run: `bin/rails test > tmp/test_full.txt 2>&1; grep -E "runs, .*assertions" tmp/test_full.txt`
Expected: `0 failures, 0 errors`.

---

# Batch 3: jobs and small fixes

### Task 11: Generate emulator ROMs under the run lock

**Files:**
- Modify: `app/jobs/soul_link/generate_run_roms_job.rb:14-17`
- Test: `test/jobs/soul_link/generate_run_roms_job_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/jobs/soul_link/generate_run_roms_job_test.rb`:

```ruby
    test "checks the session count and creates sessions under the run's row lock" do
      lock_calls = 0
      with_randomizer_stub(succeed_quietly) do
        @run.stub(:with_lock, ->(&block) { lock_calls += 1; block.call }) do
          SoulLink::GenerateRunRomsJob.perform_now(@run)
        end
      end

      assert_equal 1, lock_calls
      assert_equal 4, SoulLinkEmulatorSession.where(soul_link_run_id: @run.id).count
    end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/jobs/soul_link/generate_run_roms_job_test.rb -n "/row lock/"`
Expected: FAIL, `Expected: 1 Actual: 0`.

- [ ] **Step 3: Take the lock**

Replace:

```ruby
    def perform(soul_link_run)
      return if SoulLinkEmulatorSession.where(soul_link_run_id: soul_link_run.id).count >= SESSIONS_PER_RUN

      sessions = create_sessions(soul_link_run)
```

with:

```ruby
    def perform(soul_link_run)
      # Check and create under the run's row lock, so a double enqueue can't
      # create eight sessions.
      sessions = soul_link_run.with_lock do
        next [] if SoulLinkEmulatorSession.where(soul_link_run_id: soul_link_run.id).count >= SESSIONS_PER_RUN

        create_sessions(soul_link_run)
      end
```

Update the class comment line `# Idempotent on count: re-enqueueing ...` to read: `# Idempotent on count, checked under the run's row lock: re-enqueueing for a run that already has 4 sessions`.

- [ ] **Step 4: Run the job tests**

Run: `bin/rails test test/jobs/soul_link/generate_run_roms_job_test.rb test/channels/run_channel_test.rb`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/soul_link/generate_run_roms_job.rb test/jobs/soul_link/generate_run_roms_job_test.rb
git commit -m "fix: create emulator sessions under the run lock"
```

---

### Task 12: Refresh the roster card after a save is parsed

**Files:**
- Modify: `app/models/soul_link_emulator_save_slot.rb:22-32,55-74`
- Modify: `app/jobs/soul_link/parse_save_data_job.rb:19-22,76-78`
- Test: `test/jobs/soul_link/parse_save_data_job_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/jobs/soul_link/parse_save_data_job_test.rb` after the KG-13 test:

```ruby
    test "re-broadcasts the slot's roster card after writing parsed fields" do
      @slot.update!(save_data: "\x00".b * 0x80000)
      calls = 0

      @slot.stub(:broadcast_roster_card, -> { calls += 1 }) do
        SoulLink::SaveParser.stub(:parse, nil) do
          SoulLink::ParseSaveDataJob.perform_now(@slot)
        end
      end

      assert_equal 1, calls
    end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/jobs/soul_link/parse_save_data_job_test.rb -n "/roster card/"`
Expected: ERROR, `NameError` (the method is private, so it can't be stubbed), which also shows the job never calls it.

- [ ] **Step 3: Make the broadcast public**

In `app/models/soul_link_emulator_save_slot.rb`, move the `broadcast_roster_card` method out of the `private` section to just above `private`, with this comment:

```ruby
  # Re-renders the owning session's roster card on the emulator page.
  # Public because ParseSaveDataJob calls it: the job writes parsed_* with
  # `update_columns`, which skips the update-commit callback above.
  def broadcast_roster_card
    session = soul_link_emulator_session
    return unless session
    run = session.soul_link_run
    return unless run
    Turbo::StreamsChannel.broadcast_replace_to(
      run, :emulator,
      target: "emulator_roster_session_#{session.id}",
      partial: "emulator/run_sidebar_card",
      locals: { s: session }
    )
  end
```

Keep both callbacks and their private wrappers unchanged; `soul_link_emulator_save_slot_test.rb` covers them.

- [ ] **Step 4: Call it from the job**

In `app/jobs/soul_link/parse_save_data_job.rb#perform`, add as the last line of the method (after the `if result ... else ... end` block):

```ruby

      slot.broadcast_roster_card
```

In the class comment, replace the `**Critical**` paragraph with:

```ruby
  # **Critical**: writes via `update_columns` so the after_update_commit
  # callback that enqueued *this* job does not refire and create an
  # infinite loop. Because that also skips the model's broadcast, the job
  # re-renders the roster card itself at the end.
```

- [ ] **Step 5: Run the tests**

Run: `bin/rails test test/jobs/soul_link/parse_save_data_job_test.rb test/models/soul_link_emulator_save_slot_test.rb test/controllers/save_slots_controller_test.rb`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/models/soul_link_emulator_save_slot.rb app/jobs/soul_link/parse_save_data_job.rb test
git commit -m "fix: refresh the emulator roster card after a save is parsed"
```

---

### Task 13: Job robustness

**Files:**
- Modify: `app/jobs/application_job.rb`, `app/jobs/gym_poll_lock_job.rb`, `app/jobs/gym_poll_discord_sync_job.rb`
- Test: `test/jobs/soul_link/parse_save_data_job_test.rb`, `test/jobs/gym_poll_lock_job_test.rb`, `test/jobs/gym_poll_discord_sync_job_test.rb`

- [ ] **Step 1: Write the failing tests**

`test/jobs/soul_link/parse_save_data_job_test.rb`:

```ruby
    test "a job for a slot deleted before it runs is discarded" do
      SoulLink::ParseSaveDataJob.perform_later(@slot)
      @slot.destroy!

      assert_nothing_raised { perform_enqueued_jobs }
    end
```

`test/jobs/gym_poll_lock_job_test.rb`:

```ruby
  test "does nothing when the locked slot index matches no slot" do
    @poll.update_columns(locked_slot_index: 9)

    with_creds_and_players do
      assert_nothing_raised { GymPollLockJob.perform_now(@poll.id) }
    end
  end

  test "does nothing when no bot token is configured" do
    Rails.application.credentials.stub(:discord, nil) do
      assert_nothing_raised { GymPollLockJob.perform_now(@poll.id) }
    end
  end
```

`test/jobs/gym_poll_discord_sync_job_test.rb`:

```ruby
  test "does nothing when no bot token is configured" do
    Rails.application.credentials.stub(:discord, nil) do
      assert_nothing_raised { GymPollDiscordSyncJob.perform_now(@poll.id) }
    end
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bin/rails test test/jobs`
Expected: 4 failures (DeserializationError, NoMethodError on `nil`).

- [ ] **Step 3: Enable the ApplicationJob handlers**

Replace `app/jobs/application_job.rb` with:

```ruby
class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError
end
```

- [ ] **Step 4: Guard the lock job**

In `app/jobs/gym_poll_lock_job.rb#perform`, replace:

```ruby
    token = Rails.application.credentials.discord[:token]
```

with:

```ruby
    return Rails.logger.error("GymPollLockJob: poll #{poll.id} locked on unknown slot #{poll.locked_slot_index}") unless locked_slot(poll)

    token = Rails.application.credentials.discord&.dig(:token)
    return Rails.logger.error("GymPollLockJob: no Discord bot token configured") if token.blank?
```

In `ping_text`, replace `slot = poll.slots.find { |s| s["index"].to_i == poll.locked_slot_index }` with `slot = locked_slot(poll)`, and add at the end of the `private` section:

```ruby

  def locked_slot(poll)
    poll.slots.find { |s| s["index"].to_i == poll.locked_slot_index }
  end
```

- [ ] **Step 5: Guard the sync job**

In `app/jobs/gym_poll_discord_sync_job.rb#perform`, replace:

```ruby
    token = Rails.application.credentials.discord[:token]
```

with:

```ruby
    token = Rails.application.credentials.discord&.dig(:token)
    return Rails.logger.error("GymPollDiscordSyncJob: no Discord bot token configured") if token.blank?
```

- [ ] **Step 6: Run the job tests**

Run: `bin/rails test test/jobs`
Expected: 0 failures.

- [ ] **Step 7: Commit**

```bash
git add app/jobs test/jobs
git commit -m "fix: discard jobs for deleted records and guard poll jobs against bad state"
```

---

### Task 14: Reuse the previous run's general channel

**Files:**
- Modify: `app/services/soul_link/discord_bot.rb` (`create_new_run`; add `self.reusable_general_channel`)
- Create: `test/services/soul_link/reusable_general_channel_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/services/soul_link/reusable_general_channel_test.rb`:

```ruby
require "test_helper"

module SoulLink
  class ReusableGeneralChannelTest < ActiveSupport::TestCase
    Channel = Struct.new(:id, :name)
    Server = Struct.new(:channels)

    test "returns the previous run's general channel" do
      general = Channel.new(42, "general")
      server = Server.new([ Channel.new(7, "catches"), general ])
      previous = build(:soul_link_run, general_channel_id: 42)

      assert_equal general, SoulLink::DiscordBot.reusable_general_channel(server, previous)
    end

    test "returns nil with no previous run or when its channel is gone" do
      server = Server.new([ Channel.new(7, "general") ])

      assert_nil SoulLink::DiscordBot.reusable_general_channel(server, nil)
      assert_nil SoulLink::DiscordBot.reusable_general_channel(server, build(:soul_link_run, general_channel_id: 42))
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/services/soul_link/reusable_general_channel_test.rb`
Expected: errors, `undefined method 'reusable_general_channel'`.

- [ ] **Step 3: Add the helper and fix `create_new_run`**

Add above `def self.next_gym_for(run)`:

```ruby
    # The previous run's general channel, which a new run moves into its own
    # category so the server keeps one general channel across runs. nil when
    # there isn't one to reuse.
    def self.reusable_general_channel(server, previous_run)
      return nil unless previous_run&.general_channel_id

      server.channels.find { |c| c.id == previous_run.general_channel_id }
    end

```

In `create_new_run`, replace:

```ruby
      # Deactivate current run if exists
      SoulLinkRun.current(guild_id)&.deactivate!
```

with:

```ruby
      # Capture the current run before deactivating it: its general channel
      # is reused below.
      previous_run = SoulLinkRun.current(guild_id)
      previous_run&.deactivate!
```

and replace:

```ruby
      # Look for an existing "general" channel inside the current run's category,
      # or create a new one under the new category
      existing_run = SoulLinkRun.current(guild_id)
      general_channel = if existing_run
                          server.channels.find { |c| c.id == existing_run.general_channel_id }
      else
                          server.channels.find { |c| c.name == 'general' && c.parent_id == category.id }
      end
```

with:

```ruby
      general_channel = self.class.reusable_general_channel(server, previous_run)
```

The `if general_channel ... parent = category ... else create ... end` block after it stays.

- [ ] **Step 4: Run it to verify it passes**

Run: `bin/rails test test/services/soul_link/reusable_general_channel_test.rb`
Expected: 2 runs, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/soul_link/discord_bot.rb test/services/soul_link/reusable_general_channel_test.rb
git commit -m "fix: reuse the previous run's general channel when starting a run from Discord"
```

---

### Task 15: Build the locked species badge safely

No JS test harness exists, so this task is verified by a syntax check and by reading the diff.

**Files:**
- Modify: `app/javascript/controllers/species_assignment_controller.js` (`lockSpecies`, plus a module constant)

- [ ] **Step 1: Add the icon constant**

After the `import` lines at the top of `species_assignment_controller.js`:

```js

const LOCK_ICON = `<svg class="w-3 h-3 opacity-50" fill="currentColor" viewBox="0 0 20 20">
  <path fill-rule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clip-rule="evenodd"/>
</svg>`
```

- [ ] **Step 2: Rewrite the top of `lockSpecies`**

Replace from `lockSpecies(card, zone) {` through `const groupCard = zone?.closest("[data-group-id]")`:

```js
  lockSpecies(card, zone) {
    const speciesName = card.querySelector("span")?.textContent?.trim() || "?"

    // Replace the drop zone with a locked badge
    zone.outerHTML = `
      ...
    `

    // Update the group card's status
    const groupCard = zone?.closest("[data-group-id]")
```

with:

```js
  lockSpecies(card, zone) {
    const speciesName = card.querySelector("span")?.textContent?.trim() || "?"
    // Find the group card first: once the zone is replaced it is detached,
    // and `closest` on a detached node finds nothing.
    const groupCard = zone?.closest("[data-group-id]")

    // Replace the drop zone with a locked badge. The name goes in as text,
    // never as HTML.
    const badge = document.createElement("span")
    badge.className = "inline-flex items-center gap-1 text-xs px-3 py-1.5 rounded-lg bg-indigo-900/60 text-indigo-200 border border-indigo-700"
    badge.textContent = speciesName
    badge.insertAdjacentHTML("beforeend", LOCK_ICON)
    zone.replaceWith(badge)

    // Update the group card's status
```

The `if (groupCard) { ... }` block below stays as it is.

- [ ] **Step 3: Syntax-check**

Run: `cp app/javascript/controllers/species_assignment_controller.js tmp/species_check.mjs && node --check tmp/species_check.mjs && rm tmp/species_check.mjs`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/species_assignment_controller.js
git commit -m "fix: insert species names as text and update the group status after locking"
```

---

### Task 16: Final verification

- [ ] **Step 1: Full suite in CI mode**

Run: `CI=true bin/rails test > tmp/test_full.txt 2>&1; grep -E "runs, .*assertions" tmp/test_full.txt`
Expected: `0 failures, 0 errors, 0 skips`, run count above 964. (`CI=true` enables eager loading, which catches load-order problems a local run misses.)

- [ ] **Step 2: Lint and security scan**

Run: `bundle exec rubocop > tmp/rubocop.txt 2>&1; tail -3 tmp/rubocop.txt`
Expected: `no offenses detected`. Fix any offense in files this plan touched with `bundle exec rubocop -a <file>`, re-run the affected tests, and commit.

Run: `bundle exec brakeman -q --no-pager > tmp/brakeman.txt 2>&1; grep -E "Security Warnings|No warnings" tmp/brakeman.txt`
Expected: no new warnings compared with `main`.

- [ ] **Step 3: Review the whole diff**

Run: `git diff --stat e822ed9..HEAD`
Check that every changed file is in this plan's file map, plus the spec and plan documents.

---

### Task 17: Ship (one deploy)

A push to `main` deploys to production.

- [ ] **Step 1: Confirm a fast-forward is possible**

```bash
git fetch origin
git merge-base --is-ancestor origin/main HEAD && echo "fast-forward OK"
```

Expected: `fast-forward OK`. If not, call the `sync_with_base_branch` tool, resolve conflicts, re-run Task 16, and retry.

- [ ] **Step 2: Push the branch to `main`**

```bash
git push origin HEAD:main
git rev-parse HEAD
git ls-remote origin refs/heads/main
```

Expected: both commands print the same SHA.

- [ ] **Step 3: After the deploy finishes, ask the user before touching production data**

Ask whether to run the species backfill on production. Only with a yes, over SSH (`ssh root@4luckyclovers.com`, app at `/opt/soul_link`, `source /etc/soul_link/env` first):

```bash
cd /opt/soul_link && source /etc/soul_link/env && DRY_RUN=1 bin/rails soul_link:backfill_species_names
```

Show the user the dry-run output, and run it again without `DRY_RUN` only after they confirm.
