class DropGymSchedules < ActiveRecord::Migration[8.1]
  def change
    drop_table :gym_schedules do |t|
      t.bigint   :soul_link_run_id, null: false
      t.bigint   :gym_draft_id
      t.bigint   :proposed_by, null: false
      t.datetime :scheduled_at, null: false
      t.string   :status, default: "proposed", null: false
      t.bigint   :discord_channel_id
      t.bigint   :discord_message_id
      t.json     :state_data
      t.timestamps null: false
      t.index [:soul_link_run_id, :status]
      t.index [:soul_link_run_id]
      t.index [:gym_draft_id]
      t.foreign_key :soul_link_runs
      t.foreign_key :gym_drafts
    end
  end
end
