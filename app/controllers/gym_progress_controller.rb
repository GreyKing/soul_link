class GymProgressController < ApplicationController
  before_action :require_login

  def update
    run = current_run
    head :not_found and return unless run

    gym_number = params[:gym_number].to_i
    unless gym_number.between?(1, 8)
      render json: { error: "Invalid gym number" }, status: :unprocessable_entity
      return
    end

    # Toggle: if this gym is already beaten, un-beat it (set to one less)
    # If not yet beaten, beat it (set to this gym number)
    if run.gyms_defeated >= gym_number
      run.update!(gyms_defeated: gym_number - 1)
    else
      run.update!(gyms_defeated: gym_number)
    end

    render json: { gyms_defeated: run.gyms_defeated }
  end

  private

  def current_run
    guild_id = session[:guild_id]
    return nil unless guild_id
    SoulLinkRun.current(guild_id)
  end
end
