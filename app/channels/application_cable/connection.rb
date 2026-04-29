module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user_id

    # Channels read `connection.session[:guild_id]` to authorize subscriptions
    # against the user's logged-in guild (see RunChannel#subscribed). The
    # session lives on the connection's underlying Rack request and never
    # changes for the life of the WS connection.
    attr_reader :session

    def connect
      self.current_user_id = find_verified_user
      @session = request.session
    end

    private

    def find_verified_user
      uid = request.session[:discord_user_id]
      if uid.present?
        uid
      else
        reject_unauthorized_connection
      end
    end
  end
end
