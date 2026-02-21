class FinalizeGroupMigration < ActiveRecord::Migration[8.0]
  def change
    change_column_null :soul_link_pokemon, :soul_link_pokemon_group_id, false
    change_column_null :soul_link_pokemon, :species, false
  end
end
