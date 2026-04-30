class CreateSoulLinkEmulatorSaveSlots < ActiveRecord::Migration[8.1]
  def change
    create_table :soul_link_emulator_save_slots do |t|
      t.references :soul_link_emulator_session, null: false, foreign_key: true, index: true
      t.integer :slot_number, null: false
      t.binary  :save_data, limit: 16.megabytes
      t.string  :parsed_trainer_name, limit: 16
      t.integer :parsed_money
      t.integer :parsed_play_seconds
      t.integer :parsed_badges, default: 0, null: false
      t.integer :parsed_map_id, limit: 2
      t.datetime :parsed_at
      t.timestamps
      t.index [ :soul_link_emulator_session_id, :slot_number ], unique: true,
              name: "idx_soul_link_emulator_save_slots_session_slot"
    end

    add_column :soul_link_emulator_sessions, :active_save_slot, :integer

    reversible do |dir|
      dir.up do
        # Migrate every existing per-session save into slot 1 of that session.
        # save_data is gzipped on disk via SoulLinkEmulatorSession::GzipCoder.
        # The new SoulLinkEmulatorSaveSlot model uses the SAME coder, so we
        # want the RAW gzipped bytes copied byte-for-byte into the slot row —
        # no double-gzip, no decode/re-encode round-trip. A raw SQL INSERT ...
        # SELECT does exactly that: the BLOB column data is copied verbatim
        # at the database layer with no Ruby-side type casting.
        execute <<~SQL.squish
          INSERT INTO soul_link_emulator_save_slots (
            soul_link_emulator_session_id, slot_number, save_data,
            parsed_trainer_name, parsed_money, parsed_play_seconds,
            parsed_badges, parsed_map_id, parsed_at,
            created_at, updated_at
          )
          SELECT id, 1, save_data,
                 parsed_trainer_name, parsed_money, parsed_play_seconds,
                 COALESCE(parsed_badges, 0), parsed_map_id, parsed_at,
                 NOW(), NOW()
          FROM soul_link_emulator_sessions
          WHERE save_data IS NOT NULL
        SQL

        execute <<~SQL.squish
          UPDATE soul_link_emulator_sessions
          SET active_save_slot = 1
          WHERE save_data IS NOT NULL
        SQL
      end
    end

    # Type args make `remove_column` reversible at the schema level. On
    # rollback the columns are re-added empty — Project Owner accepts the
    # data loss (prod has 2-3 saves). Types match the original migrations
    # exactly (CreateSoulLinkEmulatorSessions + AddParsedSaveFieldsToSoulLinkEmulatorSessions).
    remove_column :soul_link_emulator_sessions, :save_data,           :binary, limit: 16.megabytes
    remove_column :soul_link_emulator_sessions, :parsed_trainer_name, :string, limit: 16
    remove_column :soul_link_emulator_sessions, :parsed_money,        :integer, limit: 4
    remove_column :soul_link_emulator_sessions, :parsed_play_seconds, :integer, limit: 4
    remove_column :soul_link_emulator_sessions, :parsed_badges,       :integer, limit: 1, default: 0, null: false
    remove_column :soul_link_emulator_sessions, :parsed_map_id,       :integer, limit: 2
    remove_column :soul_link_emulator_sessions, :parsed_at,           :datetime
  end
end
