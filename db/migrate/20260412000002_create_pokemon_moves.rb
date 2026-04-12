class CreatePokemonMoves < ActiveRecord::Migration[8.1]
  def change
    create_table :pokemon_moves do |t|
      t.string  :name,      null: false
      t.integer :power
      t.string  :move_type, null: false
      t.string  :category,  null: false
      t.integer :accuracy
      t.integer :pp
      t.integer :priority,  default: 0, null: false
      t.timestamps
    end

    add_index :pokemon_moves, :name, unique: true
  end
end
