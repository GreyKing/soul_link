class CreateSoulLinkPokemonGroups < ActiveRecord::Migration[8.0]
  def change
    create_table :soul_link_pokemon_groups do |t|
      t.references :soul_link_run, null: false, foreign_key: true
      t.string :nickname, null: false
      t.string :location, null: false
      t.string :status, null: false, default: 'caught'
      t.datetime :caught_at
      t.datetime :died_at
      t.timestamps
    end

    add_index :soul_link_pokemon_groups, [:soul_link_run_id, :status]
    add_index :soul_link_pokemon_groups, [:soul_link_run_id, :nickname]

    # Add group reference and species to existing pokemon table
    add_reference :soul_link_pokemon, :soul_link_pokemon_group, foreign_key: true, null: true
    add_column :soul_link_pokemon, :species, :string, null: true
    add_index :soul_link_pokemon, [:soul_link_pokemon_group_id, :discord_user_id],
              unique: true, name: 'index_pokemon_on_group_and_user'
  end
end
