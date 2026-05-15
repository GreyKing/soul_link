class RunsController < ApplicationController
  before_action :require_login
  before_action :load_run, only: %i[edit update]

  # Step 24 R1 — `/runs` is consolidated into the dashboard RUNS tab.
  def index
    redirect_to root_path(anchor: "runs"), status: :moved_permanently
  end

  def edit; end

  def update
    template_param = params.dig(:soul_link_run, :schedule_template)
    parsed = template_param.present? ? JSON.parse(template_param) : nil

    if @run.update(timezone: params.dig(:soul_link_run, :timezone), schedule_template: parsed)
      redirect_to edit_run_path(@run), notice: "Schedule template saved."
    else
      flash.now[:alert] = @run.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  rescue JSON::ParserError
    flash.now[:alert] = "Template payload was not valid JSON."
    render :edit, status: :unprocessable_entity
  end

  private

  def load_run
    guild_id = session[:guild_id]
    @run = SoulLinkRun.current(guild_id) if guild_id
    return if @run && @run.id == params[:id].to_i
    redirect_to login_path, alert: "Run not found in this guild."
  end
end
