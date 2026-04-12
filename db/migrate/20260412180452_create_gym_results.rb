class CreateGymResults < ActiveRecord::Migration[8.1]
  def change
    create_table :gym_results do |t|
      t.references :soul_link_run, null: false, foreign_key: true
      t.integer :gym_number, null: false
      t.datetime :beaten_at, null: false
      t.references :gym_draft, null: true, foreign_key: true
      t.json :team_snapshot

      t.timestamps
    end

    add_index :gym_results, [:soul_link_run_id, :gym_number], unique: true
  end
end
