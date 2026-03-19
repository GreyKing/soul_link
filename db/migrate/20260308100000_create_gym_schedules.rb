class CreateGymSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :gym_schedules do |t|
      t.references :soul_link_run, null: false, foreign_key: true
      t.bigint     :proposed_by,   null: false
      t.datetime   :scheduled_at,  null: false
      t.string     :status,        null: false, default: "proposed"
      t.json       :state_data
      t.bigint     :discord_message_id
      t.bigint     :discord_channel_id
      t.references :gym_draft, foreign_key: true, null: true

      t.timestamps
    end

    add_index :gym_schedules, [:soul_link_run_id, :status]
  end
end
