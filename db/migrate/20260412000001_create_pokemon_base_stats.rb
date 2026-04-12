class CreatePokemonBaseStats < ActiveRecord::Migration[8.1]
  def change
    create_table :pokemon_base_stats do |t|
      t.string  :species,             null: false
      t.integer :national_dex_number, null: false
      t.integer :hp,                  null: false
      t.integer :atk,                 null: false
      t.integer :def_stat,            null: false
      t.integer :spa,                 null: false
      t.integer :spd,                 null: false
      t.integer :spe,                 null: false
      t.string  :type1,               null: false
      t.string  :type2
      t.timestamps
    end

    add_index :pokemon_base_stats, :species, unique: true
    add_index :pokemon_base_stats, :national_dex_number, unique: true
  end
end
