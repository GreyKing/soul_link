module Api
  class BaseController < ApplicationController
    include DiscordAuthentication
    before_action :require_login_json

    private

    def require_login_json
      unless logged_in?
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end
  end
end
