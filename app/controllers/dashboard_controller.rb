class DashboardController < ApplicationController
  before_action :require_login

  def show
    run = current_run
    unless run
      redirect_to login_path, alert: "No active Soul Link run found."
      return
    end

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

    # For the quick-catch modal
    @locations = SoulLink::GameState.locations
    @pokedex_species = SoulLink::GameState.pokedex.keys.sort
  end

  private

  def current_run
    guild_id = session[:guild_id]
    return nil unless guild_id
    SoulLinkRun.current(guild_id)
  end
end
