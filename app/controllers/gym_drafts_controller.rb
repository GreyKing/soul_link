class GymDraftsController < ApplicationController
  before_action :require_login

  def create
    run = current_run
    redirect_to login_path, alert: "No active run found." and return unless run

    # Check for an existing active draft
    existing = run.gym_drafts.where(status: %w[lobby voting drafting nominating]).first
    if existing
      redirect_to gym_draft_path(existing)
      return
    end

    draft = run.gym_drafts.create!
    redirect_to gym_draft_path(draft)
  end

  def show
    @draft = GymDraft.find(params[:id])
    run = @draft.soul_link_run

    @players = SoulLink::GameState.players
    @player_name = SoulLink::GameState.player_name(current_user_id)

    # Load all caught groups for each player (for picking)
    all_groups = run.soul_link_pokemon_groups
                    .caught
                    .includes(:soul_link_pokemon)
                    .order(position: :asc)

    # Build per-player groups with their pokemon
    @player_groups = {}
    @players.each do |player|
      uid = player["discord_user_id"]
      @player_groups[uid] = all_groups.select do |group|
        group.soul_link_pokemon.any? { |p| p.discord_user_id == uid }
      end
    end

    # For the results page: type analysis of the drafted team
    if @draft.complete?
      drafted_group_ids = @draft.final_team_group_ids
      drafted_groups = all_groups.select { |g| drafted_group_ids.include?(g.id) }
      all_pokemon = drafted_groups.flat_map(&:soul_link_pokemon)

      # Group pokemon by player for the results view
      @drafted_pokemon_by_player = {}
      @players.each do |player|
        uid = player["discord_user_id"]
        @drafted_pokemon_by_player[uid] = drafted_groups.filter_map do |group|
          group.soul_link_pokemon.find { |p| p.discord_user_id == uid }
        end
      end

      # Type analysis per player
      @type_analysis_by_player = {}
      @drafted_pokemon_by_player.each do |uid, pokemon|
        @type_analysis_by_player[uid] = SoulLink::TypeChart.analyze_team(pokemon)
      end

      # Mark beaten button data
      @next_gym_number = run.gyms_defeated + 1
      @gym_already_marked = run.gym_results.exists?(gym_number: @next_gym_number)
      @next_gym_info = SoulLink::GameState.gym_info_by_number(@next_gym_number)
    end
  end

  def mark_beaten
    run = current_run
    redirect_to login_path, alert: "No active run found." and return unless run

    draft = run.gym_drafts.find_by(id: params[:id])
    unless draft&.complete?
      redirect_to gym_drafts_path, alert: "Draft is not complete."
      return
    end

    gym_number = run.gyms_defeated + 1
    unless gym_number.between?(1, 8)
      redirect_to gym_draft_path(draft), alert: "All gyms already defeated!"
      return
    end

    # Check if this gym already has a result
    if run.gym_results.exists?(gym_number: gym_number)
      redirect_to gym_draft_path(draft), alert: "Gym #{gym_number} already marked as beaten."
      return
    end

    snapshot = GymResult.snapshot_from_draft(draft)
    run.gym_results.create!(
      gym_number: gym_number,
      beaten_at: Time.current,
      gym_draft: draft,
      team_snapshot: snapshot
    )
    run.update!(gyms_defeated: gym_number)

    redirect_to root_path, notice: "Gym #{gym_number} marked as beaten!"
  rescue ActiveRecord::RecordNotUnique
    redirect_to gym_draft_path(draft), alert: "Gym #{gym_number} already marked as beaten."
  end

  private

  def current_run
    guild_id = session[:guild_id]
    return nil unless guild_id
    SoulLinkRun.current(guild_id)
  end
end
