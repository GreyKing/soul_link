class RunsController < ApplicationController
  before_action :require_login

  # Step 24 R1 — `/runs` is consolidated into the dashboard RUNS tab.
  def index
    redirect_to root_path(anchor: "runs"), status: :moved_permanently
  end

  def edit
    @run = SoulLinkRun.find(params[:id])
  end

  def update
    @run = SoulLinkRun.find(params[:id])

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
end
