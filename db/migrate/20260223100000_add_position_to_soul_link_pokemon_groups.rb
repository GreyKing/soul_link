class AddPositionToSoulLinkPokemonGroups < ActiveRecord::Migration[8.1]
  def up
    add_column :soul_link_pokemon_groups, :position, :integer

    # Backfill existing groups: order by caught_at, assign sequential positions per run
    execute <<~SQL
      UPDATE soul_link_pokemon_groups g
      JOIN (
        SELECT id,
               ROW_NUMBER() OVER (PARTITION BY soul_link_run_id ORDER BY caught_at ASC, id ASC) AS rn
        FROM soul_link_pokemon_groups
      ) ranked ON g.id = ranked.id
      SET g.position = ranked.rn
    SQL

    change_column_null :soul_link_pokemon_groups, :position, false
  end

  def down
    remove_column :soul_link_pokemon_groups, :position
  end
end
