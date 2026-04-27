class CreateSoulLinkEmulatorSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :soul_link_emulator_sessions do |t|
      t.references :soul_link_run, null: false, foreign_key: true
      t.bigint  :discord_user_id                         # nullable until claimed
      t.string  :status, default: "pending", null: false # pending | generating | ready | failed
      t.string  :seed, null: false
      t.string  :rom_path                                # nullable until generation succeeds
      t.binary  :save_data, limit: 16.megabytes          # MEDIUMBLOB on MySQL 8
      t.string  :error_message
      t.timestamps
    end

    add_index :soul_link_emulator_sessions,
              [ :soul_link_run_id, :discord_user_id ],
              unique: true,
              name: "idx_emu_session_run_user"

    add_index :soul_link_emulator_sessions,
              [ :soul_link_run_id, :status ],
              name: "idx_emu_session_run_status"
  end
end
