class CreatePokemonLearnsets < ActiveRecord::Migration[8.1]
  def change
    create_table :pokemon_learnsets do |t|
      t.references :pokemon_base_stat, null: false, foreign_key: true
      t.references :pokemon_move,      null: false, foreign_key: true
      t.string  :learn_method, null: false
      t.integer :level_learned
      t.timestamps
    end

    add_index :pokemon_learnsets, [:pokemon_base_stat_id, :pokemon_move_id, :learn_method],
              unique: true, name: "idx_learnset_unique"
  end
end
