class AddGymsDefeatedToSoulLinkRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :soul_link_runs, :gyms_defeated, :integer, default: 0, null: false
  end
end
