class CreateSoulLinkTeams < ActiveRecord::Migration[8.0]
  def change
    create_table :soul_link_teams do |t|
      t.references :soul_link_run, null: false, foreign_key: true
      t.bigint :discord_user_id, null: false
      t.string :label

      t.timestamps
    end

    add_index :soul_link_teams, [ :soul_link_run_id, :discord_user_id ], unique: true, name: "index_teams_on_run_and_user"
  end
end
