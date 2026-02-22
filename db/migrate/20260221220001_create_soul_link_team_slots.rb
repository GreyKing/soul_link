class CreateSoulLinkTeamSlots < ActiveRecord::Migration[8.0]
  def change
    create_table :soul_link_team_slots do |t|
      t.references :soul_link_team, null: false, foreign_key: true
      t.references :soul_link_pokemon_group, null: false, foreign_key: true
      t.integer :position, null: false

      t.timestamps
    end

    add_index :soul_link_team_slots, [ :soul_link_team_id, :position ],
              unique: true, name: "index_team_slots_on_team_and_position"
    add_index :soul_link_team_slots, [ :soul_link_team_id, :soul_link_pokemon_group_id ],
              unique: true, name: "index_team_slots_on_team_and_group"
  end
end
