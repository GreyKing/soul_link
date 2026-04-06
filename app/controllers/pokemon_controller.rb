class PokemonController < ApplicationController
  before_action :require_login

  def update
    run = find_run
    head :not_found and return unless run

    pokemon = run.soul_link_pokemon.find_by(id: params[:id])
    unless pokemon
      render json: { error: "Pokemon not found" }, status: :not_found
      return
    end

    unless pokemon.discord_user_id == current_user_id
      render json: { error: "Not your pokemon" }, status: :forbidden
      return
    end

    pokemon.update!(pokemon_params)
    render json: { status: "updated", pokemon_id: pokemon.id }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Create a pokemon record for the current user in a group (when none exists yet)
  def create
    run = find_run
    head :not_found and return unless run

    group = run.soul_link_pokemon_groups.find_by(id: params[:group_id])
    unless group
      render json: { error: "Group not found" }, status: :not_found
      return
    end

    # Check if the user already has a pokemon in this group
    if group.species_for(current_user_id)
      render json: { error: "You already have a pokemon in this group" }, status: :unprocessable_entity
      return
    end

    species = params[:species]&.strip
    unless species.present?
      render json: { error: "Species is required" }, status: :unprocessable_entity
      return
    end

    pokemon = run.soul_link_pokemon.create!(
      soul_link_pokemon_group: group,
      discord_user_id: current_user_id,
      species: species,
      name: group.nickname,
      location: group.location,
      status: group.status,
      level: params[:level],
      ability: params[:ability],
      nature: params[:nature]
    )

    render json: { status: "created", pokemon_id: pokemon.id }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def pokemon_params
    params.permit(:species, :level, :ability, :evolution_level, :nature)
  end

  def find_run
    guild_id = session[:guild_id]
    return nil unless guild_id

    # Support viewing any run in the guild, not just active
    if params[:run_id].present?
      SoulLinkRun.for_guild(guild_id).find_by(id: params[:run_id])
    else
      SoulLinkRun.current(guild_id)
    end
  end
end
