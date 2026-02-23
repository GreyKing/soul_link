class MapController < ApplicationController
  before_action :require_login

  def show
    run = current_run
    unless run
      redirect_to login_path, alert: "No active Soul Link run found."
      return
    end

    @run = run
    @gyms_defeated = run.gyms_defeated

    # All groups indexed by location (multiple groups possible per location)
    all_groups = run.soul_link_pokemon_groups.includes(:soul_link_pokemon).order(caught_at: :asc)
    @groups_by_location = all_groups.group_by(&:location)

    @locations = SoulLink::GameState.locations
    @progression = SoulLink::GameState.progression
    @gym_info = SoulLink::GameState.gym_info
    @players = SoulLink::GameState.players
    @pokedex_species = SoulLink::GameState.pokedex.keys.sort
  end

  private

  def current_run
    guild_id = session[:guild_id]
    return nil unless guild_id
    SoulLinkRun.current(guild_id)
  end
end
