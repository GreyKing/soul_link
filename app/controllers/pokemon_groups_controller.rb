class PokemonGroupsController < ApplicationController
  before_action :require_login

  def create
    run = current_run
    head :not_found and return unless run

    nickname = params[:nickname]&.strip
    location = params[:location]&.strip

    if nickname.blank? || location.blank?
      render json: { error: "Nickname and location are required" }, status: :unprocessable_entity
      return
    end

    group = nil
    ActiveRecord::Base.transaction do
      group = run.soul_link_pokemon_groups.create!(
        nickname: nickname,
        location: location,
        status: "caught"
      )

      # Create a SoulLinkPokemon for each player's species selection (if provided)
      species_params = params[:species] || {}
      SoulLink::GameState.players.each do |player|
        uid = player['discord_user_id']
        species = species_params[uid.to_s]&.strip
        next if species.blank?

        run.soul_link_pokemon.create!(
          soul_link_pokemon_group: group,
          discord_user_id: uid,
          species: species,
          name: nickname,
          location: location,
          status: "caught"
        )
      end
    end

    render json: { status: "saved", group_id: group.id, nickname: group.nickname }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def current_run
    guild_id = session[:guild_id]
    return nil unless guild_id
    SoulLinkRun.current(guild_id)
  end
end
