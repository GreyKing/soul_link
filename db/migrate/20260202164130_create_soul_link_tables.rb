class CreateSoulLinkTables < ActiveRecord::Migration[7.0]
  def change
    create_table :soul_link_runs do |t|
      t.integer :run_number, null: false
      t.bigint :category_id, null: false
      t.bigint :general_channel_id, null: false
      t.bigint :catches_channel_id, null: false
      t.bigint :deaths_channel_id, null: false
      t.bigint :catches_panel_message_id
      t.bigint :deaths_panel_message_id
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :soul_link_runs, :run_number, unique: true
    add_index :soul_link_runs, :active

    create_table :soul_link_pokemon do |t|
      t.references :soul_link_run, null: false, foreign_key: true
      t.string :name, null: false
      t.string :location, null: false
      t.string :status, null: false, default: 'caught' # 'caught' or 'dead'
      t.bigint :discord_user_id, null: false
      t.datetime :caught_at
      t.datetime :died_at
      t.timestamps
    end

    add_index :soul_link_pokemon, [:soul_link_run_id, :status]
    add_index :soul_link_pokemon, :status
  end
end