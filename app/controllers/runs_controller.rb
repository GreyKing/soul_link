class RunsController < ApplicationController
  before_action :require_login

  # Step 24 R1 — `/runs` is consolidated into the dashboard RUNS tab. All
  # affordances now live in `app/views/dashboard/_runs_content.html.erb`;
  # the standalone page goes away. External links keep working via 301.
  def index
    redirect_to root_path(anchor: "runs"), status: :moved_permanently
  end
end
