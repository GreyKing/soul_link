class GymSchedulesController < ApplicationController
  before_action :require_login

  def index
    run = current_run
    redirect_to login_path, alert: "No active run found." and return unless run

    @schedules = run.gym_schedules.upcoming
    @past_schedules = run.gym_schedules.where(status: %w[completed cancelled]).order(scheduled_at: :desc).limit(5)
    @players = SoulLink::GameState.players
  end

  def create
    run = current_run
    redirect_to login_path, alert: "No active run found." and return unless run

    existing = run.gym_schedules.active.first
    if existing
      redirect_to gym_schedule_path(existing), notice: "An active schedule already exists."
      return
    end

    schedule = run.gym_schedules.create!(
      proposed_by: current_user_id,
      scheduled_at: Time.zone.parse(params[:scheduled_at])
    )

    redirect_to gym_schedule_path(schedule)
  end

  def show
    @schedule = GymSchedule.find(params[:id])
    @players = SoulLink::GameState.players
    @player_name = SoulLink::GameState.player_name(current_user_id)
  end

  private

  def current_run
    guild_id = session[:guild_id]
    return nil unless guild_id
    SoulLinkRun.current(guild_id)
  end
end
