module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user_id

    def connect
      self.current_user_id = find_verified_user
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
