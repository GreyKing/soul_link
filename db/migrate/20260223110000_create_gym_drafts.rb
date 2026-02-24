class CreateGymDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :gym_drafts do |t|
      t.references :soul_link_run, null: false, foreign_key: true
      t.string :status, null: false, default: "lobby"
      t.integer :current_round, null: false, default: 0
      t.integer :current_player_index, null: false, default: 0
      t.json :pick_order
      t.json :state_data

      t.timestamps
    end

    add_index :gym_drafts, [:soul_link_run_id, :status]
  end
end
