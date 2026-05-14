class CreateGymPolls < ActiveRecord::Migration[8.1]
  def change
    create_table :gym_polls do |t|
      t.references :soul_link_run, null: false, foreign_key: true
      t.references :gym_draft,     null: true,  foreign_key: true
      t.string  :status, null: false, default: "open"
      t.bigint  :discord_message_id
      t.bigint  :discord_channel_id
      t.integer :locked_slot_index
      t.datetime :locked_at
      t.datetime :pinged_at
      t.json    :state_data, null: false
      t.timestamps
    end
    add_index :gym_polls, [:soul_link_run_id, :status]
  end
end
