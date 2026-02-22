class SpeciesAssignmentsController < ApplicationController
  before_action :require_login

  def show
    run = current_run
    unless run
      redirect_to login_path, alert: "No active Soul Link run found."
      return
    end

    @groups = run.caught_groups.includes(:soul_link_pokemon)
    @pool = run.soul_link_pokemon.unassigned.for_player(current_user_id).order(:species)
    @player_name = SoulLink::GameState.player_name(current_user_id)
    @players = SoulLink::GameState.players
  end

  def assign
    run = current_run
    head :not_found and return unless run

    pokemon = run.soul_link_pokemon.unassigned.for_player(current_user_id).find_by(id: params[:pokemon_id])
    group = run.caught_groups.find_by(id: params[:group_id])

    unless pokemon
      render json: { error: "Species not found or already assigned" }, status: :unprocessable_entity
      return
    end

    unless group
      render json: { error: "Group not found" }, status: :unprocessable_entity
      return
    end

    # Check player doesn't already have a species in this group
    if group.species_for(current_user_id)
      render json: { error: "You already have a species in this group" }, status: :unprocessable_entity
      return
    end

    pokemon.assign_to_group!(group)
    render json: { status: "assigned", pokemon_id: pokemon.id, group_id: group.id }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def current_run
    guild_id = session[:guild_id]
    return nil unless guild_id

    SoulLinkRun.current(guild_id)
  end
end
