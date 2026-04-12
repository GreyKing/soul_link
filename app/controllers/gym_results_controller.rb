class GymResultsController < ApplicationController
  before_action :require_login

  def update
    run = current_run
    head :not_found and return unless run

    result = run.gym_results.find_by(id: params[:id])
    unless result
      render json: { error: "Gym result not found" }, status: :not_found
      return
    end

    group_ids = (params[:group_ids] || []).first(6).map(&:to_i)
    if group_ids.empty?
      render json: { error: "At least one group is required" }, status: :unprocessable_entity
      return
    end

    snapshot = GymResult.snapshot_from_group_ids(run, group_ids)
    result.update!(team_snapshot: snapshot)

    render json: { status: "saved", gym_number: result.gym_number }
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
