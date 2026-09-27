module ApplicationCable
  class Channel < ActionCable::Channel::Base
    private

    # The guild the connection logged in with. Channels scope every record
    # lookup to it, so a client can't reach another server's data by id.
    def session_guild_id
      connection.session && connection.session[:guild_id]
    end
  end
end
