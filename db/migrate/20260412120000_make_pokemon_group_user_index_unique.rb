class MakePokemonGroupUserIndexUnique < ActiveRecord::Migration[8.1]
  def change
    remove_index :soul_link_pokemon, name: "index_pokemon_on_group_and_user"
    add_index :soul_link_pokemon, [:soul_link_pokemon_group_id, :discord_user_id],
              unique: true, name: "index_pokemon_on_group_and_user"
  end
end
