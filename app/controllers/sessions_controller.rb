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

    # Fetch user's guilds via Discord API (raw_info only has user data, not guilds)
    access_token = auth.credentials.token
    guilds_response = Faraday.get("https://discord.com/api/users/@me/guilds") do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
    end
    guild_ids = JSON.parse(guilds_response.body).map { |g| g["id"].to_i } rescue []
    Rails.logger.info "[SoulLink Auth] User: #{username} (#{discord_user_id}), guild_ids: #{guild_ids}"

    # Check guild membership — user must be in a guild that has any Soul Link run
    run = SoulLinkRun.where(guild_id: guild_ids).order(created_at: :desc).first

    unless run
      Rails.logger.info "[SoulLink Auth] No matching run found. DB runs: #{SoulLinkRun.pluck(:guild_id).inspect}"
      redirect_to login_path, alert: "You must be a member of a Discord server with Soul Link."
      return
    end

    # Store session data (no Users table needed)
    session[:discord_user_id] = discord_user_id
    session[:discord_username] = username
    session[:discord_avatar_url] = avatar_url
    session[:guild_id] = run.guild_id

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
