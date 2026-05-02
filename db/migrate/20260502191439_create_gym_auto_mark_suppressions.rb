class CreateGymAutoMarkSuppressions < ActiveRecord::Migration[8.1]
  def change
    create_table :gym_auto_mark_suppressions do |t|
      t.references :soul_link_run, null: false, foreign_key: true
      t.integer :gym_number, null: false
      t.timestamps
    end
    add_index :gym_auto_mark_suppressions, [ :soul_link_run_id, :gym_number ], unique: true
  end
end
