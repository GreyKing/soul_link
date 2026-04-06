class AddNatureToSoulLinkPokemon < ActiveRecord::Migration[8.1]
  def change
    add_column :soul_link_pokemon, :nature, :string
  end
end
