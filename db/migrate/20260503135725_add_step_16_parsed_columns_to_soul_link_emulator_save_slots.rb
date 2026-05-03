class AddStep16ParsedColumnsToSoulLinkEmulatorSaveSlots < ActiveRecord::Migration[8.1]
  # Step 16 — Non-decryption SRAM expansion. Five new parsed_* columns
  # populated by SoulLink::SaveParser:
  #
  #   parsed_trainer_id      uint16, mix-up detection (TID)
  #   parsed_secret_id       uint16, mix-up detection (SID)
  #   parsed_pokedex_caught  popcount of caught region (0..493)
  #   parsed_pokedex_seen    popcount of seen region (0..493)
  #   parsed_hof_count       Hall of Fame ClearCount (0..9999)
  #
  # Default :integer (4 bytes signed) — uint16 fits cleanly. We deliberately
  # avoid `limit: 2` (smallint risks overflow on the uint16 upper half).
  # All fields are nullable; nil = "never parsed this field" matching the
  # existing parsed_map_id pattern (so first-parse / parse-failure paths
  # don't have to fabricate sentinel values).
  def change
    add_column :soul_link_emulator_save_slots, :parsed_trainer_id,     :integer
    add_column :soul_link_emulator_save_slots, :parsed_secret_id,      :integer
    add_column :soul_link_emulator_save_slots, :parsed_pokedex_caught, :integer
    add_column :soul_link_emulator_save_slots, :parsed_pokedex_seen,   :integer
    add_column :soul_link_emulator_save_slots, :parsed_hof_count,      :integer
  end
end
