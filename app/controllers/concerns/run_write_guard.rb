# Refuses writes to the current run while it is read-only (wiped). Controllers
# opt in per action:
#
#   before_action :require_writable_run!, only: %i[create update]
#
# JSON requests get a 403 with the message; form submissions are redirected
# to the dashboard with it as the alert.
module RunWriteGuard
  extend ActiveSupport::Concern

  private

  def require_writable_run!
    return unless SoulLinkRun.current(session[:guild_id])&.read_only?

    if request.format.json? || request.content_mime_type&.json?
      render json: { error: SoulLinkRun::READ_ONLY_MESSAGE }, status: :forbidden
    else
      redirect_to root_path, alert: SoulLinkRun::READ_ONLY_MESSAGE
    end
  end
end
