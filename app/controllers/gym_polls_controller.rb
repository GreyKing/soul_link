class GymPollsController < ApplicationController
  before_action :require_login
  before_action :load_run

  def show
    @poll = @run.gym_polls.where(status: %w[open locked]).first
  end

  def create
    if @run.schedule_template.blank?
      render status: :unprocessable_entity,
             plain:  "Configure your weekly slots on the dashboard Schedule tab first."
      return
    end

    if @run.gym_polls.where(status: %w[open locked]).exists?
      render status: :conflict, plain: "An open poll already exists — reset it first."
      return
    end

    slots = GymPoll.materialize_slots(@run)
    @run.gym_polls.create!(state_data: { "slots" => slots, "votes" => {} })
    redirect_to gym_poll_path
  rescue GymPoll::EmptyTemplateError => e
    render status: :unprocessable_entity, plain: e.message
  end

  def destroy
    poll = @run.gym_polls.where(status: %w[open locked]).first
    poll&.destroy
    redirect_to gym_poll_path
  end

  private

  def load_run
    guild_id = session[:guild_id]
    @run = SoulLinkRun.current(guild_id) if guild_id
    redirect_to login_path, alert: "No active run found." unless @run
  end
end
