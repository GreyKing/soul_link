class GymProgressController < ApplicationController
  before_action :require_login

  def update
    run = current_run
    head :not_found and return unless run

    gym_number = params[:gym_number].to_i
    return respond_with_error("Invalid gym number") unless gym_number.between?(1, 8)

    existing = run.gym_results.find_by(gym_number: gym_number)

    if existing
      # Only allow unmark of the highest completed gym
      highest = run.gym_results.maximum(:gym_number)
      return respond_with_error("Can only unmark the most recent gym") if gym_number < highest

      existing.destroy!
      new_max = run.gym_results.maximum(:gym_number) || 0
      run.update!(gyms_defeated: new_max)
      notice = "Gym #{gym_number} unmarked."
    else
      run.gym_results.create!(
        gym_number: gym_number,
        beaten_at: Time.current
      )
      run.update!(gyms_defeated: [ run.gyms_defeated, gym_number ].max)
      notice = "Gym #{gym_number} marked beaten."
    end

    if json_request?
      render json: { gyms_defeated: run.gyms_defeated }
    else
      redirect_to root_path(anchor: "gyms"), notice: notice
    end
  end

  private

  def current_run
    guild_id = session[:guild_id]
    return nil unless guild_id
    SoulLinkRun.current(guild_id)
  end

  def json_request?
    request.content_type == "application/json"
  end

  def respond_with_error(message)
    if json_request?
      render json: { error: message }, status: :unprocessable_entity
    else
      redirect_to root_path(anchor: "gyms"), alert: message
    end
  end
end
