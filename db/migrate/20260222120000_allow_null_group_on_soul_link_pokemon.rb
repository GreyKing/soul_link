class AllowNullGroupOnSoulLinkPokemon < ActiveRecord::Migration[8.0]
  def change
    # Species pool records have no group — they're unassigned until drag-and-drop
    change_column_null :soul_link_pokemon, :soul_link_pokemon_group_id, true

    # The unique index on (group_id, discord_user_id) won't work for unassigned
    # species where group_id is NULL. Remove and re-add without uniqueness,
    # since the controller validates assignment uniqueness at the app level.
    remove_index :soul_link_pokemon, name: 'index_pokemon_on_group_and_user'
    add_index :soul_link_pokemon, [:soul_link_pokemon_group_id, :discord_user_id],
              name: 'index_pokemon_on_group_and_user'
  end
end
