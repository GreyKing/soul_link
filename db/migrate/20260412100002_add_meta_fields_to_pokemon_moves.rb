class AddMetaFieldsToPokemonMoves < ActiveRecord::Migration[8.1]
  def change
    change_table :pokemon_moves, bulk: true do |t|
      t.text    :effect
      t.text    :flavor_text
      t.integer :crit_rate, default: 0, null: false
      t.integer :drain, default: 0, null: false
      t.integer :healing, default: 0, null: false
      t.integer :flinch_chance, default: 0, null: false
      t.integer :min_hits
      t.integer :max_hits
      t.string  :ailment
      t.integer :ailment_chance, default: 0, null: false
    end
  end
end
