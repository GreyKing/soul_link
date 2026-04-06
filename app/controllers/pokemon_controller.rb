class PokemonController < ApplicationController
  before_action :require_login

  def update
    run = current_run
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

  private

  def pokemon_params
    params.permit(:species, :level, :ability, :evolution_level, :nature)
  end

  def current_run
    guild_id = session[:guild_id]
    return nil unless guild_id
    SoulLinkRun.current(guild_id)
  end
end
