class RunsController < ApplicationController
  before_action :require_login

  def index
    @guild_id = session[:guild_id]
    @current_run = SoulLinkRun.current(@guild_id)
    @past_runs = SoulLinkRun.history(@guild_id).limit(20)
    @players = SoulLink::GameState.players
  end

  private

  def current_run
    @current_run ||= SoulLinkRun.current(session[:guild_id])
  end
end
