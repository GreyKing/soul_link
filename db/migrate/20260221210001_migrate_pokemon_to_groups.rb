class MigratePokemonToGroups < ActiveRecord::Migration[8.0]
  def up
    # Each existing SoulLinkPokemon row becomes its own group with one species entry.
    # The current 'name' column holds the nickname, and species is unknown for legacy data.
    execute <<-SQL
      INSERT INTO soul_link_pokemon_groups (soul_link_run_id, nickname, location, status, caught_at, died_at, created_at, updated_at)
      SELECT soul_link_run_id, name, location, status, caught_at, died_at, created_at, updated_at
      FROM soul_link_pokemon
    SQL

    # Link each pokemon to its corresponding group.
    # Match on run_id + name + created_at to handle duplicate nicknames (e.g., RACHEL caught twice).
    execute <<-SQL
      UPDATE soul_link_pokemon p
      SET soul_link_pokemon_group_id = (
        SELECT g.id
        FROM soul_link_pokemon_groups g
        WHERE g.soul_link_run_id = p.soul_link_run_id
          AND g.nickname = p.name
          AND g.created_at = p.created_at
        LIMIT 1
      ),
      species = 'Unknown'
    SQL
  end

  def down
    execute "UPDATE soul_link_pokemon SET soul_link_pokemon_group_id = NULL, species = NULL"
    execute "DELETE FROM soul_link_pokemon_groups"
  end
end
