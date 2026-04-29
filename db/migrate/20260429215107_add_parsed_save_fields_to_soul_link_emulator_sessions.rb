class AddParsedSaveFieldsToSoulLinkEmulatorSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :soul_link_emulator_sessions, :parsed_trainer_name, :string,  limit: 16
    add_column :soul_link_emulator_sessions, :parsed_money,        :integer, limit: 4
    add_column :soul_link_emulator_sessions, :parsed_play_seconds, :integer, limit: 4
    add_column :soul_link_emulator_sessions, :parsed_badges,       :integer, limit: 1, default: 0, null: false
    add_column :soul_link_emulator_sessions, :parsed_map_id,       :integer, limit: 2
    add_column :soul_link_emulator_sessions, :parsed_at,           :datetime
  end
end
