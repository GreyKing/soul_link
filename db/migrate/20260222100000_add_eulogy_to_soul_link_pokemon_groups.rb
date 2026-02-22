class AddEulogyToSoulLinkPokemonGroups < ActiveRecord::Migration[8.0]
  def change
    add_column :soul_link_pokemon_groups, :eulogy, :text
  end
end
