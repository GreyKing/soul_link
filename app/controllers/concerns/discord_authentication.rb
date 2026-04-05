module DiscordAuthentication
  extend ActiveSupport::Concern

  included do
    helper_method :logged_in?, :current_user_id, :current_username, :current_avatar_url
  end

  def current_user_id
    session[:discord_user_id]
  end

  def current_username
    session[:discord_username]
  end

  def current_avatar_url
    session[:discord_avatar_url]
  end

  def logged_in?
    current_user_id.present?
  end

  def require_login
    unless logged_in?
      redirect_to login_path, alert: "Please sign in with Discord to continue. "
    end
  end
end
