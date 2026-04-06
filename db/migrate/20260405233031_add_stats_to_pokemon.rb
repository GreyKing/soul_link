class AddStatsToPokemon < ActiveRecord::Migration[8.1]
  def change
    add_column :soul_link_pokemon, :level, :integer
    add_column :soul_link_pokemon, :ability, :string
    add_column :soul_link_pokemon, :evolution_level, :integer
  end
end
