class SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :create

  def new
    redirect_to team_path if logged_in?
  end

  def create
    auth = request.env["omniauth.auth"]

    unless auth
      redirect_to login_path, alert: "Authentication failed."
      return
    end

    discord_user_id = auth.uid.to_i
    username = auth.info.name
    avatar_url = auth.info.image

    # Check guild membership — user must be in a guild with an active run
    guild_ids = auth.extra.raw_info.guilds&.map { |g| g["id"] } || []
    active_run = SoulLinkRun.active.where(guild_id: guild_ids).first

    unless active_run
      redirect_to login_path, alert: "You must be a member of a Discord server with an active Soul Link run."
      return
    end

    # Store session data (no Users table needed)
    session[:discord_user_id] = discord_user_id
    session[:discord_username] = username
    session[:discord_avatar_url] = avatar_url
    session[:guild_id] = active_run.guild_id

    redirect_to team_path, notice: "Welcome, #{username}!"
  end

  def failure
    redirect_to login_path, alert: "Discord authentication failed: #{params[:message]}"
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Signed out."
  end
end
