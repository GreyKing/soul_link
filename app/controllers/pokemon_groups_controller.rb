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

    group = run.soul_link_pokemon_groups.create!(
      nickname: nickname,
      location: location,
      status: "caught"
    )

    errors = []
    species_params = params[:species] || {}
    SoulLink::GameState.players.each do |player|
      uid = player['discord_user_id']
      species = species_params[uid.to_s]&.strip
      next if species.blank?

      begin
        run.soul_link_pokemon.create!(
          soul_link_pokemon_group: group,
          discord_user_id: uid,
          species: species,
          name: nickname,
          location: location,
          status: "caught"
        )
      rescue ActiveRecord::RecordInvalid => e
        errors << "#{player['display_name'] || uid}: #{e.record.errors.full_messages.join(', ')}"
      rescue ActiveRecord::RecordNotUnique
        errors << "#{player['display_name'] || uid}: already has a pokemon in this group"
      end
    end

    # Live catch embed. Last statement before render so a Discord failure
    # can never roll back the group/pokemon writes. The service is
    # fire-and-forget and swallows its own errors.
    SoulLink::CatchMessage.post_or_update(group)

    if errors.any?
      render json: { status: "partial", group_id: group.id, nickname: group.nickname, errors: errors }, status: :multi_status
    else
      render json: { status: "saved", group_id: group.id, nickname: group.nickname }
    end
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

      # One message for the whole group; the notifier rescues every
      # failure internally.
      SoulLink::DiscordNotifier.notify_group_death(run, group)

      # Step 19 — wipe-detection runs on every Mark Dead transition.
      # Idempotency lives inside the coordinator (skips if wiped_at set).
      SoulLink::WipeCoordinator.process(run)
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

    # Re-sync the live catch embed after any edit (rename, relocate, dead,
    # revive). Only groups that already have an embed — the update hook keeps
    # an existing message in sync; posting a first message is #create's job.
    # Without this guard, editing a bot-created group (which never posts, so
    # carries a nil id) would spawn a stray catch embed — and for an
    # uncaught-death group, a 💀 embed in the catches channel for a Pokemon
    # that was never caught. Fire-and-forget; a Discord failure never touches
    # the response.
    if group.discord_catch_message_id.present?
      SoulLink::CatchMessage.post_or_update(group)
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

    # Remove the catch embed BEFORE the row is gone — delete reads the
    # message id off the group.
    SoulLink::CatchMessage.delete(group)
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
