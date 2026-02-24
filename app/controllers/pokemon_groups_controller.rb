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

  def update
    run = current_run
    head :not_found and return unless run

    group = run.soul_link_pokemon_groups.find_by(id: params[:id])
    unless group
      render json: { error: "Group not found" }, status: :not_found
      return
    end

    new_status = params[:status]&.strip
    was_alive = group.caught?

    if new_status == "dead" && was_alive
      # Use mark_as_dead! to cascade status to all pokemon + remove team slots
      group.mark_as_dead!(eulogy: params[:eulogy])
      # Also update nickname/location if changed
      group.update!(
        nickname: params[:nickname]&.strip || group.nickname,
        location: params[:location]&.strip || group.location
      )
    elsif new_status == "caught" && group.dead?
      # Revive: set group + all pokemon back to caught
      ActiveRecord::Base.transaction do
        group.update!(
          nickname: params[:nickname]&.strip || group.nickname,
          location: params[:location]&.strip || group.location,
          status: "caught",
          died_at: nil,
          eulogy: nil
        )
        group.soul_link_pokemon.each { |p| p.update!(status: "caught", died_at: nil) }
      end
    else
      # Simple metadata update (no status change)
      group.update!(
        nickname: params[:nickname]&.strip || group.nickname,
        location: params[:location]&.strip || group.location,
        eulogy: group.dead? ? (params[:eulogy] || group.eulogy) : group.eulogy
      )
    end

    render json: { status: "updated", group_id: group.id, nickname: group.nickname }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def reorder
    run = current_run
    head :not_found and return unless run

    group_ids = params[:group_ids]
    unless group_ids.is_a?(Array) && group_ids.any?
      render json: { error: "group_ids array required" }, status: :unprocessable_entity
      return
    end

    ActiveRecord::Base.transaction do
      group_ids.each_with_index do |id, index|
        run.soul_link_pokemon_groups.where(id: id).update_all(position: index + 1)
      end
    end

    render json: { status: "reordered" }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    run = current_run
    head :not_found and return unless run

    group = run.soul_link_pokemon_groups.find_by(id: params[:id])
    unless group
      render json: { error: "Group not found" }, status: :not_found
      return
    end

    group.destroy!
    render json: { status: "deleted" }
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
