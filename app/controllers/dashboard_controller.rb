class DashboardController < ApplicationController
  before_action :require_login
  layout "pixeldex"

  def show
    guild_id = session[:guild_id]
    unless guild_id
      redirect_to login_path, alert: "No active Soul Link run found."
      return
    end

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

    @run = run
    @guild_id = guild_id
    @player_name = SoulLink::GameState.player_name(current_user_id)

    # Load player's team with full pokemon data
    team = run.soul_link_teams.find_by(discord_user_id: current_user_id)
    @team_slots = team&.soul_link_team_slots
                       &.includes(soul_link_pokemon_group: :soul_link_pokemon)
                       &.order(:position) || []
    @team_groups = @team_slots.map(&:soul_link_pokemon_group).compact

    # Extract current player's pokemon from team groups for type analysis
    @team_pokemon = @team_groups.filter_map do |group|
      group.soul_link_pokemon.find { |p| p.discord_user_id == current_user_id }
    end

    # Type analysis
    @type_analysis = SoulLink::TypeChart.analyze_team(@team_pokemon)

    # All groups in the run with current player's pokemon
    @all_groups = run.soul_link_pokemon_groups
                     .includes(:soul_link_pokemon)
                     .order(position: :asc)

    # Title bar stats
    @gyms_defeated = run.gyms_defeated
    @caught_count = @all_groups.count(&:caught?)
    @dead_count = @all_groups.count(&:dead?)

    # PC Box categorization
    @team_group_ids = @team_groups.map(&:id).to_set
    @on_team_groups = @all_groups.select { |g| g.caught? && @team_group_ids.include?(g.id) }
    @storage_groups = @all_groups.select { |g| g.caught? && !@team_group_ids.include?(g.id) }
    @fallen_groups = @all_groups.select(&:dead?)

    # Gym & map data
    @gym_info = SoulLink::GameState.gym_info
    @next_gym = SoulLink::GameState.next_gym_info(@gyms_defeated)
    @gym_results = run.gym_results.index_by(&:gym_number)
    @caught_groups_for_backfill = run.caught_groups.includes(:soul_link_pokemon)
    @progression = SoulLink::GameState.progression
    @groups_by_location = @all_groups.group_by(&:location)

    # Current progression segment for recent routes
    segments = @progression["segments"] || []
    @current_segment_index = [@gyms_defeated, segments.size - 1].min
    @current_segment = segments[@current_segment_index]

    # Calculator team quick-pick data
    @calc_team_pokemon = @team_groups.flat_map do |group|
      group.soul_link_pokemon.select { |p| p.discord_user_id == current_user_id }.map do |p|
        { species: p.species, level: p.level || 50, nature: p.nature }
      end
    end

    # For the quick-catch modal and pokemon modal
    @locations = SoulLink::GameState.locations
    @pokedex_species = SoulLink::GameState.pokedex.keys.sort
    @players = SoulLink::GameState.players
  end

  private

  def current_run
    guild_id = session[:guild_id]
    return nil unless guild_id
    SoulLinkRun.current(guild_id)
  end
end
