class GymReadyController < ApplicationController
  before_action :require_login

  def show
    run = current_run
    unless run
      redirect_to login_path, alert: "No active Soul Link run found."
      return
    end

    @gyms_defeated = run.gyms_defeated
    @next_gym = SoulLink::GameState.next_gym_info(@gyms_defeated)

    # Load player's team with full pokemon data
    team = run.soul_link_teams.find_by(discord_user_id: current_user_id)
    @team_slots = team&.soul_link_team_slots
                       &.includes(soul_link_pokemon_group: :soul_link_pokemon)
                       &.order(:position) || []
    @team_groups = @team_slots.map(&:soul_link_pokemon_group).compact

    # Extract just the current player's pokemon from team groups
    @player_pokemon = @team_groups.filter_map do |group|
      group.soul_link_pokemon.find { |p| p.discord_user_id == current_user_id }
    end

    # Type analysis
    @type_analysis = SoulLink::TypeChart.analyze_team(@player_pokemon)

    # Progression: all segments up to and including the current one
    @progression = SoulLink::GameState.progression
    segments = @progression["segments"] || []
    @current_segment_index = [@gyms_defeated, segments.size - 1].min
    @segments = segments[0..@current_segment_index]

    # Groups by location for caught/uncaught status on routes
    all_groups = run.soul_link_pokemon_groups.includes(:soul_link_pokemon)
    @groups_by_location = all_groups.group_by(&:location)
    @locations = SoulLink::GameState.locations
    @gym_info = SoulLink::GameState.gym_info

    @player_name = SoulLink::GameState.player_name(current_user_id)
  end

  private

  def current_run
    guild_id = session[:guild_id]
    return nil unless guild_id
    SoulLinkRun.current(guild_id)
  end
end
