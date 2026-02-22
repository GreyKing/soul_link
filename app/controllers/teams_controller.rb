class TeamsController < ApplicationController
  before_action :require_login

  def show
    run = current_run
    unless run
      redirect_to login_path, alert: "No active Soul Link run found."
      return
    end

    @team = run.soul_link_teams.find_or_create_by!(discord_user_id: current_user_id)
    @team_slots = @team.soul_link_team_slots.includes(soul_link_pokemon_group: :soul_link_pokemon).order(:position)
    @team_groups = @team_slots.map(&:soul_link_pokemon_group)
    team_group_ids = @team_groups.map(&:id)

    @pool_groups = run.caught_groups.includes(:soul_link_pokemon).where.not(id: team_group_ids)
    @player_name = SoulLink::GameState.player_name(current_user_id)
  end

  def update_slots
    run = current_run
    head :not_found and return unless run

    team = run.soul_link_teams.find_or_create_by!(discord_user_id: current_user_id)
    group_ids = params[:group_ids] || []

    # Validate: all group_ids must be caught groups in this run
    # Use a Set for fast lookup while preserving the JS-sent order
    allowed_ids = run.caught_groups.where(id: group_ids).pluck(:id).to_set
    ordered_valid_ids = group_ids.select { |id| allowed_ids.include?(id.to_i) }

    if ordered_valid_ids.length > SoulLinkTeam::MAX_SLOTS
      render json: { error: "Maximum #{SoulLinkTeam::MAX_SLOTS} Pokemon per team" }, status: :unprocessable_entity
      return
    end

    team.replace_slots!(ordered_valid_ids)
    render json: { status: "saved", slots: team.soul_link_team_slots.count }
  end

  def index
    run = current_run
    unless run
      redirect_to login_path, alert: "No active Soul Link run found."
      return
    end

    @teams = run.soul_link_teams.includes(soul_link_team_slots: { soul_link_pokemon_group: :soul_link_pokemon })
    @caught_groups = run.caught_groups.includes(:soul_link_pokemon)
    @players = SoulLink::GameState.players
  end

  private

  def current_run
    guild_id = session[:guild_id]
    return nil unless guild_id

    SoulLinkRun.current(guild_id)
  end
end
