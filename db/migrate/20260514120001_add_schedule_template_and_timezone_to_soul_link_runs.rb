class AddScheduleTemplateAndTimezoneToSoulLinkRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :soul_link_runs, :schedule_template, :json
    add_column :soul_link_runs, :timezone, :string, null: false, default: "America/Phoenix"
  end
end
