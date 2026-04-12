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

    existing = run.gym_results.find_by(gym_number: gym_number)

    if existing
      # Only allow unmark of the highest completed gym
      highest = run.gym_results.maximum(:gym_number)
      if gym_number < highest
        render json: { error: "Can only unmark the most recent gym" }, status: :unprocessable_entity
        return
      end
      existing.destroy!
      new_max = run.gym_results.maximum(:gym_number) || 0
      run.update!(gyms_defeated: new_max)
    else
      # Mark beaten: create result (no snapshot from this path)
      run.gym_results.create!(
        gym_number: gym_number,
        beaten_at: Time.current
      )
      run.update!(gyms_defeated: [run.gyms_defeated, gym_number].max)
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
